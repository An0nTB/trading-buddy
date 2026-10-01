import Foundation

/// Liest Tabellenzeilen aus einfachem HTML, wie MetaTrader-Auszüge es enthalten.
/// Kein vollständiger HTML-Parser: Er kennt nur `<tr>` und `<td>`, entfernt alle
/// anderen Tags und löst die üblichen Entities auf. Läuft auf Apple-Systemen und Linux.
enum HTMLTabelle {
    /// Alle Zeilen als Liste ihrer Zelltexte. Leerraum ist zusammengefasst und getrimmt.
    static func zeilen(_ html: String) -> [[String]] {
        var ergebnis: [[String]] = []
        var rest = html[...]
        while let start = rest.range(of: "<tr", options: .caseInsensitive) {
            let inhalt = rest[start.upperBound...]
            let ende = min(
                inhalt.range(of: "</tr>", options: .caseInsensitive)?.lowerBound ?? inhalt.endIndex,
                inhalt.range(of: "<tr", options: .caseInsensitive)?.lowerBound ?? inhalt.endIndex
            )
            ergebnis.append(zellen(inhalt[..<ende]))
            rest = inhalt[ende...]
        }
        return ergebnis
    }

    /// Text zwischen `<title>` und `</title>`, falls vorhanden.
    static func titel(_ html: String) -> String? {
        guard let start = html.range(of: "<title>", options: .caseInsensitive),
              let ende = html.range(of: "</title>", options: .caseInsensitive, range: start.upperBound..<html.endIndex)
        else { return nil }
        return text(html[start.upperBound..<ende.lowerBound])
    }

    /// Erster fett gedruckter Text im Dokument (bei MetaTrader der Name des Brokers).
    static func ersterFetterText(_ html: String) -> String? {
        guard let start = html.range(of: "<b>", options: .caseInsensitive),
              let ende = html.range(of: "</b>", options: .caseInsensitive, range: start.upperBound..<html.endIndex)
        else { return nil }
        return text(html[start.upperBound..<ende.lowerBound])
    }

    private static func zellen(_ zeile: Substring) -> [String] {
        var ergebnis: [String] = []
        var rest = zeile
        while let start = rest.range(of: "<td", options: .caseInsensitive),
              let tagEnde = rest[start.upperBound...].firstIndex(of: ">") {
            let inhalt = rest[rest.index(after: tagEnde)...]
            let ende = inhalt.range(of: "</td>", options: .caseInsensitive)?.lowerBound ?? inhalt.endIndex
            ergebnis.append(text(inhalt[..<ende]))
            rest = inhalt[ende...]
        }
        return ergebnis
    }

    /// Entfernt Tags, löst Entities auf und fasst Leerraum zusammen.
    static func text(_ html: Substring) -> String {
        var ohneTags = ""
        var imTag = false
        for zeichen in html {
            if zeichen == "<" { imTag = true; ohneTags.append(" ") }
            else if zeichen == ">" { imTag = false }
            else if !imTag { ohneTags.append(zeichen) }
        }
        let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (entity, ersatz) in entities {
            ohneTags = ohneTags.replacingOccurrences(of: entity, with: ersatz, options: .caseInsensitive)
        }
        return ohneTags
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
