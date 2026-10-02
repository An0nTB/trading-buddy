import Foundation

/// Ein Kurs, so wie eine Quelle ihn meldet. Mindestens einer von `letzter`, `geld`, `brief` ist gesetzt.
public struct Kurs: Sendable, Equatable {
    /// Symbol in der Schreibweise der Quelle, etwa "BTC/EUR" (Kraken) oder "AAPL" (Alpaca).
    public var symbol: String
    /// Letzter Abschluss.
    public var letzter: Decimal?
    /// Bester Kaufkurs im Buch (bid): zu diesem Kurs schließt man eine Kaufposition.
    public var geld: Decimal?
    /// Bester Verkaufskurs im Buch (ask): zu diesem Kurs schließt man eine Verkaufsposition.
    public var brief: Decimal?
    /// Zeit laut Quelle, ersatzweise Empfangszeit.
    public var zeit: Date
    public var quelle: String
    public var verzoegerung: Verzoegerung

    public init(symbol: String, letzter: Decimal? = nil, geld: Decimal? = nil, brief: Decimal? = nil,
                zeit: Date, quelle: String, verzoegerung: Verzoegerung = .echtzeit) {
        self.symbol = symbol
        self.letzter = letzter
        self.geld = geld
        self.brief = brief
        self.zeit = zeit
        self.quelle = quelle
        self.verzoegerung = verzoegerung
    }

    /// Anzeigekurs: letzter Abschluss, sonst Mitte aus Geld und Brief, sonst die eine Seite, die es gibt.
    public var preis: Decimal? {
        if let letzter { return letzter }
        if let geld, let brief { return (geld + brief) / 2 }
        return geld ?? brief
    }

    /// Kurs, zu dem die Position jetzt schließen würde: Kauf zum Geldkurs, Verkauf zum Briefkurs.
    /// So rechnet auch MetaTrader den schwebenden Gewinn. Fehlt die Seite, gilt `preis`.
    public func bewertungskurs(kaufposition: Bool) -> Decimal? {
        (kaufposition ? geld : brief) ?? preis
    }

    /// Sekunden seit dem Kurs.
    public func alter(jetzt: Date) -> TimeInterval { jetzt.timeIntervalSince(zeit) }

    /// R1 Erfolgskriterium: Kursalter in der Anzeige unter 30 s. Bei verzögerten Quellen zählt der Verzug dazu.
    public func istVeraltet(jetzt: Date, grenze: TimeInterval = 30) -> Bool {
        alter(jetzt: jetzt) > grenze + verzoegerung.sekunden
    }
}

public enum Verzoegerung: Sendable, Equatable {
    case echtzeit
    case verzoegert(minuten: Int)

    var sekunden: TimeInterval {
        switch self {
        case .echtzeit: 0
        case .verzoegert(let minuten): TimeInterval(minuten * 60)
        }
    }
}

/// Zustand der Verbindung einer Quelle, für die Anzeige.
public enum Verbindungsstatus: Sendable, Equatable {
    case verbunden
    /// Getrennt; die Quelle verbindet sich nach einer Pause neu.
    case getrennt(grund: String)
    /// Endgültig beendet, kein neuer Versuch (Schlüssel fehlt oder falsch, Anbieter verweigert).
    case beendet(grund: String)
}

/// Was eine Quelle meldet.
public enum Quellereignis: Sendable, Equatable {
    case kurs(Kurs)
    case status(Verbindungsstatus)
}

/// Zahl aus JSON, als Text ("65000.1", Coinbase, Binance) oder als Zahl (65000.1, Kraken, Alpaca).
/// Zahlen gehen über die kürzeste Textform von Double, damit 0.1 als 0.1 ankommt und nicht als 0.1000000000000000055.
struct Zahl: Decodable, Sendable {
    let wert: Decimal

    init(from decoder: Decoder) throws {
        let behaelter = try decoder.singleValueContainer()
        let text: String
        if let s = try? behaelter.decode(String.self) {
            text = s
        } else {
            let zahl = try behaelter.decode(Double.self)
            text = "\(zahl)"
        }
        guard let wert = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(in: behaelter, debugDescription: "keine Zahl: \(text)")
        }
        self.wert = wert
    }
}

enum Zeitstempel {
    /// RFC 3339 mit beliebig vielen Nachkommastellen (Coinbase und Alpaca senden bis zu neun).
    /// Swift liest höchstens drei, deshalb wird gekürzt.
    static func lies(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let punkt = text.firstIndex(of: ".") else {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
        let nachPunkt = text[text.index(after: punkt)...]
        let ziffern = nachPunkt.prefix { $0.isNumber }
        let zone = nachPunkt.dropFirst(ziffern.count)
        let millis = String((ziffern + "000").prefix(3))
        return formatter.date(from: String(text[..<punkt]) + "." + millis + zone)
    }

    static func ausMillisekunden(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}

/// JSON-Text für Anfragen an die Anbieter; Schlüssel sortiert, damit Tests den Text vergleichen können.
func jsonText<T: Encodable>(_ wert: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let daten = (try? encoder.encode(wert)) ?? Data()
    return String(decoding: daten, as: UTF8.self)
}
