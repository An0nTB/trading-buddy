import Foundation
import GRDB
import TradingCore

/// Alle geschlossenen Trades mit offenen Duplikatverdachten. Die Liste bleibt vollständig; Summen und
/// Kennzahlen verwenden ausschließlich `auswertbareTrades`, bis der Nutzer einen Hand-Trade bestätigt.
public struct TradeBestand: Sendable {
    public var trades: [Trade]
    /// Hand-Ticket auf mögliche Broker-Tickets, sortiert. Es wird niemals automatisch zusammengelegt.
    public var moeglicheDuplikate: [String: [String]]

    public var auswertbareTrades: [Trade] {
        trades.filter { moeglicheDuplikate[$0.id] == nil }
    }
}

extension Journal {
    /// Prüft den aktuellen Bestand in einer Lesetransaktion: nach jedem Import, Handeintrag und beim Start.
    /// So bleiben auch CSV-Trades aus der Positionsbildung und bereits vorhandene Überschneidungen erfasst.
    /// Verdachte werden abgeleitet; nur die ausdrückliche Entscheidung „eigenständig“ wird gespeichert.
    public func tradeBestand(konto: Konto, zeitzone: TimeZone = .current) throws -> TradeBestand {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        return try lies { db in
            let zeilen = try GeschlossenZeile.filter(Column("kontoId") == kontoId)
                .order(Column("closeTime"), Column("ticket")).fetchAll(db)
            let handLauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(kontoId)).fetchOne(db)
            let handTickets = Set(zeilen.filter { $0.importlaufId == handLauf?.id }.map(\.ticket))
            let ohneSchlusszeit = Set(zeilen.filter { !$0.ausstiegszeitBekannt }.map(\.ticket))
            let bestaetigt = Set(try String.fetchAll(db, sql: """
                SELECT ticket FROM handtradeEigenstaendig WHERE kontoId = ?
                """, arguments: [kontoId]))
            var trades = try zeilen.map { zeile in
                var trade = Trade(try zeile.modell())
                trade.markterwartung = try zeile.erwartung()
                if let produkt = Hebelprodukt.erkenne(trade.symbol) {
                    trade.basiswert = produkt.basiswert
                    if zeile.markterwartung == nil { trade.markterwartung = produkt.markterwartung }
                }
                return trade
            }
            let ausfuehrungen = try AusfuehrungZeile.filter(Column("kontoId") == kontoId)
                .order(Column("zeit"), Column("vorgangId")).fetchAll(db).map { try $0.modell() }
            let massnahmen = try KapitalmassnahmeZeile.filter(Column("kontoId") == kontoId)
                .order(Column("zeit"), Column("vorgangId")).fetchAll(db).map { try $0.modell() }
            trades += Positionsbildung.bilde(ausfuehrungen, kapitalmassnahmen: massnahmen).trades
            let broker = trades.filter { !handTickets.contains($0.id) && !ohneSchlusszeit.contains($0.id) }
            var kalender = Calendar(identifier: .gregorian)
            kalender.timeZone = zeitzone
            var verdacht: [String: [String]] = [:]
            for hand in trades where handTickets.contains(hand.id)
                && !bestaetigt.contains(hand.id) && !ohneSchlusszeit.contains(hand.id) {
                let tickets = broker.filter {
                    Self.moeglichesDuplikat(hand, $0, kalender: kalender, waehrung: konto.waehrung)
                }.map(\.id).sorted()
                if !tickets.isEmpty { verdacht[hand.id] = tickets }
            }
            return TradeBestand(trades: trades, moeglicheDuplikate: verdacht)
        }
    }

    /// Bestätigt einen geschlossenen Hand-Trade als eigenständig. Erneute Importe erhalten die Entscheidung;
    /// Bearbeiten oder Löschen des Hand-Trades verwirft sie mit der ersetzten Positionszeile.
    public func behalteHandtrade(konto: Konto, ticket: String) throws {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        try schreibe { db in
            guard let lauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(kontoId)).fetchOne(db),
                  try GeschlossenZeile.filter(Column("kontoId") == kontoId && Column("ticket") == ticket
                    && Column("importlaufId") == lauf.id!).fetchOne(db) != nil else {
                throw SpeicherFehler.ungueltigerWert("Trade \(ticket) ist kein geschlossener Hand-Trade")
            }
            try db.execute(sql: """
                INSERT OR IGNORE INTO handtradeEigenstaendig (kontoId, ticket) VALUES (?, ?)
                """, arguments: [kontoId, ticket])
        }
    }

    private static func moeglichesDuplikat(_ hand: Trade, _ broker: Trade, kalender: Calendar,
                                          waehrung: String) -> Bool {
        func schluessel(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        }
        func instrumente(_ trade: Trade) -> Set<String> {
            Set([trade.symbol, trade.basiswert].compactMap { $0 }.map(schluessel).filter { !$0.isEmpty })
        }
        // Relativ statt pauschal ein Cent: auch bei kleinen Devisen- und Scheinpreisen eng bleiben.
        func gleicherKurs(_ a: Decimal, _ b: Decimal) -> Bool {
            abs(a - b) <= max(abs(a), abs(b)) / 10_000
        }
        return !instrumente(hand).isDisjoint(with: instrumente(broker))
            && hand.richtung == broker.richtung && hand.lots == broker.lots
            && hand.waehrung(kontowaehrung: waehrung) == broker.waehrung(kontowaehrung: waehrung)
            && hand.eroeffnungstag(kalender) == broker.eroeffnungstag(kalender)
            && hand.schlusstag(kalender) == broker.schlusstag(kalender)
            && gleicherKurs(hand.openPrice, broker.openPrice) && gleicherKurs(hand.closePrice, broker.closePrice)
    }
}
