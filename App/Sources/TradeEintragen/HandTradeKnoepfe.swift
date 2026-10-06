import SwiftUI
import TradingCore

/// „Bearbeiten…“ und „Löschen…“ für von Hand eingetragene Trades, im Kopf des Trades-Inspektors.
/// Bei importierten Trades zeigt die Ansicht nichts.
struct HandTradeKnoepfe: View {
    let trade: Trade
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var bearbeitung: TradeEntwurf?
    @State private var loeschfrage = false
    @State private var fehler: String?

    var body: some View {
        if modell.istHandtrade(trade) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                HStack(spacing: Abstand.kachelAbstand) {
                    Button("Bearbeiten…", systemImage: "pencil") { bearbeite() }
                    Button("Löschen…", systemImage: "trash", role: .destructive) { loeschfrage = true }
                }
                .buttonStyle(.borderless)
                if let fehler {
                    Text(verbatim: fehler)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.verlust)
                }
            }
            .sheet(item: $bearbeitung) { entwurf in
                TradeEintragenBlatt(bearbeite: entwurf)
            }
            .confirmationDialog("Diesen Trade löschen?", isPresented: $loeschfrage, titleVisibility: .visible) {
                Button("Trade löschen", role: .destructive) { loesche() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Der von Hand eingetragene Trade verschwindet samt Journal, Tags und Bildern. Das lässt sich nicht rückgängig machen.")
            }
        }
    }

    private func bearbeite() {
        fehler = nil
        bearbeitung = modell.handEntwurf(trade)
        if bearbeitung == nil { fehler = String(localized: "Der Trade ließ sich nicht laden.") }
    }

    private func loesche() {
        fehler = nil
        do {
            try modell.loescheHandtrade(trade)
        } catch {
            fehler = Importlesung.fehlertext(error)
        }
    }
}

extension TradeEntwurf: Identifiable {
    /// Für `.sheet(item:)`: das Ticket, bei einem neuen Entwurf leer.
    var id: String { ticket ?? "" }
}
