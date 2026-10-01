import Foundation

/// Ausführung (Fill) bei Brokern, die Käufe und Verkäufe einzeln exportieren,
/// etwa Trade Republic und Scalable (R2, Schicht 2). Trades entstehen daraus erst
/// durch die Positionsbildung.
public struct Ausfuehrung: Sendable, Equatable {
    /// Kennung des Brokers für den Vorgang (transaction_id, reference).
    public var id: String
    public var zeit: Date
    /// Broker liefert nur das Datum (Uhrzeit 00:00:00); zählt nicht für Auswertungen nach Uhrzeit.
    public var nurDatum: Bool
    /// ISIN oder Symbol; Käufe und Verkäufe werden darüber zusammengeführt.
    public var kennung: String
    public var name: String
    public var seite: Side
    /// Stückzahl, immer positiv.
    public var menge: Decimal
    public var preis: Decimal
    /// Kassenwirkung ohne Kosten laut Broker: negativ beim Kauf, positiv beim Verkauf.
    /// Grundlage für das Ergebnis, weil der Preis gerundet sein kann.
    public var betrag: Decimal
    /// Gebühr, als Kassenwirkung meist negativ.
    public var gebuehr: Decimal
    /// Steuer, negativ als Abzug, positiv als Erstattung.
    public var steuer: Decimal
    public var waehrung: String
    public var sparplan: Bool
    /// Zelltexte der Originalzeile (Regel 9: Rohzeile aufbewahren).
    public var rohzeile: [String]

    public init(id: String, zeit: Date, nurDatum: Bool = false, kennung: String, name: String, seite: Side,
                menge: Decimal, preis: Decimal, betrag: Decimal, gebuehr: Decimal = 0, steuer: Decimal = 0,
                waehrung: String, sparplan: Bool = false, rohzeile: [String] = []) {
        self.id = id
        self.zeit = zeit
        self.nurDatum = nurDatum
        self.kennung = kennung
        self.name = name
        self.seite = seite
        self.menge = menge
        self.preis = preis
        self.betrag = betrag
        self.gebuehr = gebuehr
        self.steuer = steuer
        self.waehrung = waehrung
        self.sparplan = sparplan
        self.rohzeile = rohzeile
    }
}
