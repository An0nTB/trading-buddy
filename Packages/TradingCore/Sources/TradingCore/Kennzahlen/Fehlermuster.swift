import Foundation

/// Fehlermuster aus R5 Kapitel 09 Abschnitt 2, die sich aus den Exportdaten erkennen lassen.
/// FOMO-Einstieg (braucht Setup und Kursverlauf) und Nachrichten-Glücksspiel (braucht den
/// Termin-Kalender) fehlen noch; Randzeiten zeigt die Aufschlüsselung nach Stunde.
public enum Fehlermuster: String, Sendable, CaseIterable {
    case revancheTrade
    case ueberhandeln
    case stopNichtEingehalten
    case gewinneZuFrueh
    case verliererLaufenLassen
    case verbilligen
    case ohneStop
    case schwankendeGroesse
    case groesseNachGewinnserie
    case staendigesUmplanen

    /// Schwellen der Regeln. Vorschläge aus R5, am echten Datensatz zu kalibrieren;
    /// gehören später in die Einstellungen.
    public struct Schwellen: Sendable, Equatable {
        /// Revanche: Abstand Schluss Verlust bis nächste Eröffnung.
        public var revancheMinuten: Double = 15
        /// Überhandeln: Trades am Tag über Median plus diese Zahl.
        public var ueberhandelnUeberMedian: Int = 2
        /// Überhandeln: so viele Tage mit Trades braucht der Median mindestens. Darunter prüft die Regel
        /// nur gegen ein eigenes Limit (`maxTradesProTag`); drei Tage ergeben kein „üblich“ (Tim 05.10.2026).
        public var ueberhandelnMindestTage: Int = 10
        /// Eigenes Tageslimit, etwa aus den Handelsregeln (`Handelsregeln.maxTradesJeTag`). Gesetzt gilt es
        /// als Grenze für „Überhandeln“ statt des Medians, unabhängig von der Zahl der Tage.
        public var maxTradesProTag: Int? = nil
        /// Stop nicht eingehalten: Verlust kleiner als dieses R.
        public var stopVerlustR: Decimal = Decimal(string: "-1.2")!
        /// Gewinne zu früh: erzielt weniger als dieser Anteil des geplanten Ziels.
        public var zielAnteil: Decimal = Decimal(string: "0.5")!
        /// Verlierer laufen lassen: Ø Haltedauer Verlierer ÷ Gewinner über diesem Faktor.
        public var haltedauerFaktor: Double = 1.5
        /// Schwankende Größe: Variationskoeffizient des Risikos je Trade.
        public var variationskoeffizient: Double = 0.5
        /// Größe nach Gewinnserie: Gewinne in Folge davor.
        public var gewinnserie: Int = 2
        /// Größe nach Gewinnserie und Revanche: Risiko bzw. Lots über Median mal Faktor.
        public var groessenFaktor: Decimal = Decimal(string: "1.5")!
        /// Ständiges Umplanen: Stornoquote darüber.
        public var stornoquote: Decimal = Decimal(string: "0.5")!

        public init() {}
    }
}

/// Ein Treffer einer Regel. Bei Regeln über den ganzen Zeitraum ist `trades` leer
/// und `wert` enthält die Kennzahl, die die Schwelle überschritten hat.
public struct Befund: Sendable, Equatable {
    public var muster: Fehlermuster
    /// IDs der betroffenen Trades.
    public var trades: [String]
    /// Summe netto der betroffenen Trades.
    public var netto: Decimal
    /// Summe der R-Multiples der betroffenen Trades mit bekanntem Risiko.
    public var summeR: Decimal?
    /// Kennzahl oder Grenze der Regel; bei „Überhandeln“ die Grenze an Positionen je Tag.
    public var wert: Decimal?
    /// Grundgesamtheit, auf die sich die Regel stützt. Unter 30: nur beschreiben.
    public var stichprobe: Int

    public var genugDaten: Bool { stichprobe >= Kennzahlen.mindestanzahl }
}
