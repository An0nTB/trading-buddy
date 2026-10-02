import Foundation

/// Eigene Handelsregeln eines Kontos (Doc 18, F1; Entscheidung 27 vom 02.10.2026).
/// Jede Grenze ist freiwillig; `nil` heißt „Regel aus“. Beträge in Kontowährung, positiv angegeben.
/// Gespeichert je Konto in TradingStore; geprüft nach jedem Import (E3 Option 1), nicht live.
public struct Handelsregeln: Codable, Sendable, Equatable {
    /// Nach diesem realisierten Tagesverlust (netto) keine neuen Trades mehr am selben Tag.
    public var maxTagesverlust: Decimal?
    /// Höchstens so viele eröffnete Trades je Kalendertag.
    public var maxTradesJeTag: Int?
    /// Nach so vielen Verlusten in Folge am selben Tag keine neuen Trades mehr an diesem Tag.
    /// Ein Gewinner oder ein neuer Tag setzt die Zählung zurück.
    public var stoppNachVerlusten: Int?
    /// Höchstes Risiko je Trade (Abstand Einstieg bis Stop); auch ein Verlust darüber zählt als Verstoß.
    public var maxRisikoJeTrade: Decimal?
    /// Regeln einer Prop-Firm, wenn das Konto eine Challenge oder ein finanziertes Konto ist.
    public var propFirm: PropFirmRegeln?

    public init(maxTagesverlust: Decimal? = nil, maxTradesJeTag: Int? = nil, stoppNachVerlusten: Int? = nil,
                maxRisikoJeTrade: Decimal? = nil, propFirm: PropFirmRegeln? = nil) {
        self.maxTagesverlust = maxTagesverlust
        self.maxTradesJeTag = maxTradesJeTag
        self.stoppNachVerlusten = stoppNachVerlusten
        self.maxRisikoJeTrade = maxRisikoJeTrade
        self.propFirm = propFirm
    }

    /// Keine Regel gesetzt: Die App zeigt dann keine Ampel und keine Disziplin-Kurve.
    public var leer: Bool {
        maxTagesverlust == nil && maxTradesJeTag == nil && stoppNachVerlusten == nil && maxRisikoJeTrade == nil
            && propFirm == nil
    }
}

/// Ein Trade, der eine Handelsregel verletzt hat.
public struct Regelverstoss: Sendable, Equatable {
    public enum Art: String, Codable, Sendable, CaseIterable {
        case tagesverlust
        case tradesJeTag
        case stoppNachVerlusten
        case risikoJeTrade
        /// Im Journal als „nicht regeltreu“ markiert.
        case manuell
    }

    public var art: Art
    public var trade: String
    /// Beginn des Kalendertags der Eröffnung in der Zeitzone der Prüfung.
    public var tag: Date

    public init(art: Art, trade: String, tag: Date) {
        self.art = art
        self.trade = trade
        self.tag = tag
    }
}
