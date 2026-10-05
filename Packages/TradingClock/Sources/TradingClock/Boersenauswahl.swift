import Foundation

/// Was der Nutzer an der Börsenuhr frei wählt: welche Börsen in welcher Reihenfolge,
/// eigene Handelszeiten für mitgelieferte Börsen und ganz eigene Börsen.
/// Die App speichert die Auswahl als JSON (Codable) in ihren Einstellungen.
public struct Boersenauswahl: Sendable, Hashable, Codable {
    /// Kennungen der angezeigten Börsen in Anzeigereihenfolge. Leer heißt: die mitgelieferten aus
    /// `Boersenuhr.standardAngezeigt` und alle eigenen, in Standardreihenfolge (bis 0.4.0: alle).
    public var angezeigt: [String]
    /// Eigene Handelszeiten je Kennung. Feiertage der Börse gelten weiter.
    public var angepassteZeiten: [String: [Handelszeit]]
    /// Vom Nutzer angelegte Börsen.
    public var eigene: [Boerse]
    /// Vom Nutzer hinzugefügte Feiertagskalender, zum Beispiel anderer Länder.
    public var kalender: [Feiertagskalender]
    /// Welche Kalender zusätzlich für welche Börse gelten, je Börsenkennung eine Liste von Kalenderkennungen.
    public var kalenderJeBoerse: [String: [String]]
    /// Welche Sitzungsarten je Börse mitzählen. Ohne Eintrag: nur Kernhandel.
    public var sitzungsartenJeBoerse: [String: [Sitzungsart]]

    public init(angezeigt: [String] = [], angepassteZeiten: [String: [Handelszeit]] = [:], eigene: [Boerse] = [],
                kalender: [Feiertagskalender] = [], kalenderJeBoerse: [String: [String]] = [:],
                sitzungsartenJeBoerse: [String: [Sitzungsart]] = [:]) {
        self.angezeigt = angezeigt
        self.angepassteZeiten = angepassteZeiten
        self.eigene = eigene
        self.kalender = kalender
        self.kalenderJeBoerse = kalenderJeBoerse
        self.sitzungsartenJeBoerse = sitzungsartenJeBoerse
    }

    private enum CodingKeys: String, CodingKey {
        case angezeigt, angepassteZeiten, eigene, kalender, kalenderJeBoerse, sitzungsartenJeBoerse
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        angezeigt = try c.decodeIfPresent([String].self, forKey: .angezeigt) ?? []
        angepassteZeiten = try c.decodeIfPresent([String: [Handelszeit]].self, forKey: .angepassteZeiten) ?? [:]
        eigene = try c.decodeIfPresent([Boerse].self, forKey: .eigene) ?? []
        kalender = try c.decodeIfPresent([Feiertagskalender].self, forKey: .kalender) ?? []
        kalenderJeBoerse = try c.decodeIfPresent([String: [String]].self, forKey: .kalenderJeBoerse) ?? [:]
        // Unbekannte Arten aus einer neueren App-Version überspringen statt die ganze Auswahl zu verwerfen.
        let roh = try c.decodeIfPresent([String: [String]].self, forKey: .sitzungsartenJeBoerse) ?? [:]
        sitzungsartenJeBoerse = roh.mapValues { $0.compactMap(Sitzungsart.init(rawValue:)) }
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
    /// Alle mitgelieferten Börsen plus die eigenen aus der Auswahl, ohne Filter, mit angepassten
    /// Zeiten und zugeordneten Kalendern. Für die Liste „Börsen hinzufügen“ in den Einstellungen.
    /// Fehlerhafte Einträge der Auswahl werden übersprungen, damit ein einzelner Fehler nicht die
    /// ganze Uhr leert; welche das sind, sagt `Boersenauswahl.probleme()`. Werfen kann die Funktion
    /// nur, wenn die mitgelieferten Börsendateien selbst fehlen oder kaputt sind.
    public static func verfuegbar(_ auswahl: Boersenauswahl = Boersenauswahl()) throws -> Boersenuhr {
        let basis = try mitgeliefert()
        return Boersenuhr(geordnet: auswahl.bereinigt(mitgeliefert: basis.boersen).boersen)
    }

    /// Die Uhr, wie der Nutzer sie gewählt hat: angepasste Zeiten angewandt, nur die angezeigten
    /// Börsen in seiner Reihenfolge. Unbekannte Kennungen in `angezeigt` werden übersprungen,
    /// damit eine gelöschte eigene Börse die Uhr nicht lahmlegt. Ohne Auswahl: `standardAngezeigt`
    /// plus eigene Börsen; die übrigen mitgelieferten stehen nur in `verfuegbar`.
    public static func mit(_ auswahl: Boersenauswahl) throws -> Boersenuhr {
        let alle = try verfuegbar(auswahl)
        guard !auswahl.angezeigt.isEmpty else {
            let standard = Set(standardAngezeigt).union(auswahl.eigene.map(\.id))
            return Boersenuhr(geordnet: alle.boersen.filter { standard.contains($0.id) })
        }
        var gesehen = Set<String>()
        let gewaehlt = auswahl.angezeigt.filter { gesehen.insert($0).inserted }.compactMap { alle[$0] }
        return Boersenuhr(geordnet: gewaehlt)
    }
}

extension Boersenauswahl {
    /// Was an der Auswahl nicht stimmt, zum Beispiel für einen Hinweis in den Einstellungen.
    /// Leer heißt: Die Uhr nutzt alles so, wie es gespeichert ist.
    public func probleme() throws -> [BoersenuhrFehler] {
        bereinigt(mitgeliefert: try Boersenuhr.mitgelieferteBoersen()).probleme
    }

    func bereinigt(mitgeliefert: [Boerse]) -> (boersen: [Boerse], probleme: [BoersenuhrFehler]) {
        var probleme: [BoersenuhrFehler] = []
        func notiere(_ fehler: Error) {
            probleme.append(fehler as? BoersenuhrFehler ?? .ungueltigeHandelszeit(id: "?", grund: "\(fehler)"))
        }

        var kalenderNachId: [String: Feiertagskalender] = [:]
        for k in kalender {
            do { try k.pruefe() } catch { notiere(error); continue }
            if kalenderNachId[k.id] != nil { probleme.append(.doppelterKalender(id: k.id)); continue }
            kalenderNachId[k.id] = k
        }

        var ids = Set(mitgeliefert.map(\.id))
        var alle = mitgeliefert
        for b in eigene {
            do { try b.pruefe() } catch { notiere(error); continue }
            guard ids.insert(b.id).inserted else { probleme.append(.doppelteBoerse(id: b.id)); continue }
            alle.append(b)
        }

        let ergebnis = alle.map { b -> Boerse in
            var neu = b
            if let zeiten = angepassteZeiten[b.id] {
                do { neu = try b.mitHandelszeiten(zeiten) } catch { notiere(error) }
            }
            // Unbekannte Kalenderkennungen überspringen, damit ein gelöschter Kalender die Uhr nicht lahmlegt.
            return neu.mitKalendern((kalenderJeBoerse[b.id] ?? []).compactMap { kalenderNachId[$0] })
                .mitSitzungsarten(Set(sitzungsartenJeBoerse[b.id] ?? [.kern]))
        }
        return (ergebnis, probleme)
    }
}
