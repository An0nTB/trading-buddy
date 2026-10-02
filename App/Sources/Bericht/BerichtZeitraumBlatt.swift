import SwiftUI
import TradingCore

/// Bericht über frei gewählte Tage (Tim 02.10.2026, Frage 4). Mac: eigenes kleines Fenster, geöffnet aus
/// dem Menü „Bericht als PDF“; die Szene hängt AP11 in TradingBuddyApp ein
/// (uebergabe/Bericht_Zeitraum_einhaengen.patch). iPhone und iPad: Blatt über der Kennzahlen-Seite.
struct BerichtZeitraumBlatt: View {
    static let fensterID = "bericht-zeitraum"
    @Environment(AppModell.self) private var modell
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thema) private var thema
    @AppStorage("farbwelt") private var farbwelt = Farbwelt.nordlicht
    /// Standard: die letzten sieben Tage einschließlich heute.
    @State private var von = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var bis = Date()
    @State private var meldung: String?
    #if os(iOS)
    @State private var datei: BerichtDatei?
    #endif

    var body: some View {
        #if os(macOS)
        VStack(alignment: .trailing, spacing: Abstand.raster * 4) {
            formular
            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("PDF erstellen") { erstelle() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Abstand.raster * 5)
        // Nur Mindestbreite, keine harte Breite im Fensterinhalt (Lehre aus dem Startabsturz 02.10.2026).
        .frame(minWidth: 340)
        #else
        NavigationStack {
            formular
                .navigationTitle("Bericht für Zeitraum")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("PDF erstellen") { erstelle() }
                    }
                }
        }
        .sheet(item: $datei) { datei in
            BerichtVorschau(datei: datei)
        }
        #endif
    }

    private var formular: some View {
        Form {
            DatePicker("Von", selection: $von, displayedComponents: .date)
            DatePicker("Bis", selection: $bis, displayedComponents: .date)
            Text("Beide Tage zählen mit. Ein Trade zählt zum Tag, an dem er geschlossen wurde. Verglichen wird mit dem gleich langen Zeitraum davor.")
                .font(.footnote)
                .foregroundStyle(thema.textSchwach)
            if let meldung {
                Text(verbatim: meldung)
                    .font(.footnote)
                    .foregroundStyle(thema.verlust)
            }
        }
        .formStyle(.grouped)
    }

    private func erstelle() {
        guard let ergebnis = modell.zeitraumbericht(von: von, bis: bis) else {
            meldung = String(localized: "„Bis“ liegt vor „Von“.")
            return
        }
        meldung = nil
        let thema = BerichtPDF.druckthema(farbwelt)
        do {
            #if os(macOS)
            if try BerichtAusgabe.sichern(ergebnis, thema: thema) { dismiss() }
            #else
            datei = try BerichtAusgabe.datei(ergebnis, thema: thema)
            #endif
        } catch {
            meldung = error.localizedDescription
        }
    }
}
