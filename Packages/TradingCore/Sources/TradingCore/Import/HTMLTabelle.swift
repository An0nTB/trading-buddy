import Foundation

/// Liest Tabellenzeilen aus einfachem HTML, wie MetaTrader-Auszüge es enthalten.
/// Kein vollständiger HTML-Parser: Er kennt nur `<tr>` und `<td>`, entfernt alle
/// anderen Tags und löst die üblichen Entities auf. Läuft auf Apple-Systemen und Linux.
enum HTMLTabelle {
    /// Alle Zeilen als Liste ihrer Zelltexte. Leerraum ist zusammengefasst und getrimmt.
    /// - Parameters:
    ///   - kopfzellen: auch `<th>` als Zelle lesen (MetaTrader 5 setzt Abschnittstitel und Kontokopf in `<th>`).
    ///   - ohneVersteckte: Zellen mit `class="hidden"` weglassen (MetaTrader 5 schiebt solche Zellen ein).
    static func zeilen(_ html: String, kopfzellen: Bool = false, ohneVersteckte: Bool = false) -> [[String]] {
        var ergebnis: [[String]] = []
        var rest = html[...]
        while let start = rest.range(of: "<tr", options: .caseInsensitive) {
            let inhalt = rest[start.upperBound...]
            let ende = min(
                inhalt.range(of: "</tr>", options: .caseInsensitive)?.lowerBound ?? inhalt.endIndex,
                inhalt.range(of: "<tr", options: .caseInsensitive)?.lowerBound ?? inhalt.endIndex
            )
            ergebnis.append(zellen(inhalt[..<ende], kopfzellen: kopfzellen, ohneVersteckte: ohneVersteckte))
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

    private static func zellen(_ zeile: Substring, kopfzellen: Bool, ohneVersteckte: Bool) -> [String] {
        var ergebnis: [String] = []
        var rest = zeile
        while let start = naechsteZelle(rest, kopfzellen: kopfzellen),
              let tagEnde = rest[start.upperBound...].firstIndex(of: ">") {
            let attribute = rest[start.upperBound..<tagEnde].lowercased()
            let inhalt = rest[rest.index(after: tagEnde)...]
            let ende = [inhalt.range(of: "</td>", options: .caseInsensitive)?.lowerBound,
                        kopfzellen ? inhalt.range(of: "</th>", options: .caseInsensitive)?.lowerBound : nil]
                .compactMap { $0 }.min() ?? inhalt.endIndex
            let versteckt = attribute.contains("class=\"hidden\"") || attribute.contains("class=hidden")
            if !(ohneVersteckte && versteckt) { ergebnis.append(text(inhalt[..<ende])) }
            rest = inhalt[ende...]
        }
        return ergebnis
    }

    /// Beginn der nächsten `<td` (oder `<th`) mit Leerraum oder `>` danach, damit `<thead>` nicht zählt.
    private static func naechsteZelle(_ text: Substring, kopfzellen: Bool) -> Range<Substring.Index>? {
        var rest = text
        while true {
            let td = rest.range(of: "<td", options: .caseInsensitive)
            let th = kopfzellen ? rest.range(of: "<th", options: .caseInsensitive) : nil
            guard let treffer = [td, th].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else {
                return nil
            }
            if treffer.upperBound == rest.endIndex { return nil }
            let folgend = rest[treffer.upperBound]
            if folgend == ">" || folgend.isWhitespace { return treffer }
            rest = rest[treffer.upperBound...]
        }
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
