import SwiftUI

/// Blatt „Werte für den Kurschart“: eigenen Wert eingeben, eigene Werte entfernen (Tim 05.10.2026).
struct ChartwerteBlatt: View {
    /// Wird mit dem neuen Wert aufgerufen, damit der Kurschart ihn gleich zeigt.
    let gewaehlt: (String) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen
    @State private var eingabe = ""
    @State private var meldung: String?

    var body: some View {
        let kurse = modell.kurse
        NavigationStack {
            Form {
                Section {
                    TextField("Wert", text: $eingabe, prompt: Text("BTC/EUR, ETH/USD oder AAPL"))
                        .onSubmit(hinzufuegen)
                    Button("Hinzufügen", action: hinzufuegen)
                        .disabled(eingabe.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let meldung {
                        Text(verbatim: meldung)
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.verlust)
                    }
                }
                Section("Eigene Werte") {
                    if kurse.chartwerte.isEmpty {
                        Text("Noch keine eigenen Werte.")
                            .foregroundStyle(thema.textSchwach)
                    }
                    ForEach(kurse.chartwerte, id: \.self) { wert in
                        HStack {
                            Text(verbatim: wert)
                            Spacer()
                            Button("Entfernen", systemImage: "trash") { kurse.entferneChartwert(wert) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                        .contextMenu {
                            Button("Entfernen", role: .destructive) { kurse.entferneChartwert(wert) }
                        }
                    }
                }
                Section {
                    Text("Krypto kommt von Kraken ohne Schlüssel, US-Aktien von Alpaca mit dem Schlüssel aus Einstellungen › Kurse. CFDs und Devisen des Brokers haben keinen freien Kurs.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Werte für den Kurschart")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { schliessen() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 380)
        #endif
    }

    private func hinzufuegen() {
        switch modell.kurse.fuegeChartwertHinzu(eingabe) {
        case .wert(let symbol):
            meldung = nil
            eingabe = ""
            gewaehlt(symbol)
            schliessen()
        case .fehler(let text):
            meldung = text
        }
    }
}
