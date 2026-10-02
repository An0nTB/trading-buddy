import Foundation

/// Ein Ziel aus einer Wochen- oder Monatsauswertung (Rezept Punkt 7), z. B. „Höchstens 2 Revanche-Trades“.
/// Das nächste Review greift es auf und hakt es ab (Punkt 6). Gespeichert je Konto in TradingStore
/// (Migration v4), gelesen von Export und Connector. Eingegeben wird es in der App; der Connector liest nur.
public struct Reviewziel: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case offen
        case erreicht
        case verfehlt
        /// Nicht mehr verfolgt, ohne Urteil über erreicht oder verfehlt.
        case verworfen
    }

    /// Von der Datenbank vergeben; `nil`, solange das Ziel nicht gespeichert ist.
    public var id: Int64?
    public var text: String
    /// Zeitraum, in dem das Ziel gilt: `von` einschließlich, `bis` ausschließlich.
    public var von: Date
    public var bis: Date
    /// Was gemessen wird, frei benannt, z. B. „Revanche-Trades“ oder „Trades je Tag“; freiwillig.
    public var messgroesse: String?
    /// Zielwert zur Messgröße, z. B. 2; freiwillig.
    public var zielwert: Decimal?
    public var status: Status
    /// Was beim Abhaken festgestellt wurde, z. B. „1 Revanche-Trade statt höchstens 2“.
    public var ergebnis: String?
    public var erstellt: Date
    public var geaendert: Date

    public init(id: Int64? = nil, text: String, von: Date, bis: Date, messgroesse: String? = nil,
                zielwert: Decimal? = nil, status: Status = .offen, ergebnis: String? = nil,
                erstellt: Date = Date(), geaendert: Date? = nil) {
        self.id = id
        self.text = text
        self.von = von
        self.bis = bis
        self.messgroesse = messgroesse
        self.zielwert = zielwert
        self.status = status
        self.ergebnis = ergebnis
        self.erstellt = erstellt
        self.geaendert = geaendert ?? erstellt
    }
}
