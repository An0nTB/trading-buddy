import Foundation

/// Alle Termine aus einer oder mehreren Jahresdateien, nach Zeit sortiert.
///
/// ```swift
/// let kalender = try Terminkalender.mitgeliefert()
/// let gehalten = kalender.termine(von: trade.eroeffnet, bis: trade.geschlossen,
///                                 waehrungen: Terminkalender.waehrungen(symbol: trade.symbol))
/// ```
public struct Terminkalender: Sendable {
    public let dateien: [Jahresdatei]
    public let termine: [Termin]

    /// `zusaetzlich`: Termine von außerhalb der Jahresdateien, etwa Börsenfeiertage aus der Börsenuhr.
    public init(_ dateien: [Jahresdatei], zusaetzlich: [Termin] = []) throws {
        let alle = dateien.flatMap(\.termine) + zusaetzlich
        var ids: Set<String> = []
        for termin in alle {
            guard ids.insert(termin.id).inserted else { throw TerminkalenderFehler.doppelteID(termin.id) }
        }
        self.dateien = dateien.sorted { $0.jahr < $1.jahr }
        termine = alle.sorted { a, b in
            a.beginn != b.beginn ? a.beginn < b.beginn : a.id < b.id
        }
    }

    /// Derselbe Kalender mit weiteren Terminen, etwa Börsenfeiertagen; doppelte IDs werfen.
    public func mit(_ zusaetzlich: [Termin]) throws -> Terminkalender {
        let bisher = Set(dateien.flatMap(\.termine).map(\.id))
        return try Terminkalender(dateien, zusaetzlich: termine.filter { !bisher.contains($0.id) } + zusaetzlich)
    }

    /// Liest alle JSON-Dateien aus dem Ordner `Termine` im Paket.
    public static func mitgeliefert(zusaetzlich: [Termin] = []) throws -> Terminkalender {
        guard let ordner = Bundle.module.url(forResource: "Termine", withExtension: nil) else {
            throw TerminkalenderFehler.mitgelieferteDatenFehlen
        }
        let dateien = try FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try Terminkalender(dateien.map { try Jahresdatei.lade(json: Data(contentsOf: $0)) }, zusaetzlich: zusaetzlich)
    }

    /// Termine, die ganz oder teilweise in [von, bis] liegen; mit `waehrungen` nur solche,
    /// die mindestens eine davon betreffen. Für „über Termin gehalten“ (Doc 18 F9):
    /// `von` = Eröffnung, `bis` = Schließung des Trades. `regionen` und `mindestens` filtern für die Kalender-Seite.
    public func termine(von: Date, bis: Date, waehrungen: Set<String>? = nil, arten: Set<Terminart>? = nil,
                        regionen: Set<String>? = nil, mindestens: Wichtigkeit? = nil) -> [Termin] {
        termine.filter { t in
            t.liegt(zwischen: von, und: bis) && t.passt(waehrungen: waehrungen, arten: arten,
                                                       regionen: regionen, mindestens: mindestens)
        }
    }

    /// Ist die Art für das Jahr vollständig erfasst? Ohne Daten sagt ein leeres Ergebnis nichts.
    public func abgedeckt(jahr: Int, art: Terminart) -> Bool {
        dateien.contains { $0.jahr == jahr && $0.vollstaendig.contains(art) }
    }

    /// Ist [von, bis] für alle `arten` vollständig erfasst (Jahre in UTC gezählt, Einschätzung genügt)?
    /// Standard sind die Kernarten; Konjunktur, Index und Co. gelten nie als vollständig.
    public func abgedeckt(von: Date, bis: Date, arten: Set<Terminart> = Terminart.kern) -> Bool {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(secondsFromGMT: 0)!
        let jahre = kalender.component(.year, from: von)...kalender.component(.year, from: max(von, bis))
        return jahre.allSatisfy { jahr in arten.allSatisfy { abgedeckt(jahr: jahr, art: $0) } }
    }
}
