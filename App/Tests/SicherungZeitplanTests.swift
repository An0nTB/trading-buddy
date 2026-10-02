#if os(macOS)
import Foundation
import Testing
@testable import Trading_Buddy

/// Zeitplan der Datensicherung (`istFaellig`) gegen eine eigene `UserDefaults`-Suite, nie gegen die Einstellungen des Nutzers.
@Suite struct SicherungZeitplanTests {
    private func mitAblage(_ pruefe: (UserDefaults) throws -> Void) rethrows {
        let name = "appt-sicherung-\(UUID().uuidString)"
        let ablage = UserDefaults(suiteName: name)!
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        try pruefe(ablage)
    }

    private let jetzt = AppTestdaten.zeit(2026, 10, 2, 12)

    @Test func ausgeschaltetOderOhneOrdnerNieFaellig() {
        mitAblage { ablage in
            #expect(!Sicherungsdienst.istFaellig(jetzt: jetzt, ablage: ablage))
            ablage.set(true, forKey: Sicherungsdienst.schluesselAktiv)
            #expect(!Sicherungsdienst.istFaellig(jetzt: jetzt, ablage: ablage))
            ablage.set(false, forKey: Sicherungsdienst.schluesselAktiv)
            ablage.set(Data([1]), forKey: Sicherungsdienst.schluesselOrdner)
            #expect(!Sicherungsdienst.istFaellig(jetzt: jetzt, ablage: ablage))
        }
    }

    @Test func ohneLetzteSicherungSofortFaellig() {
        mitAblage { ablage in
            ablage.set(true, forKey: Sicherungsdienst.schluesselAktiv)
            ablage.set(Data([1]), forKey: Sicherungsdienst.schluesselOrdner)
            #expect(Sicherungsdienst.istFaellig(jetzt: jetzt, ablage: ablage))
        }
    }

    /// Fällig genau ab einem Tag Abstand, nicht eine Sekunde früher.
    @Test func faelligAbEinemTagAbstand() {
        mitAblage { ablage in
            ablage.set(true, forKey: Sicherungsdienst.schluesselAktiv)
            ablage.set(Data([1]), forKey: Sicherungsdienst.schluesselOrdner)
            let letzte = jetzt.addingTimeInterval(-Sicherungsdienst.abstand)
            ablage.set(letzte.addingTimeInterval(1).timeIntervalSince1970, forKey: Sicherungsdienst.schluesselLetzte)
            #expect(!Sicherungsdienst.istFaellig(jetzt: jetzt, ablage: ablage))
            ablage.set(letzte.timeIntervalSince1970, forKey: Sicherungsdienst.schluesselLetzte)
            #expect(Sicherungsdienst.istFaellig(jetzt: jetzt, ablage: ablage))
        }
    }
}
#endif
