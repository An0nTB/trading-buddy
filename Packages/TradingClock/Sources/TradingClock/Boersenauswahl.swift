import Foundation

/// Was der Nutzer an der Börsenuhr frei wählt: welche Börsen in welcher Reihenfolge,
/// eigene Handelszeiten für mitgelieferte Börsen und ganz eigene Börsen.
/// Die App speichert die Auswahl als JSON (Codable) in ihren Einstellungen.
public struct Boersenauswahl: Sendable, Hashable, Codable {
    /// Kennungen der angezeigten Börsen in Anzeigereihenfolge. Leer heißt: alle in Standardreihenfolge.
    public var angezeigt: [String]
    /// Eigene Handelszeiten je Kennung. Feiertage der Börse gelten weiter.
    public var angepassteZeiten: [String: [Handelszeit]]
    /// Vom Nutzer angelegte Börsen.
    public var eigene: [Boerse]

    public init(angezeigt: [String] = [], angepassteZeiten: [String: [Handelszeit]] = [:], eigene: [Boerse] = []) {
        self.angezeigt = angezeigt
        self.angepassteZeiten = angepassteZeiten
        self.eigene = eigene
    }

    private enum CodingKeys: String, CodingKey { case angezeigt, angepassteZeiten, eigene }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        angezeigt = try c.decodeIfPresent([String].self, forKey: .angezeigt) ?? []
        angepassteZeiten = try c.decodeIfPresent([String: [Handelszeit]].self, forKey: .angepassteZeiten) ?? [:]
        eigene = try c.decodeIfPresent([Boerse].self, forKey: .eigene) ?? []
    }
}

extension Boerse {
    /// Kopie mit anderen Handelszeiten; Zeitzone und Feiertage bleiben.
    /// Beispiel: Xetra-Kalender, aber 08:00 bis 22:00 wie viele außerbörsliche Handelsplätze.
    public func mitHandelszeiten(_ zeiten: [Handelszeit]) throws -> Boerse {
        var kopie = self
        kopie.handelszeiten = zeiten
        kopie.durchgehend = false
        try kopie.pruefe()
        return kopie
    }

    /// Eigene Börse ohne JSON-Datei, zum Beispiel aus einem Formular der App.
    /// Ohne Feiertage; `datenGueltigBis` bleibt leer, die Uhr warnt also nicht.
    public static func eigene(id: String, name: String, zeitzone: String,
                              tage: [Wochentag] = [.montag, .dienstag, .mittwoch, .donnerstag, .freitag],
                              beginn: Uhrzeit, ende: Uhrzeit, endeNachTagen: Int = 0,
                              feiertage: [Feiertag] = [], stand: Kalendertag) throws -> Boerse {
        try Boerse(id: id, name: name, zeitzone: zeitzone,
                   handelszeiten: [Handelszeit(tage: tage, beginn: beginn, ende: ende, endeNachTagen: endeNachTagen)],
                   feiertage: feiertage, stand: stand, hinweise: ["Vom Nutzer angelegt."])
    }
}

extension Boersenuhr {
    /// Alle mitgelieferten Börsen plus die eigenen aus der Auswahl, ohne Filter.
    /// Für die Liste „Börsen hinzufügen“ in den Einstellungen.
    public static func verfuegbar(_ auswahl: Boersenauswahl = Boersenauswahl()) throws -> Boersenuhr {
        try mitgeliefert(zusaetzlich: auswahl.eigene).angepasst(auswahl.angepassteZeiten)
    }

    /// Die Uhr, wie der Nutzer sie gewählt hat: angepasste Zeiten angewandt, nur die angezeigten
    /// Börsen in seiner Reihenfolge. Unbekannte Kennungen in `angezeigt` werden übersprungen,
    /// damit eine gelöschte eigene Börse die Uhr nicht lahmlegt.
    public static func mit(_ auswahl: Boersenauswahl) throws -> Boersenuhr {
        let alle = try verfuegbar(auswahl)
        guard !auswahl.angezeigt.isEmpty else { return alle }
        var gesehen = Set<String>()
        let gewaehlt = auswahl.angezeigt.filter { gesehen.insert($0).inserted }.compactMap { alle[$0] }
        return Boersenuhr(geordnet: gewaehlt)
    }

    func angepasst(_ zeiten: [String: [Handelszeit]]) throws -> Boersenuhr {
        Boersenuhr(geordnet: try boersen.map { b in try zeiten[b.id].map { try b.mitHandelszeiten($0) } ?? b })
    }
}
