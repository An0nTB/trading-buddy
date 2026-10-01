import Foundation

/// Abgeschlossener Trade, unabhängig vom Broker. Grundlage aller Kennzahlen.
/// Beträge in Kontowährung, Zeiten in UTC.
public struct Trade: Sendable, Equatable, Identifiable {
    public var id: String
    public var symbol: String
    public var side: Side
    public var lots: Decimal
    public var openTime: Date
    public var closeTime: Date
    public var openPrice: Decimal
    public var closePrice: Decimal
    /// Stop laut Export. Bei MetaTrader der letzte Stand, nicht zwingend der beim Einstieg.
    public var stopLoss: Decimal?
    public var takeProfit: Decimal?
    public var commission: Decimal
    public var swap: Decimal
    /// Kursergebnis ohne Kosten.
    public var profit: Decimal
    /// Abgeführte oder erstattete Steuern (Trade Republic, Scalable); bei MetaTrader 0.
    public var taxes: Decimal

    public init(id: String, symbol: String, side: Side, lots: Decimal, openTime: Date, closeTime: Date,
                openPrice: Decimal, closePrice: Decimal, stopLoss: Decimal? = nil, takeProfit: Decimal? = nil,
                commission: Decimal = 0, swap: Decimal = 0, profit: Decimal, taxes: Decimal = 0) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.lots = lots
        self.openTime = openTime
        self.closeTime = closeTime
        self.openPrice = openPrice
        self.closePrice = closePrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.commission = commission
        self.swap = swap
        self.profit = profit
        self.taxes = taxes
    }

    public init(_ p: ClosedPosition) {
        self.init(id: p.ticket, symbol: p.symbol, side: p.side, lots: p.lots, openTime: p.openTime,
                  closeTime: p.closeTime, openPrice: p.openPrice, closePrice: p.closePrice,
                  stopLoss: p.stopLoss, takeProfit: p.takeProfit, commission: p.commission,
                  swap: p.swap, profit: p.profit)
    }

    /// Kosten (Kommission, Swap und Steuern), meist negativ.
    public var costs: Decimal { commission + swap + taxes }
    /// Ergebnis nach Kosten. Alle Kennzahlen rechnen damit.
    public var netProfit: Decimal { profit + costs }
    public var holdingTime: TimeInterval { closeTime.timeIntervalSince(openTime) }

    public enum Outcome: Sendable, Equatable {
        case win, loss, breakeven
    }

    public var outcome: Outcome {
        netProfit > 0 ? .win : (netProfit < 0 ? .loss : .breakeven)
    }

    /// Geplantes Risiko (1 R) in Kontowährung: Abstand Einstieg bis Stop mal Wert je Kurspunkt.
    /// Der Wert je Kurspunkt kommt aus dem Trade selbst (Kursergebnis ÷ Kursbewegung),
    /// so braucht es keine Kontraktgrößen je Instrument.
    /// `nil` ohne Stop, bei Stop auf der Gewinnseite (nachgezogen) oder ohne Kursbewegung.
    public var risk: Decimal? {
        guard let stop = stopLoss else { return nil }
        let abstand = side == .buy ? openPrice - stop : stop - openPrice
        let bewegung = side == .buy ? closePrice - openPrice : openPrice - closePrice
        guard abstand > 0, bewegung != 0 else { return nil }
        let wertJePunkt = profit / bewegung
        guard wertJePunkt > 0 else { return nil }
        return abstand * wertJePunkt
    }

    /// Ergebnis nach Kosten in Vielfachen des Risikos. `nil`, wenn das Risiko unbekannt ist.
    public var rMultiple: Decimal? {
        guard let risk else { return nil }
        return netProfit / risk
    }
}

extension Decimal {
    /// Kaufmännisch gerundet auf `stellen` Nachkommastellen.
    public func gerundet(_ stellen: Int) -> Decimal {
        var wert = self
        var ergebnis = Decimal()
        NSDecimalRound(&ergebnis, &wert, stellen, .plain)
        return ergebnis
    }
}
