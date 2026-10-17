import Foundation
import Testing
@testable import TradingCore

private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
private let utc = TimeZone(secondsFromGMT: 0)!
private let newYork = TimeZone(identifier: "America/New_York")!

private func trade(_ id: String, auf: String, zu: String, risiko: Decimal = 0,
                   netto: Decimal = 0, nurDatum: Bool = false) -> Trade {
    var t = Trade(id: id, symbol: "Testwert", side: .buy, lots: 1, openTime: zeit(auf), closeTime: zeit(zu),
                  openPrice: 100, closePrice: 100, profit: netto, nurDatum: nurDatum)
    t.geplantesRisiko = risiko
    return t
}

@Test func teilverkaufUndOffenerRestSindEinePosition() {
    let teil = trade("Teil", auf: "2026-10-01T08:00:00Z", zu: "2026-10-01T09:00:00Z", risiko: 30)
    let rest = OffenerTrade(id: "Kauf", openTime: teil.openTime, risiko: 20,
                            positionsschluessel: teil.positionsschluessel)
    let regeln = Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 50)
    #expect(Regelpruefung.pruefe([teil], regeln: regeln, zeitzone: utc, offene: [rest]).isEmpty)
    let neu = trade("Neu", auf: "2026-10-02T08:00:00Z", zu: "2026-10-02T09:00:00Z", risiko: 30)
    let verstoesse = Regelpruefung.pruefe([teil, neu], regeln: regeln, zeitzone: utc, offene: [rest])
    #expect(verstoesse.map(\.trade) == ["Neu"])
    #expect(verstoesse.map(\.art) == [.offenePositionen])
    let zuEng = Regelpruefung.pruefe([teil], regeln: Handelsregeln(maxOffenesRisiko: 49), zeitzone: utc, offene: [rest])
    #expect(Set(zuEng.map(\.trade)) == ["Teil", "Kauf"])
    #expect(zuEng.allSatisfy { $0.art == .offenesRisiko })
}

@Test func teilrisikoEntfaelltAbDemJeweiligenSchluss() {
    let teile = [trade("Teil1", auf: "2026-10-01T08:00:00Z", zu: "2026-10-01T09:00:00Z", risiko: 30),
                 trade("Teil2", auf: "2026-10-01T08:00:00Z", zu: "2026-10-01T12:00:00Z", risiko: 20)]
    let regeln = Handelsregeln(maxOffenesRisiko: 50)
    for (auf, erwartet) in [("2026-10-01T08:30:00Z", true), ("2026-10-01T09:00:00Z", false),
                            ("2026-10-01T10:00:00Z", false), ("2026-10-01T12:00:00Z", false)] {
        let neu = trade("Neu", auf: auf, zu: "2026-10-01T13:00:00Z", risiko: 30)
        let verstoesse = Regelpruefung.pruefe(teile + [neu], regeln: regeln, zeitzone: utc)
        #expect(verstoesse.contains { $0.trade == "Neu" && $0.art == .offenesRisiko } == erwartet)
    }
}

@Test func datumsteilBleibtAmUnbekanntenSchlusstagImRisiko() {
    let teile = [trade("Teil1", auf: "2026-09-30T00:00:00Z", zu: "2026-10-01T00:00:00Z",
                       risiko: 30, nurDatum: true),
                 trade("Teil2", auf: "2026-09-30T00:00:00Z", zu: "2026-10-03T00:00:00Z",
                       risiko: 20, nurDatum: true)]
    let regeln = Handelsregeln(maxOffenesRisiko: 50)
    for (auf, erwartet) in [("2026-10-01T15:00:00Z", true), ("2026-10-02T15:00:00Z", false)] {
        let neu = trade("Neu", auf: auf, zu: "2026-10-04T15:00:00Z", risiko: 30)
        let verstoesse = Regelpruefung.pruefe(teile + [neu], regeln: regeln, zeitzone: newYork)
        #expect(verstoesse.contains { $0.trade == "Neu" && $0.art == .offenesRisiko } == erwartet)
    }
}

@Test(arguments: ["America/New_York", "Europe/Berlin", "UTC"])
func datumsschlussZaehltNichtZumAnfangSeinesBuchungstags(zone: String) throws {
    let zeitzone = try #require(TimeZone(identifier: zone))
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = zeitzone
    let beginn = try #require(kalender.date(from: DateComponents(year: 2026, month: 10, day: 1)))
    let folgetag = try #require(kalender.date(byAdding: .day, value: 1, to: beginn))
    let t = trade("Datum", auf: "2026-09-29T00:00:00Z", zu: "2026-10-01T00:00:00Z",
                   netto: -100, nurDatum: true)
    let bezug = Kontostandbezug(betrag: 1000, seit: zeit("2026-09-01T00:00:00Z"))
    let stand = bezug.stand(bei: beginn, trades: [t], zeitzone: zeitzone)
    #expect(stand == 1000)
    #expect(Handelsregeln.grenze(betrag: nil, prozent: 1, stand: stand) == 10)
    #expect(bezug.stand(bei: folgetag, trades: [t], zeitzone: zeitzone) == 900)
    #expect(bezug.stand(bei: folgetag, trades: [t], ohneBetrag: [t.id], zeitzone: zeitzone) == 1000)
    let spaeter = Kontostandbezug(betrag: 900, seit: folgetag)
    #expect(spaeter.stand(bei: beginn, trades: [t], zeitzone: zeitzone) == 1000)
}

@Test func echteSchlusszeitBleibtBeimKontostandErhalten() {
    let t = trade("Uhrzeit", auf: "2026-09-30T23:00:00Z", zu: "2026-10-01T00:00:00Z", netto: -100)
    let bezug = Kontostandbezug(betrag: 1000, seit: zeit("2026-09-01T00:00:00Z"))
    #expect(bezug.stand(bei: zeit("2026-10-01T04:00:00Z"), trades: [t], zeitzone: newYork) == 900)
}

@Test func prozentregelnNutzenDenBuchungstagInNewYork() {
    let datum = trade("Datum", auf: "2026-09-29T00:00:00Z", zu: "2026-10-01T00:00:00Z",
                       netto: -100, nurDatum: true)
    let verlust = trade("Verlust", auf: "2026-10-01T13:00:00Z", zu: "2026-10-01T14:00:00Z",
                         netto: Decimal(string: "-9.5")!)
    var neu = trade("Neu", auf: "2026-10-01T15:00:00Z", zu: "2026-10-01T16:00:00Z",
                     risiko: Decimal(string: "9.5")!)
    neu.stopLoss = Decimal(string: "90.5")!
    neu.wertJePunkt = 1
    let bezug = Kontostandbezug(betrag: 1000, seit: zeit("2026-09-01T00:00:00Z"))
    let regeln = Handelsregeln(maxTagesverlustProzent: 1, maxRisikoJeTradeProzent: 1,
                               maxOffenesRisikoProzent: 1, kontostand: bezug)
    let verstoesse = Regelpruefung.pruefe([datum, verlust, neu], regeln: regeln, zeitzone: newYork)
    #expect(!verstoesse.contains { $0.trade == "Neu" })
    let folgetag = trade("Folgetag", auf: "2026-10-02T15:00:00Z", zu: "2026-10-02T16:00:00Z")
    let monatsregeln = Handelsregeln(maxMonatsverlustProzent: Decimal(string: "10.5")!, kontostand: bezug)
    #expect(Regelpruefung.pruefe([datum, folgetag], regeln: monatsregeln, zeitzone: newYork).isEmpty)
}

@Test func getrennteOffeneKaeufeBleibenTrotzGleichemNaeherungsschluesselEigenstaendig() {
    let auf = zeit("2026-10-01T00:00:00Z")
    let schluessel = Trade.positionsschluessel(symbol: "Testwert", side: .buy, openTime: auf)
    let offene = [OffenerTrade(id: "Kauf1", openTime: auf, nurDatum: true, positionsschluessel: schluessel),
                  OffenerTrade(id: "Kauf2", openTime: auf, nurDatum: true, positionsschluessel: schluessel)]
    let regeln = Handelsregeln(maxOffenePositionen: 1)
    let ohneTeile = Regelpruefung.pruefe([], regeln: regeln, zeitzone: utc, offene: offene)
    #expect(ohneTeile.map(\.trade) == ["Kauf2"] && ohneTeile.map(\.art) == [.offenePositionen])
    let teil = trade("Anteil", auf: "2026-10-01T00:00:00Z", zu: "2026-10-02T00:00:00Z", nurDatum: true)
    let mitTeil = Regelpruefung.pruefe([teil], regeln: regeln, zeitzone: utc, offene: offene)
    // Einer der Käufe ist der Rest des Teils, der zweite bleibt eine weitere offene Position.
    #expect(mitTeil.map(\.trade) == ["Kauf2"] && mitTeil.map(\.art) == [.offenePositionen])
}
