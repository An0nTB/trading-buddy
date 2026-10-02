import Foundation
import SwiftUI

/// Sprache der Oberfläche (Tim 30.09.2026, Doc 02: Deutsch mit englischer Option, jeder Nutzer wählt selbst;
/// Paket 6 am 02.10.2026). „Wie System“ folgt der Systemsprache bzw. der Sprache, die in den
/// Systemeinstellungen für diese App eingestellt ist. Zahlen, Beträge und Daten folgen weiter der Region
/// des Systems (Englisch mit Region Deutschland zeigt also „1.234,50 €“).
///
/// Die Wahl wirkt nach einem Neustart der App: Texte aus `String(localized:)`, Menüs und Fenstertitel
/// lädt das System beim Start in der Sprache aus `AppleLanguages`; ein Umschalten zur Laufzeit hätte
/// halb deutsche, halb englische Fenster ergeben.
enum Sprache: String, CaseIterable, Hashable, Identifiable {
    case system, deutsch, englisch

    static let schluessel = "app.sprache"

    var id: String { rawValue }

    var titel: LocalizedStringKey {
        switch self {
        case .system: "Wie System"
        case .deutsch: "Deutsch"
        case .englisch: "English"
        }
    }

    /// Sprachkennung für `AppleLanguages`; `nil` heißt: Eintrag entfernen, das System entscheidet.
    var kennung: String? {
        switch self {
        case .system: nil
        case .deutsch: "de"
        case .englisch: "en"
        }
    }

    /// Eingestellte Sprache; fehlt der Wert, gilt das System.
    static var aktuell: Sprache {
        Sprache(rawValue: UserDefaults.standard.string(forKey: schluessel) ?? "") ?? .system
    }

    /// Schreibt die Wahl in den App-Bereich der Benutzereinstellungen; gilt ab dem nächsten Start.
    func anwenden(_ standard: UserDefaults = .standard) {
        if let kennung {
            standard.set([kennung], forKey: "AppleLanguages")
        } else {
            standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

/// Auswahl für den Reiter Allgemein der Einstellungen (Einhängung durch AP11, uebergabe/Englisch_einhaengen.patch).
struct SpracheFeld: View {
    @AppStorage(Sprache.schluessel) private var sprache = Sprache.system
    @Environment(\.thema) private var thema

    var body: some View {
        Picker("Sprache", selection: $sprache) {
            ForEach(Sprache.allCases) { wahl in
                Text(wahl.titel).tag(wahl)
            }
        }
        .onChange(of: sprache) { _, neu in neu.anwenden() }
        Text("Eine geänderte Sprache gilt nach einem Neustart der App. Zahlen, Beträge und Daten folgen der Region in den Systemeinstellungen.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }
}
