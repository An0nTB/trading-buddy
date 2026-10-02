import SwiftUI

/// Szene für abgetrennte Bereiche (Stand-Doc 27): ein Fenster je Bereich, dasselbe App-Modell wie das
/// Hauptfenster, also gleiche Daten, gleiches Konto und gleiche Filter. Ein zweiter Aufruf für denselben
/// Bereich holt das vorhandene Fenster nach vorn, statt ein weiteres zu öffnen.
struct BereichFensterSzene: Scene {
    let modell: AppModell

    var body: some Scene {
        WindowGroup("Bereich", id: FensterID.bereich, for: Bereich.self) { $bereich in
            MitThema {
                BereichFenster(bereich: bereich ?? .uebersicht)
            }
            .environment(modell)
        }
        #if os(macOS)
        .defaultSize(width: 760, height: 560)
        #endif
    }
}

/// Inhalt eines abgetrennten Fensters: die Seite wie im Hauptfenster, dazu am Mac die Stecknadel;
/// die Börsenuhr wahlweise kompakt (F5).
struct BereichFenster: View {
    let bereich: Bereich
    @Environment(\.thema) private var thema
    /// Abgetrennte Börsenuhr kompakt oder voll; gilt für alle Börsenuhr-Fenster, Standard kompakt.
    @AppStorage("boersenuhr.kompakt") private var kompakt = true
    #if os(macOS)
    @AppStorage private var angeheftet: Bool
    #endif

    init(bereich: Bereich) {
        self.bereich = bereich
        #if os(macOS)
        _angeheftet = AppStorage(wrappedValue: bereich.startetAngeheftet, bereich.anheftSchluessel)
        #endif
    }

    private var zeigtKompakt: Bool { bereich == .boersenuhr && kompakt }

    private var mindestgroesse: CGSize { zeigtKompakt ? Bereich.kompaktgroesse : bereich.mindestgroesse }

    var body: some View {
        NavigationStack {
            inhalt
                .frame(minWidth: mindestgroesse.width, minHeight: mindestgroesse.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(thema.grund)
                .navigationTitle(bereich.titel)
                .toolbar {
                    // Werkzeugleiste immer gleich aufgebaut, nur der Inhalt ist bedingt (Startabsturz 02.10.2026).
                    ToolbarItemGroup(placement: .primaryAction) {
                        if bereich == .boersenuhr {
                            Toggle(isOn: $kompakt) {
                                Label("Kompakt", systemImage: "rectangle.compress.vertical")
                            }
                            .toggleStyle(.button)
                            .help("Kompakte Börsenuhr mit Countdown oder volle Ansicht")
                        }
                        #if os(macOS)
                        Stecknadel(angeheftet: $angeheftet)
                        #endif
                    }
                }
        }
        #if os(macOS)
        .background(FensterEbene(angeheftet: angeheftet))
        #endif
    }

    @ViewBuilder
    private var inhalt: some View {
        if zeigtKompakt {
            MiniBoersenuhr()
        } else {
            BereichInhalt(bereich: bereich)
        }
    }
}
