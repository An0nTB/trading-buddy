import SwiftUI
import TradingStore

/// Bereiche der App (Doc 10, Aufbau A): Seitenleiste am Mac und iPad, Tab-Leiste am iPhone.
enum Bereich: String, Identifiable, Hashable {
    case uebersicht, trades, kennzahlen, fehlermuster, kalender, tag, steuer, nachrichten, kurschart, boersenuhr, positionsrechner, importieren, konten, einstellungen, mehr, ziele, lernen

    var id: String { rawValue }

    /// Seitenleiste, Abschnitt „Journal“.
    static let journal: [Bereich] = [.uebersicht, .tag, .trades, .kennzahlen, .fehlermuster, .ziele, .kalender, .steuer]
    /// Seitenleiste, Abschnitt „Markt“ (Börsenuhr nach Tims Wunsch vom 01.10.2026, Positionsrechner aus #47; nicht in Aufbau A gezeichnet).
    static let markt: [Bereich] = [.nachrichten, .kurschart, .boersenuhr, .positionsrechner]
    /// Seitenleiste, Abschnitt „Daten“.
    static let daten: [Bereich] = [.importieren, .konten]
    /// Seitenleiste, Abschnitt „Wissen“ (Lernbereich, Stand-Doc 40).
    static let wissen: [Bereich] = [.lernen]
    /// Tab-Leiste am iPhone.
    static let tabs: [Bereich] = [.uebersicht, .trades, .kennzahlen, .kalender, .mehr]
    /// Einträge unter „Mehr“ am iPhone.
    static let unterMehr: [Bereich] = [.tag, .fehlermuster, .ziele, .steuer, .nachrichten, .kurschart, .boersenuhr, .positionsrechner, .importieren, .konten, .lernen, .einstellungen]

    var titel: LocalizedStringKey {
        switch self {
        case .uebersicht: "Übersicht"
        case .trades: "Trades"
        case .kennzahlen: "Kennzahlen"
        case .fehlermuster: "Fehlermuster"
        case .ziele: "Ziele"
        case .kalender: "Kalender"
        case .tag: "Tag"
        case .steuer: "Steuer"
        case .nachrichten: "Nachrichten"
        case .kurschart: "Kurschart"
        case .boersenuhr: "Börsenuhr"
        case .positionsrechner: "Positionsrechner"
        case .importieren: "Import"
        case .konten: "Konten und Kosten"
        case .einstellungen: "Einstellungen"
        case .mehr: "Mehr"
        case .lernen: "Lernen"
        }
    }

    var symbol: String {
        switch self {
        case .uebersicht: "square.grid.2x2"
        case .trades: "list.bullet.rectangle"
        case .kennzahlen: "chart.bar.xaxis"
        case .fehlermuster: "exclamationmark.triangle"
        case .ziele: "target"
        case .kalender: "calendar"
        case .tag: "sun.max"
        case .steuer: "percent"
        case .nachrichten: "newspaper"
        case .kurschart: "chart.xyaxis.line"
        case .boersenuhr: "clock"
        case .positionsrechner: "plus.forwardslash.minus"
        case .importieren: "square.and.arrow.down"
        case .konten: "building.columns"
        case .einstellungen: "gear"
        case .mehr: "ellipsis"
        case .lernen: "book"
        }
    }
}

/// Wurzel des Hauptfensters: wählt zwischen Seitenleiste und Tab-Leiste und zeigt Fehler.
struct Hauptfenster: View {
    @Environment(AppModell.self) private var modell
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if breite == .compact {
                TabLeiste()
            } else {
                Seitenleiste()
            }
            #else
            Seitenleiste()
            #endif
        }
        .alert("Fehler", isPresented: fehlerSichtbar) {
            Button("OK") { modell.fehler = nil }
        } message: {
            Text(verbatim: modell.fehler ?? "")
        }
        .fragBradBlatt() // Frag Henry (Doc 31): an der Wurzel, damit es auch in der Tab-Leiste am iPhone wirkt
    }

    private var fehlerSichtbar: Binding<Bool> {
        Binding(get: { modell.fehler != nil }, set: { if !$0 { modell.fehler = nil } })
    }
}

/// Mac und iPad: Seitenleiste mit den Abschnitten Journal und Daten, Konto-Zeile unten.
struct Seitenleiste: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        NavigationSplitView {
            // Konto-Zeile unter der List statt als safeAreaInset: Der Inset ließ AppKit die Seitenleiste bei jedem
            // Layout-Pass neu messen (Startabsturz 02.10.2026, Update-Constraints-Schleife; Befund Codex und AP11).
            VStack(spacing: 0) {
                List(selection: auswahl) {
                    Section("Journal") {
                        ForEach(Bereich.journal) { bereich in
                            Label(bereich.titel, systemImage: bereich.symbol)
                                .listItemTint(thema.akzent)
                                .tag(bereich)
                                .inNeuemFenster(bereich) // P12 Eigene Fenster
                        }
                    }
                    Section("Markt") {
                        ForEach(Bereich.markt) { bereich in
                            Label(bereich.titel, systemImage: bereich.symbol)
                                .listItemTint(thema.akzent)
                                .tag(bereich)
                                .inNeuemFenster(bereich) // P12 Eigene Fenster
                        }
                    }
                    Section("Daten") {
                        ForEach(Bereich.daten) { bereich in
                            Label(bereich.titel, systemImage: bereich.symbol)
                                .listItemTint(thema.akzent)
                                .tag(bereich)
                                .inNeuemFenster(bereich) // P12 Eigene Fenster
                        }
                    }
                    Section("Wissen") {
                        ForEach(Bereich.wissen) { bereich in
                            Label(bereich.titel, systemImage: bereich.symbol)
                                .listItemTint(thema.akzent)
                                .tag(bereich)
                                .inNeuemFenster(bereich) // P12 Eigene Fenster
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                KontoZeile()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .navigationTitle("Henry")
            .navigationSplitViewColumnWidth(min: 180, ideal: Abstand.seitenleiste)
        } detail: {
            BereichInhalt(bereich: modell.bereich)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(thema.grund)
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    private var auswahl: Binding<Bereich?> {
        Binding(get: { modell.bereich }, set: { if let bereich = $0 { modell.bereich = bereich } })
    }
}

/// Konto-Zeile unten in der Seitenleiste: Konto wählen, Währung und Anzahl Trades.
struct KontoZeile: View {
    @Environment(AppModell.self) private var modell

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster / 2) {
            if modell.konten.isEmpty {
                Label("Noch kein Konto", systemImage: "building.columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Auswahlknopf("Konto", anzeige: kontoText, auswahl: kontoAuswahl, mitHintergrund: false) {
                    ForEach(modell.konten, id: \.id) { konto in
                        Text(verbatim: kontoName(konto)).tag(konto.id)
                    }
                }
                Text(verbatim: "\(modell.waehrung) · \(modell.alleTrades.count) Trades")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Abstand.kachelAbstand)
        .padding(.vertical, Abstand.raster * 2)
    }

    private var kontoAuswahl: Binding<Int64?> {
        Binding(get: { modell.konto?.id }, set: { modell.waehleKonto($0) })
    }

    private var kontoText: String {
        modell.konto.map(kontoName) ?? ""
    }

    private func kontoName(_ konto: Konto) -> String {
        "\(konto.broker) · \(konto.kontoname)"
    }
}

#if os(iOS)
/// iPhone: Tab-Leiste Übersicht, Trades, Kennzahlen, Kalender, Mehr (Doc 10, Abschnitt 8).
struct TabLeiste: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        TabView(selection: tabAuswahl) {
            ForEach(Bereich.tabs) { bereich in
                Tab(bereich.titel, systemImage: bereich.symbol, value: bereich) {
                    NavigationStack {
                        BereichInhalt(bereich: bereich)
                            .background(thema.grund)
                    }
                }
            }
        }
    }

    /// Bereiche ohne eigenen Tab (Fehlermuster, Import, Konten, Einstellungen) liegen unter „Mehr“.
    private var tabAuswahl: Binding<Bereich> {
        Binding(get: { Bereich.tabs.contains(modell.bereich) ? modell.bereich : .mehr },
                set: { modell.bereich = $0 })
    }
}
#endif

/// Inhalt eines Bereichs, gleich für Seitenleiste und Tab-Leiste.
struct BereichInhalt: View {
    let bereich: Bereich
    @Environment(AppModell.self) private var modell

    var body: some View {
        switch bereich {
        case .uebersicht: UebersichtView()
        case .trades: TradesView()
        case .kennzahlen: KennzahlenView()
        case .fehlermuster: FehlermusterView()
        case .ziele: ZieleView()
        case .kalender: KalenderView()
        case .tag: TagView() // Paket P7 (#65); dauerhafte Ablage folgt mit TradingStore v8
        case .steuer: SteuerView()
        case .nachrichten: NachrichtenView()
        case .kurschart: KurschartView() // Kurse-Thread, Stand-Doc 20 Abschnitt 11
        case .boersenuhr: BoersenuhrView()
        case .positionsrechner:
            // Kontostand kennt die App nicht (die Kapitalkurve startet bei 0), der Nutzer trägt ihn ein.
            PositionsrechnerView(kontogroesse: nil, waehrung: modell.waehrung)
        case .importieren: ImportView()
        case .konten: KontenView()
        case .einstellungen: EinstellungenView()
        case .mehr: MehrListe()
        case .lernen: LernenView() // Lernbereich Trading-Wissen (Stand-Doc 40)
        }
    }
}

/// „Mehr“ am iPhone: Liste der Bereiche ohne eigenen Tab.
struct MehrListe: View {
    var body: some View {
        List(Bereich.unterMehr) { bereich in
            NavigationLink(value: bereich) {
                Label(bereich.titel, systemImage: bereich.symbol)
            }
        }
        .navigationTitle("Mehr")
        .navigationDestination(for: Bereich.self) { bereich in
            BereichInhalt(bereich: bereich)
        }
    }
}
