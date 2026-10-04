import Foundation

/// Ein Kontoauszug, den ein MetaTrader-4-Broker per Mail verschickt
/// (Daily Confirmation oder Monthly Statement). Testdaten: erfundene Beispielauszüge
/// in Tests/TradingCoreTests/Fixtures/MT4.
public struct MT4Statement: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case daily
        case monthly
    }

    public var kind: Kind
    public var broker: String
    public var accountNumber: String
    public var accountName: String
    /// Zeitzone des Handelsservers, mit der alle Zeiten nach UTC umgerechnet wurden.
    public var serverZeitzone: TimeZone
    /// Stichzeitpunkt des Auszugs (Kopfzeile, Serverzeit umgerechnet).
    public var reportTime: Date
    public var closedPositions: [ClosedPosition]
    public var cancelledOrders: [CancelledOrder]
    public var openPositions: [OpenPosition]
    public var workingOrders: [WorkingOrder]
    /// Summenzeile unter „Closed Transactions“, wie im Auszug gedruckt.
    public var closedTotals: Totals
    /// Summenzeile unter „Open Trades“, wie im Auszug gedruckt.
    public var openTotals: Totals
    /// „Closed Trade P/L“ unter den geschlossenen Positionen.
    public var closedTradePL: Decimal
    /// „Floating P/L“ unter den offenen Positionen.
    public var floatingPL: Decimal
    public var summary: AccountSummary
}

extension MT4Statement {
    /// Liest einen Auszug.
    /// - Parameter serverZeitzone: Zeitzone des Handelsservers. Steht nicht im Auszug,
    ///   deshalb fragt die App sie beim Import ab.
    public static func parse(html: String, serverZeitzone: TimeZone) throws -> MT4Statement {
        let titel = HTMLTabelle.titel(html) ?? ""
        let kind: Kind
        if titel.contains("Daily Confirmation") { kind = .daily }
        else if titel.contains("Monthly Statement") { kind = .monthly }
        else { throw MT4ImportFehler.keinMT4Auszug }

        var leser = MT4Zeilenleser(zeitzone: serverZeitzone)
        for zeile in HTMLTabelle.zeilen(html) {
            try leser.lies(zeile)
        }

        func betrag(_ werte: [String: String], _ name: String) throws -> Decimal {
            guard let text = werte[name] else { throw MT4ImportFehler.fehlenderWert(name) }
            return try MT4Werte.zahl(text)
        }
        func summe(_ zellen: [String]?, _ name: String) throws -> Totals {
            guard let zellen, zellen.count == 3 else { throw MT4ImportFehler.fehlenderWert(name) }
            return Totals(commission: try MT4Werte.zahl(zellen[0]),
                          swap: try MT4Werte.zahl(zellen[1]),
                          profit: try MT4Werte.zahl(zellen[2]))
        }

        let k = leser.konto
        guard let nummer = k["A/C No"], let name = k["Name"], let stichtag = leser.kopfzeit else {
            throw MT4ImportFehler.fehlenderWert("Kopfzeile")
        }
        let s = leser.uebersicht
        let summary = AccountSummary(
            previousBalance: try s["Previous Ledger Balance"].map(MT4Werte.zahl),
            closedTradePL: try betrag(s, "Closed Trade P/L"),
            depositWithdrawal: try betrag(s, "Deposit/Withdrawal"),
            balance: try betrag(s, "Balance"),
            floatingPL: try betrag(s, "Floating P/L"),
            equity: try betrag(s, "Equity"),
            creditFacility: try betrag(s, "Total Credit Facility"),
            marginRequirement: try betrag(s, "Margin Requirement"),
            availableMargin: try betrag(s, "Available Margin")
        )
        return MT4Statement(
            kind: kind,
            broker: HTMLTabelle.ersterFetterText(html) ?? "",
            accountNumber: nummer,
            accountName: name,
            serverZeitzone: serverZeitzone,
            reportTime: try MT4Werte.berichtszeit(stichtag, zeitzone: serverZeitzone),
            closedPositions: leser.geschlossen,
            cancelledOrders: leser.geloescht,
            openPositions: leser.offen,
            workingOrders: leser.wartend,
            closedTotals: try summe(leser.summen["Closed Transactions"], "Summe Closed Transactions"),
            openTotals: try summe(leser.summen["Open Trades"], "Summe Open Trades"),
            closedTradePL: try betrag(leser.werte["Closed Transactions"] ?? [:], "Closed Trade P/L"),
            floatingPL: try betrag(leser.werte["Open Trades"] ?? [:], "Floating P/L"),
            summary: summary
        )
    }
}
