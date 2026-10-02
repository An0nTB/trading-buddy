import Foundation
import TradingCore
import TradingNews
import TradingQuotes

/// Bildet eigene Trades und Meldungen auf die Chart-Typen aus TradingQuotes ab. Liest nur: Trades aus dem
/// AppModell, Meldungen über die öffentliche Liste des Nachrichtendiensts, Kerzen aus dem Kursdienst.
enum KurschartQuellen {
    /// Gängige Namen zu Krypto-Kürzeln, damit Meldungen ohne Kürzel („Bitcoin fällt …“) ebenfalls passen.
    static let kryptoNamen: [String: String] = [
        "BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana", "XRP": "Ripple", "ADA": "Cardano",
        "DOGE": "Dogecoin", "DOT": "Polkadot", "LTC": "Litecoin", "LINK": "Chainlink", "AVAX": "Avalanche"
    ]

    /// Ein- und Ausstieg je Trade dieses Journal-Symbols; das Ergebnis steht am Ausstieg.
    static func marken(_ trades: [Trade], symbol: String) -> [Chartmarke] {
        trades.filter { $0.symbol == symbol }.flatMap { trade -> [Chartmarke] in
            let kauf = trade.side == .buy
            return [Chartmarke(tradeID: trade.id, art: .einstieg, zeit: trade.openTime, preis: trade.openPrice, kauf: kauf),
                    Chartmarke(tradeID: trade.id, art: .ausstieg, zeit: trade.closeTime, preis: trade.closePrice,
                               kauf: kauf, ergebnis: trade.netProfit)]
        }
    }

    /// Suchbegriffe wie auf der Nachrichtenseite: Kürzel, bei Krypto zusätzlich der Name.
    static func begriffe(_ zuordnung: Kurszuordnung) -> [Merkbegriff] {
        guard zuordnung.quelle == "kraken" else { return [Merkbegriff(art: .symbol, text: zuordnung.quellSymbol)] }
        let basis = String(zuordnung.quellSymbol.split(separator: "/").first ?? "")
        var begriffe = [Merkbegriff(art: .symbol, text: basis)]
        if let name = kryptoNamen[basis] { begriffe.append(Merkbegriff(art: .name, text: name)) }
        return begriffe
    }

    /// Meldungen zu diesem Wert, mit derselben Zuordnung wie die Merkliste (TradingNews).
    static func meldungen(_ alle: [Meldung], zuordnung: Kurszuordnung) -> [Chartmeldung] {
        let begriffe = begriffe(zuordnung)
        return alle.filter { meldung in begriffe.contains { Zuordnung.trifft(meldung, $0) } }
            .map { Chartmeldung(id: $0.id, zeit: $0.zeit, titel: $0.titel, quelle: $0.quelle, link: $0.link) }
    }

    /// Journal-Symbole mit freier Kursquelle (Krypto über Kraken, US-Aktien über Alpaca), meist gehandelte zuerst.
    @MainActor
    static func symbole(_ trades: [Trade], kurse: Kursdienst) -> [String] {
        var anzahl: [String: Int] = [:]
        for trade in trades { anzahl[trade.symbol, default: 0] += 1 }
        return anzahl.keys
            .filter { symbol in
                guard let quelle = kurse.zuordnung(fuer: symbol).zuordnung?.quelle else { return false }
                return quelle == "kraken" || quelle == "alpaca"
            }
            .sorted { (anzahl[$0] ?? 0, $1) > (anzahl[$1] ?? 0, $0) }
    }
}
