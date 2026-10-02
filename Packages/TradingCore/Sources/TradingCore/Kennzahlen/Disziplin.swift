import Foundation

/// Disziplin-Kurve neben der Kapitalkurve (Doc 18, F1; Vorbild Edgewonk „Tiltmeter“):
/// je regeltreuem Trade +1, je Trade mit mindestens einem Verstoß −1, fortlaufend summiert.
/// Dazu der Vergleich „ohne Regelbrüche“ (R5 Kapitel 13, Nr. 8). Sortiert wie `Kapitalverlauf`.
public struct Disziplin: Sendable, Equatable {
    public struct Punkt: Sendable, Equatable {
        public var trade: String
        public var zeit: Date
        public var regeltreu: Bool
        /// Kontostand nach diesem Trade, ab 0.
        public var kapital: Decimal
        /// Fortlaufende Summe aus +1 und −1.
        public var wert: Int
    }

    public var punkte: [Punkt]
    public var regeltreu: Int
    public var verletzt: Int
    /// Anteil regeltreuer Trades; `nil` ohne Trades.
    public var quote: Decimal?
    public var nettoRegeltreu: Decimal
    public var nettoVerletzt: Decimal

    /// - Parameter propFirm: Verstöße gegen Prop-Firm-Regeln (Doc 18 F10, Tim 02.10.2026 Antwort 12d);
    ///   ein Trade mit eigenem oder Prop-Firm-Verstoß zählt einmal als verletzt.
    public init(trades: [Trade], verstoesse: [Regelverstoss], propFirm: [PropFirmPruefung.Verstoss] = []) {
        let betroffen = Set(verstoesse.map(\.trade)).union(propFirm.map(\.trade))
        let sortiert = trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
        var kapital: Decimal = 0
        var wert = 0
        punkte = sortiert.map { t in
            let treu = !betroffen.contains(t.id)
            kapital += t.netProfit
            wert += treu ? 1 : -1
            return Punkt(trade: t.id, zeit: t.closeTime, regeltreu: treu, kapital: kapital, wert: wert)
        }
        let treue = sortiert.filter { !betroffen.contains($0.id) }
        let brueche = sortiert.filter { betroffen.contains($0.id) }
        regeltreu = treue.count
        verletzt = brueche.count
        quote = sortiert.isEmpty ? nil : Decimal(treue.count) / Decimal(sortiert.count)
        nettoRegeltreu = treue.map(\.netProfit).reduce(0, +)
        nettoVerletzt = brueche.map(\.netProfit).reduce(0, +)
    }

    /// Grundgesamtheit für Schlüsse: unter 30 Trades nur beschreiben.
    public var genugDaten: Bool { punkte.count >= Kennzahlen.mindestanzahl }
}
