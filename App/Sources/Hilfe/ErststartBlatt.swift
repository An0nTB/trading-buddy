#if os(macOS)
import SwiftUI

/// „Erste Schritte“ (Nachtpaket AP11, Beta-Weg): drei Schritte bis zur ersten Auswertung in Claude.
/// Erscheint beim Start, solange kein Konto existiert; über Hilfe › „Erste Schritte …“ jederzeit wieder.
struct ErststartBlatt: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HilfeBlaetterZeigen.ausgeblendetSchluessel) private var ausgeblendet = false

    var body: some View {
        let kontoDa = !modell.konten.isEmpty
        let exportDa = ExportOrdner.gemerkterOrdner() != nil
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text("Erste Schritte")
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
            Text("Drei Schritte, dann rechnet Henry mit deinen Trades und Claude kann darauf antworten.")
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.textSchwach)

            ErststartSchritt(nummer: 1, titel: "Konto anlegen", erledigt: kontoDa,
                             text: "Ein Konto entsteht mit dem ersten Import. Henry liest Broker und Kontonummer aus der Datei; Namen und Kontowährung legst du im Import-Blatt fest.")
            ErststartSchritt(nummer: 2, titel: "Datei importieren", erledigt: kontoDa,
                             text: "Lade beim Broker den Kontoauszug herunter (MetaTrader: Bericht als HTML, sonst CSV oder Excel) und wähle ihn auf der Import-Seite.") {
                Button("Zur Import-Seite") {
                    modell.bereich = .importieren
                    dismiss()
                }
            }
            ErststartSchritt(nummer: 3, titel: "Claude verbinden", erledigt: exportDa,
                             text: "Wähle in den Einstellungen unter „Claude“ einen Export-Ordner. Installiere dann die Erweiterung „Henry“ in Claude Desktop und trage dort denselben Ordner ein.") {
                SettingsLink { Text("Einstellungen öffnen") }
            }

            Divider()
            HStack {
                Toggle("Nicht mehr zeigen", isOn: $ausgeblendet)
                Spacer()
                Button("Fertig") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Wieder aufrufbar über Hilfe › Erste Schritte.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        .padding(Abstand.seitenrand)
        .frame(minWidth: 480, idealWidth: 540)
    }
}

/// Ein Schritt mit Nummer oder Haken, Erklärung und optionalem Knopf.
private struct ErststartSchritt<Aktion: View>: View {
    let nummer: Int
    let titel: LocalizedStringKey
    let erledigt: Bool
    let text: LocalizedStringKey
    let aktion: () -> Aktion
    @Environment(\.thema) private var thema

    init(nummer: Int, titel: LocalizedStringKey, erledigt: Bool, text: LocalizedStringKey,
         @ViewBuilder aktion: @escaping () -> Aktion) {
        self.nummer = nummer
        self.titel = titel
        self.erledigt = erledigt
        self.text = text
        self.aktion = aktion
    }

    var body: some View {
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            Image(systemName: erledigt ? "checkmark.circle.fill" : "\(nummer).circle")
                .font(.title2)
                .foregroundStyle(erledigt ? thema.gewinn : thema.akzent)
                .accessibilityLabel(erledigt ? Text("erledigt") : Text(verbatim: "\(nummer)"))
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(titel).font(.headline).foregroundStyle(thema.text)
                Text(text)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                    .fixedSize(horizontal: false, vertical: true)
                aktion()
            }
        }
    }
}

extension ErststartSchritt where Aktion == EmptyView {
    init(nummer: Int, titel: LocalizedStringKey, erledigt: Bool, text: LocalizedStringKey) {
        self.init(nummer: nummer, titel: titel, erledigt: erledigt, text: text) { EmptyView() }
    }
}
#endif
