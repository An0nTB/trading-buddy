import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import TradingCore

/// Liest die Kursdateien der EZB (eurofxref-daily.xml, eurofxref-hist-90d.xml, eurofxref-hist.xml).
/// Aufbau: `<Cube><Cube time="JJJJ-MM-TT"><Cube currency="USD" rate="1.1708"/>…</Cube>…</Cube>`
/// im Namensraum `http://www.ecb.int/vocabulary/2002-08-01/eurofxref`, Einheit Fremdwährung je 1 Euro.
/// Der Aufbau ist aus der EZB-Dokumentation nachgebaut; die Cloud-Sitzung konnte die Datei nicht abrufen (Doc 34).
public enum EZBKursdatei {
    public enum Fehler: LocalizedError, Sendable, Equatable {
        /// Keine Kurse gefunden, z. B. eine HTML-Fehlerseite statt XML.
        case keineKurse
        /// Die Datei bricht mitten im XML ab (z. B. Verbindung beim Laden der Verlaufsdatei getrennt).
        /// Ein Teil darf nicht als Erfolg in den Zwischenspeicher, sonst fehlen die alten Tage dauerhaft.
        case unvollstaendig

        /// Text für die Steuer-Seite („Abruf: …“), ohne Typnamen.
        public var errorDescription: String? {
            switch self {
            case .keineKurse: "Die EZB-Datei enthält keine Kurse."
            case .unvollstaendig: "Die EZB-Datei kam unvollständig an."
            }
        }
    }

    /// Alle Tage mit ihren Kursen. Unlesbare Kurszeilen fallen weg; eine Datei ganz ohne Kurse
    /// oder eine abgebrochene Datei ist ein Fehler.
    public static func lies(_ daten: Data) throws -> [Journaltag: [String: Decimal]] {
        let sammler = Sammler()
        let parser = XMLParser(data: daten)
        parser.delegate = sammler
        parser.shouldResolveExternalEntities = false
        // Nur `parse()` reicht nicht: FoundationXML unter Linux meldet eine abgeschnittene Datei als Erfolg.
        // Deshalb zählt zusätzlich, ob das äußere Cube geschlossen wurde und die Datei mit dem
        // Schluss-Tag des Wurzelelements endet (z. B. `</gesmes:Envelope>`).
        let vollstaendig = parser.parse() && sammler.aeussererCubeGeschlossen && !sammler.fehler
            && endetMitSchlussTag(daten, wurzel: sammler.wurzel)
        let kurse = sammler.kurse.filter { !$0.value.isEmpty }
        guard !kurse.isEmpty else { throw Fehler.keineKurse }
        guard vollstaendig else { throw Fehler.unvollstaendig }
        return kurse
    }

    /// Ob die Datei (ohne Leerraum am Ende) mit `</wurzel>` endet.
    static func endetMitSchlussTag(_ daten: Data, wurzel: String?) -> Bool {
        guard let wurzel, !wurzel.isEmpty else { return false }
        var ende = daten.endIndex
        while ende > daten.startIndex, [0x20, 0x09, 0x0A, 0x0D].contains(daten[daten.index(before: ende)]) {
            ende = daten.index(before: ende)
        }
        return daten[daten.startIndex..<ende].reversed().starts(with: Array("</\(wurzel)>".utf8).reversed())
    }

    /// Dezimalzahl mit Punkt, unabhängig von der Spracheinstellung.
    static func zahl(_ text: String) -> Decimal? {
        let sauber = text.trimmingCharacters(in: .whitespaces)
        guard !sauber.isEmpty, sauber.allSatisfy({ "0123456789.".contains($0) }),
              let wert = Decimal(string: sauber, locale: Locale(identifier: "en_US_POSIX")), wert > 0 else { return nil }
        return wert
    }

    final class Sammler: NSObject, XMLParserDelegate {
        var kurse: [Journaltag: [String: Decimal]] = [:]
        private var tag: Journaltag?
        /// Verschachtelung der Cube-Elemente: 1 = Hülle aller Tage, 2 = Tag, 3 = Kurs.
        private var tiefe = 0
        private(set) var aeussererCubeGeschlossen = false
        private(set) var fehler = false
        /// Name des Wurzelelements, wie er in der Datei steht.
        private(set) var wurzel: String?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if wurzel == nil { wurzel = qualifiedName ?? name }
            guard name == "Cube" else { return }
            tiefe += 1
            if let zeit = attributes["time"] {
                tag = Journaltag(zeit)
                if let tag, kurse[tag] == nil { kurse[tag] = [:] }
            } else if let tag, let waehrung = attributes["currency"], let rate = attributes["rate"],
                      let wert = EZBKursdatei.zahl(rate) {
                kurse[tag, default: [:]][waehrung.uppercased()] = wert
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard name == "Cube" else { return }
            if tiefe == 1 { aeussererCubeGeschlossen = true }
            tiefe -= 1
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            fehler = true
        }
    }
}
