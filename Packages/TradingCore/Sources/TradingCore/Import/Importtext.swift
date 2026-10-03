import Foundation

/// Text einer Importdatei, gleich in welcher Kodierung sie gespeichert ist.
/// Broker liefern UTF-8, MetaTrader 5 UTF-16; wer eine CSV in Excel öffnet und neu speichert,
/// bekommt unter Windows meist Windows-1252 („ANSI“) oder „Unicode-Text“ (UTF-16).
public enum Importtext {
    public enum Kodierung: String, Sendable, Equatable {
        case utf8, utf16LE, utf16BE, windows1252
    }

    /// Text der Datei; `nil` bei Binärdaten (etwa einer Excel- oder ZIP-Datei).
    public static func lies(_ daten: Data) -> String? { erkenne(daten)?.text }

    /// Text und erkannte Kodierung. Reihenfolge: Byte-Order-Mark, UTF-16 ohne Mark, UTF-8, Windows-1252.
    /// Ein Byte-Order-Mark am Anfang fällt immer weg.
    public static func erkenne(_ daten: Data) -> (text: String, kodierung: Kodierung)? {
        let bytes = [UInt8](daten)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(bytes: bytes.dropFirst(3), encoding: .utf8).map { (ohneMark($0), .utf8) }
        }
        if bytes.starts(with: [0xFF, 0xFE]) { return utf16(bytes.dropFirst(2), kleinesEnde: true) }
        if bytes.starts(with: [0xFE, 0xFF]) { return utf16(bytes.dropFirst(2), kleinesEnde: false) }
        // Ohne Mark: Ist in der Probe mindestens jedes vierte Byte an ungerader (gerader) Stelle null,
        // ist es UTF-16 Little (Big) Endian. Text in UTF-8 oder Windows-1252 enthält keine Nullbytes.
        let probe = Array(bytes.prefix(200))
        if probe.count >= 20 {
            let ungerade = stride(from: 1, to: probe.count, by: 2).filter { probe[$0] == 0 }.count
            let gerade = stride(from: 0, to: probe.count, by: 2).filter { probe[$0] == 0 }.count
            if ungerade >= probe.count / 4, ungerade > gerade { return utf16(bytes[...], kleinesEnde: true) }
            if gerade >= probe.count / 4, gerade > ungerade { return utf16(bytes[...], kleinesEnde: false) }
        }
        if bytes.contains(0) { return nil }
        if let text = String(bytes: bytes, encoding: .utf8) { return (ohneMark(text), .utf8) }
        return (ohneMark(windows1252(bytes)), .windows1252)
    }

    private static func utf16(_ bytes: ArraySlice<UInt8>, kleinesEnde: Bool) -> (text: String, kodierung: Kodierung)? {
        guard bytes.count % 2 == 0 else { return nil }
        var einheiten: [UInt16] = []
        einheiten.reserveCapacity(bytes.count / 2)
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let a = UInt16(bytes[i]), b = UInt16(bytes[i + 1])
            einheiten.append(kleinesEnde ? a | b << 8 : a << 8 | b)
            i += 2
        }
        // Ungültige Ersatzpaare sind ein Zeichen, dass es doch kein UTF-16 ist.
        var text = ""
        var dekoder = UTF16()
        var iterator = einheiten.makeIterator()
        while true {
            switch dekoder.decode(&iterator) {
            case .scalarValue(let s): text.unicodeScalars.append(s)
            case .emptyInput: return (ohneMark(text), kleinesEnde ? .utf16LE : .utf16BE)
            case .error: return nil
            }
        }
    }

    /// Windows-1252: wie ISO 8859-1, nur 0x80 bis 0x9F tragen Zeichen wie € und „“.
    /// Die fünf dort unbelegten Bytes bleiben als gleichwertiger Unicode-Wert stehen.
    static func windows1252(_ bytes: [UInt8]) -> String {
        var text = ""
        text.unicodeScalars.reserveCapacity(bytes.count)
        for byte in bytes {
            if (0x80...0x9F).contains(byte), let wert = sonderzeichen1252[byte] {
                text.unicodeScalars.append(Unicode.Scalar(wert)!)
            } else {
                text.unicodeScalars.append(Unicode.Scalar(byte))
            }
        }
        return text
    }

    static let sonderzeichen1252: [UInt8: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
        0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D,
        0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
        0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    private static func ohneMark(_ text: String) -> String {
        text.unicodeScalars.first == "\u{FEFF}" ? String(String.UnicodeScalarView(text.unicodeScalars.dropFirst())) : text
    }
}
