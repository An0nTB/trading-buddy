import SwiftUI
import TradingCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Screenshots des Tages: Bilder hierher ziehen oder über „Bild“ wählen. Die App kopiert sie in ihren
/// Bilderordner und speichert nur den relativen Pfad; im Export für Claude stehen keine Bilddaten.
struct TagBilderKarte: View {
    let tagModell: TagModell
    @Environment(\.thema) private var thema
    @State private var waehlen = false
    @State private var zielAktiv = false
    @State private var gross: GrossesBild?

    private static let typen: [UTType] = [.png, .jpeg, .heic]

    var body: some View {
        Karte("Screenshots") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 160), spacing: Abstand.raster * 2)],
                      alignment: .leading, spacing: Abstand.raster * 2) {
                ForEach(tagModell.bilder, id: \.datei) { bild in
                    Button {
                        gross = GrossesBild(bild: bild)
                    } label: {
                        BildVorschau(datei: bild.datei)
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Bild entfernen", systemImage: "trash", role: .destructive) {
                            tagModell.entferne(bild)
                        }
                    }
                }
                ablageFeld
            }
            Text("Die App legt eine Kopie im eigenen Bilderordner ab. Gespeichert wird nur der Verweis; die Bilder gehen nicht in den Export für Claude.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        .fileImporter(isPresented: $waehlen, allowedContentTypes: Self.typen, allowsMultipleSelection: true) { ergebnis in
            switch ergebnis {
            case .success(let urls): tagModell.fuegeBilderHinzu(urls)
            case .failure(let fehler): tagModell.fehler = fehler.localizedDescription
            }
        }
        .sheet(item: $gross) { auswahl in
            BildBlatt(bild: auswahl.bild) { tagModell.entferne(auswahl.bild) }
        }
    }

    /// Feld zum Hineinziehen; ein Klick öffnet die Dateiauswahl.
    private var ablageFeld: some View {
        Button {
            waehlen = true
        } label: {
            VStack(spacing: Abstand.raster) {
                Image(systemName: "photo.badge.plus")
                Text("Bild hierher ziehen oder wählen")
                    .multilineTextAlignment(.center)
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(zielAktiv ? thema.akzent : thema.textSchwach)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(zielAktiv ? thema.akzentTint : .clear,
                        in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
            .overlay(RoundedRectangle(cornerRadius: Abstand.radiusKnopf)
                .strokeBorder(zielAktiv ? thema.akzent : thema.linie, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            let dateien = urls.filter(\.isFileURL)
            guard !dateien.isEmpty else { return false }
            tagModell.fuegeBilderHinzu(dateien)
            return true
        } isTargeted: { zielAktiv = $0 }
    }
}

/// Gewähltes Bild für die Großansicht; der Pfad ist eindeutig.
struct GrossesBild: Identifiable {
    let bild: Bildverweis
    var id: String { bild.datei }
}

/// Lädt ein Bild aus dem Bilderordner abseits des Hauptthreads; ohne Datei ein Platzhalter.
struct BildVorschau: View {
    let datei: String
    var anpassen: ContentMode = .fill
    @Environment(\.thema) private var thema
    @State private var bild: Image?
    @State private var fehlt = false

    var body: some View {
        ZStack {
            Rectangle().fill(thema.flaeche2)
            if let bild {
                bild
                    .resizable()
                    .aspectRatio(contentMode: anpassen)
            } else if fehlt {
                Image(systemName: "photo")
                    .foregroundStyle(thema.textSchwach)
                    .help("Datei fehlt im Bilderordner")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: datei) { await lade() }
    }

    private func lade() async {
        guard let url = Bilderordner.url(fuer: datei) else {
            fehlt = true
            return
        }
        let daten = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        guard let daten else {
            fehlt = true
            return
        }
        #if os(macOS)
        bild = NSImage(data: daten).map { Image(nsImage: $0) }
        #else
        bild = UIImage(data: daten).map { Image(uiImage: $0) }
        #endif
        fehlt = bild == nil
    }
}

/// Großansicht eines Screenshots mit Entfernen.
struct BildBlatt: View {
    let bild: Bildverweis
    let entfernen: () -> Void
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        NavigationStack {
            BildVorschau(datei: bild.datei, anpassen: .fit)
                .navigationTitle(Text(verbatim: Format.zeit(bild.erstellt)))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { schliessen() }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Bild entfernen", role: .destructive) {
                            entfernen()
                            schliessen()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 440)
        #endif
    }
}
