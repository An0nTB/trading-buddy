import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

@Suite struct OffeneRegelnTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func zeit(_ stunde: Int) -> Date {
        Date(timeIntervalSince1970: 1_746_403_200 + Double(stunde) * 3600) // 05.05.2025
    }

    private func anfrage(offene: [OffenerTrade]?, regeln: Handelsregeln,
                         waehrung: String? = nil, mitRisiko: Bool = true) throws -> Anfrage {
        let b = Trade(id: "B", symbol: "Index", side: .buy, lots: 1, openTime: zeit(10), closeTime: zeit(11),
                      openPrice: 100, closePrice: 110, profit: 10, waehrung: waehrung)
            .mitGeplantemRisiko(mitRisiko ? 40 : nil)
        let export = JournalExport(konten: [.init(broker: "Test", kontonummer: "1234", waehrung: "EUR",
                                                  trades: [b], regeln: regeln, offene: offene)],
                                   zeitzone: utc, erstellt: zeit(12))
        var argumente = ["monat": "2025-05"]
        if let waehrung { argumente["waehrung"] = waehrung }
        return try Anfrage.lies(argumente, export: JournalExport.lese(export.json()))
    }

    @Test func weiterhinOffenesAZaehltBeimGeschlossenenB() throws {
        let a = OffenerTrade(id: "A", openTime: zeit(-24), risiko: 70)
        let anfrage = try anfrage(offene: [a], regeln: Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 100))
        let verstoesse = anfrage.verstoesse(anfrage.konto.trades)
        #expect(Set(verstoesse.map(\.art)) == [.offenePositionen, .offenesRisiko])
        #expect(verstoesse.allSatisfy { $0.trade == "B" })
        let text = Ausgabe.auswertung(anfrage)
        #expect(text.contains("| Offene Positionen | 1 |"))
        #expect(text.contains("| Offenes Risiko | 1 |"))
        #expect(!text.contains("Kein Verstoß") && !text.contains("nicht vollständig geprüft"))
    }

    @Test func offenesRisikoMitProzentgrenze() throws {
        var regeln = Handelsregeln(maxOffenesRisikoProzent: 10)
        regeln.kontostand = Kontostandbezug(betrag: 1000, seit: zeit(-48))
        let anfrage = try anfrage(offene: [.init(id: "A", openTime: zeit(9), risiko: 70)], regeln: regeln)
        #expect(anfrage.verstoesse(anfrage.konto.trades).contains { $0.art == .offenesRisiko && $0.trade == "B" })
        #expect(!anfrage.offeneRegelnUnvollstaendig)
    }

    @Test func spaeterEroeffnetePositionVerletztBKeineGrenze() throws {
        let anfrage = try anfrage(offene: [.init(id: "A", openTime: zeit(12), risiko: 70)],
                                  regeln: Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 100))
        #expect(anfrage.verstoesse(anfrage.konto.trades).isEmpty)
        #expect(Ausgabe.auswertung(anfrage).contains("Kein Verstoß im Zeitraum (1 Trades geprüft)."))
    }

    @Test func fehlenderBestandIstNichtDasselbeWieLeer() throws {
        let regeln = Handelsregeln(maxOffenePositionen: 1)
        let alt = try anfrage(offene: nil, regeln: regeln)
        let text = Ausgabe.auswertung(alt)
        #expect(text.contains("nicht vollständig geprüft"))
        #expect(!text.contains("Kein Verstoß"))
        let leer = try anfrage(offene: [], regeln: regeln)
        #expect(!leer.offeneRegelnUnvollstaendig)
        #expect(Ausgabe.auswertung(leer).contains("Kein Verstoß"))
    }

    @Test func fehlendeRisikenUndKontostandWerdenNichtAlsGeprueftGemeldet() throws {
        let ohneRisiko = try anfrage(offene: [.init(id: "A", openTime: zeit(9))],
                                     regeln: Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 100))
        let text = Ausgabe.auswertung(ohneRisiko)
        #expect(text.contains("nicht vollständig geprüft") && text.contains("| Offene Positionen | 1 |"))
        #expect(!text.contains("Ohne Verstoß:"))
        let ohneGeschlossenesRisiko = try anfrage(offene: [], regeln: Handelsregeln(maxOffenesRisiko: 100),
                                                 mitRisiko: false)
        #expect(ohneGeschlossenesRisiko.offeneRegelnUnvollstaendig)
        let ohneStand = try anfrage(offene: [], regeln: Handelsregeln(maxOffenesRisikoProzent: 10))
        #expect(Ausgabe.auswertung(ohneStand).contains("nicht vollständig geprüft"))
    }

    @Test func fehlendeUhrzeitUndFremdwaehrungBleibenErkennbar() throws {
        let ohneUhrzeit = try anfrage(offene: [.init(id: "A", openTime: zeit(0), nurDatum: true, risiko: 70)],
                                      regeln: Handelsregeln(maxOffenePositionen: 1))
        #expect(ohneUhrzeit.offeneRegelnUnvollstaendig)
        let fremd = try anfrage(offene: [.init(id: "A", openTime: zeit(9), risiko: 700)],
                                regeln: Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 100), waehrung: "USD")
        #expect(fremd.konto.offene?.first?.risiko == nil)
        #expect(fremd.verstoesse(fremd.konto.trades).map(\.art) == [.offenePositionen])
        #expect(Ausgabe.auswertung(fremd).contains("nicht vollständig geprüft"))
    }

    @Test func unvollstaendigerBestandBeruecksichtigtBekanntePositionen() throws {
        var anfrage = try anfrage(offene: [.init(id: "A", openTime: zeit(9), risiko: 70)],
                                  regeln: Handelsregeln(maxOffenePositionen: 1))
        anfrage.konto.offeneVollstaendig = false
        let text = Ausgabe.auswertung(anfrage)
        #expect(text.contains("nicht vollständig geprüft") && text.contains("| Offene Positionen | 1 |"))
        #expect(!text.contains("Kein Verstoß") && !text.contains("Ohne Verstoß:"))
    }
}
