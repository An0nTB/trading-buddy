import SwiftUI
import TradingAssistant
#if os(macOS)
import AppKit
#endif

/// Claude-Projekt für Frag Henry (Tim 17.10.2026): Auswertungen öffnen das eingetragene Projekt, Code- oder Chat-Projekt,
/// die Frage liegt in der Zwischenablage. Nur die Kennung liegt in den UserDefaults dieses Macs, nie im Export und nie
/// im Repo. Leer heißt wie bisher: neuer Chat ohne Projekt. Die Kursanalyse bleibt immer ohne Projekt.
enum ClaudeProjekt {
    static let schluessel = "claudeProjekt"

    /// Eingetragenes Projekt; `nil` ohne gültigen Eintrag.
    static var ziel: ClaudeProjektziel? {
        UserDefaults.standard.string(forKey: schluessel).flatMap(FragBrad.projekt)
    }

    /// Projekt für diese Vorlage, falls eines eingetragen ist und die Vorlage es nutzt.
    static func fuer(_ vorlage: FragBradVorlage) -> ClaudeProjektziel? {
        FragBrad.nutztProjekt(vorlage) ? ziel : nil
    }

    /// Satz für „Projekt testen“: kommt in die Zwischenablage, Claude antwortet mit dem Stand der Erweiterung.
    /// Deutsch wie alle Fragetexte (Englisch gilt nicht für den Fragetext).
    static let testsatz = "Henry-Status: Rufe henry_status auf und nenne den Stand der Erweiterung."

    #if os(macOS)
    /// Legt `text` in die Zwischenablage und öffnet das Projekt in Claude Desktop; `false` ohne Claude Desktop.
    @MainActor
    static func oeffne(_ ziel: ClaudeProjektziel, text: String) -> Bool {
        FragBradOeffner.kopiere(text)
        guard let link = ziel.link, NSWorkspace.shared.urlForApplication(toOpen: link) != nil else { return false }
        return NSWorkspace.shared.open(link)
    }
    #endif
}

#if os(macOS)
/// Feld im Reiter Claude der Einstellungen: Link oder Kennung einfügen, gespeichert wird nur die Kennung, eine
/// ungültige Eingabe gar nicht. Mit Kurzanleitung und Knopf „Projekt testen“.
struct ClaudeProjektFeld: View {
    @AppStorage(ClaudeProjekt.schluessel) private var gespeichert = ""
    @State private var eingabe = ""
    @State private var meldung: String?
    @Environment(\.thema) private var thema

    var body: some View {
        LabeledContent("Claude-Projekt") {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                HStack {
                    TextField("Claude-Projekt", text: $eingabe, prompt: Text("Link oder Kennung des Projekts"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onChange(of: eingabe) { uebernehmen() }
                    Button("Projekt testen", action: testen)
                        .disabled(FragBrad.projekt(eingabe) == nil)
                    Button("Entfernen") { eingabe = "" }
                        .disabled(eingabe.isEmpty && gespeichert.isEmpty)
                }
                Text(verbatim: meldung ?? status)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(gueltig ? thema.textSchwach : thema.warnung)
                DisclosureGroup("So findest du den Link") {
                    Text("Claude im Browser öffnen (claude.ai), dort das Projekt öffnen und die Adresse aus der Adresszeile kopieren. Ein Claude-Code-Projekt sieht so aus: claude.ai/code/project/chan_…, ein Chat-Projekt so: claude.ai/project/…. Hier einfügen, mehr ist nicht nötig. Die Erweiterung „Henry“ muss in Claude Desktop installiert sein, sonst sieht Claude im Projekt keine Zahlen. Leer lassen heißt: Frag Henry öffnet wie bisher einen neuen Chat.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Schrift.beschriftung)
            }
        }
        .onAppear { eingabe = gespeichert }
    }

    private var gueltig: Bool {
        eingabe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || FragBrad.projekt(eingabe) != nil
    }

    private func uebernehmen() {
        meldung = nil
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            gespeichert = ""
        } else if let ziel = FragBrad.projekt(text) {
            gespeichert = ziel.kennung
        }
    }

    private func testen() {
        guard let ziel = FragBrad.projekt(eingabe) else { return }
        meldung = ClaudeProjekt.oeffne(ziel, text: ClaudeProjekt.testsatz)
            ? String(localized: "Ein Testsatz liegt in der Zwischenablage. In Claude mit ⌘V einfügen und abschicken; Henry nennt dann den Stand der Erweiterung.")
            : String(localized: "Claude Desktop ist auf diesem Mac nicht installiert.")
    }

    private var status: String {
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return String(localized: "Leer: Frag Henry öffnet einen neuen Chat ohne Projekt.")
        }
        switch FragBrad.projekt(text) {
        case .code(let id)?:
            return String(localized: "Claude-Code-Projekt \(id). Auswertungen öffnen dort, die Frage liegt in der Zwischenablage. Die Kursanalyse bleibt ohne Projekt. Nur auf diesem Mac gespeichert.")
        case .chat(let id)?:
            return String(localized: "Chat-Projekt \(id). Auswertungen öffnen dort, die Frage liegt in der Zwischenablage. Die Kursanalyse bleibt ohne Projekt. Nur auf diesem Mac gespeichert.")
        case nil:
            return String(localized: "Keine Projekt-Kennung erkannt, nichts gespeichert. Erwartet wird ein Link wie claude.ai/code/project/chan_… oder claude.ai/project/… oder die Kennung allein.")
        }
    }
}
#endif
