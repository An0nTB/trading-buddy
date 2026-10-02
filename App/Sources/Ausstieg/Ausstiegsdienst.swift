import Foundation
import Observation
import TradingCore

/// Ausstiegsanalyse der App (Doc 39, Paket B3): hält die Übersicht des Kerzenspeichers, nimmt Kerzen aus dem
/// MT4-Import und später aus dem Kursabruf (Paket B2) an und rechnet je Trade `Ausstiegsanalyse` aus dem Kern.
/// Nur beschreibend: Rückblick auf vergangene Kurse, keine Aussage über künftige.
///
/// Eine geteilte Instanz statt eines Felds im `AppModell`, damit dieses Paket ohne Änderung fremder Dateien baut.
@Observable @MainActor
final class Ausstiegsdienst {
    static let geteilt = Ausstiegsdienst()

    /// Gespeicherte Symbole; leer, bis `ladeBestand()` lief.
    private(set) var bestand: [Kerzenbestand] = []
    /// Zählt jede Änderung am Speicher hoch, damit Karten und Seite neu rechnen.
    private(set) var stand = 0

    /// Bewegung nach dem Ausstieg: eine Stunde (Vorgabe des Kerns).
    nonisolated static let nachlauf: TimeInterval = 3_600

    private let speicher: Zeitkerzenspeicher
    private var bestandGeladen = false

    init(speicher: Zeitkerzenspeicher = Zeitkerzenspeicher()) {
        self.speicher = speicher
    }

    /// Liest `bestand.json` einmal; weitere Aufrufe tun nichts.
    func ladeBestand() async {
        guard !bestandGeladen else { return }
        bestandGeladen = true
        let speicher = self.speicher
        bestand = await Task.detached { speicher.bestand() }.value
    }

    func hatKerzen(_ symbol: String) -> Bool { bestand.contains { $0.symbol == symbol } }

    /// Schnittstelle für den Kursabruf (Paket B2) und den MT4-Import: Kerzen eines Journal-Symbols für ein
    /// Zeitfenster übernehmen. Gespeicherte Kerzen, die im Fenster beginnen, ersetzt der neue Stand;
    /// ohne Fenster gilt die Spanne der Kerzen.
    /// - Parameter quelle: Herkunft für die Anzeige, z. B. „MT4“, „Alpaca“, „Binance“.
    func uebernimm(_ kerzen: [Zeitkerze], symbol: String, quelle: String, fenster: DateInterval? = nil) async throws {
        let speicher = self.speicher
        let neu = try await Task.detached {
            try speicher.speichere(kerzen, symbol: symbol, quelle: quelle, fenster: fenster)
        }.value
        bestand.removeAll { $0.symbol == symbol }
        if let neu { bestand.append(neu) }
        bestand.sort { $0.symbol < $1.symbol }
        bestandGeladen = true
        stand += 1
    }

    func loesche(symbol: String) async throws {
        let speicher = self.speicher
        try await Task.detached { try speicher.loesche(symbol: symbol) }.value
        bestand.removeAll { $0.symbol == symbol }
        stand += 1
    }

    /// Analyse eines Trades; `nil` ohne Uhrzeit oder ohne Kerze in der Haltedauer.
    func analyse(_ trade: Trade) async -> Ausstiegsanalyse? {
        guard !trade.nurDatum else { return nil }
        return await analysen([trade])[trade.id]
    }

    /// Kerzen für den Chart eines Trades (F8): Haltedauer, davor ein Viertel der Haltedauer (mindestens 30 Minuten),
    /// danach mindestens der Nachlauf. Leer ohne Uhrzeit oder ohne gespeicherte Kurse.
    func chartkerzen(_ trade: Trade) async -> [Zeitkerze] {
        guard !trade.nurDatum, hatKerzen(trade.symbol) else { return [] }
        let speicher = self.speicher
        let symbol = trade.symbol
        let rand = max(trade.holdingTime / 4, 1_800)
        let von = trade.openTime.addingTimeInterval(-rand)
        let bis = max(trade.openTime, trade.closeTime).addingTimeInterval(max(rand, Self.nachlauf))
        return await Task.detached { speicher.kerzen(symbol: symbol, von: von, bis: bis) }.value
    }

    /// Analysen mehrerer Trades nach Trade-ID. Liest je Symbol nur die Monate der Trades.
    func analysen(_ trades: [Trade]) async -> [String: Ausstiegsanalyse] {
        await analysen(trades, angeglichen: []).original
    }

    /// Wie `analysen(_:)`, dazu dieselbe Rechnung für die in die Kontowährung angeglichenen Trades
    /// (`Waehrungsangleich.trades`, gleiche IDs und Kurse), damit `liegengelassen` sich summieren lässt (Doc 40 W2).
    /// Die Kerzen werden dafür nur einmal gelesen.
    func analysen(_ trades: [Trade], angeglichen: [Trade])
        async -> (original: [String: Ausstiegsanalyse], angeglichen: [String: Ausstiegsanalyse]) {
        let speicher = self.speicher
        let symbole = Set(bestand.map(\.symbol))
        let passend = trades.filter { !$0.nurDatum && symbole.contains($0.symbol) }
        guard !passend.isEmpty else { return ([:], [:]) }
        let varianten = Dictionary(angeglichen.map { ($0.id, $0) }, uniquingKeysWith: { erste, _ in erste })
        return await Task.detached { Self.rechne(passend, varianten: varianten, speicher: speicher) }.value
    }

    /// Je Symbol in zeitlicher Reihenfolge; jede Monatsdatei wird einmal gelesen und verworfen, sobald kein
    /// späterer Trade sie mehr braucht. So liegen nie alle Monate eines Symbols auf einmal im Speicher.
    nonisolated private static func rechne(_ trades: [Trade], varianten: [String: Trade], speicher: Zeitkerzenspeicher)
        -> (original: [String: Ausstiegsanalyse], angeglichen: [String: Ausstiegsanalyse]) {
        var ergebnis: [String: Ausstiegsanalyse] = [:]
        var angeglichen: [String: Ausstiegsanalyse] = [:]
        for (symbol, gruppe) in Dictionary(grouping: trades, by: \.symbol) {
            var geladen: [String: [Zeitkerze]] = [:]
            for trade in gruppe.sorted(by: { $0.openTime < $1.openTime }) {
                let bis = max(trade.openTime, trade.closeTime).addingTimeInterval(nachlauf)
                // Eine Kerze, die vor dem Einstieg beginnt, kann noch im Vormonat liegen: einen Tag Vorlauf wie im Ausschnitt.
                let monate = Zeitkerzenspeicher.monate(von: trade.openTime.addingTimeInterval(-86_400), bis: bis)
                guard let erster = monate.first else { continue }
                geladen = geladen.filter { $0.key >= erster }
                var kerzen: [Zeitkerze] = []
                for monat in monate {
                    if geladen[monat] == nil { geladen[monat] = speicher.kerzen(symbol: symbol, monat: monat) }
                    kerzen += ausschnitt(geladen[monat] ?? [], von: trade.openTime, bis: bis)
                }
                guard !kerzen.isEmpty else { continue }
                ergebnis[trade.id] = Ausstiegsanalyse(trade: trade, kerzen: kerzen, nachlauf: nachlauf)
                if let variante = varianten[trade.id] {
                    angeglichen[trade.id] = Ausstiegsanalyse(trade: variante, kerzen: kerzen, nachlauf: nachlauf)
                }
            }
        }
        return (ergebnis, angeglichen)
    }

    /// Kerzen, die vor `bis` beginnen und nach `von` enden, aus einer aufsteigend sortierten Liste.
    /// Sucht den Anfang binär, weil ein Monat Minutenkurse rund 40.000 Kerzen hat.
    nonisolated private static func ausschnitt(_ kerzen: [Zeitkerze], von: Date, bis: Date) -> [Zeitkerze] {
        // Längste übliche Kerze (Tag) als Vorlauf, damit eine Kerze, die vor `von` beginnt, nicht fehlt.
        let suchbeginn = von.addingTimeInterval(-86_400)
        var unten = 0
        var oben = kerzen.count
        while unten < oben {
            let mitte = (unten + oben) / 2
            if kerzen[mitte].beginn < suchbeginn { unten = mitte + 1 } else { oben = mitte }
        }
        var ergebnis: [Zeitkerze] = []
        var i = unten
        while i < kerzen.count, kerzen[i].beginn < bis {
            if kerzen[i].ende > von { ergebnis.append(kerzen[i]) }
            i += 1
        }
        return ergebnis
    }
}
