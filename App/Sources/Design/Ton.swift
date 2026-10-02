import Foundation
import SwiftUI

/// Tonfall der Randstellen (Tim 02.10.2026 03:48 UTC Schalter „Ton“; 11:02 UTC Henry statt Brad, Old Money):
/// „Henry“ spricht Begrüßung, leere Seiten und Erfolgsmeldungen ruhig und trocken, „Sachlich“ ist der bisherige Text.
/// Zahlen, Steuer, Regelverstöße, Warnungen und Fehler haben nur die sachliche Fassung. Schlüssel und Rohwerte
/// teilen sich App und Export (AP12, Feld `ton` in JournalExport): Schlüssel bleibt `brad.ton`, Rohwert „henry“
/// löst „bro“ ab; ein gespeichertes „bro“ liest die App als Henry (Festlegung AP11 11:08 UTC, Connector liest beide).
/// Ansichten lesen `@AppStorage(Ton.schluessel)`, Meldungen aus Funktionen `Ton.aktuell`.
enum Ton: String, CaseIterable, Hashable {
    case henry, sachlich

    static let schluessel = "brad.ton"

    /// Alter Name des Falls (Brad); bleibt, bis alle Stellen `henry` schreiben.
    static let bro = Ton.henry

    var titel: LocalizedStringKey {
        switch self {
        case .henry: "Henry"
        case .sachlich: "Sachlich"
        }
    }

    /// Eingestellter Ton; fehlt der Wert oder steht noch „bro“, spricht Henry.
    static var aktuell: Ton {
        Ton(rawValue: UserDefaults.standard.string(forKey: schluessel) ?? "") ?? .henry
    }

    /// Wählt die Fassung zum Ton; beide Texte gehen durch die Lokalisierung.
    func text(_ sachlich: String.LocalizationValue, henry: String.LocalizationValue) -> String {
        String(localized: self == .henry ? henry : sachlich)
    }

    /// Alte Beschriftung (Brad); ruft die Henry-Fassung auf, bis alle Stellen umgestellt sind.
    func text(_ sachlich: String.LocalizationValue, bro: String.LocalizationValue) -> String {
        text(sachlich, henry: bro)
    }
}
