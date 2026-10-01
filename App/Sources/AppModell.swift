import Foundation
import Observation
import TradingCore
import TradingStore

/// Zeitraum-Filter: alles oder ein Kalendermonat (Monatsanfang in der Zeitzone des Nutzers).
enum Zeitraum: Hashable {
    case alle
    case monat(Date)
}

/// Eine importierte Datei in der Liste unter „Import“.
struct ImportEintrag: Identifiable {
    var id: Int64
    var konto: Konto
    var lauf: Importlauf
}

/// Zustand der App: das Journal auf der Festplatte, die Trades des gewählten Kontos
/// und die Filter der Oberfläche. Kennzahlen und Fehlermuster rechnet der Rechenkern bei Bedarf neu.
@Observable @MainActor
final class AppModell {
    private(set) var journal: Journal?
    private(set) var konten: [Konto] = []
    private(set) var importe: [ImportEintrag] = []
    /// Alle Trades des gewählten Kontos, vor Filtern.
    private(set) var alleTrades: [Trade] = []
    /// Alle gelöschten Pending Orders des gewählten Kontos, vor Filtern.
    private(set) var alleGeloeschten: [CancelledOrder] = []
    private(set) var kontoId: Int64?
    var fehler: String?
    /// Stand der Exportdatei für den Claude-Connector, angezeigt im Reiter Claude der Einstellungen.
    private(set) var exportStand = ""

    // Zustand der Oberfläche
    var bereich: Bereich = .uebersicht
    var zeitraum: Zeitraum = .alle
    var instrument: String?

    init() {
        do {
            journal = try Journal(pfad: Self.datenbankpfad())
            laden()
            exportiere()
        } catch {
            fehler = error.localizedDescription
        }
    }

    var konto: Konto? { konten.first { $0.id == kontoId } ?? konten.first }
    var waehrung: String { konto?.waehrung ?? "EUR" }
    /// Wochentag, Stunde und Tagesgrenze in der Zeitzone des Nutzers.
    var zeitzone: TimeZone { .current }

    private var kalender: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        return kalender
    }

    /// Trades nach Zeitraum und Instrument: Grundlage aller Zahlen in der Oberfläche.
    var trades: [Trade] {
        let kalender = self.kalender
        return alleTrades.filter { trade in
            if let instrument, trade.symbol != instrument { return false }
            if case .monat(let monat) = zeitraum, monatsanfang(trade.closeTime, kalender) != monat { return false }
            return true
        }
    }

    /// Gelöschte Pending Orders im gewählten Zeitraum (für die Stornoquote), Instrumentfilter gilt mit.
    var geloeschteOrders: Int {
        let kalender = self.kalender
        return alleGeloeschten.filter { order in
            if let instrument, order.symbol != instrument { return false }
            if case .monat(let monat) = zeitraum, monatsanfang(order.cancelledAt, kalender) != monat { return false }
            return true
        }.count
    }

    /// Monate mit Trades, neuester zuerst.
    var monate: [Date] {
        let kalender = self.kalender
        return Set(alleTrades.map { monatsanfang($0.closeTime, kalender) }).sorted(by: >)
    }

    var symbole: [String] { Set(alleTrades.map(\.symbol)).sorted() }

    var kennzahlen: Kennzahlen { Kennzahlen(trades: trades) }
    var kapitalverlauf: Kapitalverlauf { Kapitalverlauf(trades: trades) }
    var befunde: [Befund] {
        Fehlermuster.pruefe(trades, geloeschteOrders: geloeschteOrders, zeitzone: zeitzone)
    }

    /// Trades nach Schlusszeit, neueste zuerst.
    var tradesNeuesteZuerst: [Trade] {
        trades.sorted { ($0.closeTime, $0.id) > ($1.closeTime, $1.id) }
    }

    /// Welche Fehlermuster bei welchem Trade angeschlagen haben.
    var musterJeTrade: [String: [Fehlermuster]] {
        var ergebnis: [String: [Fehlermuster]] = [:]
        for befund in befunde {
            for id in befund.trades { ergebnis[id, default: []].append(befund.muster) }
        }
        return ergebnis
    }

    /// Trades ohne Stop im Export: ohne Stop kein R.
    var ohneStop: Int { trades.filter { $0.stopLoss == nil }.count }

    func waehleKonto(_ id: Int64?) {
        kontoId = id
        laden()
    }

    func laden() {
        guard let journal else { return }
        do {
            konten = try journal.konten()
            importe = try konten.flatMap { konto in
                try journal.importe(konto: konto).map { ImportEintrag(id: $0.id ?? 0, konto: konto, lauf: $0) }
            }
            if let konto {
                alleTrades = try journal.geschlossenePositionen(konto: konto).map { Trade($0) }
                alleGeloeschten = try journal.geloeschteOrders(konto: konto)
            } else {
                alleTrades = []
                alleGeloeschten = []
            }
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Das Konto zu Broker und Nummer, falls schon angelegt.
    func bekanntesKonto(broker: String, kontonummer: String) -> Konto? {
        konten.first { $0.broker == broker && $0.kontonummer == kontonummer }
    }

    /// Tickets, die für dieses Konto schon gespeichert sind (Zahl „Schon bekannt“ im Import-Blatt).
    func bekannteTickets(broker: String, kontonummer: String) -> Set<String> {
        guard let journal,
              let konto = bekanntesKonto(broker: broker, kontonummer: kontonummer),
              let positionen = try? journal.geschlossenePositionen(konto: konto)
        else { return [] }
        return Set(positionen.map(\.ticket))
    }

    func importiere(daten: Data, dateiname: String, serverZeitzone: TimeZone,
                    waehrung: String) throws -> ImportErgebnis {
        guard let journal else { throw CocoaError(.fileNoSuchFile) }
        let ergebnis = try journal.importiereMT4(datei: daten, dateiname: dateiname,
                                                 serverZeitzone: serverZeitzone, kontowaehrung: waehrung)
        laden()
        exportiere()
        return ergebnis
    }

    /// Schreibt die Exportdatei für den Claude-Connector neu (AP12), nur am Mac.
    func exportiere() {
        #if os(macOS)
        exportStand = ExportOrdner.schreibe(journal, zeitzone: zeitzone)
        #endif
    }

    /// `Application Support/Trading Buddy/journal.sqlite`, in der Sandbox im Container der App.
    private static func datenbankpfad() throws -> String {
        let ordner = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Trading Buddy", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner.appendingPathComponent("journal.sqlite").path
    }
}

private func monatsanfang(_ datum: Date, _ kalender: Calendar) -> Date {
    kalender.dateInterval(of: .month, for: datum)?.start ?? datum
}

extension Fehlermuster {
    var titel: String {
        switch self {
        case .revancheTrade: String(localized: "Revanche-Trade")
        case .ueberhandeln: String(localized: "Überhandeln")
        case .stopNichtEingehalten: String(localized: "Stop nicht eingehalten")
        case .gewinneZuFrueh: String(localized: "Gewinne zu früh")
        case .verliererLaufenLassen: String(localized: "Verlierer laufen lassen")
        case .verbilligen: String(localized: "Verbilligen")
        case .ohneStop: String(localized: "Ohne Stop")
        case .schwankendeGroesse: String(localized: "Schwankende Größe")
        case .groesseNachGewinnserie: String(localized: "Größe nach Gewinnserie")
        case .staendigesUmplanen: String(localized: "Ständiges Umplanen")
        }
    }

    /// Die Regel im Klartext, mit den Standardschwellen.
    var regel: String {
        switch self {
        case .revancheTrade: String(localized: "Eröffnet bis 15 Minuten nach einem Verlust, mit mehr Lots als üblich.")
        case .ueberhandeln: String(localized: "Tage mit mehr als Median plus 2 Trades.")
        case .stopNichtEingehalten: String(localized: "Verlust größer als 1,2 R.")
        case .gewinneZuFrueh: String(localized: "Gewinner, die weniger als die Hälfte des Wegs zum Ziel mitgenommen haben.")
        case .verliererLaufenLassen: String(localized: "Verlierer im Schnitt mehr als 1,5-mal so lange gehalten wie Gewinner.")
        case .verbilligen: String(localized: "Nachkauf in gleicher Richtung zu schlechterem Kurs, während die erste Position offen ist.")
        case .ohneStop: String(localized: "Trade ohne Stop-Loss.")
        case .schwankendeGroesse: String(localized: "Risiko je Trade stark gestreut (Variationskoeffizient über 0,5).")
        case .groesseNachGewinnserie: String(localized: "Nach zwei Gewinnen in Folge mehr als 1,5-mal das übliche Risiko.")
        case .staendigesUmplanen: String(localized: "Mehr als die Hälfte der Pending Orders gelöscht.")
        }
    }
}
