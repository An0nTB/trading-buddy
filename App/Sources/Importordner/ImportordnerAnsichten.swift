#if os(macOS)
import SwiftUI

/// Reiter „Import“ der Einstellungen: Import-Ordner ein- und ausschalten und wählen (Doc 45).
struct ImportordnerFelder: View {
    @Environment(\.thema) private var thema
    @State private var ordnerWaehlen = false
    @State private var fehler = ""

    var body: some View {
        let ordner = Importordner.geteilt
        Form {
            Toggle("Import-Ordner beobachten", isOn: Binding(get: { ordner.aktiv }, set: { ordner.setzeAktiv($0) }))
            Toggle("Mitteilung nach stillem Import", isOn: Binding(get: { ordner.mitteilung },
                                                                  set: { ordner.setzeMitteilung($0) }))
            LabeledContent("Ordner") {
                VStack(alignment: .leading, spacing: Abstand.raster) {
                    Text(verbatim: ordner.ordnerPfad ?? String(localized: "noch nicht gewählt"))
                        .textSelection(.enabled)
                    Button("Ordner wählen") { ordnerWaehlen = true }
                }
            }
            Text("Neue Auszüge in diesem Ordner importiert die App selbst, wenn das Konto schon angelegt ist und eindeutig passt. Bei einem neuen Konto, mehreren passenden Konten oder unbekanntem Format fragt sie auf der Seite Import nach. Die Dateien bleiben liegen; schon importierte erkennt die App wieder.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            if let status = [fehler, ordner.stand].first(where: { !$0.isEmpty }) {
                Text(verbatim: status)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $ordnerWaehlen, allowedContentTypes: [.folder]) { ergebnis in
            switch ergebnis {
            case .success(let url):
                do {
                    try ordner.waehle(url)
                    fehler = ""
                } catch {
                    fehler = error.localizedDescription
                }
            case .failure(let problem):
                fehler = problem.localizedDescription
            }
        }
    }
}

/// Auf der Seite Import über der Liste: Dateien aus dem Import-Ordner, zu denen die App nachfragt,
/// und die stillen Importe dieser Sitzung. Ohne beides unsichtbar.
struct ImportordnerKarte: View {
    @Environment(\.thema) private var thema
    @State private var vorschau: ImportVorschau?
    @State private var lesefehler = false

    var body: some View {
        let ordner = Importordner.geteilt
        if !ordner.rueckfragen.isEmpty || !ordner.zuletzt.isEmpty {
            VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                if !ordner.rueckfragen.isEmpty {
                    Text("Import-Ordner: wartet auf dich")
                        .font(Schrift.fliesstext.weight(.semibold))
                        .foregroundStyle(thema.text)
                    ForEach(ordner.rueckfragen) { rueckfrage in
                        zeile(rueckfrage, ordner)
                    }
                }
                if let letzte = ordner.zuletzt.first {
                    Label(String(localized: "Zuletzt aus dem Import-Ordner: \(letzte.dateiname), \(letzte.text), \(Self.zeitpunkt(letzte.zeit))"),
                          systemImage: "tray.and.arrow.down")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            .padding(Abstand.kachelInnen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(thema.flaeche, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
            .sheet(item: $vorschau, onDismiss: { Task { await ordner.pruefe() } }) { vorschau in
                ImportBlatt(vorschau: vorschau)
            }
            .alert("Datei nicht lesbar", isPresented: $lesefehler) {
                Button("OK") { lesefehler = false }
            } message: {
                Text("Die Datei liegt nicht mehr im Ordner oder lässt sich nicht öffnen. Lege sie erneut hinein oder wähle „Ignorieren“.")
            }
        }
    }

    /// Heute nur die Uhrzeit, sonst mit Datum; „Zuletzt“ übersteht einen Neustart.
    static func zeitpunkt(_ zeit: Date) -> String {
        Calendar.current.isDateInToday(zeit)
            ? zeit.formatted(date: .omitted, time: .shortened)
            : zeit.formatted(date: .abbreviated, time: .shortened)
    }

    private func zeile(_ rueckfrage: Importordner.Rueckfrage, _ ordner: Importordner) -> some View {
        HStack(spacing: Abstand.kachelAbstand) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: rueckfrage.dateiname)
                    .foregroundStyle(thema.text)
                Text(verbatim: rueckfrage.grund)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Spacer()
            Button("Ignorieren") { ordner.ignoriere(rueckfrage) }
            Button("Prüfen") {
                vorschau = ordner.vorschau(rueckfrage)
                lesefehler = vorschau == nil
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
#endif
