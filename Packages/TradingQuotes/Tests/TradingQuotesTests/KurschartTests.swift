import Foundation
import Testing
@testable import TradingQuotes

/// Kurschart: Zeitraum, Marken, Meldungen je Kerze. Tage ab 2027-01-01 00:00 UTC.
let chartStart = Date(timeIntervalSince1970: 1_798_761_600)

func chartTag(_ n: Int, stunde: Double = 0) -> Date { chartStart.addingTimeInterval(Double(n) * 86_400 + stunde * 3600) }

func chartVerlauf(tage: Int) -> Kursverlauf {
    let kerzen = (0..<tage).map { n in
        Tageskerze(zeit: chartTag(n), eroeffnung: 100, hoch: 110, tief: 90, schluss: 105, abgeschlossen: n < tage - 1)
    }
    return Kursverlauf(journalSymbol: "AAPL.US", quelle: "alpaca", quellSymbol: "AAPL", kerzen: kerzen, geladen: chartStart)
}

func chartMeldung(_ id: String, _ zeit: Date) -> Chartmeldung {
    Chartmeldung(id: id, zeit: zeit, titel: id, quelle: "Test", link: URL(string: "https://example.invalid/\(id)")!)
}

@Test func kurschartSchneidetDenZeitraumZu() throws {
    let jetzt = chartTag(99, stunde: 12)
    let chart = try #require(Kurschart.baue(chartVerlauf(tage: 100), zeitraum: .monat, marken: [], meldungen: [], jetzt: jetzt))
    #expect(chart.kerzen.count == 30)
    #expect(chart.kerzen.first?.zeit == chartTag(70))
    #expect(chart.laufend)
    #expect(chart.tief == 90)
    #expect(chart.hoch == 110)
    let leer = Kurschart.baue(chartVerlauf(tage: 10), zeitraum: .monat, marken: [], meldungen: [],
                              jetzt: chartTag(80))
    #expect(leer == nil)
}

@Test func kurschartBehaeltPassendeMarkenUndZaehltDenRest() throws {
    let jetzt = chartTag(29, stunde: 12)
    let marken = [
        Chartmarke(tradeID: "1", art: .ausstieg, zeit: chartTag(5, stunde: 15), preis: 108, kauf: true, ergebnis: 12),
        Chartmarke(tradeID: "1", art: .einstieg, zeit: chartTag(5, stunde: 10), preis: 95, kauf: true),
        Chartmarke(tradeID: "2", art: .einstieg, zeit: chartTag(6), preis: 120, kauf: false),
        Chartmarke(tradeID: "3", art: .einstieg, zeit: chartTag(7), preis: 1_000, kauf: true),
        Chartmarke(tradeID: "4", art: .einstieg, zeit: chartTag(-40), preis: 100, kauf: true)
    ]
    let chart = try #require(Kurschart.baue(chartVerlauf(tage: 30), zeitraum: .monat, marken: marken,
                                            meldungen: [], jetzt: jetzt))
    #expect(chart.marken.map(\.id) == ["1|einstieg", "1|ausstieg", "2|einstieg"])
    #expect(chart.ausserhalb == 1)
    #expect(chart.hoch == 120)
    #expect(chart.tief == 90)
}

@Test func kurschartOrdnetMeldungenDerKerzeDesTagesZu() throws {
    var verlauf = chartVerlauf(tage: 10)
    verlauf.kerzen.remove(at: 5)   // Tag 5 ohne Kerze, etwa ein Samstag
    let meldungen = [chartMeldung("a", chartTag(5, stunde: 9)), chartMeldung("b", chartTag(4, stunde: 8)),
                     chartMeldung("c", chartTag(4, stunde: 20)), chartMeldung("alt", chartTag(-3))]
    let chart = try #require(Kurschart.baue(verlauf, zeitraum: .monat, marken: [], meldungen: meldungen,
                                            jetzt: chartTag(9, stunde: 12)))
    #expect(chart.nachrichtentage.map(\.tag) == [chartTag(4)])
    #expect(chart.nachrichtentage.first?.meldungen.map(\.id) == ["a", "c", "b"])
}
