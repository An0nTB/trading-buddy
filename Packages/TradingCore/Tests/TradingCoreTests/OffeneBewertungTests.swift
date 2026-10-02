import Foundation
import Testing
@testable import TradingCore

/// Ausgedachte offene Positionen, Sollwerte von Hand gerechnet (Rechenweg im Kommentar).
private func d(_ text: String) -> Decimal { Decimal(string: text)! }

private func offen(_ seite: Side, einstieg: String, aktuell: String, profit: String,
                   kommission: String = "0", swap: String = "0") -> OpenPosition {
    OpenPosition(ticket: "1", rohzeile: [], side: seite, lots: d("0.1"), symbol: "eurusd",
                 openTime: Date(timeIntervalSince1970: 0), openPrice: d(einstieg), currentPrice: d(aktuell),
                 commission: d(kommission), swap: d(swap), profit: d(profit))
}

@Test func verkaufMitNeuemKurs() {
    // Bewegung im Auszug 1,10000 − 1,09900 = 0,001 bei 10 € → 10.000 € je Kurseinheit.
    // Neuer Kurs 1,09800: Bewegung 0,002 → brutto 20 €, netto 20 − 1 − 0,5 = 18,5 €.
    let p = offen(.sell, einstieg: "1.10000", aktuell: "1.09900", profit: "10", kommission: "-1", swap: "-0.5")
    let e = OffeneBewertung.bewerte(p, kurs: d("1.09800"))
    #expect(e.wertJePunkt == 10000)
    #expect(e.brutto == 20)
    #expect(e.kosten == d("-1.5"))
    #expect(e.netto == d("18.5"))
    #expect(e.unsicher == false)
    #expect(e.waehrung == nil)
}

@Test func kaufDrehtInVerlust() {
    // Auszug: 100 → 110 bei 20 € → 2 € je Punkt. Neuer Kurs 95: −5 × 2 = −10 €.
    let e = OffeneBewertung.bewerte(offen(.buy, einstieg: "100", aktuell: "110", profit: "20"), kurs: 95)
    #expect(e.brutto == -10)
    #expect(e.netto == -10)
}

@Test func ohneKursbewegungImAuszugKeinErgebnis() {
    // Aktueller Kurs gleich Einstieg: Wert je Punkt nicht bestimmbar.
    let e = OffeneBewertung.bewerte(offen(.buy, einstieg: "100", aktuell: "100", profit: "0"), kurs: 105)
    #expect(e.wertJePunkt == nil)
    #expect(e.brutto == nil)
    #expect(e.netto == nil)
    #expect(e.unsicher == false)
}

@Test func kleinesAuszugsergebnisIstUnsicher() {
    // 0,06 € auf Cent gerundet: bis zu ±0,005 €, also rund 8 % Unsicherheit im Wert je Punkt.
    let e = OffeneBewertung.bewerte(offen(.sell, einstieg: "0.84092", aktuell: "0.84086", profit: "0.06"), kurs: d("0.84000"))
    #expect(e.wertJePunkt == 1000)
    #expect(e.brutto == d("0.92"))
    #expect(e.unsicher == true)
}

@Test func offenerKaufAusDerPositionsbildung() {
    // 10 Stück für 1.000 € plus 1 € Gebühr; Kurs 105: 1.050 − 1.000 = 50 €, netto 49 €.
    let kauf = Ausfuehrung(id: "k1", zeit: Date(timeIntervalSince1970: 0), kennung: "DE0007164600", name: "SAP",
                           seite: .buy, menge: 10, preis: 100, betrag: -1000, gebuehr: -1, waehrung: "EUR")
    let e = OffeneBewertung.bewerte(kauf, kurs: 105)
    #expect(e.symbol == "SAP")
    #expect(e.einstieg == 100)
    #expect(e.brutto == 50)
    #expect(e.netto == 49)
    #expect(e.waehrung == "EUR")
}

@Test func summeNurBeiGleicherWaehrungUndBekanntenWerten() {
    let kauf = Ausfuehrung(id: "k1", zeit: Date(timeIntervalSince1970: 0), kennung: "X", name: "",
                           seite: .buy, menge: 2, preis: 10, betrag: -20, waehrung: "EUR")
    let a = OffeneBewertung.bewerte(kauf, kurs: 12)
    let b = OffeneBewertung.bewerte(kauf, kurs: 9)
    #expect(OffeneBewertung.summe([a, b]) == 2)
    let mt4 = OffeneBewertung.bewerte(offen(.buy, einstieg: "100", aktuell: "110", profit: "20"), kurs: 95)
    #expect(OffeneBewertung.summe([a, mt4]) == nil)
    let ohne = OffeneBewertung.bewerte(offen(.buy, einstieg: "100", aktuell: "100", profit: "0"), kurs: 95)
    #expect(OffeneBewertung.summe([mt4, ohne]) == nil)
    #expect(OffeneBewertung.summe([]) == 0)
}
