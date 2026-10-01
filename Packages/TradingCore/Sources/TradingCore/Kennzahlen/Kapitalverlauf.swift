import Foundation

/// Kontostand nach jedem Trade, Drawdown und Serien (R5, Kapitel 08 Abschnitt 4).
/// Trades werden nach Schlusszeit sortiert, bei gleicher Zeit nach ID.
public struct Kapitalverlauf: Sendable, Equatable {
    /// Kontostand nach jedem Trade.
    public var punkte: [Decimal]
    /// Größter Rückgang vom bisherigen Hoch, positiv.
    public var maxDrawdown: Decimal
    /// Rückgang bezogen auf das Hoch davor. `nil` ohne positives Startkapital.
    public var maxDrawdownProzent: Decimal?
    public var laengsteGewinnserie: Int
    public var laengsteVerlustserie: Int

    public init(trades: [Trade], startkapital: Decimal = 0) {
        let sortiert = trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
        var stand = startkapital
        var hoch = startkapital
        var dd: Decimal = 0
        var ddProzent: Decimal? = nil
        var gewinnSerie = 0, verlustSerie = 0
        punkte = []
        laengsteGewinnserie = 0
        laengsteVerlustserie = 0
        for trade in sortiert {
            stand += trade.netProfit
            punkte.append(stand)
            if stand > hoch { hoch = stand }
            if hoch - stand > dd {
                dd = hoch - stand
                ddProzent = hoch > 0 && startkapital > 0 ? dd / hoch : nil
            }
            gewinnSerie = trade.outcome == .win ? gewinnSerie + 1 : 0
            verlustSerie = trade.outcome == .loss ? verlustSerie + 1 : 0
            laengsteGewinnserie = max(laengsteGewinnserie, gewinnSerie)
            laengsteVerlustserie = max(laengsteVerlustserie, verlustSerie)
        }
        maxDrawdown = dd
        maxDrawdownProzent = ddProzent
    }
}
