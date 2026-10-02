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

    public init(_ dateien: [Jahresdatei]) throws {
        var ids: Set<String> = []
        for termin in dateien.flatMap(\.termine) {
            guard ids.insert(termin.id).inserted else { throw TerminkalenderFehler.doppelteID(termin.id) }
        }
        self.dateien = dateien.sorted { $0.jahr < $1.jahr }
        termine = dateien.flatMap(\.termine).sorted { a, b in
            a.beginn != b.beginn ? a.beginn < b.beginn : a.id < b.id
        }
    }

    /// Liest alle JSON-Dateien aus dem Ordner `Termine` im Paket.
    public static func mitgeliefert() throws -> Terminkalender {
        guard let ordner = Bundle.module.url(forResource: "Termine", withExtension: nil) else {
            throw TerminkalenderFehler.mitgelieferteDatenFehlen
        }
        let dateien = try FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try Terminkalender(dateien.map { try Jahresdatei.lade(json: Data(contentsOf: $0)) })
    }

    /// Termine, die ganz oder teilweise in [von, bis] liegen; mit `waehrungen` nur solche,
    /// die mindestens eine davon betreffen. Für „über Termin gehalten“ (Doc 18 F9):
    /// `von` = Eröffnung, `bis` = Schließung des Trades.
    public func termine(von: Date, bis: Date, waehrungen: Set<String>? = nil, arten: Set<Terminart>? = nil) -> [Termin] {
        termine.filter { t in
            t.liegt(zwischen: von, und: bis)
                && (waehrungen.map { !t.waehrungen.isDisjoint(with: $0) } ?? true)
                && (arten.map { $0.contains(t.art) } ?? true)
        }
    }

    /// Ist die Art für das Jahr vollständig erfasst? Ohne Daten sagt ein leeres Ergebnis nichts.
    public func abgedeckt(jahr: Int, art: Terminart) -> Bool {
        dateien.contains { $0.jahr == jahr && $0.vollstaendig.contains(art) }
    }

    /// Ist [von, bis] für alle `arten` vollständig erfasst (Jahre in UTC gezählt, Einschätzung genügt)?
    public func abgedeckt(von: Date, bis: Date, arten: Set<Terminart> = Set(Terminart.allCases)) -> Bool {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(secondsFromGMT: 0)!
        let jahre = kalender.component(.year, from: von)...kalender.component(.year, from: max(von, bis))
        return jahre.allSatisfy { jahr in arten.allSatisfy { abgedeckt(jahr: jahr, art: $0) } }
    }
}
