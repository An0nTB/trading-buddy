import SwiftUI
import TradingStore

/// Einstellungen (Doc 10, Abschnitt 7): am Mac ein Fenster mit Reitern, am iPhone eine Liste unter „Mehr“.
/// Alles gilt sofort, kein Speichern-Knopf; Ausnahme „Regeln“, die in der Datenbank liegen und geprüft werden.
struct EinstellungenView: View {
    var body: some View {
        #if os(macOS)
        TabView {
            Tab("Allgemein", systemImage: "gearshape") {
                Form { AllgemeinFelder() }
                    .formStyle(.grouped)
            }
            Tab("Erscheinungsbild", systemImage: "paintpalette") {
                Form { ErscheinungsbildFelder() }
                    .formStyle(.grouped)
            }
            Tab("Börsen", systemImage: "clock") {
                Form { BoersenEinstellungen() }
                    .formStyle(.grouped)
            }
            Tab("Konten", systemImage: "building.columns") {
                KontenView()
            }
            Tab("Regeln", systemImage: "checklist") {
                Form { RegelnEinstellungen() }
                    .formStyle(.grouped)
            }
            Tab("Kurse", systemImage: "chart.line.uptrend.xyaxis") {
                Form { KurseEinstellungen() }
                    .formStyle(.grouped)
            }
            Tab("Claude", systemImage: "sparkles") {
                ClaudeFelder()
            }
        }
        .frame(width: 720, height: 480)
        #else
        Form {
            Section("Erscheinungsbild") { ErscheinungsbildFelder() }
            Section("Allgemein") { AllgemeinFelder() }
            Section("Börsenuhr") {
                NavigationLink("Börsen verwalten") {
                    Form { BoersenEinstellungen() }
                        .navigationTitle("Börsen")
                }
            }
            Section("Regeln") {
                NavigationLink("Handelsregeln und Prop-Firm") {
                    Form { RegelnEinstellungen() }
                        .navigationTitle("Regeln")
                }
            }
            Section("Kurse") {
                NavigationLink("Kurse offener Trades") {
                    Form { KurseEinstellungen() }
                        .navigationTitle("Kurse")
                }
            }
            Section("Claude") {
                Text("Der Claude-Connector und der Export-Ordner laufen am Mac.")
            }
        }
        .navigationTitle("Einstellungen")
        #endif
    }
}

/// Reiter Allgemein: Sprache und Anzeigewährung (beide folgen dem System bzw. dem Konto).
struct AllgemeinFelder: View {
    @AppStorage(Ton.schluessel) private var ton = Ton.bro
    @Environment(\.thema) private var thema

    var body: some View {
        Picker("Ton", selection: $ton) {
            ForEach(Ton.allCases, id: \.self) { wahl in
                Text(wahl.titel).tag(wahl)
            }
        }
        .pickerStyle(.segmented)
        Text("„Brad“ spricht Begrüßung, leere Seiten und Erfolgsmeldungen locker, „Sachlich“ nüchtern. Zahlen, Steuer, Regelverstöße, Warnungen und Fehler bleiben in beiden Stellungen sachlich; der Export für den Claude-Connector trägt die Einstellung mit.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        LabeledContent("Sprache") { Text("Wie System") }
        LabeledContent("Anzeigewährung") { Text("Kontowährung, Umrechnung folgt") }
        Text("Die Sprache stellst du in den Systemeinstellungen je App um; die App liefert Deutsch und Englisch.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }
}

/// Reiter Erscheinungsbild: System/Hell/Dunkel und die vier Farbwelten (Doc 10, E1 und Farbwelten).
struct ErscheinungsbildFelder: View {
    @AppStorage("erscheinungsbild") private var erscheinungsbild = Erscheinungsbild.system
    @AppStorage("farbwelt") private var farbwelt = Farbwelt.nordlicht
    @AppStorage("flaechenGetoent") private var flaechenGetoent = true
    @Environment(\.thema) private var thema
    @Environment(\.colorScheme) private var modus

    var body: some View {
        Picker("Erscheinungsbild", selection: $erscheinungsbild) {
            ForEach(Erscheinungsbild.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        Text("System folgt der Einstellung in den Systemeinstellungen, auch dem automatischen Wechsel am Abend.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        LabeledContent("Farbwelt") {
            HStack(spacing: Abstand.kachelAbstand) {
                ForEach(Farbwelt.allCases) { welt in
                    FarbweltKarte(welt: welt, gewaehlt: welt == farbwelt, modus: modus) { farbwelt = welt }
                }
            }
        }
        Text("Je Farbwelt: Akzent, Gewinn, Verlust. Gilt sofort, in Hell und Dunkel.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        Toggle("Flächen tönen", isOn: $flaechenGetoent)
        Text("An: Grund, Kacheln und Linien nehmen die Farbwelt leicht an. Aus: neutrales Weiß oder Dunkel, die Farbwelt färbt nur Akzent, Gewinn und Verlust.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }
}

/// Eine Farbwelt als Karte mit drei Farbfeldern (Akzent, Gewinn, Verlust) und Auswahlkreis.
struct FarbweltKarte: View {
    let welt: Farbwelt
    let gewaehlt: Bool
    let modus: ColorScheme
    let waehle: () -> Void
    @Environment(\.thema) private var thema

    var body: some View {
        let probe = welt.thema(modus)
        Button(action: waehle) {
            VStack(spacing: Abstand.raster * 2) {
                HStack(spacing: Abstand.raster) {
                    ForEach([probe.akzent, probe.gewinn, probe.verlust], id: \.self) { farbe in
                        RoundedRectangle(cornerRadius: Abstand.radiusKnopf)
                            .fill(farbe)
                            .frame(width: 28, height: 20)
                    }
                }
                Label(welt.name, systemImage: gewaehlt ? "largecircle.fill.circle" : "circle")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.text)
            }
            .padding(Abstand.raster * 2)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
            .overlay(
                RoundedRectangle(cornerRadius: Abstand.radiusKachel)
                    .stroke(gewaehlt ? thema.akzent : thema.linie, lineWidth: gewaehlt ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(gewaehlt ? .isSelected : [])
    }
}

/// Konten und Kosten: Liste der Konten aus der Datenbank. Das Kostenprofil je Konto kommt später.
struct KontenView: View {
    @AppStorage(Ton.schluessel) private var ton = Ton.bro
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Kopfzeile("Konten und Kosten", untertitel: String(localized: "\(modell.konten.count) Konten"))
            if modell.konten.isEmpty {
                ContentUnavailableView(ton.text("Noch kein Konto", bro: "Noch kein Konto, Bro."), systemImage: "building.columns",
                                       description: Text(verbatim: ton.text("Konten entstehen beim ersten Import eines Auszugs.",
                                                                            bro: "Das erste Konto legt Brad beim ersten Import an.")))
            } else {
                List(modell.konten, id: \.id) { konto in
                    HStack {
                        VStack(alignment: .leading, spacing: Abstand.raster) {
                            Text(verbatim: "\(konto.broker) · \(konto.kontoname)")
                                .foregroundStyle(thema.text)
                            Text(verbatim: "\(String(localized: "Konto")) ••••\(konto.kontonummer.suffix(4)) · \(konto.waehrung)")
                                .font(Schrift.beschriftung)
                                .foregroundStyle(thema.textSchwach)
                        }
                        Spacer()
                        Text("Kostenprofil folgt")
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                    .listRowBackground(thema.flaeche)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(Abstand.seitenrand)
    }
}

#if os(macOS)
/// Reiter Claude: Export-Ordner für den Connector (Entscheidung 13, AP6) und die exportierten Felder.
struct ClaudeFelder: View {
    @State private var ordnerWaehlen = false
    @State private var fehler = ""
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        Form {
            LabeledContent("Export-Ordner") {
                VStack(alignment: .leading, spacing: Abstand.raster) {
                    Text(verbatim: ExportOrdner.gemerkterOrdner()?.path ?? String(localized: "noch nicht gewählt"))
                        .textSelection(.enabled)
                    Button("exportFolder.choose") { ordnerWaehlen = true }
                }
            }
            Text("Claude Desktop liest diesen Ordner über die Erweiterung „Brad“. Derselbe Ordner muss in den Einstellungen der Erweiterung stehen.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            LabeledContent("Exportierte Felder") {
                Text("Ticketnummer, Zeiten, Instrument, Richtung, Lots, Kurse, Stop und Ziel, Kommission, Swap, Steuern (falls der Broker sie meldet), Ergebnis, Zeitpunkte gelöschter Orders, Journal (Stop, Setup, Regeltreue, Zustand, Marktumfeld, Grund), Ziele aus Reviews, Broker, Kontowährung, Zeitzone und die letzten vier Stellen der Kontonummer. Nicht: Name, volle Kontonummer, Saldo.")
            }
            if let status = [fehler, modell.exportStand].first(where: { !$0.isEmpty }) {
                Text(verbatim: status)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .formStyle(.grouped)
        .task { modell.exportiere() }
        .fileImporter(isPresented: $ordnerWaehlen, allowedContentTypes: [.folder]) { ergebnis in
            switch ergebnis {
            case .success(let url):
                do {
                    try ExportOrdner.merke(url)
                    fehler = ""
                    modell.exportiere()
                } catch {
                    fehler = error.localizedDescription
                }
            case .failure(let problem):
                fehler = problem.localizedDescription
            }
        }
    }
}
#endif
