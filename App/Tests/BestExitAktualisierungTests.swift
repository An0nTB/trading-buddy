import Foundation
import Testing
import TradingCore
@testable import Trading_Buddy

@Suite @MainActor struct BestExitAktualisierungTests {
    private typealias T = AppTestdaten
    private typealias Schluessel = BestExitKarte.Schluessel

    private func trade() -> Trade {
        Trade(id: "123", symbol: "BTC/EUR", side: .buy, lots: 1,
              openTime: T.zeit(2026, 10, 4, 9), closeTime: T.zeit(2026, 10, 4, 10),
              openPrice: 100, closePrice: 110, stopLoss: 90, profit: 10)
    }

    @Test func gleicherTradeMitGeaendertenWertenRechnetNeu() {
        let vorher = trade()
        let alt = Schluessel(trades: [vorher], stand: 1, konto: 1, waehrung: "EUR")
        let aenderungen: [(inout Trade) -> Void] = [
            { $0.stopLoss = 95 }, { $0.geplantesRisiko = 50 },
            { $0.openPrice = 101 }, { $0.closePrice = 112 }, { $0.profit = 12 },
            { $0.lots = 2 }, { $0.commission = -1 }, { $0.swap = -1 }, { $0.taxes = -1 },
            { $0.openTime = $0.openTime.addingTimeInterval(60) },
            { $0.closeTime = $0.closeTime.addingTimeInterval(60) },
            { $0.symbol = "BTC/USD" }, { $0.side = .sell }, { $0.nurDatum = true }, { $0.waehrung = "USD" }
        ]
        for aenderung in aenderungen {
            var neu = vorher
            aenderung(&neu)
            #expect(neu.id == vorher.id)
            #expect(Schluessel(trades: [neu], stand: 1, konto: 1, waehrung: "EUR") != alt)
        }
        #expect(Schluessel(trades: [vorher], stand: 1, konto: 1, waehrung: "EUR") == alt)
    }

    private func auswertung(_ trade: Trade) -> BestExitAuswertung {
        let kerze = Zeitkerze(beginn: trade.openTime, dauer: 60, open: 100, high: 112, low: 99, close: 110)
        return BestExitAuswertung(trades: [trade], kerzenJeTrade: [trade.id: [kerze]], gleicheWaehrung: true)
    }

    @Test func ergebnisPasstNurZuKontoWaehrungUndKursstand() async {
        let berechnung = BestExitKarte.Berechnung()
        let alt = Schluessel(trades: [trade()], stand: 1, konto: 1, waehrung: "EUR")
        await berechnung.aktualisiere(alt) { auswertung(alt.trades[0]) }
        #expect(berechnung.ergebnis(fuer: alt)?.summeTatsaechlichR == 1)
        var neu = alt
        neu.konto = 2
        #expect(neu != alt)
        #expect(berechnung.ergebnis(fuer: neu) == nil)
        neu = alt
        neu.waehrung = "USD"
        #expect(neu != alt)
        #expect(berechnung.ergebnis(fuer: neu) == nil)
        neu = alt
        neu.stand += 1
        #expect(neu != alt)
        #expect(berechnung.ergebnis(fuer: neu) == nil)
    }

    @Test func gleicherTradeErhaeltNachStopAenderungNeueBestExitWerte() async {
        var t = trade()
        let berechnung = BestExitKarte.Berechnung()
        let alt = Schluessel(trades: [t], stand: 1, konto: 1, waehrung: "EUR")
        await berechnung.aktualisiere(alt) { auswertung(t) }
        #expect(berechnung.ergebnis(fuer: alt)?.summeTatsaechlichR == 1)
        t.stopLoss = 95
        let neu = Schluessel(trades: [t], stand: 1, konto: 1, waehrung: "EUR")
        #expect(berechnung.ergebnis(fuer: neu) == nil)
        await berechnung.aktualisiere(neu) {
            #expect(berechnung.ergebnis(fuer: alt) == nil)
            #expect(berechnung.rechnet)
            return auswertung(t)
        }
        #expect(berechnung.ergebnis(fuer: neu)?.summeTatsaechlichR == 2)
        #expect(!berechnung.rechnet)
    }

    @Test func kontowechselVerwirftAuchVerspaetetesAltesErgebnis() async {
        let berechnung = BestExitKarte.Berechnung()
        let alt = Schluessel(trades: [trade()], stand: 1, konto: 1, waehrung: "EUR")
        var neu = alt
        neu.konto = 2
        neu.trades[0].stopLoss = 95
        let altesErgebnis = auswertung(alt.trades[0])
        let neuesErgebnis = auswertung(neu.trades[0])
        await berechnung.aktualisiere(alt) { altesErgebnis }
        #expect(berechnung.ergebnis(fuer: neu) == nil)

        // Während die alte Berechnung wartet, beginnt und endet die Berechnung für das neue Konto.
        await berechnung.aktualisiere(alt) {
            await berechnung.aktualisiere(neu) {
                #expect(berechnung.ergebnis(fuer: alt) == nil)
                #expect(berechnung.ergebnis(fuer: neu) == nil)
                #expect(berechnung.rechnet)
                return neuesErgebnis
            }
            return altesErgebnis
        }
        #expect(berechnung.ergebnis(fuer: neu)?.summeTatsaechlichR == 2)
        #expect(berechnung.ergebnis(fuer: alt) == nil)
        #expect(!berechnung.rechnet)
        berechnung.zuruecksetzen()
        #expect(berechnung.ergebnis(fuer: neu) == nil)
        #expect(!berechnung.rechnet)
    }

    @Test func abgebrocheneBerechnungVeroeffentlichtKeinErgebnis() async {
        let berechnung = BestExitKarte.Berechnung()
        let schluessel = Schluessel(trades: [trade()], stand: 1, konto: 1, waehrung: "EUR")
        let ergebnis = auswertung(trade())
        let task = Task { @MainActor in
            await berechnung.aktualisiere(schluessel) { ergebnis }
        }
        task.cancel()
        await task.value
        #expect(berechnung.ergebnis(fuer: schluessel) == nil)
        #expect(!berechnung.rechnet)
    }
}
