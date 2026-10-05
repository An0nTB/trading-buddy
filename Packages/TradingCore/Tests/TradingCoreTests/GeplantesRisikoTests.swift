import Foundation
import Testing
@testable import TradingCore

/// Geplantes Risiko für Trades ohne Stop (Scalable, Trade Republic). Erfundene Trades, Sollwerte von Hand.

private let utc = TimeZone(secondsFromGMT: 0)!

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

/// Kauf zu 100, Verkauf zu 85, Kursergebnis −150 ohne Kosten: Wert je Kurspunkt 10.
private func verlust(stop: Decimal? = nil, id: String = "g1") -> Trade {
    Trade(id: id, symbol: "Beispiel AG", side: .buy, lots: 10,
          openTime: Date(timeIntervalSince1970: 1_750_000_000), closeTime: Date(timeIntervalSince1970: 1_750_086_400),
          openPrice: 100, closePrice: 85, stopLoss: stop, profit: -150)
}

@Test func geplantesRisikoOhneStop() {
    var t = verlust()
    t.geplantesRisiko = 100
    #expect(t.stopRisiko == nil)
    #expect(t.risk == 100)
    #expect(t.rMultiple == d("-1.5"))
    #expect(t.risikoAngenommen)
}

@Test func geplantPerMethodeGleichWiePerKopie() {
    var kopie = verlust()
    kopie.geplantesRisiko = 100
    let methode = verlust().mitGeplantemRisiko(100)
    #expect(methode == kopie)
    #expect(methode.geplantesRisiko == 100)
    // nil entfernt das geplante Risiko wieder.
    let ohne = methode.mitGeplantemRisiko(nil)
    #expect(ohne.geplantesRisiko == nil)
    #expect(ohne.risk == nil)
    #expect(ohne == verlust())
}

@Test func geplantEchterStopHatVorrang() {
    // Stop 95: Abstand 5 × Wert je Punkt 10 = 50; −150 ÷ 50 = −3 R.
    let t = verlust(stop: 95).mitGeplantemRisiko(100)
    #expect(t.stopRisiko == 50)
    #expect(t.risk == 50)
    #expect(t.rMultiple == -3)
    #expect(!t.risikoAngenommen)
}

@Test func geplantOhneStopUndOhneGeplantesRisiko() {
    let t = verlust()
    #expect(t.risk == nil)
    #expect(t.rMultiple == nil)
    #expect(!t.risikoAngenommen)
}

@Test func geplantNullOderNegativWirdIgnoriert() {
    let null = verlust().mitGeplantemRisiko(0)
    #expect(null.risk == nil)
    #expect(null.rMultiple == nil)
    #expect(!null.risikoAngenommen)

    let negativ = verlust().mitGeplantemRisiko(-100)
    #expect(negativ.risk == nil)
    #expect(negativ.rMultiple == nil)
    #expect(!negativ.risikoAngenommen)

    // Mit Stop bleibt es beim Stop.
    let mitStop = verlust(stop: 95).mitGeplantemRisiko(-100)
    #expect(mitStop.risk == 50)
    #expect(!mitStop.risikoAngenommen)
}

@Test func geplantBeiStopAufDerGewinnseite() {
    // Stop 105 bei Kauf zu 100 (nachgezogen) gibt kein Risiko aus dem Stop; dann gilt das geplante.
    let t = verlust(stop: 105).mitGeplantemRisiko(100)
    #expect(t.stopRisiko == nil)
    #expect(t.risk == 100)
    #expect(t.rMultiple == d("-1.5"))
    #expect(t.risikoAngenommen)
}

@Test func geplantKennzahlenZaehlenAngenommenesR() {
    // R −3 (Stop) und −1,5 (angenommen): Mittel −2,25; dritter Trade ohne beides zählt nicht.
    let trades = [verlust(stop: 95, id: "g1"), verlust(id: "g2").mitGeplantemRisiko(100), verlust(id: "g3")]
    let k = Kennzahlen(trades: trades)
    #expect(k.anzahlMitR == 2)
    #expect(k.anzahlRAngenommen == 1)
    #expect(k.erwartungswertR == d("-2.25"))
}

@Test func geplantOhneStopBleibtBefund() {
    // Das geplante Risiko ersetzt keinen Stop: „ohne Stop“ bleibt, das R zählt in die Summe.
    let t = verlust().mitGeplantemRisiko(100)
    let befunde = Fehlermuster.pruefe([t], zeitzone: utc)
    let ohneStop = befunde.first { $0.muster == .ohneStop }
    #expect(ohneStop?.trades == ["g1"])
    #expect(ohneStop?.summeR == d("-1.5"))
}
