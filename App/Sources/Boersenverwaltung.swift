import Foundation
import Observation
import TradingClock

/// Was der Nutzer an der Börsenuhr gewählt hat (Stand-Doc 15, Entscheidungen U6 und U7): welche Börsen in
/// welcher Reihenfolge, eigene Handelszeiten, eigene Börsen und zusätzliche Feiertagskalender.
/// Gespeichert als JSON in den Einstellungen der App; die mitgelieferten Börsendateien bleiben unverändert.
@Observable @MainActor
final class Boersenverwaltung {
    static let schluessel = "boersenauswahl"

    private(set) var auswahl: Boersenauswahl
    /// Die Uhr, wie der Nutzer sie sieht: nur die gewählten Börsen in seiner Reihenfolge.
    private(set) var uhr: Boersenuhr?
    /// Alle Börsen, die sich anzeigen lassen (mitgelieferte und eigene), mit angepassten Zeiten und Kalendern.
    private(set) var verfuegbar: Boersenuhr?
    /// Letzter Fehler beim Laden oder Ändern, für die Anzeige; `nil`, wenn alles stimmt.
    private(set) var fehler: String?
    /// Einträge der gespeicherten Auswahl, die die Uhr überspringt (TradingClock 0.3.1, `Boersenauswahl.probleme()`),
    /// in Klartext; leer, wenn die Uhr alles so nimmt, wie es gespeichert ist.
    private(set) var probleme: [String] = []

    /// Die mitgelieferten Börsen, wie sie im Paket stehen (für „Vorgabe wiederherstellen“).
    private let mitgeliefert: [Boerse]
    private let speicher: UserDefaults

    init(speicher: UserDefaults = .standard) {
        self.speicher = speicher
        mitgeliefert = (try? Boersenuhr.mitgelieferteBoersen()) ?? []
        if let daten = speicher.data(forKey: Self.schluessel),
           let gespeichert = try? JSONDecoder().decode(Boersenauswahl.self, from: daten) {
            auswahl = gespeichert
        } else {
            auswahl = Boersenauswahl()
        }
        baue()
    }

    /// Kennungen der angezeigten Börsen in Anzeigereihenfolge (leer gespeichert heißt: alle).
    var angezeigt: [String] { uhr?.boersen.map(\.id) ?? [] }

    /// Börsen, die es gibt, aber die der Nutzer ausgeblendet hat.
    var ausgeblendet: [Boerse] {
        let sichtbar = Set(angezeigt)
        return verfuegbar?.boersen.filter { !sichtbar.contains($0.id) } ?? []
    }

    func boerse(_ id: String) -> Boerse? { verfuegbar?[id] }
    func istEigene(_ id: String) -> Bool { auswahl.eigene.contains { $0.id == id } }
    func istAngepasst(_ id: String) -> Bool { auswahl.angepassteZeiten[id] != nil }
    func kalender(fuer id: String) -> [String] { auswahl.kalenderJeBoerse[id] ?? [] }

    /// Sitzungsarten, die die Uhr für eine Börse mitrechnet; ohne Eintrag nur Kernhandel (Entscheidung U8).
    func sitzungsarten(_ id: String) -> Set<Sitzungsart> {
        Set(auswahl.sitzungsartenJeBoerse[id] ?? [.kern])
    }

    /// Schaltet eine Zusatzsitzung (vor-, nachbörslich, Nacht) zu oder ab. Nur Kernhandel löscht den Eintrag.
    func setzeSitzungsart(_ art: Sitzungsart, boerse id: String, an: Bool) {
        var arten = sitzungsarten(id)
        if an { arten.insert(art) } else { arten.remove(art) }
        arten.insert(.kern)
        aendere { auswahl in
            if arten == [.kern] {
                auswahl.sitzungsartenJeBoerse[id] = nil
            } else {
                auswahl.sitzungsartenJeBoerse[id] = Sitzungsart.allCases.filter(arten.contains)
            }
        }
    }

    /// Mitgelieferte Handelszeiten einer Börse ohne Anpassung des Nutzers; `nil` bei eigenen Börsen.
    func vorgabe(_ id: String) -> [Handelszeit]? {
        mitgeliefert.first { $0.id == id }?.handelszeiten
    }

    /// Wendet eine Änderung an, prüft sie über das Paket und speichert sie. Scheitert die Prüfung,
    /// bleibt die alte Auswahl, und der Grund steht in `fehler`.
    @discardableResult
    func aendere(_ aenderung: (inout Boersenauswahl) throws -> Void) -> Bool {
        var neu = auswahl
        do {
            try aenderung(&neu)
            _ = try Boersenuhr.mit(neu)
        } catch {
            fehler = Self.text(error)
            return false
        }
        auswahl = neu
        fehler = nil
        if let daten = try? JSONEncoder().encode(neu) {
            speicher.set(daten, forKey: Self.schluessel)
        }
        baue()
        return true
    }

    /// Fehler aus der Oberfläche (etwa beim Lesen einer Datei) an derselben Stelle anzeigen.
    func melde(_ text: String) {
        fehler = text
    }

    func zeige(_ id: String) {
        let liste = angezeigt
        guard !liste.contains(id) else { return }
        aendere { $0.angezeigt = liste + [id] }
    }

    /// Blendet eine Börse aus; die letzte bleibt, weil eine leere Liste „alle“ bedeutet.
    func blendeAus(_ id: String) {
        let liste = angezeigt.filter { $0 != id }
        guard !liste.isEmpty else { return }
        aendere { $0.angezeigt = liste }
    }

    /// Verschiebt eine Börse um `schritt` Plätze (negativ nach oben).
    func verschiebe(_ id: String, um schritt: Int) {
        var liste = angezeigt
        guard let i = liste.firstIndex(of: id), liste.indices.contains(i + schritt) else { return }
        liste.swapAt(i, i + schritt)
        aendere { $0.angezeigt = liste }
    }

    func verschiebe(von quelle: IndexSet, nach ziel: Int) {
        var liste = angezeigt
        liste.move(fromOffsets: quelle, toOffset: ziel)
        aendere { $0.angezeigt = liste }
    }

    /// Eigene Handelszeiten für eine mitgelieferte Börse; gleich der Vorgabe oder `nil` hebt die Anpassung auf.
    /// Geprüft wird vor dem Speichern über `mitHandelszeiten`, damit falsche Zeiten nie in der Auswahl landen.
    func setzeZeiten(_ id: String, _ zeiten: [Handelszeit]?) {
        let standard = vorgabe(id)
        let aktuell = boerse(id)
        aendere { auswahl in
            if let zeiten, zeiten != standard {
                if let aktuell { _ = try aktuell.mitHandelszeiten(zeiten) }
                auswahl.angepassteZeiten[id] = zeiten
            } else {
                auswahl.angepassteZeiten.removeValue(forKey: id)
            }
        }
    }

    /// Legt eine eigene Börse an oder ersetzt die mit gleicher Kennung und zeigt sie an.
    func speichereEigene(_ boerse: Boerse) {
        let liste = angezeigt
        aendere { auswahl in
            auswahl.eigene.removeAll { $0.id == boerse.id }
            auswahl.eigene.append(boerse)
            auswahl.angepassteZeiten.removeValue(forKey: boerse.id)
            if !liste.contains(boerse.id) { auswahl.angezeigt = liste + [boerse.id] }
        }
    }

    func loescheEigene(_ id: String) {
        let liste = angezeigt.filter { $0 != id }
        aendere { auswahl in
            auswahl.eigene.removeAll { $0.id == id }
            auswahl.angepassteZeiten.removeValue(forKey: id)
            auswahl.kalenderJeBoerse.removeValue(forKey: id)
            auswahl.angezeigt = liste
        }
    }

    /// Fügt einen Feiertagskalender hinzu; einer mit gleicher Kennung wird ersetzt.
    func speichereKalender(_ kalender: Feiertagskalender) {
        aendere { auswahl in
            auswahl.kalender.removeAll { $0.id == kalender.id }
            auswahl.kalender.append(kalender)
        }
    }

    func loescheKalender(_ id: String) {
        aendere { auswahl in
            auswahl.kalender.removeAll { $0.id == id }
            auswahl.kalenderJeBoerse = auswahl.kalenderJeBoerse.compactMapValues { ids in
                let rest = ids.filter { $0 != id }
                return rest.isEmpty ? nil : rest
            }
        }
    }

    /// Ordnet einer Börse einen Kalender zu oder nimmt die Zuordnung zurück.
    func ordneKalender(_ kalenderId: String, boerse: String, zu: Bool) {
        aendere { auswahl in
            var ids = (auswahl.kalenderJeBoerse[boerse] ?? []).filter { $0 != kalenderId }
            if zu { ids.append(kalenderId) }
            auswahl.kalenderJeBoerse[boerse] = ids.isEmpty ? nil : ids
        }
    }

    /// Liest eine JSON-Datei, die eine Börse (Dateiformat 1, erkennbar an `zeitzone`) oder einen
    /// Feiertagskalender enthält. Mitgelieferte Börsen lassen sich so nicht überschreiben.
    func importiere(daten: Data) {
        let objekt = (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any]
        guard let objekt else {
            fehler = String(localized: "Die Datei ist kein JSON-Objekt.")
            return
        }
        do {
            if objekt["zeitzone"] != nil {
                let boerse = try Boerse.lade(json: daten)
                guard !mitgeliefert.contains(where: { $0.id == boerse.id }) else {
                    fehler = String(localized: "Kennung „\(boerse.id)“ gehört zu einer mitgelieferten Börse. Zeiten dort über „Einrichten“ anpassen.")
                    return
                }
                speichereEigene(boerse)
            } else {
                speichereKalender(try Feiertagskalender.lade(json: daten))
            }
        } catch {
            fehler = Self.text(error)
        }
    }

    /// Kennung für eine neue eigene Börse aus dem Namen, eindeutig gegenüber allen Börsen.
    func freieKennung(aus name: String) -> String {
        Self.freieKennung(aus: name, vergeben: Set((verfuegbar?.boersen.map(\.id) ?? []) + mitgeliefert.map(\.id)),
                          sonst: "boerse")
    }

    /// Kennung für einen neuen Feiertagskalender, eindeutig gegenüber den vorhandenen.
    func freieKalenderKennung(aus name: String) -> String {
        Self.freieKennung(aus: name, vergeben: Set(auswahl.kalender.map(\.id)), sonst: "kalender")
    }

    /// Kleinbuchstaben und Ziffern ohne Akzente, alles andere wird zum Bindestrich; bei Dopplung mit Zähler.
    static func freieKennung(aus name: String, vergeben: Set<String>, sonst: String) -> String {
        let flach = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        let zeichen = flach.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let kern = zeichen.split(separator: "-").joined(separator: "-")
        let basis = kern.isEmpty ? sonst : kern
        var kandidat = basis
        var zaehler = 2
        while vergeben.contains(kandidat) {
            kandidat = "\(basis)-\(zaehler)"
            zaehler += 1
        }
        return kandidat
    }

    private func baue() {
        do {
            verfuegbar = try Boersenuhr.verfuegbar(auswahl)
            uhr = try Boersenuhr.mit(auswahl)
            probleme = try auswahl.probleme().map { Self.text($0) }
        } catch {
            verfuegbar = nil
            uhr = nil
            fehler = Self.text(error)
        }
    }

    /// Fehler des Pakets in Klartext. Fälle, die diese Fassung nicht kennt (das Paket wächst, etwa
    /// `leereKennungOderName` in 0.3.1), erscheinen als Rohtext statt den Build zu brechen.
    static func text(_ fehler: Error) -> String {
        guard let fehler = fehler as? BoersenuhrFehler else { return fehler.localizedDescription }
        switch fehler {
        case .ungueltigesDatum(let text):
            return String(localized: "Datum „\(text)“ ist nicht JJJJ-MM-TT.")
        case .ungueltigeUhrzeit(let text):
            return String(localized: "Uhrzeit „\(text)“ ist nicht HH:MM.")
        case .unbekanntesFormat(let id, let format):
            return String(localized: "„\(id)“: Dateiformat \(format) kennt diese Version nicht.")
        case .unbekannteZeitzone(let id, let zeitzone):
            return String(localized: "„\(id)“: Zeitzone „\(zeitzone)“ ist unbekannt. Erwartet wird ein IANA-Name wie Europe/Berlin.")
        case .keineHandelszeiten(let id):
            return String(localized: "„\(id)“: keine Handelszeiten angegeben.")
        case .ungueltigeHandelszeit(let id, let grund):
            return String(localized: "„\(id)“: Handelszeit ungültig (\(grund)).")
        case .doppelteBoerse(let id):
            return String(localized: "Kennung „\(id)“ gibt es schon.")
        case .doppelterKalender(let id):
            return String(localized: "Kalender „\(id)“ gibt es schon.")
        case .mitgelieferteDatenFehlen:
            return String(localized: "Die mitgelieferten Börsendaten fehlen im Paket.")
        default:
            return String(describing: fehler)
        }
    }
}
