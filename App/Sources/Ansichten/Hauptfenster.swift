import SwiftUI

/// Bereiche der Seitenleiste (Doc 10, Aufbau A).
enum Bereich: String, CaseIterable, Identifiable, Hashable {
    case uebersicht, trades, kennzahlen, fehlermuster, kalender, importieren, konten
    #if os(iOS)
    case einstellungen
    #endif

    var id: String { rawValue }

    var titel: LocalizedStringKey {
        switch self {
        case .uebersicht: "Übersicht"
        case .trades: "Trades"
        case .kennzahlen: "Kennzahlen"
        case .fehlermuster: "Fehlermuster"
        case .kalender: "Kalender"
        case .importieren: "Import"
        case .konten: "Konten und Kosten"
        #if os(iOS)
        case .einstellungen: "Einstellungen"
        #endif
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
        #if os(iOS)
        case .einstellungen: "gear"
        #endif
        }
    }
}

struct Hauptfenster: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var bereich: Bereich? = .uebersicht

    var body: some View {
        NavigationSplitView {
            List(selection: $bereich) {
                ForEach(Bereich.allCases) { b in
                    NavigationLink(value: b) { Label(b.titel, systemImage: b.symbol) }
                }
            }
            .navigationTitle("Trading Buddy")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            #endif
        } detail: {
            Group {
                switch bereich ?? .uebersicht {
                case .uebersicht: UebersichtView()
                case .trades: TradesView()
                case .kennzahlen: KennzahlenView()
                case .fehlermuster: FehlermusterView()
                case .importieren: ImportView()
                case .kalender:
                    ContentUnavailableView("Kalender folgt", systemImage: "calendar",
                                           description: Text("Termine und Börsenzeiten kommen nach der ersten Version."))
                case .konten:
                    ContentUnavailableView("Konten und Kosten folgen", systemImage: "building.columns",
                                           description: Text("Das Kostenprofil je Konto kommt im nächsten Schritt."))
                #if os(iOS)
                case .einstellungen: EinstellungenView()
                #endif
                }
            }
            .background(thema.grund)
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        .alert("Fehler", isPresented: Binding(get: { modell.fehler != nil }, set: { if !$0 { modell.fehler = nil } })) {
            Button("OK") { modell.fehler = nil }
        } message: {
            Text(modell.fehler ?? "")
        }
    }
}
