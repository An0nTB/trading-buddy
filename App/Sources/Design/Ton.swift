import Foundation
import SwiftUI

/// Tonfall der Randstellen (Tim 02.10.2026 03:48 bis 03:51 UTC; Hauptthread: Schalter „Ton“, ab Werk Brad):
/// „Brad“ spricht Begrüßung, leere Seiten und Erfolgsmeldungen locker, „Sachlich“ ist der bisherige Text.
/// Zahlen, Steuer, Regelverstöße, Warnungen und Fehler haben nur die sachliche Fassung. Schlüssel und Rohwerte
/// teilen sich App und Export (AP12, Feld `ton` in JournalExport). Ansichten lesen `@AppStorage(Ton.schluessel)`,
/// Meldungen aus Funktionen `Ton.aktuell`.
enum Ton: String, CaseIterable, Hashable {
    case bro, sachlich

    static let schluessel = "brad.ton"

    var titel: LocalizedStringKey {
        switch self {
        case .bro: "Brad"
        case .sachlich: "Sachlich"
        }
    }

    /// Eingestellter Ton; fehlt der Wert, spricht Brad.
    static var aktuell: Ton {
        Ton(rawValue: UserDefaults.standard.string(forKey: schluessel) ?? "") ?? .bro
    }

    /// Wählt die Fassung zum Ton; beide Texte gehen durch die Lokalisierung.
    func text(_ sachlich: String.LocalizationValue, bro: String.LocalizationValue) -> String {
        String(localized: self == .bro ? bro : sachlich)
    }
}
