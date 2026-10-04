import SwiftUI
import TradingStore
#if os(macOS)
import AppKit
#endif

/// Statt der Seiten, wenn die Journal-Datei beim Start beschädigt ist oder aus einer neueren App-Version stammt
/// (AP9 #225). Zwei Wege, beide legen die alte Datei nur beiseite: letzte Sicherung zurückspielen oder neu beginnen.
struct StartfehlerView: View {
    let fehler: JournalFehler
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var angebot: Startwiederherstellung.Angebot?
    @State private var gesucht = false
    @State private var neuFragen = false

    /// Der gemerkte Sicherungsordner (nur macOS, Tagesseite-Thread).
    private static var ordner: URL? {
        #if os(macOS)
        Sicherungsdienst.gemerkterOrdner()
        #else
        nil
        #endif
    }

    private var neuererVersion: Bool {
        if case .ausNeuererVersion = fehler { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Text("Das Journal lässt sich nicht öffnen")
                    .font(Schrift.titel)
                    .foregroundStyle(thema.text)
                if neuererVersion {
                    Text("Bitte die neuere App-Version verwenden. Die Datei ist in Ordnung; diese Version kennt nur ihren Aufbau noch nicht.")
                        .font(Schrift.fliesstext)
                        .foregroundStyle(thema.text)
                }
                Text(verbatim: fehler.localizedDescription)
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
                Text("Beide Wege benennen die alte Datei nur um; gelöscht wird nichts.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                Divider()
                sicherung
                Divider()
                Button("Neu beginnen", role: .destructive) { neuFragen = true }
            }
            .padding(Abstand.seitenrand)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task {
            let ordner = Self.ordner
            angebot = await Task.detached(priority: .userInitiated) { Startwiederherstellung.angebot(in: ordner) }.value
            gesucht = true
        }
        .confirmationDialog("Mit einem leeren Journal beginnen?", isPresented: $neuFragen, titleVisibility: .visible) {
            Button("Neu beginnen", role: .destructive) {
                do { try modell.startNeu() } catch { modell.fehler = error.localizedDescription }
            }
        } message: {
            Text(neuererVersion
                 ? "Die alte Datei ist gültig und bleibt umbenannt liegen. Mit der neueren App-Version lässt sie sich später wieder öffnen."
                 : "Die alte Datei bleibt umbenannt liegen. Trades, Journal und Regeln beginnen leer.")
        }
    }

    @ViewBuilder private var sicherung: some View {
        if !gesucht {
            ProgressView("Sicherung wird gesucht …")
        } else if let angebot {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text("Letzte Sicherung: \(angebot.datei.lastPathComponent)")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                Text("\(angebot.pruefung.konten) Konten, \(angebot.pruefung.geschlossenePositionen) geschlossene Positionen")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                if let letzter = angebot.pruefung.letzterTrade {
                    Text("Letzter Trade darin: \(letzter.formatted(date: .abbreviated, time: .shortened))")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                Button("Letzte Sicherung zurückspielen") {
                    do {
                        try modell.startAusSicherung(angebot, ordner: Self.ordner)
                    } catch {
                        modell.fehler = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            Text("Keine brauchbare Sicherung im Sicherungsordner gefunden.")
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.textSchwach)
        }
    }
}

extension View {
    /// Meldung nach dem Ausweg aus der Journal-Datei, mit „Im Finder zeigen“ für die beiseitegelegte Datei.
    func startmeldung(_ modell: AppModell) -> some View {
        @Bindable var modell = modell
        let sichtbar = Binding(get: { modell.startmeldung != nil }, set: { if !$0 { modell.startmeldung = nil } })
        return alert("Journal wieder bereit", isPresented: sichtbar) {
            #if os(macOS)
            if let beiseite = modell.startmeldung?.beiseite {
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([beiseite]) }
            }
            #endif
            Button("OK") {}
        } message: {
            Text(verbatim: modell.startmeldung?.text ?? "")
        }
    }
}
