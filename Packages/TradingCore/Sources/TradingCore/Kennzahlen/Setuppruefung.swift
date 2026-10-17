import Foundation

/// Kill-Kriterium je Setup (E7, Tim 17.10.2026): Nach N Trades zählt der Erwartungswert in R nach Kosten; ist er
/// nicht positiv, geht das Setup nicht auf Echtgeld. Demo- und Echtgeld-Trades zählen getrennt (E1).
public struct Setuppruefung: Sendable, Equatable, Codable {
    public var setup: String
    /// `Kontoart` als Text („echt“, „demo“), damit eine neue Art ältere Connectoren nicht stört.
    public var kontoart: String
    /// Trades mit diesem Setup in Konten dieser Art; Teilverkäufe zählen einzeln wie in den Kennzahlen.
    public var anzahl: Int
    /// Durchschnitt R nach Kosten über die Trades mit bekanntem Risiko; `nil` ohne solche.
    public var erwartungswertR: Decimal?
    /// Trades mit R, davon mit angenommenem Risiko (ohne Stop).
    public var anzahlMitR: Int
    public var anzahlRAngenommen: Int
    /// N der Karte (`Setup.pruefungNachTrades`).
    public var schwelle: Int
    /// `anzahl` hat `schwelle` erreicht: Die Prüfung ist fällig.
    public var faellig: Bool
    /// Fällig und Erwartungswert in R nicht über 0 (oder unbekannt): nach der Regel kein Echtgeld.
    public var nichtBestanden: Bool

    public init(setup: String, kontoart: Kontoart, trades: [Trade], schwelle: Int) {
        let k = Kennzahlen(trades: trades)
        self.setup = setup
        self.kontoart = kontoart.rawValue
        anzahl = k.anzahl
        erwartungswertR = k.erwartungswertR
        anzahlMitR = k.anzahlMitR
        anzahlRAngenommen = k.anzahlRAngenommen
        self.schwelle = schwelle
        faellig = k.anzahl >= schwelle
        nichtBestanden = faellig && (k.erwartungswertR ?? 0) <= 0
    }

    /// Prüfstände aller Karten mit `pruefungNachTrades`, je Kontoart mit mindestens einem Trade.
    /// - Parameter konten: Trades je Konto mit Kontoart und Setup je Trade-ID (aus dem Journal).
    public static func berechne(playbook: [Setup],
                                konten: [(kontoart: Kontoart, trades: [Trade], setups: [String: String])])
        -> [Setuppruefung] {
        var ergebnis: [Setuppruefung] = []
        for karte in playbook {
            guard let schwelle = karte.pruefungNachTrades, schwelle > 0 else { continue }
            let schluessel = Setup.schluessel(karte.name)
            for art in Kontoart.allCases {
                let trades = konten.filter { $0.kontoart == art }.flatMap { konto in
                    konto.trades.filter { konto.setups[$0.id].map(Setup.schluessel) == schluessel }
                }
                guard !trades.isEmpty else { continue }
                ergebnis.append(Setuppruefung(setup: karte.name, kontoart: art, trades: trades, schwelle: schwelle))
            }
        }
        return ergebnis
    }
}
