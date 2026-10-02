import Foundation

/// Liest Zeitangaben der Feeds und Schnittstellen.
/// RSS: RFC 822/2822 („Tue, 29 Sep 2026 19:25:00 +0200“, „Thu, 01 Oct 2026 07:35:04 GMT“).
/// Atom, Alpaca, Marketaux: ISO 8601, auch mit sechs Nachkommastellen („2024-11-08T01:24:00.000000Z“).
public enum Zeitleser {
    static let rfcFormate = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm Z",
        "EEE, dd MMM yyyy HH:mm zzz",
        "dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss zzz"
    ]

    public static func lies(_ text: String) -> Date? {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roh.isEmpty else { return nil }
        if let iso = iso8601(roh) { return iso }
        let formatierer = DateFormatter()
        formatierer.locale = Locale(identifier: "en_US_POSIX")
        formatierer.timeZone = TimeZone(identifier: "UTC")
        for format in rfcFormate {
            formatierer.dateFormat = format
            if let datum = formatierer.date(from: roh) { return datum }
        }
        return nil
    }

    /// ISO 8601 mit beliebig vielen Nachkommastellen; gekürzt auf Millisekunden.
    static func iso8601(_ text: String) -> Date? {
        guard text.count >= 19, text.dropFirst(4).first == "-", text.dropFirst(10).first == "T" else { return nil }
        var normal = text
        if let punkt = text.firstIndex(of: ".") {
            let nachPunkt = text[text.index(after: punkt)...]
            let ziffern = nachPunkt.prefix(while: { $0.isNumber })
            let rest = nachPunkt.dropFirst(ziffern.count)
            let ms = String((ziffern + "000").prefix(3))
            normal = String(text[..<punkt]) + "." + ms + rest
        }
        let formatierer = ISO8601DateFormatter()
        formatierer.formatOptions = normal.contains(".")
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatierer.date(from: normal)
    }

    /// UTC ohne Zeitzone, wie Marketaux `published_after` es erwartet („2026-10-02T06:00:00“).
    static func utcOhneZone(_ datum: Date) -> String {
        let formatierer = DateFormatter()
        formatierer.locale = Locale(identifier: "en_US_POSIX")
        formatierer.timeZone = TimeZone(identifier: "UTC")
        formatierer.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatierer.string(from: datum)
    }

    static func iso(_ datum: Date) -> String {
        let formatierer = ISO8601DateFormatter()
        formatierer.formatOptions = [.withInternetDateTime]
        return formatierer.string(from: datum)
    }
}
