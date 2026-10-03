import Foundation
import TradingStore

/// Klartext für Fehler des Speichers überall, wo die App `error.localizedDescription` zeigt (Sicherung,
/// Wiederherstellen, Laden, Inspektor, Bilder, Export). Ohne das sähe man „TradingStore.SpeicherFehler-Fehler 5“
/// statt des Grundes (Doc 55, J-Befund Fehlertexte).
extension SpeicherFehler: @retroactive LocalizedError {
    public var errorDescription: String? {
        // Der Grund bei `ungueltigerWert` ist schon ein ganzer Satz (etwa „Sicherung nicht abgelegt (Fehler 28)“).
        if case .ungueltigerWert(let grund) = self { return grund }
        return Importlesung.fehlertext(self)
    }
}
