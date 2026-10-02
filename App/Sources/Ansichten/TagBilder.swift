import SwiftUI
import TradingCore
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif
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

    var body: some View {
        Karte("Screenshots") {
            BilderRaster(bilder: tagModell.bilder,
                         hinzufuegen: { tagModell.fuegeBilderHinzu($0) },
                         entfernen: { tagModell.entferne($0) },
                         meldeFehler: { tagModell.fehler = $0 })
            Text("Die App legt eine Kopie im eigenen Bilderordner ab. Gespeichert wird nur der Verweis; die Bilder gehen nicht in den Export für Claude.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }
}

/// Raster mit Vorschauen und Ablagefeld, gemeinsam für Tag, Trade und verpassten Trade: Bilder hineinziehen,
/// über das Feld eine Datei wählen, am iPhone auch aus den Fotos. Klick öffnet die Großansicht.
struct BilderRaster: View {
    let bilder: [Bildverweis]
    let hinzufuegen: ([Bildquelle]) -> Void
    let entfernen: (Bildverweis) -> Void
    let meldeFehler: (String) -> Void
    @Environment(\.thema) private var thema
    @State private var waehlen = false
    @State private var zielAktiv = false
    @State private var gross: GrossesBild?
    #if os(iOS)
    @State private var fotos: [PhotosPickerItem] = []
    #endif

    static let typen: [UTType] = [.png, .jpeg, .heic]

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 160), spacing: Abstand.raster * 2)],
                      alignment: .leading, spacing: Abstand.raster * 2) {
                ForEach(bilder, id: \.datei) { bild in
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
                            entfernen(bild)
                        }
                    }
                }
                ablageFeld
            }
            #if os(iOS)
            PhotosPicker(selection: $fotos, matching: .images) {
                Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderless)
            #endif
        }
        #if os(iOS)
        .onChange(of: fotos) {
            let auswahl = fotos
            guard !auswahl.isEmpty else { return }
            fotos = []
            Task { await uebernimmFotos(auswahl) }
        }
        #endif
        .fileImporter(isPresented: $waehlen, allowedContentTypes: Self.typen,
                      allowsMultipleSelection: true) { ergebnis in
            switch ergebnis {
            case .success(let urls): hinzufuegen(urls.map(Bildquelle.datei))
            case .failure(let fehler): meldeFehler(fehler.localizedDescription)
            }
        }
        .sheet(item: $gross) { auswahl in
            BildBlatt(bild: auswahl.bild) { entfernen(auswahl.bild) }
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
            hinzufuegen(dateien.map(Bildquelle.datei))
            return true
        } isTargeted: { zielAktiv = $0 }
    }

    #if os(iOS)
    /// Lädt die gewählten Fotos als Daten; das Format kommt aus dem Foto (HEIC, JPEG oder PNG).
    private func uebernimmFotos(_ auswahl: [PhotosPickerItem]) async {
        var quellen: [Bildquelle] = []
        var ersterFehler: String?
        for foto in auswahl {
            let typ = foto.supportedContentTypes.first { typ in Self.typen.contains { typ.conforms(to: $0) } }
            guard let endung = typ?.preferredFilenameExtension else {
                ersterFehler = ersterFehler
                    ?? String(localized: "Ein Foto hat kein unterstütztes Format. Möglich sind PNG, JPEG und HEIC.")
                continue
            }
            do {
                if let daten = try await foto.loadTransferable(type: Data.self) {
                    quellen.append(.daten(daten, endung: endung, name: String(localized: "Foto")))
                }
            } catch {
                ersterFehler = ersterFehler ?? error.localizedDescription
            }
        }
        if !quellen.isEmpty { hinzufuegen(quellen) }
        if let ersterFehler { meldeFehler(ersterFehler) }
    }
    #endif
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
