import Foundation
import Testing
@testable import TradingCore

/// Sollwerte unabhängig in Python (decimal, ROUND_DOWN) gerechnet; Rechenweg im Kommentar.
private func z(_ text: String) -> Decimal { Decimal(string: text)! }

@Suite("Positionsgrößen-Rechner")
struct PositionsgroesseTests {
    @Test("R5-Beispiel: 10.000 €, 1 %, DAX-CFD, Stop 40 Punkte → 2,5 Kontrakte")
    func r5Beispiel() throws {
        let r = try Positionsrechnung(kontogroesse: 10_000, risiko: .prozent(1), stopAbstand: .punkte(40),
                                      instrument: .indexCFD).berechne()
        #expect(r.risikoBetrag == 100)
        #expect(r.risikoJeEinheit == 40)
        #expect(r.groesse == z("2.5"))
        #expect(r.tatsaechlichesRisiko == 100)
        #expect(r.tatsaechlichesRisikoProzent == 1)
        #expect(r.unterMinimum == false)
    }

    @Test("EUR/USD: 2 % von 5.000 €, 25 Pips, USD→EUR 0,92 → 0,43 Lot statt 0,4347…")
    func forexMitUmrechnung() throws {
        // 25 × 0,0001 × 100.000 × 0,92 = 230 € je Lot; 100 / 230 = 0,4347… → 0,43; 0,43 × 230 = 98,90
        let r = try Positionsrechnung(kontogroesse: 5_000, risiko: .prozent(2), stopAbstand: .pips(25),
                                      instrument: .forexLot, umrechnung: z("0.92")).berechne()
        #expect(r.risikoJeEinheit == 230)
        #expect(r.groesse == z("0.43"))
        #expect(r.tatsaechlichesRisiko == z("98.9"))
        #expect(r.tatsaechlichesRisikoProzent == z("1.978"))
        #expect(r.roheGroesse > r.groesse)
    }

    @Test("USD/JPY: Pipgröße 0,01, fester Betrag 150 €, JPY→EUR 0,0062 → 0,80 Lot")
    func forexJPY() throws {
        // 30 × 0,01 × 100.000 × 0,0062 = 186 € je Lot; 150 / 186 = 0,806… → 0,80; 0,80 × 186 = 148,80
        var jpy = Positionsrechnung.Instrument.forexLot
        jpy.pipGroesse = z("0.01")
        let r = try Positionsrechnung(kontogroesse: 20_000, risiko: .betrag(150), stopAbstand: .pips(30),
                                      instrument: jpy, umrechnung: z("0.0062")).berechne()
        #expect(r.risikoJeEinheit == 186)
        #expect(r.groesse == z("0.8"))
        #expect(r.tatsaechlichesRisiko == z("148.8"))
        #expect(r.tatsaechlichesRisikoProzent == z("0.744"))
    }

    @Test("Aktie: 0,5 % von 8.000 €, Stop 3 % unter 150 € → 8 Stück")
    func aktieProzentStop() throws {
        // Abstand 150 × 3 / 100 = 4,50; 40 / 4,5 = 8,88… → 8; 8 × 4,5 = 36
        let r = try Positionsrechnung(kontogroesse: 8_000, risiko: .prozent(z("0.5")),
                                      stopAbstand: .prozent(3, einstieg: 150), instrument: .aktie).berechne()
        #expect(r.risikoBetrag == 40)
        #expect(r.groesse == 8)
        #expect(r.tatsaechlichesRisiko == 36)
        #expect(r.tatsaechlichesRisikoProzent == z("0.45"))
    }

    @Test("Stop als Kurs, auch für Short (Stop über dem Einstieg) → 16 Stück")
    func stopAlsKurs() throws {
        // |42,50 − 40,10| = 2,40; 40 / 2,4 = 16,66… → 16; 16 × 2,4 = 38,40
        for (einstieg, stop) in [(z("42.5"), z("40.1")), (z("40.1"), z("42.5"))] {
            let r = try Positionsrechnung(kontogroesse: 8_000, risiko: .prozent(z("0.5")),
                                          stopAbstand: .kurs(einstieg: einstieg, stop: stop), instrument: .aktie).berechne()
            #expect(r.groesse == 16)
            #expect(r.tatsaechlichesRisiko == z("38.4"))
        }
    }

    @Test("Kosten je Einheit zählen zum Risiko: 2 € je Kontrakt → 2,3 statt 2,5")
    func kostenZaehlenMit() throws {
        // 40 + 2 = 42 je Kontrakt; 100 / 42 = 2,38… → 2,3; 2,3 × 42 = 96,60
        let r = try Positionsrechnung(kontogroesse: 10_000, risiko: .prozent(1), stopAbstand: .punkte(40),
                                      instrument: .indexCFD, kostenJeEinheit: 2).berechne()
        #expect(r.groesse == z("2.3"))
        #expect(r.tatsaechlichesRisiko == z("96.6"))
    }

    @Test("Genau ein Mindestschritt passt noch: 0,5 % von 1.000 €, 50 Pips → 0,01 Lot")
    func genauMinimum() throws {
        // 50 × 0,0001 × 100.000 = 500 je Lot; 5 / 500 = 0,01
        let r = try Positionsrechnung(kontogroesse: 1_000, risiko: .prozent(z("0.5")), stopAbstand: .pips(50),
                                      instrument: .forexLot).berechne()
        #expect(r.groesse == z("0.01"))
        #expect(r.unterMinimum == false)
    }

    @Test("Unter dem Minimum: Größe 0 und Hinweis, was das Minimum riskiert")
    func unterMinimum() throws {
        // 0,3 % von 1.000 = 3; 3 / 500 = 0,006 < 0,01 → 0; Minimum riskiert 0,01 × 500 = 5
        let forex = try Positionsrechnung(kontogroesse: 1_000, risiko: .prozent(z("0.3")), stopAbstand: .pips(50),
                                          instrument: .forexLot).berechne()
        #expect(forex.groesse == 0)
        #expect(forex.unterMinimum)
        #expect(forex.risikoBeiMinimum == 5)
        #expect(forex.tatsaechlichesRisiko == 0)
        // Eigenes Minimum 1 Kontrakt bei Schritt 0,1: 100 / 150 = 0,66… → 0,6 < 1 → 0; Minimum riskiert 150
        let cfd = Positionsrechnung.Instrument(einheit: .kontrakt, kontraktgroesse: 1, schritt: z("0.1"), minimum: 1)
        let r = try Positionsrechnung(kontogroesse: 10_000, risiko: .prozent(1), stopAbstand: .punkte(150),
                                      instrument: cfd).berechne()
        #expect(r.groesse == 0)
        #expect(r.unterMinimum)
        #expect(r.risikoBeiMinimum == 150)
    }

    @Test("Rückrichtung: 0,5 Lot EUR/USD mit 25 Pips riskieren 115 € = 2,3 %")
    func rueckrichtung() throws {
        let rechnung = Positionsrechnung(kontogroesse: 5_000, risiko: .prozent(2), stopAbstand: .pips(25),
                                         instrument: .forexLot, umrechnung: z("0.92"))
        let ergebnis = try rechnung.risikoBei(groesse: z("0.5"))
        #expect(ergebnis.betrag == 115)
        #expect(ergebnis.prozent == z("2.3"))
        #expect(throws: Positionsrechnung.Fehler.groesseUngueltig) { try rechnung.risikoBei(groesse: 0) }
    }

    @Test("Ungültige Eingaben werfen statt Unsinn zu rechnen")
    func fehler() {
        func rechne(konto: Decimal = 10_000, risiko: Positionsrechnung.Risiko = .prozent(1),
                    stop: Positionsrechnung.StopAbstand = .punkte(40),
                    instrument: Positionsrechnung.Instrument = .indexCFD, umrechnung: Decimal = 1) throws {
            _ = try Positionsrechnung(kontogroesse: konto, risiko: risiko, stopAbstand: stop,
                                      instrument: instrument, umrechnung: umrechnung).berechne()
        }
        #expect(throws: Positionsrechnung.Fehler.kontogroesseUngueltig) { try rechne(konto: 0) }
        #expect(throws: Positionsrechnung.Fehler.risikoUngueltig) { try rechne(risiko: .prozent(0)) }
        #expect(throws: Positionsrechnung.Fehler.risikoUngueltig) { try rechne(risiko: .betrag(20_000)) }
        #expect(throws: Positionsrechnung.Fehler.stopAbstandUngueltig) { try rechne(stop: .punkte(0)) }
        #expect(throws: Positionsrechnung.Fehler.stopAbstandUngueltig) { try rechne(stop: .kurs(einstieg: 10, stop: 10)) }
        #expect(throws: Positionsrechnung.Fehler.stopAbstandUngueltig) { try rechne(stop: .prozent(2, einstieg: 0)) }
        let kaputt = Positionsrechnung.Instrument(einheit: .lot, kontraktgroesse: 100_000, schritt: 0)
        #expect(throws: Positionsrechnung.Fehler.instrumentUngueltig) { try rechne(instrument: kaputt) }
        #expect(throws: Positionsrechnung.Fehler.instrumentUngueltig) { try rechne(umrechnung: 0) }
    }

    @Test("Abrunden auf Schritte bleibt exakt")
    func abrunden() {
        #expect(Positionsrechnung.abrunden(z("0.4347826"), auf: z("0.01")) == z("0.43"))
        #expect(Positionsrechnung.abrunden(z("2.5"), auf: z("0.1")) == z("2.5"))
        #expect(Positionsrechnung.abrunden(z("16.99"), auf: 1) == 16)
        #expect(Positionsrechnung.abrunden(z("7"), auf: 5) == 5)
    }
}
