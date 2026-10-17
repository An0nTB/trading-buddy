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
    /// Höchstes Risiko je Trade (Abstand Einstieg bis Stop, `Trade.stopRisiko`; ein geplantes Risiko zählt
    /// nicht); auch ein Verlust darüber zählt als Verstoß.
    public var maxRisikoJeTrade: Decimal?
    /// Regeln einer Prop-Firm, wenn das Konto eine Challenge oder ein finanziertes Konto ist.
    public var propFirm: PropFirmRegeln?

    // Grenzen in Prozent vom Kontostand (E2, Tim 17.10.2026), als Prozentzahl (1,5 heißt 1,5 %). Bezug ist
    // `kontostand`; ohne ihn gelten sie nicht. Sind Betrag und Prozent gesetzt, gilt die engere Grenze.
    /// Tagesverlust in Prozent vom Kontostand zu Tagesbeginn.
    public var maxTagesverlustProzent: Decimal?
    /// Risiko je Trade in Prozent vom Kontostand zu Tagesbeginn.
    public var maxRisikoJeTradeProzent: Decimal?
    /// Realisierter Nettoverlust im Kalendermonat (E3); danach keine neuen Trades mehr in diesem Monat.
    public var maxMonatsverlust: Decimal?
    /// Monatsverlust in Prozent vom Kontostand zu Monatsbeginn.
    public var maxMonatsverlustProzent: Decimal?
    /// Höchstens so viele Positionen gleichzeitig offen, die neue mitgezählt (E6).
    public var maxOffenePositionen: Int?
    /// Höchstes Risiko aller offenen Positionen zusammen, die neue mitgezählt (E6). Risiko wie `Trade.risk`.
    public var maxOffenesRisiko: Decimal?
    /// Offenes Risiko in Prozent vom Kontostand zu Tagesbeginn.
    public var maxOffenesRisikoProzent: Decimal?
    /// Bezug der Prozentgrenzen (Tim 17.10.2026: Startwert + Ergebnisse).
    public var kontostand: Kontostandbezug?

    public init(maxTagesverlust: Decimal? = nil, maxTradesJeTag: Int? = nil, stoppNachVerlusten: Int? = nil,
                maxRisikoJeTrade: Decimal? = nil, propFirm: PropFirmRegeln? = nil,
                maxTagesverlustProzent: Decimal? = nil, maxRisikoJeTradeProzent: Decimal? = nil,
                maxMonatsverlust: Decimal? = nil, maxMonatsverlustProzent: Decimal? = nil,
                maxOffenePositionen: Int? = nil, maxOffenesRisiko: Decimal? = nil,
                maxOffenesRisikoProzent: Decimal? = nil, kontostand: Kontostandbezug? = nil) {
        self.maxTagesverlust = maxTagesverlust
        self.maxTradesJeTag = maxTradesJeTag
        self.stoppNachVerlusten = stoppNachVerlusten
        self.maxRisikoJeTrade = maxRisikoJeTrade
        self.propFirm = propFirm
        self.maxTagesverlustProzent = maxTagesverlustProzent
        self.maxRisikoJeTradeProzent = maxRisikoJeTradeProzent
        self.maxMonatsverlust = maxMonatsverlust
        self.maxMonatsverlustProzent = maxMonatsverlustProzent
        self.maxOffenePositionen = maxOffenePositionen
        self.maxOffenesRisiko = maxOffenesRisiko
        self.maxOffenesRisikoProzent = maxOffenesRisikoProzent
        self.kontostand = kontostand
    }

    /// Keine Regel gesetzt: Die App zeigt dann keine Ampel und keine Disziplin-Kurve. Ein Kontostand allein ist
    /// keine Regel.
    public var leer: Bool {
        maxTagesverlust == nil && maxTradesJeTag == nil && stoppNachVerlusten == nil && maxRisikoJeTrade == nil
            && propFirm == nil && maxTagesverlustProzent == nil && maxRisikoJeTradeProzent == nil
            && maxMonatsverlust == nil && maxMonatsverlustProzent == nil && maxOffenePositionen == nil
            && maxOffenesRisiko == nil && maxOffenesRisikoProzent == nil
    }

    /// Wirksame Grenze aus Betrag und Prozent vom Kontostand `stand`: die engere von beiden. Prozent zählt nur bei
    /// positivem Stand; `nil`, wenn keine Grenze gilt.
    public static func grenze(betrag: Decimal?, prozent: Decimal?, stand: Decimal?) -> Decimal? {
        var kandidaten: [Decimal] = []
        if let betrag { kandidaten.append(betrag) }
        if let prozent, let stand, stand > 0 { kandidaten.append(stand * prozent / 100) }
        return kandidaten.min()
    }
}

/// Kontostand als Bezug der Prozentgrenzen (E2): ein eingetragener Stand zu einem Zeitpunkt, fortgeschrieben mit
/// den realisierten Ergebnissen danach (Tim 17.10.2026, Karte „Startwert + Ergebnisse“). Ein- und Auszahlungen
/// zählen nicht; nach einer solchen trägt man einen neuen Startwert ein.
public struct Kontostandbezug: Codable, Sendable, Equatable {
    public var betrag: Decimal
    public var seit: Date

    public init(betrag: Decimal, seit: Date) {
        self.betrag = betrag
        self.seit = seit
    }

    /// Stand zum Zeitpunkt `zeit`: Startwert plus Netto der Trades, die zwischen `seit` und `zeit` schlossen.
    /// Liegt `zeit` vor `seit`, werden die Ergebnisse dazwischen abgezogen. `ohneBetrag` wie bei der Regelprüfung.
    public func stand(bei zeit: Date, trades: [Trade], ohneBetrag: Set<String> = []) -> Decimal {
        var stand = betrag
        for t in trades where !ohneBetrag.contains(t.id) {
            if t.closeTime >= seit && t.closeTime < zeit { stand += t.netProfit }
            if t.closeTime >= zeit && t.closeTime < seit { stand -= t.netProfit }
        }
        return stand
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
        /// Monatsverlust erreicht (E3).
        case monatsverlust
        /// Mehr Trades am Tag, als die Setup-Karte erlaubt (E4).
        case tradesJeSetup
        /// Gegen die Haltedauer der Setup-Karte gehalten: über Nacht oder übers Wochenende (E5).
        case haltedauer
        /// Zu viele Positionen gleichzeitig offen (E6).
        case offenePositionen
        /// Offenes Risiko über der Grenze (E6).
        case offenesRisiko
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
