import Foundation

/// Richtung einer Position.
public enum Side: String, Sendable, Equatable {
    case buy
    case sell
}

/// Auftragsart, so wie MetaTrader sie in Auszügen schreibt.
public enum OrderType: String, Sendable, Equatable, CaseIterable {
    case buy
    case sell
    case buyLimit = "buy limit"
    case sellLimit = "sell limit"
    case buyStop = "buy stop"
    case sellStop = "sell stop"

    /// Richtung, die der Auftrag eröffnen würde.
    public var side: Side {
        switch self {
        case .buy, .buyLimit, .buyStop: .buy
        case .sell, .sellLimit, .sellStop: .sell
        }
    }
}

/// Geschlossene Position. Beträge in Kontowährung, Zeiten in UTC.
public struct ClosedPosition: Sendable, Equatable {
    public var ticket: String
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

    /// Ergebnis nach Kosten: Kommission + Swap + Kursergebnis.
    public var netProfit: Decimal { commission + swap + profit }
}

/// Offene Position zum Zeitpunkt des Auszugs.
public struct OpenPosition: Sendable, Equatable {
    public var ticket: String
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

    /// Schwebendes Ergebnis nach Kosten.
    public var netProfit: Decimal { commission + swap + profit }
}

/// Gelöschte Pending Order. Wird gespeichert, zählt aber nie als Trade.
public struct CancelledOrder: Sendable, Equatable {
    public var ticket: String
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
}

/// Noch wartende Pending Order zum Zeitpunkt des Auszugs.
public struct WorkingOrder: Sendable, Equatable {
    public var ticket: String
    public var type: OrderType
    public var lots: Decimal
    public var symbol: String
    public var placedAt: Date
    public var orderPrice: Decimal
    public var stopLoss: Decimal?
    public var takeProfit: Decimal?
    public var marketPrice: Decimal
}

/// Summenzeile unter einem Abschnitt (Kommission, Swap, Kursergebnis).
public struct Totals: Sendable, Equatable {
    public var commission: Decimal
    public var swap: Decimal
    public var profit: Decimal

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
}
