import Foundation
import Testing
@testable import Trading_Buddy

/// G16 (Doc 49): Nach dem Wiederherstellen merkt die App einen Schutzzeitpunkt, damit das Aufräumen keine Screenshots
/// löscht, die die zurückgespielte Datenbank nicht kennt. Geprüft gegen eine eigene `UserDefaults`-Suite.
@Suite @MainActor struct BilderschutzTests {
    @Test func schutzzeitpunktWirdGemerkt() {
        let name = "appt-bilder-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let ablage = UserDefaults(suiteName: name)!
        #expect(Bilderordner.schutzzeitpunkt(ablage: ablage) == nil)
        let zeit = AppTestdaten.zeit(2026, 10, 2, 22, 43)
        Bilderordner.schuetzeBestand(jetzt: zeit, ablage: ablage)
        #expect(Bilderordner.schutzzeitpunkt(ablage: ablage) == zeit)
        let spaeter = zeit.addingTimeInterval(3600)
        Bilderordner.schuetzeBestand(jetzt: spaeter, ablage: ablage)
        #expect(Bilderordner.schutzzeitpunkt(ablage: ablage) == spaeter)
    }

    /// Ohne einen einzigen Verweis räumt die App nichts auf (leere oder neue Datenbank); der echte Ordner bleibt unberührt.
    @Test func ohneVerweiseWirdNichtsGeloescht() {
        #expect(Bilderordner.raeumeAuf(behalten: [], geschuetztBis: nil) == 0)
    }
}
