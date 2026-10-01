import SwiftUI
import TradingStore

/// Bereiche der App (Doc 10, Aufbau A): Seitenleiste am Mac und iPad, Tab-Leiste am iPhone.
enum Bereich: String, Identifiable, Hashable {
    case uebersicht, trades, kennzahlen, fehlermuster, kalender, importieren, konten, einstellungen, mehr

    var id: String { rawValue }

    /// Seitenleiste, Abschnitt „Journal“.
    static let journal: [Bereich] = [.uebersicht, .trades, .kennzahlen, .fehlermuster, .kalender]
    /// Seitenleiste, Abschnitt „Daten“.
    static let daten: [Bereich] = [.importieren, .konten]
    /// Tab-Leiste am iPhone.
    static let tabs: [Bereich] = [.uebersicht, .trades, .kennzahlen, .kalender, .mehr]
    /// Einträge unter „Mehr“ am iPhone.
    static let unterMehr: [Bereich] = [.fehlermuster, .importieren, .konten, .einstellungen]

    var titel: LocalizedStringKey {
        switch self {
        case .uebersicht: "Übersicht"
        case .trades: "Trades"
        case .kennzahlen: "Kennzahlen"
        case .fehlermuster: "Fehlermuster"
        case .kalender: "Kalender"
        case .importieren: "Import"
        case .konten: "Konten und Kosten"
        case .einstellungen: "Einstellungen"
        case .mehr: "Mehr"
        }
    }

    var symbol: String {
        switch self {
        case .uebersicht: "square.grid.2x2"
        case .trades: "list.bullet.rectangle"
        case .kennzahlen: "chart.bar.xaxis"
        case .fehlermuster: "exclamationmark.triangle"
        case .kalender: "calendar"
        case .importieren: "square.and.arrow.down"
        case .konten: "building.columns"
        case .einstellungen: "gear"
        case .mehr: "ellipsis"
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
            List(selection: auswahl) {
                Section("Journal") {
                    ForEach(Bereich.journal) { bereich in
                        Label(bereich.titel, systemImage: bereich.symbol).tag(bereich)
                    }
                }
                Section("Daten") {
                    ForEach(Bereich.daten) { bereich in
                        Label(bereich.titel, systemImage: bereich.symbol).tag(bereich)
                    }
                }
            }
            .navigationTitle("Trading Buddy")
            .navigationSplitViewColumnWidth(min: 180, ideal: Abstand.seitenleiste)
            .safeAreaInset(edge: .bottom) { KontoZeile() }
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
                Picker("Konto", selection: kontoAuswahl) {
                    ForEach(modell.konten, id: \.id) { konto in
                        Text(verbatim: "\(konto.broker) · \(konto.kontoname)").tag(konto.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
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

    var body: some View {
        switch bereich {
        case .uebersicht: UebersichtView()
        case .trades: TradesView()
        case .kennzahlen: KennzahlenView()
        case .fehlermuster: FehlermusterView()
        case .kalender:
            Platzhalter(titel: "Kalender folgt", symbol: "calendar",
                        text: "Termine und Börsenzeiten kommen mit dem Wirtschaftskalender nach der ersten Version.")
        case .importieren: ImportView()
        case .konten: KontenView()
        case .einstellungen: EinstellungenView()
        case .mehr: MehrListe()
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
