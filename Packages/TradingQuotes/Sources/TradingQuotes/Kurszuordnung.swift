import Foundation

/// Welche Quelle den Kurs für ein Symbol aus dem Journal liefert.
/// Die App speichert Zuordnungen als JSON; der Nutzer kann Vorschläge ändern und eigene anlegen.
public struct Kurszuordnung: Sendable, Equatable, Codable {
    /// Symbol so, wie es im Journal steht, etwa "BTC/EUR", "AAPL.US" oder "de40".
    public var journalSymbol: String
    /// `Kursquelle.id`, etwa "kraken".
    public var quelle: String
    /// Symbol in der Schreibweise der Quelle.
    public var quellSymbol: String
    /// Gesetzt, wenn der Kurs nur eine Näherung ist, etwa ein Basiswert statt des CFD-Kurses des Brokers.
    /// Die App zeigt den Text neben dem Kurs.
    public var naeherung: String?

    public init(journalSymbol: String, quelle: String, quellSymbol: String, naeherung: String? = nil) {
        self.journalSymbol = journalSymbol
        self.quelle = quelle
        self.quellSymbol = quellSymbol
        self.naeherung = naeherung
    }
}

/// Vorschlag für ein Journal-Symbol: eine Zuordnung oder der Grund, warum es keinen freien Kurs gibt.
public enum Zuordnungsvorschlag: Sendable, Equatable {
    case zuordnung(Kurszuordnung)
    case ohneQuelle(grund: String)
}

/// Schlägt Zuordnungen nach einfachen Regeln vor. Was nicht eindeutig ist, bekommt keinen Vorschlag;
/// der Nutzer ordnet es selbst zu (dann mit Hinweis „Näherung“, wenn es ein Basiswert ist).
public enum Kurszuordner {
    /// Bekannte Krypto-Kürzel. Bewusst kurz: Nur was Kraken sicher führt, bekommt einen Vorschlag.
    static let krypto: Set<String> = ["BTC", "ETH", "SOL", "XRP", "ADA", "DOT", "LTC", "DOGE", "LINK", "AVAX",
                                      "BCH", "XLM", "ATOM", "UNI", "MATIC", "POL", "TRX", "ETC", "XTZ", "ALGO"]
    /// Gegenwährungen, in denen Krypto-Paare gehandelt werden.
    static let gegenwaehrungen = ["USDT", "USDC", "EUR", "USD", "GBP", "CHF", "BTC", "ETH"]

    public static let grundCFD = "CFD oder Devisenpaar des Brokers: Jeder Broker stellt eigene Kurse, ein freier neutraler Kurs fehlt (R1). Eine eigene Zuordnung auf den Basiswert ist möglich und gilt als Näherung."
    public static let hinweisKryptoCFD = "Krypto-CFD des Brokers, Kurs von Kraken als Näherung."
    public static let grundUnbekannt = "Symbol nicht eindeutig erkannt. Bitte selbst zuordnen."
    public static let grundISIN = "ISIN ohne Börsenkürzel. Bitte das Kürzel selbst zuordnen (US-Aktien über Alpaca); deutsche Kurse sind noch nicht angebunden."

    public static func vorschlag(fuer journalSymbol: String) -> Zuordnungsvorschlag {
        let symbol = journalSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        if let paar = kryptoPaar(symbol) {
            // Kleingeschrieben heißt MetaTrader, also ein Krypto-CFD des Brokers: Börsenkurs nur als Näherung.
            let naeherung = istMetaTraderSymbol(journalSymbol) ? hinweisKryptoCFD : nil
            return .zuordnung(Kurszuordnung(journalSymbol: journalSymbol, quelle: "kraken",
                                            quellSymbol: paar.basis + "/" + paar.gegen, naeherung: naeherung))
        }
        if krypto.contains(symbol) {
            // Krypto ohne Gegenwährung (Bitpanda, Trade Republic): Konten in Euro.
            return .zuordnung(Kurszuordnung(journalSymbol: journalSymbol, quelle: "kraken", quellSymbol: symbol + "/EUR"))
        }
        if symbol.hasSuffix(".US") {
            let ticker = String(symbol.dropLast(3))
            if istTicker(ticker) {
                return .zuordnung(Kurszuordnung(journalSymbol: journalSymbol, quelle: "alpaca", quellSymbol: ticker))
            }
        }
        if istISIN(symbol) { return .ohneQuelle(grund: grundISIN) }
        if istMetaTraderSymbol(journalSymbol) { return .ohneQuelle(grund: grundCFD) }
        return .ohneQuelle(grund: grundUnbekannt)
    }

    /// "BTC/EUR", "BTC-EUR", "BTCEUR", "BTCUSDT".
    static func kryptoPaar(_ symbol: String) -> (basis: String, gegen: String)? {
        let ohneTrenner = symbol.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "-", with: "")
        for gegen in gegenwaehrungen where ohneTrenner.hasSuffix(gegen) {
            let basis = String(ohneTrenner.dropLast(gegen.count))
            if krypto.contains(basis), basis != gegen { return (basis: basis, gegen: gegen) }
        }
        return nil
    }

    static func istTicker(_ text: String) -> Bool {
        (1...5).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0 == ".") }
    }

    static func istISIN(_ text: String) -> Bool {
        text.count == 12 && text.prefix(2).allSatisfy { $0.isASCII && $0.isLetter }
            && text.dropFirst(2).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && text.last?.isNumber == true
    }

    /// MetaTrader schreibt Symbole klein, oft mit Endung des Brokers ("eurgbpc", "de40", "xauusd").
    static func istMetaTraderSymbol(_ text: String) -> Bool {
        !text.isEmpty && text == text.lowercased() && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }
    }
}
