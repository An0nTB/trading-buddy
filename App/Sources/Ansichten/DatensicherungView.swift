#if os(macOS)
import SwiftUI
import TradingStore
import UniformTypeIdentifiers

/// Reiter Sicherung: Ordner, täglicher Lauf, Aufbewahrung, „Jetzt sichern“ und „Wiederherstellen“ mit
/// Prüfung und Rückfrage (Frage 5, Tim 02.10.2026). Logik in `Sicherungsdienst`, Store-Teil AP9.
struct DatensicherungFelder: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @AppStorage(Sicherungsdienst.schluesselAktiv) private var aktiv = false
    @AppStorage(Sicherungsdienst.schluesselBehalten) private var behalten = Sicherungsdienst.standardBehalten
    @AppStorage(Sicherungsdienst.schluesselLetzte) private var letzte = 0.0
    /// Ein einziger Dateiwähler für Ordner und Sicherung: zwei `.fileImporter` am selben View reagieren nicht
    /// verlässlich beide (dritter Gegencheck G18). `waehlerArt` bleibt nach dem Schließen stehen, damit die
    /// Antwort der richtigen Wahl zugeordnet wird.
    @State private var waehlerOffen = false
    @State private var waehlerArt = Waehler.ordner
    @AppStorage(Sicherungsdienst.schluesselStand) private var stand = ""
    @State private var auswahl: Auswahl?
    @State private var laeuft = false

    enum Waehler {
        case ordner, sicherung
    }

    /// Gewählte Sicherung mit Prüfbericht, für die Rückfrage.
    struct Auswahl {
        let datei: URL
        let pruefung: Sicherungspruefung
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Ordner") {
                    VStack(alignment: .leading, spacing: Abstand.raster) {
                        Text(verbatim: Sicherungsdienst.gemerkterOrdner()?.path ?? String(localized: "noch nicht gewählt"))
                            .textSelection(.enabled)
                        Button("Ordner wählen …") { oeffne(.ordner) }
                    }
                }
                Toggle("Täglich sichern", isOn: $aktiv)
                Stepper(value: $behalten, in: Sicherungsdienst.behaltenBereich) {
                    Text("Aufbewahren: \(behalten) Sicherungen")
                }
                LabeledContent("Letzte Sicherung") {
                    Text(verbatim: letzte > 0
                         ? Date(timeIntervalSince1970: letzte).formatted(date: .abbreviated, time: .shortened)
                         : String(localized: "noch keine"))
                }
                Button("Jetzt sichern") {
                    laeuft = true
                    Task {
                        await Sicherungsdienst.sichere(modell.journal)
                        laeuft = false
                    }
                }
                .disabled(laeuft || modell.journal == nil || Sicherungsdienst.gemerkterOrdner() == nil)
            } footer: {
                Text("Gesichert werden die Datenbank und die Screenshots. Ist „Täglich sichern“ an, sichert die App beim Start und danach einmal am Tag, solange sie läuft. Schlüssel aus dem Schlüsselbund kommen nicht in die Sicherung.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Section {
                Button("Wiederherstellen …") { oeffne(.sicherung) }
                    .disabled(laeuft || modell.journal == nil)
            } footer: {
                Text("Vor dem Wiederherstellen prüft die App die Datei und legt den aktuellen Stand beiseite.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            if !stand.isEmpty {
                Text(verbatim: stand)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $waehlerOffen,
                      allowedContentTypes: waehlerArt == .ordner ? [UTType.folder] : [Self.sqlite]) { ergebnis in
            switch ergebnis {
            case .success(let url): gewaehlt(url)
            case .failure(let problem): stand = problem.localizedDescription
            }
        }
        .alert(titel, isPresented: rueckfrageSichtbar, presenting: auswahl) { gewaehlt in
            Button("Wiederherstellen", role: .destructive) { stelleWiederHer(gewaehlt.datei) }
            Button("Abbrechen", role: .cancel) {}
        } message: { gewaehlt in
            Text(verbatim: rueckfrage(gewaehlt.pruefung))
        }
    }

    static let sqlite = UTType(filenameExtension: Sicherungsdienst.endung) ?? .data

    private func oeffne(_ art: Waehler) {
        waehlerArt = art
        waehlerOffen = true
    }

    private func gewaehlt(_ url: URL) {
        switch waehlerArt {
        case .ordner:
            do {
                try Sicherungsdienst.merke(url)
                stand = ""
            } catch {
                stand = error.localizedDescription
            }
        case .sicherung:
            Task { await pruefe(url) }
        }
    }

    private func pruefe(_ datei: URL) async {
        let pruefung = await Sicherungsdienst.pruefe(datei)
        guard pruefung.laesstSichWiederherstellen else {
            switch pruefung.zustand {
            case .neuer:
                stand = String(localized: "Die Sicherung stammt aus einer neueren Version der App. Bitte zuerst die App aktualisieren.")
            default:
                stand = String(localized: "Die Datei ist keine lesbare Sicherung und wird nicht eingespielt. \(pruefung.hinweis)")
            }
            return
        }
        auswahl = Auswahl(datei: datei, pruefung: pruefung)
    }

    private var titel: String {
        String(localized: "Sicherung „\(auswahl?.datei.lastPathComponent ?? "")“ einspielen?")
    }

    private var rueckfrageSichtbar: Binding<Bool> {
        Binding(get: { auswahl != nil }, set: { if !$0 { auswahl = nil } })
    }

    private func rueckfrage(_ p: Sicherungspruefung) -> String {
        let bis = p.letzterTrade.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "–"
        let trades = p.geschlossenePositionen + p.ausfuehrungen
        return String(localized: "\(p.konten) Konten, \(trades) Trades und Ausführungen, letzter Trade \(bis). Der aktuelle Stand wird ersetzt und vorher beiseitegelegt.")
    }

    private func stelleWiederHer(_ datei: URL) {
        guard let journal = modell.journal else { return }
        laeuft = true
        Task {
            do {
                stand = try await Sicherungsdienst.stelleWiederHer(datei, journal: journal)
                modell.laden()
                modell.exportiere()
            } catch {
                stand = error.localizedDescription
            }
            laeuft = false
        }
    }
}
#endif
