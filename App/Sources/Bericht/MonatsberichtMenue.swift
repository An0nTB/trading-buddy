import SwiftUI
import TradingCore
#if os(iOS)
import PDFKit
#endif

/// Menü „Bericht als PDF“ mit den Monaten und Kalenderwochen, in denen Trades geschlossen wurden
/// (neueste zuerst). Mac: Sichern-Dialog. iPhone und iPad: Vorschau mit Teilen-Knopf. Einhängen übernimmt AP11
/// (Menü „Ablage“ und Werkzeugleiste, Patch in uebergabe/Monatsbericht_PDF_einhaengen.patch).
struct MonatsberichtMenue: View {
    /// Mehr Monate machen das Menü unübersichtlich; ältere Berichte sind selten.
    static let hoechstensMonate = 24
    /// Ein Vierteljahr Wochen; der Wochenbericht dient der laufenden Auswertung.
    static let hoechstensWochen = 13
    @Environment(AppModell.self) private var modell
    @AppStorage("farbwelt") private var farbwelt = Farbwelt.nordlicht
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @State private var datei: BerichtDatei?
    @State private var zeitraumOffen = false
    #endif

    var body: some View {
        let wochen = Array(modell.berichtWochen.prefix(Self.hoechstensWochen))
        Menu("Bericht als PDF", systemImage: "doc.richtext") {
            Section("Monatsbericht") {
                ForEach(modell.monate.prefix(Self.hoechstensMonate), id: \.self) { monat in
                    Button(Format.monat(monat)) {
                        erstelle(modell.monatsbericht(monat))
                    }
                }
            }
            Section("Wochenbericht") {
                ForEach(wochen, id: \.self) { montag in
                    Button(wochentitel(montag)) {
                        erstelle(modell.wochenbericht(montag))
                    }
                }
            }
            Divider()
            Button("Zeitraum …") {
                #if os(macOS)
                openWindow(id: BerichtZeitraumBlatt.fensterID)
                #else
                zeitraumOffen = true
                #endif
            }
        }
        .disabled(modell.monate.isEmpty)
        .help("Monats- oder Wochenbericht des gewählten Kontos als PDF, zum Ablegen oder Weitergeben")
        #if os(iOS)
        .sheet(item: $datei) { datei in
            BerichtVorschau(datei: datei)
        }
        .sheet(isPresented: $zeitraumOffen) {
            BerichtZeitraumBlatt()
        }
        #endif
    }

    /// z. B. „KW 40: 28.09.2026 bis 04.10.2026“.
    private func wochentitel(_ montag: Date) -> String {
        let zeitraum = Zeitspanne.woche(mit: montag, zeitzone: modell.zeitzone)
        let erster = BerichtKontext.datum(Journaltag(zeitraum.von, zeitzone: modell.zeitzone))
        let letzter = BerichtKontext.datum(Journaltag(zeitraum.bis.addingTimeInterval(-1), zeitzone: modell.zeitzone))
        guard let kw = zeitraum.kalenderwoche(zeitzone: modell.zeitzone) else {
            return String(localized: "\(erster) bis \(letzter)")
        }
        return String(localized: "KW \(kw.woche): \(erster) bis \(letzter)")
    }

    private func erstelle(_ ergebnis: BerichtErgebnis) {
        let thema = BerichtPDF.druckthema(farbwelt)
        do {
            #if os(macOS)
            _ = try BerichtAusgabe.sichern(ergebnis, thema: thema)
            #else
            datei = try BerichtAusgabe.datei(ergebnis, thema: thema)
            #endif
        } catch {
            modell.fehler = error.localizedDescription
        }
    }
}

#if os(iOS)
struct BerichtDatei: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Vorschau des fertigen PDFs mit Teilen-Blatt (Dateien, Mail, Drucken).
struct BerichtVorschau: View {
    let datei: BerichtDatei
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BerichtPDFAnsicht(url: datei.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(datei.url.deletingPathExtension().lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: datei.url)
                    }
                }
        }
    }
}

struct BerichtPDFAnsicht: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let ansicht = PDFView()
        ansicht.autoScales = true
        ansicht.document = PDFDocument(url: url)
        return ansicht
    }

    func updateUIView(_ ansicht: PDFView, context: Context) {}
}
#endif
