import SwiftUI
import TradingCore
import UniformTypeIdentifiers

/// Platzhalter-Startansicht, bis das Design-Paket (AP10) steht.
struct StartView: View {
    @State private var connectorStatus = ""
    @State private var ordnerWaehlen = false

    var body: some View {
        VStack(spacing: 8) {
            Text("greeting")
                .font(.largeTitle)
            Text("version \(TradingCore.version)")
                .foregroundStyle(.secondary)
            #if os(macOS)
            Button("exportFolder.choose") { ordnerWaehlen = true }
                .padding(.top, 12)
            // Experiment AP6, nur Entwickleranzeige, daher nicht übersetzt
            Text(verbatim: connectorStatus)
                .font(.caption)
                .foregroundStyle(.tertiary)
            #endif
        }
        .padding()
        #if os(macOS)
        .task { connectorStatus = ExportOrdner.schreibeTestdatei() }
        .fileImporter(isPresented: $ordnerWaehlen, allowedContentTypes: [.folder]) { ergebnis in
            switch ergebnis {
            case .success(let url):
                do {
                    try ExportOrdner.merke(url)
                    connectorStatus = ExportOrdner.schreibeTestdatei()
                } catch {
                    connectorStatus = "Connector-Test: Fehler \(error.localizedDescription)"
                }
            case .failure(let fehler):
                connectorStatus = "Connector-Test: Fehler \(fehler.localizedDescription)"
            }
        }
        #endif
    }
}

#Preview {
    StartView()
}
