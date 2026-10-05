import Foundation
import TradingQuotes

/// Eingabe „Wert hinzufügen“ im Kurschart (Tim 05.10.2026): Ergebnis ist das Symbol in Journal-Schreibweise,
/// unter dem der Kursdienst Tageskerzen lädt, oder eine Meldung für den Nutzer.
enum Chartwerteingabe: Equatable {
    case wert(String)
    case fehler(String)

    /// Krypto als Paar oder Kürzel über Kraken (ohne Schlüssel), US-Aktien als Kürzel über Alpaca (mit Schlüssel).
    /// CFDs und Devisen haben keine freie Quelle.
    static func pruefe(_ eingabe: String, alpacaSchluessel: Bool) -> Chartwerteingabe {
        let roh = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = roh.uppercased()
        guard !text.isEmpty else {
            return .fehler(String(localized: "Bitte einen Wert eingeben, etwa BTC/EUR oder AAPL."))
        }
        if case .zuordnung(let z) = Kurszuordner.vorschlag(fuer: text), z.quelle == "kraken" {
            return .wert(z.quellSymbol)
        }
        let ticker = text.hasSuffix(".US") ? String(text.dropLast(3)) : text
        if (1...5).contains(ticker.count), ticker.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == ".") }) {
            guard alpacaSchluessel else {
                return .fehler(String(localized: "US-Aktien laufen über Alpaca und brauchen dort einen kostenlosen Schlüssel: Einstellungen › Kurse."))
            }
            return .wert(ticker + ".US")
        }
        return .fehler(String(localized: "„\(roh)“ hat keine freie Kursquelle. Möglich sind Krypto wie BTC/EUR oder ETH/USD und US-Aktien wie AAPL."))
    }

    /// Symbole der Merkliste, soweit sie eine freie Quelle haben; US-Aktien nur mit Alpaca-Schlüssel.
    static func ausMerkliste(_ begriffe: [String], alpacaSchluessel: Bool) -> [String] {
        begriffe.compactMap { begriff in
            if case .wert(let symbol) = pruefe(begriff, alpacaSchluessel: alpacaSchluessel) { return symbol }
            return nil
        }
    }

    /// Auswahl im Kurschart: erst Werte aus dem Journal, dann eigene, dann die Merkliste; jeder Wert einmal.
    static func liste(journal: [String], eigene: [String], merkliste: [String]) -> [String] {
        var gesehen: Set<String> = []
        return (journal + eigene + merkliste).filter { gesehen.insert($0).inserted }
    }
}
