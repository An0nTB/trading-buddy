import Foundation

/// Art einer Handelssitzung. US-Börsen handeln außer im Kernhandel auch vor- und nachbörslich,
/// Nasdaq ab 06.12.2026 zusätzlich nachts (21:00 bis 04:00 New York; Nasdaq-FAQ 2026).
public enum Sitzungsart: String, Sendable, Hashable, Codable, CaseIterable {
    case kern, vorboerslich, nachboerslich, nacht
}

extension Boerse {
    /// Sitzungsarten, die in den Handelszeiten vorkommen, in fester Reihenfolge; für die Einstellungen.
    public var verfuegbareSitzungsarten: [Sitzungsart] {
        let vorhanden = Set(handelszeiten.map(\.art))
        return Sitzungsart.allCases.filter(vorhanden.contains)
    }

    /// Kopie, die die genannten Sitzungsarten mitrechnet. Arten ohne Handelszeiten stören nicht.
    /// Leer heißt: nur Kernhandel, damit eine Börse nie ganz ohne Sitzungen dasteht.
    public func mitSitzungsarten(_ arten: Set<Sitzungsart>) -> Boerse {
        var kopie = self
        kopie.sitzungsarten = arten.isEmpty ? [.kern] : arten
        return kopie
    }

    /// Welche Art von Sitzung zu diesem Zeitpunkt läuft, oder `nil`, wenn keine mitgerechnete läuft.
    /// Aneinander anschließende Sitzungen verschmelzen in `sitzungen`; hier zählt die einzelne Handelszeit.
    public func sitzungsart(bei zeitpunkt: Date) -> Sitzungsart? {
        if durchgehend { return .kern }
        let bis = zeitpunkt.addingTimeInterval(1)
        return Sitzungsart.allCases.first { art in
            sitzungsarten.contains(art)
                && mitSitzungsarten([art]).sitzungen(von: zeitpunkt, bis: bis).contains { $0.enthaelt(zeitpunkt) }
        }
    }
}
