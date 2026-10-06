import Foundation
import Testing
import TradingCalendar
@testable import Trading_Buddy

/// Börsenfeiertage der Börsenuhr als Termine der Kalender-Seite (Stand-Doc 63). Geprüft werden Werte, keine Texte.
@Suite struct BoersenfeiertageKalenderTests {
    @Test func feiertageSindGanztaegigUndEindeutig() {
        let termine = Termindienst.boersenfeiertage()
        #expect(!termine.isEmpty)
        #expect(termine.allSatisfy(\.ganztaegig))
        #expect(Set(termine.map(\.id)).count == termine.count)
    }

    /// Ein Nasdaq-Feiertag, den die NYSE auch hat, steht nur einmal im Kalender.
    @Test func nasdaqDoppeltEntfaellt() {
        let termine = Termindienst.boersenfeiertage()
        // Kennung „boerse-<börse>-<jahr>-<monat>-<tag>“: verglichen wird der Datumsteil.
        let tage = { (boerse: String) in
            Set(termine.map(\.id).filter { $0.hasPrefix("boerse-\(boerse)-") }.map { $0.dropFirst("boerse-\(boerse)-".count) })
        }
        #expect(tage("nasdaq").isDisjoint(with: tage("nyse")))
    }
}
