import TradingCore
import TradingStore

extension Trade {
    /// Der Trade, wie App und Connector-Export ihn rechnen: Ein im Journal nachgetragener
    /// Stop beim Einstieg ersetzt den Stop aus dem Auszug (MT4 kennt nur den letzten Stop).
    func mitJournal(_ eintrag: Journaleintrag?) -> Trade {
        guard let stop = eintrag?.stopEinstieg else { return self }
        var trade = self
        trade.stopLoss = stop
        return trade
    }
}
