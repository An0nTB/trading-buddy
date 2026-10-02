import Foundation

extension Terminkalender {
    /// Währungen, für die Termine geführt werden.
    public static let gefuehrteWaehrungen: Set<String> = ["USD", "EUR", "GBP", "JPY", "CHF"]

    /// Gängige Index-CFD-Namen und ihre Währung (Einschätzung nach üblichen Broker-Symbolen).
    static let indizes: [(name: String, waehrung: String)] = [
        ("US30", "USD"), ("US100", "USD"), ("US500", "USD"), ("NAS100", "USD"), ("SPX500", "USD"),
        ("USTEC", "USD"), ("DJ30", "USD"), ("US2000", "USD"),
        ("GER40", "EUR"), ("GER30", "EUR"), ("DE40", "EUR"), ("DE30", "EUR"), ("EU50", "EUR"),
        ("EUSTX50", "EUR"), ("FRA40", "EUR"), ("F40", "EUR"),
        ("UK100", "GBP"), ("JP225", "JPY"), ("JPN225", "JPY"), ("SWI20", "CHF"), ("CH20", "CHF")
    ]

    /// Betroffene Währungen eines Symbols: Kürzel im Namen („EURUSD.m“ → EUR, USD; „BTCUSDT“ → USD)
    /// oder ein bekannter Index („GER40“ → EUR). Leer, wenn nichts passt; dann gilt kein Termin als betroffen.
    public static func waehrungen(symbol: String) -> Set<String> {
        let roh = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        var ergebnis = Set(gefuehrteWaehrungen.filter { roh.contains($0) })
        for index in indizes where roh.hasPrefix(index.name) {
            ergebnis.insert(index.waehrung)
        }
        return ergebnis
    }
}
