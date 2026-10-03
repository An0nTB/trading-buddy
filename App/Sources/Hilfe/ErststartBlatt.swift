#if os(macOS)
import SwiftUI

/// „Erste Schritte“ (Nachtpaket AP11, Beta-Weg): drei Schritte bis zur ersten Auswertung in Claude.
/// Erscheint beim Start, solange kein Konto existiert; über Hilfe › „Erste Schritte …“ jederzeit wieder.
struct ErststartBlatt: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HilfeBlaetterZeigen.ausgeblendetSchluessel) private var ausgeblendet = false
    @AppStorage(Ton.schluessel) private var ton = Ton.henry

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

            if !kontoDa {
                beispieldaten
            }

            ErststartSchritt(nummer: 1, titel: "Konto anlegen", erledigt: kontoDa,
                             text: "Ein Konto entsteht mit dem ersten Import. Henry liest Broker und Kontonummer aus der Datei; Namen und Kontowährung legst du im Import-Blatt fest.")
            ErststartSchritt(nummer: 2, titel: "Datei importieren", erledigt: kontoDa,
                             text: "Lade beim Broker den Kontoauszug herunter und wähle ihn auf der Import-Seite. MetaTrader 4: den Tagesauszug als HTML aus der Mail deines Brokers. MetaTrader 5: den Handelsbericht. Andere Broker: CSV oder Excel.") {
                Button("Zur Import-Seite") {
                    modell.bereich = .importieren
                    dismiss()
                }
            }
            ErststartSchritt(nummer: 3, titel: "Claude verbinden", erledigt: exportDa,
                             text: "Wähle in den Einstellungen unter „Claude“ einen Export-Ordner. Die Erweiterung „Henry“ ist die Datei „Henry-Connector“, die du mit der App bekommen hast: Doppelklick öffnet sie in Claude Desktop. Trag dort denselben Ordner ein.") {
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
        .onExitCommand { dismiss() } // Esc schließt wie „Fertig“ (Doc 55 J16)
    }
}

extension ErststartBlatt {
    /// Beispieldaten für Tester (Hauptthread 03.10.2026): erst ansehen, später mit einem Klick entfernen.
    private var beispieldaten: some View {
        HStack(alignment: .center, spacing: Abstand.kachelAbstand) {
            Text(ton.text("Ohne eigene Datei: Ein Beispielkonto mit 60 erfundenen Trades zeigt, was die App kann. Entfernen geht mit einem Klick unten in der Seitenleiste.",
                          henry: "Erst einmal nur schauen? Ein Beispielkonto mit 60 erfundenen Trades. Später unten in der Seitenleiste mit einem Klick wieder fort."))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Mit Beispieldaten ansehen") {
                do {
                    try modell.legeBeispieldatenAn()
                    modell.bereich = .uebersicht
                    dismiss()
                } catch {
                    modell.fehler = String(localized: "Beispieldaten: \(error.localizedDescription)")
                }
            }
        }
        .padding(Abstand.kachelAbstand)
        .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
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
