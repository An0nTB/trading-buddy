#if os(macOS)
import Foundation
import PDFKit
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Steuer-Orientierung als PDF je Kalenderjahr (#210, Doc 22): Jahre nur mit Verkäufen, Verkaufsjahr in deutscher
/// Zeit, Trades ohne Euro-Kurs ausgewiesen, Seite 2 nur bei Krypto, Hinweis „Orientierung, keine Steuerberatung“ im
/// Fuß. Journal im Arbeitsspeicher; das PDF entsteht nur als Daten, nichts wird gesichert.
@Suite @MainActor struct SteuerAnlageTests {
    private typealias T = AppTestdaten

    private func depot() throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-steuer-scalable.csv",
                                kontonummer: "DE0012345678", kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        return m
    }

    /// ETH/USD (netto +43,90 USD, Schluss 03.04.2026) auf einem Euro-Konto.
    private func kraken(kurse: Bool) throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        if kurse {
            m.ezb.kurse = Referenzkurse(kurse: [T.tag(2026, 4, 1): ["USD": T.d("1.25")],
                                                T.tag(2026, 4, 3): ["USD": T.d("1.25")]])
        }
        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "S").utf8), dateiname: "appt-steuer-kraken.csv",
                                kontonummer: "KR-00004444", kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        return m
    }

    private struct PDFInhalt {
        var seiten: Int
        var text: String
    }

    private func pdf(_ anlage: SteuerAnlage) throws -> PDFInhalt {
        let daten = try #require(anlage.daten(thema: BerichtPDF.druckthema(.nordlicht)))
        let dokument = try #require(PDFDocument(data: daten))
        let text = (0..<dokument.pageCount).compactMap { dokument.page(at: $0)?.string }.joined(separator: "\n")
        return PDFInhalt(seiten: dokument.pageCount, text: text)
    }

    private func ohneLeerraum(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    /// Depot ohne Krypto: ein Jahr, eine Seite, Summe in Euro, Hinweis im Fuß.
    @Test func depotOhneKryptoNurSeiteEins() throws {
        let m = try depot()
        #expect(m.steuerjahre == [2026])
        let anlage = try #require(m.steuerAnlage(2026, jetzt: T.zeit(2026, 10, 3, 12)))
        #expect(anlage.krypto == nil)
        #expect(anlage.toepfe.count == 1)
        #expect(anlage.toepfe.first?.saldo == T.d("48"))
        #expect(anlage.ohneKurs == 0)
        #expect(anlage.kontext.waehrung == "EUR")
        #expect(anlage.kontext.dateiname == "Henry Steuer-Orientierung 2026.pdf")

        let inhalt = try pdf(anlage)
        #expect(inhalt.seiten == 1)
        #expect(!SteuerAnlage.fusshinweis.isEmpty)
        #expect(ohneLeerraum(inhalt.text).contains(ohneLeerraum(SteuerAnlage.fusshinweis)))
    }

    /// Ein Jahr ohne Verkäufe steht nicht im Menü und hat keine Töpfe.
    @Test func jahrOhneTradesFehlt() throws {
        let m = try depot()
        #expect(!m.steuerjahre.contains(2025))
        let leer = try #require(m.steuerAnlage(2025))
        #expect(leer.toepfe.isEmpty)
        #expect(leer.ohneKurs == 0)
        #expect(AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false).steuerjahre.isEmpty)
    }

    /// Krypto ohne EZB-Kurs: Seite 2 kommt, der Trade steht in keiner Summe und ist ausgewiesen.
    @Test func kryptoOhneKursAusgewiesenMitSeiteZwei() throws {
        let m = try kraken(kurse: false)
        #expect(m.steuerjahre == [2026])
        let anlage = try #require(m.steuerAnlage(2026))
        let topf = try #require(anlage.toepfe.first)
        #expect(anlage.toepfe.count == 1)
        #expect(topf.topf == .krypto)
        #expect(topf.anzahl == 1)
        #expect(topf.ohneEuro == 1)
        #expect(topf.saldo == 0)
        let krypto = try #require(anlage.krypto)
        #expect(krypto.ohneEuro >= 1)
        #expect(!krypto.vollstaendig)
        #expect(anlage.ohneKurs > 0)
        #expect(try pdf(anlage).seiten == 2)
    }

    /// Dieselbe Datei mit EZB-Kurs: nichts mehr ohne Euro-Wert, Saldo 43,90 USD / 1,25 = 35,12 EUR.
    @Test func kryptoMitKursInDerSumme() throws {
        let m = try kraken(kurse: true)
        let anlage = try #require(m.steuerAnlage(2026))
        #expect(anlage.ohneKurs == 0)
        #expect(anlage.toepfe.first?.saldo == T.d("35.12"))
        #expect(anlage.krypto?.ohneEuro == 0)
    }

    /// Verkauf am 31.12. um 23:30 UTC ist in deutscher Zeit schon der 1.1.: er gehört ins neue Jahr.
    @Test func verkaufsjahrNachDeutscherZeit() throws {
        let kopf = #""txid","ordertxid","pair","aclass","subclass","time","type","ordertype","price","cost","fee","vol","margin","misc","ledgers","posttxid","posstatuscode","cprice","ccost","cfee","cvol","cmargin","net","trades""#
        func zeile(_ nr: Int, _ zeit: String, _ art: String, _ preis: String, _ kosten: String) -> String {
            #""TSTJ\#(nr)-AAAAA-00000\#(nr)","OSTJ\#(nr)-AAAAA-00000\#(nr)","XXBTZEUR","forex","crypto","\#(zeit)","\#(art)","limit","\#(preis)","\#(kosten)","1.00000","0.50000000","0.00000","","LSTJ\#(nr)-AAAAA-00000\#(nr)","","","","","","","","","""#
        }
        let datei = [kopf,
                     zeile(1, "2025-12-31 10:00:00.0000", "buy", "60000.00", "30000.00000"),
                     zeile(2, "2025-12-31 23:30:00.0000", "sell", "61000.00", "30500.00000"),
                     ""].joined(separator: "\n")
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(datei.utf8), dateiname: "appt-steuer-jahreswechsel.csv",
                                kontonummer: "KR-00005555", kontoname: "Kraken", waehrung: "EUR", zeitzone: .gmt)
        #expect(m.steuerjahre.first == 2026)
        #expect(m.topfsummen(jahr: 2026).map(\.anzahl) == [1])
        #expect(m.topfsummen(jahr: 2025).isEmpty)
    }
}
#endif
