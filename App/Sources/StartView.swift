import SwiftUI
import TradingCore

/// Platzhalter-Startansicht, bis das Design-Paket (AP10) steht.
struct StartView: View {
    @State private var connectorStatus = ""

    var body: some View {
        VStack(spacing: 8) {
            Text("greeting")
                .font(.largeTitle)
            Text("version \(TradingCore.version)")
                .foregroundStyle(.secondary)
            // Experiment AP6, nur Entwickleranzeige, daher nicht übersetzt
            Text(verbatim: connectorStatus)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .task {
            #if os(macOS)
            connectorStatus = ConnectorTest.schreibe()
            #endif
        }
    }
}

#Preview {
    StartView()
}
