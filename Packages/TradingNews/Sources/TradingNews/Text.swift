import Foundation

/// Bereinigt Anrisse: ohne HTML, Entitäten aufgelöst, Leerraum zusammengefasst, gekürzt.
enum Text {
    /// Höchstlänge eines Anrisses in Zeichen. Mehr als ein Anriss soll die App nicht zeigen (Lizenz, R6).
    static let anrissLaenge = 300

    static func anriss(_ roh: String?) -> String? {
        guard let roh else { return nil }
        let text = gekuerzt(bereinigt(roh), auf: anrissLaenge)
        return text.isEmpty ? nil : text
    }

    static func bereinigt(_ roh: String) -> String {
        zusammengefasst(entitaetenAufgeloest(ohneTags(roh)))
    }

    static func ohneTags(_ text: String) -> String {
        var ergebnis = ""
        var inTag = false
        for zeichen in text {
            if zeichen == "<" { inTag = true; ergebnis.append(" "); continue }
            if zeichen == ">" && inTag { inTag = false; continue }
            if !inTag { ergebnis.append(zeichen) }
        }
        return ergebnis
    }

    static let benannte: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "euro": "€", "ndash": "–", "mdash": "—", "hellip": "…", "bdquo": "„", "ldquo": "“", "rdquo": "”",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚"
    ]

    static func entitaetenAufgeloest(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var ergebnis = ""
        var rest = Substring(text)
        while let und = rest.firstIndex(of: "&") {
            ergebnis += rest[..<und]
            let nach = rest[rest.index(after: und)...]
            if let semi = nach.prefix(10).firstIndex(of: ";") {
                let name = String(nach[..<semi])
                if let ersatz = aufgeloest(name) {
                    ergebnis += ersatz
                    rest = nach[nach.index(after: semi)...]
                    continue
                }
            }
            ergebnis += "&"
            rest = nach
        }
        ergebnis += rest
        return ergebnis
    }

    private static func aufgeloest(_ name: String) -> String? {
        if let benannt = benannte[name] { return benannt }
        guard name.hasPrefix("#") else { return nil }
        let zahl = name.dropFirst()
        let wert: UInt32?
        if zahl.hasPrefix("x") || zahl.hasPrefix("X") {
            wert = UInt32(zahl.dropFirst(), radix: 16)
        } else {
            wert = UInt32(zahl)
        }
        guard let wert, let skalar = Unicode.Scalar(wert) else { return nil }
        return String(Character(skalar))
    }

    static func zusammengefasst(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Kürzt an einer Wortgrenze und hängt „…“ an.
    static func gekuerzt(_ text: String, auf laenge: Int) -> String {
        guard text.count > laenge else { return text }
        let schnitt = text.prefix(laenge)
        let bisWort = schnitt.lastIndex(of: " ").map { schnitt[..<$0] } ?? schnitt
        return bisWort.trimmingCharacters(in: .whitespaces) + "…"
    }
}
