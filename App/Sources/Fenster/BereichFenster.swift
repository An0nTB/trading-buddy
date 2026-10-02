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
        // Beim Start öffnet nur das Hauptfenster; abgetrennte Fenster kommen über die Wiederherstellung zurück.
        .defaultLaunchBehavior(.suppressed)
        #endif
    }
}

/// Inhalt eines abgetrennten Fensters: die Seite wie im Hauptfenster, dazu am Mac die Stecknadel.
struct BereichFenster: View {
    let bereich: Bereich
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    #if os(macOS)
    @Environment(\.appearsActive) private var aktiv
    @Environment(\.openWindow) private var openWindow
    @AppStorage private var angeheftet: Bool
    #endif

    init(bereich: Bereich) {
        self.bereich = bereich
        #if os(macOS)
        _angeheftet = AppStorage(wrappedValue: bereich.startetAngeheftet, bereich.anheftSchluessel)
        #endif
    }

    var body: some View {
        NavigationStack {
            BereichInhalt(bereich: bereich)
                .frame(minWidth: bereich.mindestgroesse.width, minHeight: bereich.mindestgroesse.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(thema.grund)
                .navigationTitle(bereich.titel)
                #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Stecknadel(angeheftet: $angeheftet) }
                }
                #endif
        }
        #if os(macOS)
        .background(FensterEbene(angeheftet: angeheftet))
        // Karten springen über `modell.bereich` in eine andere Seite des Hauptfensters; kommt der Sprung
        // aus diesem Fenster, holt es das Hauptfenster nach vorn.
        .onChange(of: modell.bereich) {
            if aktiv { openWindow(id: FensterID.haupt) }
        }
        #endif
    }
}
