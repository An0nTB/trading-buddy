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
