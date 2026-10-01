import Foundation
import GRDB
import TradingCore

// Tabellenzeilen der Datenbank. Sie bleiben intern: Nach außen gibt der Speicher die Typen
// aus TradingCore zurück, damit Kennzahlen und Oberfläche nur ein Datenmodell kennen.

/// Ein Handelskonto bei einem Broker.
public struct Konto: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "konto"
    public var id: Int64?
    public var broker: String
    public var kontonummer: String
    public var kontoname: String
    /// ISO-Währungscode, z. B. „EUR“.
    public var waehrung: String

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Eine importierte Datei.
public struct Importlauf: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "importlauf"
    public var id: Int64?
    public var kontoId: Int64
    /// Welcher Importer die Datei gelesen hat, z. B. „MT4-Auszug“.
    public var importer: String
    /// Version des Rechenkerns beim Import (`TradingCore.version`).
    public var importerVersion: String
    public var dateiname: String
    /// SHA-256 des Dateiinhalts als Hex-Text.
    public var dateiHash: String
    /// Inhalt der Originaldatei.
    public var datei: Data
    /// „daily“ oder „monthly“.
    public var art: String
    public var stichtag: Date
    /// Bezeichner der Serverzeitzone, mit der die Zeiten nach UTC umgerechnet wurden.
    public var serverZeitzone: String
    public var importiertAm: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct KontostandZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kontostand"
    var importlaufId: Int64
    var previousBalance: Decimal?
    var closedTradePL: Decimal
    var depositWithdrawal: Decimal
    var balance: Decimal
    var floatingPL: Decimal
    var equity: Decimal
    var creditFacility: Decimal
    var marginRequirement: Decimal
    var availableMargin: Decimal

    init(importlaufId: Int64, _ s: AccountSummary) {
        self.importlaufId = importlaufId
        previousBalance = s.previousBalance
        closedTradePL = s.closedTradePL
        depositWithdrawal = s.depositWithdrawal
        balance = s.balance
        floatingPL = s.floatingPL
        equity = s.equity
        creditFacility = s.creditFacility
        marginRequirement = s.marginRequirement
        availableMargin = s.availableMargin
    }

    var modell: AccountSummary {
        AccountSummary(previousBalance: previousBalance, closedTradePL: closedTradePL,
                       depositWithdrawal: depositWithdrawal, balance: balance, floatingPL: floatingPL,
                       equity: equity, creditFacility: creditFacility,
                       marginRequirement: marginRequirement, availableMargin: availableMargin)
    }
}

struct GeschlossenZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "geschlossenePosition"
    var kontoId: Int64
    var importlaufId: Int64
    var ticket: String
    var rohzeile: [String]
    var side: String
    var lots: Decimal
    var symbol: String
    var openTime: Date
    var openPrice: Decimal
    var stopLoss: Decimal?
    var takeProfit: Decimal?
    var closeTime: Date
    var closePrice: Decimal
    var commission: Decimal
    var swap: Decimal
    var profit: Decimal

    init(kontoId: Int64, importlaufId: Int64, _ p: ClosedPosition) {
        self.kontoId = kontoId
        self.importlaufId = importlaufId
        ticket = p.ticket
        rohzeile = p.rohzeile
        side = p.side.rawValue
        lots = p.lots
        symbol = p.symbol
        openTime = p.openTime
        openPrice = p.openPrice
        stopLoss = p.stopLoss
        takeProfit = p.takeProfit
        closeTime = p.closeTime
        closePrice = p.closePrice
        commission = p.commission
        swap = p.swap
        profit = p.profit
    }

    func modell() throws -> ClosedPosition {
        ClosedPosition(ticket: ticket, rohzeile: rohzeile, side: try seite(side), lots: lots, symbol: symbol,
                       openTime: openTime, openPrice: openPrice, stopLoss: stopLoss,
                       takeProfit: takeProfit, closeTime: closeTime, closePrice: closePrice,
                       commission: commission, swap: swap, profit: profit)
    }
}

struct GeloeschtZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "geloeschteOrder"
    var kontoId: Int64
    var importlaufId: Int64
    var ticket: String
    var rohzeile: [String]
    var type: String
    var lots: Decimal
    var symbol: String
    var placedAt: Date
    var orderPrice: Decimal
    var stopLoss: Decimal?
    var takeProfit: Decimal?
    var cancelledAt: Date
    var marketPrice: Decimal

    init(kontoId: Int64, importlaufId: Int64, _ o: CancelledOrder) {
        self.kontoId = kontoId
        self.importlaufId = importlaufId
        ticket = o.ticket
        rohzeile = o.rohzeile
        type = o.type.rawValue
        lots = o.lots
        symbol = o.symbol
        placedAt = o.placedAt
        orderPrice = o.orderPrice
        stopLoss = o.stopLoss
        takeProfit = o.takeProfit
        cancelledAt = o.cancelledAt
        marketPrice = o.marketPrice
    }

    func modell() throws -> CancelledOrder {
        CancelledOrder(ticket: ticket, rohzeile: rohzeile, type: try auftragsart(type), lots: lots, symbol: symbol,
                       placedAt: placedAt, orderPrice: orderPrice, stopLoss: stopLoss,
                       takeProfit: takeProfit, cancelledAt: cancelledAt, marketPrice: marketPrice)
    }
}

struct OffenZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "offenePosition"
    var importlaufId: Int64
    var ticket: String
    var rohzeile: [String]
    var side: String
    var lots: Decimal
    var symbol: String
    var openTime: Date
    var openPrice: Decimal
    var stopLoss: Decimal?
    var takeProfit: Decimal?
    var currentPrice: Decimal
    var commission: Decimal
    var swap: Decimal
    var profit: Decimal

    init(importlaufId: Int64, _ p: OpenPosition) {
        self.importlaufId = importlaufId
        ticket = p.ticket
        rohzeile = p.rohzeile
        side = p.side.rawValue
        lots = p.lots
        symbol = p.symbol
        openTime = p.openTime
        openPrice = p.openPrice
        stopLoss = p.stopLoss
        takeProfit = p.takeProfit
        currentPrice = p.currentPrice
        commission = p.commission
        swap = p.swap
        profit = p.profit
    }

    func modell() throws -> OpenPosition {
        OpenPosition(ticket: ticket, rohzeile: rohzeile, side: try seite(side), lots: lots, symbol: symbol,
                     openTime: openTime, openPrice: openPrice, stopLoss: stopLoss,
                     takeProfit: takeProfit, currentPrice: currentPrice,
                     commission: commission, swap: swap, profit: profit)
    }
}

struct WartendZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "wartendeOrder"
    var importlaufId: Int64
    var ticket: String
    var rohzeile: [String]
    var type: String
    var lots: Decimal
    var symbol: String
    var placedAt: Date
    var orderPrice: Decimal
    var stopLoss: Decimal?
    var takeProfit: Decimal?
    var marketPrice: Decimal

    init(importlaufId: Int64, _ o: WorkingOrder) {
        self.importlaufId = importlaufId
        ticket = o.ticket
        rohzeile = o.rohzeile
        type = o.type.rawValue
        lots = o.lots
        symbol = o.symbol
        placedAt = o.placedAt
        orderPrice = o.orderPrice
        stopLoss = o.stopLoss
        takeProfit = o.takeProfit
        marketPrice = o.marketPrice
    }

    func modell() throws -> WorkingOrder {
        WorkingOrder(ticket: ticket, rohzeile: rohzeile, type: try auftragsart(type), lots: lots, symbol: symbol,
                     placedAt: placedAt, orderPrice: orderPrice, stopLoss: stopLoss,
                     takeProfit: takeProfit, marketPrice: marketPrice)
    }
}

private func seite(_ text: String) throws -> Side {
    guard let wert = Side(rawValue: text) else { throw SpeicherFehler.unbekannterWert(text) }
    return wert
}

private func auftragsart(_ text: String) throws -> OrderType {
    guard let wert = OrderType(rawValue: text) else { throw SpeicherFehler.unbekannterWert(text) }
    return wert
}
