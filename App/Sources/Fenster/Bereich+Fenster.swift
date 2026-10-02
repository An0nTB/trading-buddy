import SwiftUI

/// Kennungen der Fenster-Szenen (Stand-Doc 27).
enum FensterID {
    /// Hauptfenster mit Seitenleiste.
    static let haupt = "haupt"
    /// Abgetrennte Bereiche, ein Fenster je Bereich.
    static let bereich = "bereich"
}

/// Abgetrennte Fenster merken sich ihren Bereich für die Wiederherstellung beim nächsten Start
/// (`WindowGroup(for:)` verlangt einen speicherbaren Wert; Rohwert ist String).
extension Bereich: Codable {}

extension Bereich {
    /// Bereiche, die sich als eigenes Fenster öffnen lassen: alle Seiten der Seitenleiste.
    static var abtrennbar: [Bereich] { journal + markt + daten }

    /// Kleine Werkzeuge: starten angeheftet (Tim, 02.10.2026) und passen in schmale Fenster.
    /// Ausdrücklich benannt, damit neue Bereiche unter „Markt“ (etwa Nachrichten) normal starten.
    static let werkzeuge: [Bereich] = [.boersenuhr, .positionsrechner]

    /// Börsenuhr und Positionsrechner starten angeheftet (Tim, 02.10.2026).
    var startetAngeheftet: Bool { Bereich.werkzeuge.contains(self) }

    /// Kleine Bereiche passen in schmale Fenster, alle anderen brauchen Platz für Kacheln und Tabellen.
    var mindestgroesse: CGSize {
        Bereich.werkzeuge.contains(self) ? CGSize(width: 320, height: 240) : CGSize(width: 560, height: 420)
    }

    /// Mindestgröße der kompakten Börsenuhr.
    static let kompaktgroesse = CGSize(width: 240, height: 150)

    /// Schlüssel in den Einstellungen für „immer im Vordergrund“ je Bereich.
    var anheftSchluessel: String { "angeheftet.\(rawValue)" }
}
