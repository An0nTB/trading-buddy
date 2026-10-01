import Foundation

/// Geschlossene Position. Beträge in Kontowährung, Zeiten in UTC.
public struct ClosedPosition: Sendable, Equatable {
    public var ticket: String
    /// Zelltexte der Originalzeile, nur Leerraum zusammengefasst (Regel 9: Rohzeile aufbewahren).
    public var rohzeile: [String]
    public var side: Side
    public var lots: Decimal
    public var symbol: String
    public var openTime: Date
    public var openPrice: Decimal
    /// `nil`, wenn kein Stop gesetzt war (MetaTrader schreibt dann 0).
    public var stopLoss: Decimal?
    public var takeProfit: Decimal?
    public var closeTime: Date
    public var closePrice: Decimal
    public var commission: Decimal
    public var swap: Decimal
    /// Ergebnis aus der Kursbewegung, ohne Kommission und Swap.
    public var profit: Decimal

    public init(ticket: String, rohzeile: [String], side: Side, lots: Decimal, symbol: String, openTime: Date, openPrice: Decimal, stopLoss: Decimal? = nil, takeProfit: Decimal? = nil, closeTime: Date, closePrice: Decimal, commission: Decimal, swap: Decimal, profit: Decimal) {
        self.ticket = ticket
        self.rohzeile = rohzeile
        self.side = side
        self.lots = lots
        self.symbol = symbol
        self.openTime = openTime
        self.openPrice = openPrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.closeTime = closeTime
        self.closePrice = closePrice
        self.commission = commission
        self.swap = swap
        self.profit = profit
    }

    /// Ergebnis nach Kosten: Kommission + Swap + Kursergebnis.
    public var netProfit: Decimal { commission + swap + profit }
}

/// Offene Position zum Zeitpunkt des Auszugs.
public struct OpenPosition: Sendable, Equatable {
    public var ticket: String
    /// Zelltexte der Originalzeile, nur Leerraum zusammengefasst (Regel 9: Rohzeile aufbewahren).
    public var rohzeile: [String]
    public var side: Side
    public var lots: Decimal
    public var symbol: String
    public var openTime: Date
    public var openPrice: Decimal
    public var stopLoss: Decimal?
    public var takeProfit: Decimal?
    /// Kurs zum Zeitpunkt des Auszugs.
    public var currentPrice: Decimal
    public var commission: Decimal
    public var swap: Decimal
    public var profit: Decimal

    public init(ticket: String, rohzeile: [String], side: Side, lots: Decimal, symbol: String, openTime: Date, openPrice: Decimal, stopLoss: Decimal? = nil, takeProfit: Decimal? = nil, currentPrice: Decimal, commission: Decimal, swap: Decimal, profit: Decimal) {
        self.ticket = ticket
        self.rohzeile = rohzeile
        self.side = side
        self.lots = lots
        self.symbol = symbol
        self.openTime = openTime
        self.openPrice = openPrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.currentPrice = currentPrice
        self.commission = commission
        self.swap = swap
        self.profit = profit
    }

    /// Schwebendes Ergebnis nach Kosten.
    public var netProfit: Decimal { commission + swap + profit }
}

/// Gelöschte Pending Order. Wird gespeichert, zählt aber nie als Trade.
public struct CancelledOrder: Sendable, Equatable {
    public var ticket: String
    /// Zelltexte der Originalzeile, nur Leerraum zusammengefasst (Regel 9: Rohzeile aufbewahren).
    public var rohzeile: [String]
    public var type: OrderType
    public var lots: Decimal
    public var symbol: String
    public var placedAt: Date
    public var orderPrice: Decimal
    public var stopLoss: Decimal?
    public var takeProfit: Decimal?
    public var cancelledAt: Date
    /// Marktkurs beim Löschen.
    public var marketPrice: Decimal

    public init(ticket: String, rohzeile: [String], type: OrderType, lots: Decimal, symbol: String, placedAt: Date, orderPrice: Decimal, stopLoss: Decimal? = nil, takeProfit: Decimal? = nil, cancelledAt: Date, marketPrice: Decimal) {
        self.ticket = ticket
        self.rohzeile = rohzeile
        self.type = type
        self.lots = lots
        self.symbol = symbol
        self.placedAt = placedAt
        self.orderPrice = orderPrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.cancelledAt = cancelledAt
        self.marketPrice = marketPrice
    }
}

/// Noch wartende Pending Order zum Zeitpunkt des Auszugs.
public struct WorkingOrder: Sendable, Equatable {
    public var ticket: String
    /// Zelltexte der Originalzeile, nur Leerraum zusammengefasst (Regel 9: Rohzeile aufbewahren).
    public var rohzeile: [String]
    public var type: OrderType
    public var lots: Decimal
    public var symbol: String
    public var placedAt: Date
    public var orderPrice: Decimal
    public var stopLoss: Decimal?
    public var takeProfit: Decimal?
    public var marketPrice: Decimal

    public init(ticket: String, rohzeile: [String], type: OrderType, lots: Decimal, symbol: String, placedAt: Date, orderPrice: Decimal, stopLoss: Decimal? = nil, takeProfit: Decimal? = nil, marketPrice: Decimal) {
        self.ticket = ticket
        self.rohzeile = rohzeile
        self.type = type
        self.lots = lots
        self.symbol = symbol
        self.placedAt = placedAt
        self.orderPrice = orderPrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.marketPrice = marketPrice
    }
}

/// Summenzeile unter einem Abschnitt (Kommission, Swap, Kursergebnis).
public struct Totals: Sendable, Equatable {
    public var commission: Decimal
    public var swap: Decimal
    public var profit: Decimal

    public init(commission: Decimal, swap: Decimal, profit: Decimal) {
        self.commission = commission
        self.swap = swap
        self.profit = profit
    }

    public var net: Decimal { commission + swap + profit }
}

/// Kontoübersicht am Ende des Auszugs.
public struct AccountSummary: Sendable, Equatable {
    /// Kontostand am Vortag. Fehlt im Monatsauszug.
    public var previousBalance: Decimal?
    public var closedTradePL: Decimal
    public var depositWithdrawal: Decimal
    public var balance: Decimal
    public var floatingPL: Decimal
    public var equity: Decimal
    public var creditFacility: Decimal
    public var marginRequirement: Decimal
    public var availableMargin: Decimal

    public init(previousBalance: Decimal? = nil, closedTradePL: Decimal, depositWithdrawal: Decimal, balance: Decimal, floatingPL: Decimal, equity: Decimal, creditFacility: Decimal, marginRequirement: Decimal, availableMargin: Decimal) {
        self.previousBalance = previousBalance
        self.closedTradePL = closedTradePL
        self.depositWithdrawal = depositWithdrawal
        self.balance = balance
        self.floatingPL = floatingPL
        self.equity = equity
        self.creditFacility = creditFacility
        self.marginRequirement = marginRequirement
        self.availableMargin = availableMargin
    }
}
