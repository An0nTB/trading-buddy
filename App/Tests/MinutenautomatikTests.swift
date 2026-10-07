import Foundation
import Testing
import TradingCore
@testable import Trading_Buddy

private let jetztFest = AppTestdaten.zeit(2026, 10, 5, 12)

/// Automatischer Abruf der Minutenkerzen (Tim 05.10.2026): wann er anläuft und welche Trades er nimmt.
@Suite struct MinutenautomatikTests {
    private typealias T = AppTestdaten

    private func trade(_ id: String, auf: Date, zu: Date, nurDatum: Bool = false) -> Trade {
        Trade(id: id, symbol: "BTC/EUR", side: .buy, lots: 1, openTime: auf, closeTime: zu,
              openPrice: 100, closePrice: 110, profit: 10, nurDatum: nurDatum)
    }

    @Test @MainActor func gleicheTicketsVerschiedenerKontenWerdenAbgerufen() async {
        let automatik = Minutenautomatik()
        let t = trade("123", auf: T.zeit(2026, 10, 4, 9), zu: T.zeit(2026, 10, 4, 10))
        var abrufe: [Int64] = []
        for kontoId in [Int64(1), 2, 1, 2] {
            var gespeichert: Set<String> = []
            await automatik.rufeAb(kontoId: kontoId, trades: [t], jetzt: jetztFest, vorhandene: { _ in
                gespeichert
            }, lade: { trades in
                abrufe.append(kontoId)
                gespeichert.formUnion(trades.map(\.id))
            })
        }
        #expect(abrufe == [1, 2])
    }

    @Test @MainActor func nachlaufWirdBeiSpaeteremAnlassFaellig() async {
        let automatik = Minutenautomatik()
        let t = trade("123", auf: T.zeit(2026, 10, 5, 11), zu: T.zeit(2026, 10, 5, 11, 30))
        var abrufe = 0
        var gespeichert: Set<String> = []
        for jetzt in [jetztFest, jetztFest.addingTimeInterval(1_800), jetztFest.addingTimeInterval(3_600)] {
            await automatik.rufeAb(kontoId: 1, trades: [t], jetzt: jetzt, vorhandene: { _ in
                gespeichert
            }, lade: { trades in
                abrufe += 1
                gespeichert.formUnion(trades.map(\.id))
            })
            #expect(abrufe == (jetzt == jetztFest ? 0 : 1))
        }
    }

    @Test @MainActor func fehlenderAbrufWirdWiederholtUndTeilerfolgBleibtErledigt() async {
        let automatik = Minutenautomatik()
        let trades = ["A", "B"].map { trade($0, auf: T.zeit(2026, 10, 4, 9), zu: T.zeit(2026, 10, 4, 10)) }
        var gespeichert: Set<String> = []
        var abrufe: [[String]] = []
        for versuch in 1...3 {
            await automatik.rufeAb(kontoId: 1, trades: trades, jetzt: jetztFest, vorhandene: { _ in
                gespeichert
            }, lade: { fehlend in
                abrufe.append(fehlend.map(\.id))
                // B liefert zuerst einen Fehler oder keine Kerzen; nur A wird gespeichert.
                gespeichert.formUnion(versuch == 1 ? ["A"] : ["B"])
            })
        }
        #expect(abrufe == [["A", "B"], ["B"]])
    }

    @Test @MainActor func vorhandeneKerzenBrauchenKeinenAbruf() async {
        let automatik = Minutenautomatik()
        let t = trade("123", auf: T.zeit(2026, 10, 4, 9), zu: T.zeit(2026, 10, 4, 10))
        await automatik.rufeAb(kontoId: 1, trades: [t], jetzt: jetztFest, vorhandene: { _ in
            [t.id]
        }, lade: { _ in
            Issue.record("Vorhandene Kerzen wurden erneut angefordert")
        })
    }

    @Test func nimmtNurTradesWieDerKnopfUndHoechstens31TageAlt() {
        let passend = trade("passend", auf: T.zeit(2026, 10, 4, 9), zu: T.zeit(2026, 10, 4, 10))
        let ohneUhrzeit = trade("ohneUhrzeit", auf: T.zeit(2026, 10, 4), zu: T.zeit(2026, 10, 4), nurDatum: true)
        let zuAlt = trade("zuAlt", auf: T.zeit(2026, 8, 1, 9), zu: T.zeit(2026, 8, 1, 10))
        // Schluss vor 30 Minuten: das Fenster (Ausstieg plus eine Stunde) läuft noch.
        let nochOffen = trade("nochOffen", auf: T.zeit(2026, 10, 5, 11), zu: T.zeit(2026, 10, 5, 11, 30))
        // Haltedauer über 31 Tage: zu langes Fenster für die Quelle.
        let zuLang = trade("zuLang", auf: T.zeit(2026, 8, 20), zu: T.zeit(2026, 10, 1))
        let ids = Minutenautomatik.kandidaten([passend, ohneUhrzeit, zuAlt, nochOffen, zuLang], jetzt: jetztFest).map(\.id)
        #expect(ids == ["passend"])
    }

    @Test func grenzeVon31TagenGiltAbSchluss() {
        let knapp = trade("knapp", auf: T.zeit(2026, 9, 4, 11), zu: T.zeit(2026, 9, 4, 12, 30))
        let drueber = trade("drueber", auf: T.zeit(2026, 9, 4, 10), zu: T.zeit(2026, 9, 4, 11))
        let ids = Minutenautomatik.kandidaten([knapp, drueber], jetzt: jetztFest).map(\.id)
        #expect(ids == ["knapp"])
    }
}
