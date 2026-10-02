import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Liest RSS 2.0 und Atom. Übernimmt nur Überschrift, Anriss, Link und Zeit; `content:encoded`
/// und Atom-`content` bleiben bewusst liegen (Volltext, Lizenz R6).
/// Geprüfte Formate (02.10.2026): finanzen.net (RSS 2.0, Anriss als HTML in CDATA, RFC-822-Zeit mit +0200),
/// Börse Frankfurt (RSS 2.0 mit media-Namensraum, Zeit in GMT), EZB und Fed (RSS 2.0).
public enum RSSLeser {
    /// - Parameters:
    ///   - quelle: Anzeigename der Quelle, z. B. „finanzen.net“.
    ///   - jetzt: Ersatzzeit für Einträge ohne lesbare Zeit.
    public static func lies(_ daten: Data, quelle: String, jetzt: Date) -> [Meldung] {
        let sammler = Sammler()
        let parser = XMLParser(data: daten)
        parser.delegate = sammler
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        // Auch bei einem Fehler mitten im Feed gelten die bis dahin vollständigen Einträge.
        return sammler.eintraege.compactMap { $0.meldung(quelle: quelle, jetzt: jetzt) }
    }

    struct Eintrag {
        var titel = ""
        var link = ""
        var atomLink: String?
        var guid = ""
        var anriss = ""
        var zeit = ""

        func meldung(quelle: String, jetzt: Date) -> Meldung? {
            let titelText = Text.bereinigt(titel)
            guard !titelText.isEmpty else { return nil }
            let kandidaten = [link, atomLink ?? "", guid].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let adresse = kandidaten.first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }),
                  let url = URL(string: adresse) else { return nil }
            return Meldung(titel: titelText, anriss: Text.anriss(anriss), quelle: quelle, link: url,
                           zeit: Zeitleser.lies(zeit) ?? jetzt, herkunft: .rss)
        }
    }

    final class Sammler: NSObject, XMLParserDelegate {
        var eintraege: [Eintrag] = []
        private var aktuell: Eintrag?
        private var puffer = ""
        /// Tiefe innerhalb eines Eintrags; nur direkte Kinder zählen (Tiefe 1).
        private var tiefe = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "item" || name == "entry" {
                aktuell = Eintrag()
                tiefe = 0
                return
            }
            guard aktuell != nil else { return }
            tiefe += 1
            puffer = ""
            if tiefe == 1, name == "link", let href = attributes["href"] {
                let rel = attributes["rel"] ?? "alternate"
                if rel == "alternate", aktuell?.atomLink == nil { aktuell?.atomLink = href }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if aktuell != nil { puffer += string }
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            if aktuell != nil, let text = String(data: block, encoding: .utf8) { puffer += text }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            guard var eintrag = aktuell else { return }
            if name == "item" || name == "entry" {
                eintraege.append(eintrag)
                aktuell = nil
                return
            }
            if tiefe == 1 {
                let text = puffer
                switch name {
                case "title": eintrag.titel = text
                case "link": if !text.isEmpty { eintrag.link = text }
                case "guid", "id": eintrag.guid = text
                case "description", "summary": if eintrag.anriss.isEmpty { eintrag.anriss = text }
                case "pubDate", "published", "dc:date":
                    eintrag.zeit = text
                case "updated":
                    if eintrag.zeit.isEmpty { eintrag.zeit = text }
                default: break
                }
                aktuell = eintrag
            }
            tiefe -= 1
            puffer = ""
        }
    }
}
