import SwiftUI
import TradingCore

/// Platzhalter-Startansicht, bis das Design-Paket (AP10) steht.
struct StartView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("greeting")
                .font(.largeTitle)
            Text("version \(TradingCore.version)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    StartView()
}
