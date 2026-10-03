import SwiftUI

extension View {
    /// Einhängezeile an der Wurzel des Hauptfensters (Doc 51): prüft beim Start höchstens einmal am Tag und zeigt
    /// eine neuere Version einmal als ruhigen Hinweis mit Link zur Download-Seite. Nur am Mac, iPhone und iPad
    /// bekommen Updates später über TestFlight oder den App Store.
    func aktualisierungsHinweis() -> some View {
        modifier(AktualisierungsHinweis())
    }
}

struct AktualisierungsHinweis: ViewModifier {
    #if os(macOS)
    private var dienst: Aktualisierungsdienst { .geteilt }
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .task {
                // Nie im App-Testlauf, damit Tests nicht ins Netz gehen.
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                await dienst.pruefe()
            }
            .alert(titel, isPresented: sichtbar, presenting: dienst.hinweis) { neu in
                Button("Download-Seite öffnen") {
                    openURL(neu.seite)
                    dienst.gemeldet()
                }
                Button("Später", role: .cancel) { dienst.gemeldet() }
            } message: { _ in
                Text("Henry lädt und installiert nichts selbst. Die Seite zeigt, was neu ist, und die Datei zum Laden.")
            }
    }

    private var titel: String {
        String(localized: "Henry \(dienst.hinweis?.version ?? "") ist da")
    }

    private var sichtbar: Binding<Bool> {
        Binding(get: { dienst.hinweis != nil }, set: { if !$0 { dienst.gemeldet() } })
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}

#if os(macOS)
/// Schalter und Stand für Einstellungen › Allgemein (Mac).
struct AktualisierungFelder: View {
    @AppStorage(Aktualisierung.schalterSchluessel) private var pruefen = true
    private var dienst: Aktualisierungsdienst { .geteilt }
    @Environment(\.openURL) private var openURL
    @Environment(\.thema) private var thema

    var body: some View {
        Toggle("Nach Updates suchen", isOn: $pruefen)
        Text("Einmal am Tag fragt Henry bei GitHub nach, ob es eine neue Version gibt. Hinaus geht nur diese Anfrage, keine Daten aus dem Journal. Henry lädt und installiert nichts selbst.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        LabeledContent("Version") {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: stand)
                HStack {
                    Button("Jetzt prüfen") { Task { await dienst.pruefe(erzwungen: true) } }
                        .disabled(dienst.laeuft)
                    if dienst.gibtNeuere, let neu = dienst.neueste {
                        Button("Download-Seite öffnen") { openURL(neu.seite) }
                    }
                }
            }
        }
    }

    private var stand: String {
        let eigene = Aktualisierung.eigeneVersion
        if dienst.laeuft { return String(localized: "Henry \(eigene) · wird geprüft …") }
        if let fehler = dienst.fehler { return String(localized: "Henry \(eigene) · Prüfung fehlgeschlagen: \(fehler)") }
        if dienst.gibtNeuere, let neu = dienst.neueste {
            return String(localized: "Henry \(eigene) · neu: \(neu.version)")
        }
        guard let zeit = dienst.letztePruefung else { return String(localized: "Henry \(eigene) · noch nicht geprüft") }
        let wann = zeit.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Henry \(eigene) · aktuell, geprüft \(wann)")
    }
}
#endif
