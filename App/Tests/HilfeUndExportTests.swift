import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Hilfe-Menü aus #197: „Erste Schritte“ nur beim ersten Start ohne Konto, „Problem melden“ ohne echte Daten.
/// Nur synthetische Angaben; `Fehlerprotokoll` bekommt eigene, eindeutige Texte.
@Suite @MainActor struct HilfeMenueTests {
    private typealias T = AppTestdaten

    /// Wahrheitstafel: nur ohne Haken, ohne Konto und außerhalb der Tests zeigt die App das Blatt beim Start.
    @Test func erststartNurOhneKontoOhneHakenUndAusserhalbDerTests() {
        for ausgeblendet in [false, true] {
            for kontoVorhanden in [false, true] {
                for imTest in [false, true] {
                    let erwartet = !ausgeblendet && !kontoVorhanden && !imTest
                    #expect(HilfeBlaetterZeigen.zeigeBeimStart(ausgeblendet: ausgeblendet, kontoVorhanden: kontoVorhanden,
                                                               imTest: imTest) == erwartet)
                }
            }
        }
    }

    @Test func bereinigtEntferntBenutzernamenUndLangeNummern() {
        #expect(Diagnose.bereinigt("/Users/appt-ich/Dokumente und /Users/appt-du/x.csv", heimordner: "/Users/appt-ich")
                == "~/Dokumente und /Users/…/x.csv")
        // Vierstellige Zahlen (Jahre, Kontoendziffern) bleiben, ab fünf Stellen wird gekürzt.
        #expect(Diagnose.bereinigt("2026 1234 12345 DE0012345678", heimordner: "/") == "2026 1234 ••• DE•••")
    }

    private func angaben(fehler: [(zeit: Date, text: String)]) -> Diagnose.Angaben {
        Diagnose.Angaben(app: "9.9 (99)", kern: "0.24.0", connector: "0.14.0", system: "Testsystem 1.0", konten: 2,
                         importordnerAktiv: true, fehler: fehler)
    }

    @Test func diagnoseOhneFehler() {
        let text = Diagnose.text(angaben(fehler: []))
        #expect(text.split(separator: "\n").count == 8)
        for wert in ["9.9 (99)", "0.24.0", "0.14.0", "Testsystem 1.0", ": 2"] {
            #expect(text.contains(wert), "\(wert) fehlt")
        }
    }

    /// Fehlertexte mit Kontonummer und Pfad: Zeit bleibt, Nummer und Benutzername nicht.
    @Test func diagnoseMitFehlernOhneEchteDaten() {
        let text = Diagnose.text(angaben(fehler: [
            (zeit: T.zeit(2026, 10, 3, 12), text: "Lesen: DE0012345678 in /Users/appt-person/Downloads/appt.csv"),
            (zeit: T.zeit(2026, 10, 3, 13), text: "Speichern: Ticket 87654321"),
        ]))
        #expect(text.split(separator: "\n").count == 10)
        #expect(text.contains("2026-10-03T12:00:00Z"))
        #expect(text.contains("2026-10-03T13:00:00Z"))
        #expect(!text.contains("0012345678"))
        #expect(!text.contains("87654321"))
        #expect(!text.contains("appt-person"))
        #expect(text.contains("DE•••"))
    }

    /// Höchstens zehn Einträge, die neuesten bleiben.
    @Test func fehlerprotokollBehaeltDieLetztenZehn() {
        let texte = (0..<12).map { "appt-fehler-\(UUID().uuidString)-\($0)" }
        for text in texte { Fehlerprotokoll.merke(text, zeit: T.zeit(2026, 10, 3, 12)) }
        #expect(Fehlerprotokoll.eintraege.count == Fehlerprotokoll.hoechstens)
        #expect(Fehlerprotokoll.eintraege.map { $0.text } == Array(texte.suffix(Fehlerprotokoll.hoechstens)))
    }

    /// Abweichende Vorgänge: höchstens fünf Tickets in der Meldung, der Rest als Anzahl (Doc 52 H5).
    @Test func abweichenderDatensatzNenntHoechstensFuenfTickets() {
        let tickets = ["A", "B", "C", "D", "E", "F", "G"].map { "APPT-\($0)" }
        let lang = Importlesung.fehlertext(SpeicherFehler.abweichenderDatensatz(tickets: tickets))
        for ticket in tickets.prefix(5) { #expect(lang.contains(ticket), "\(ticket) fehlt") }
        #expect(!lang.contains("APPT-F"))
        #expect(!lang.contains("APPT-G"))
        #expect(lang.contains("2"))
        let kurz = Importlesung.fehlertext(SpeicherFehler.abweichenderDatensatz(tickets: Array(tickets.prefix(5))))
        for ticket in tickets.prefix(5) { #expect(kurz.contains(ticket), "\(ticket) fehlt") }
    }

    #if os(macOS)
    /// Der Build nimmt `Connector/manifest.json` als Ressource mit; die Diagnose nennt dessen Version.
    @Test func diagnoseKenntAppUndConnectorVersion() {
        #expect(Diagnose.connectorVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
        #expect(!Diagnose.appVersion.contains("?"))
    }
    #endif

    /// Codex-Review 04.10.2026: Ins Fehlerprotokoll kommt nur die Fehlerart, nie Spalten, Tickets oder Feldinhalte.
    @Test func fehlerartOhneInhalte() {
        let kopf = Importlesung.kategorie(CSVImportFehler.unbekanntesFormat(kopf: ["appt-spalte", "DE0012345678"]))
        #expect(kopf == "CSVImportFehler.unbekanntesFormat")
        let zeit = Importlesung.kategorie(CSVImportFehler.ungueltigeZeit(zeile: 7, text: "appt-feld"))
        #expect(zeit == "CSVImportFehler.ungueltigeZeit")
        let datensatz = Importlesung.kategorie(SpeicherFehler.abweichenderDatensatz(tickets: ["APPT-1"]))
        #expect(datensatz == "SpeicherFehler.abweichenderDatensatz")
        #expect(Importlesung.kategorie(SpeicherFehler.keinText) == "SpeicherFehler.keinText")
        let cocoa = Importlesung.kategorie(CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/appt/x.csv"]))
        #expect(!cocoa.contains("appt"))
    }

    /// Lesefehler einer unbekannten Datei: Meldung für den Nutzer, Fehlerart ohne Dateiinhalt.
    @Test func lesefehlerHatKategorie() {
        let daten = Data("appt-geheim;appt-spalte\n1;2\n".utf8)
        guard case .fehler(_, let kategorie) = Importlesung.lies(daten, dateiname: "appt-name.csv",
                                                               serverzeit: T.utc, xtbZeit: T.utc) else {
            Issue.record("Unbekannte Datei erkannt")
            return
        }
        #expect(!kategorie.contains("appt"))
    }

    /// Rückfragen des Import-Ordners erscheinen nur als Zahl.
    @Test func rueckfragenNurAlsZahl() {
        var a = angaben(fehler: [])
        a.rueckfragen = 3
        let text = Diagnose.text(a)
        #expect(text.contains("offene Rückfragen: 3"))
    }
}

/// Disziplin mit Betragsregeln (#202, #205, Kern 0.24.0, Doc 54): Ein Trade ohne EZB-Kurs zählt bei Anzahl-Regeln
/// mit, bei Tagesverlust und Risiko je Trade nicht. Ergänzung zu `DisziplinOhneKursTests` (Trades je Tag).
@Suite @MainActor struct DisziplinBetragsregelTests {
    private typealias T = AppTestdaten

    /// Euro-Konto: ETH/USD am 01.04.2026 mit Verlust (netto rund −102 USD), danach am selben Tag BTC/EUR mit Gewinn.
    private static let kraken: String = {
        let kopf = #""txid","ordertxid","pair","aclass","subclass","time","type","ordertype","price","cost","fee","vol","margin","misc","ledgers","posttxid","posstatuscode","cprice","ccost","cfee","cvol","cmargin","net","trades""#
        func zeile(_ nr: Int, _ paar: String, _ zeit: String, _ art: String, _ preis: String, _ kosten: String) -> String {
            #""TBTR\#(nr)-AAAAA-00000\#(nr)","OBTR\#(nr)-AAAAA-00000\#(nr)","\#(paar)","forex","crypto","\#(zeit)","\#(art)","limit","\#(preis)","\#(kosten)","1.00000","0.50000000","0.00000","","LBTR\#(nr)-AAAAA-00000\#(nr)","","","","","","","","","""#
        }
        return [kopf,
                zeile(1, "XETHZUSD", "2026-04-01 07:00:00.0000", "buy", "3000.00", "1500.00000"),
                zeile(2, "XETHZUSD", "2026-04-01 08:00:00.0000", "sell", "2800.00", "1400.00000"),
                zeile(3, "XXBTZEUR", "2026-04-01 10:00:00.0000", "buy", "60000.00", "30000.00000"),
                zeile(4, "XXBTZEUR", "2026-04-02 09:00:00.0000", "sell", "61000.00", "30500.00000"),
                ""].joined(separator: "\n")
    }()

    private func modell(kurse: Bool) throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        if kurse { m.ezb.kurse = Referenzkurse(kurse: [T.tag(2026, 4, 1): ["USD": T.d("1.25")]]) }
        _ = try m.importiereCSV(daten: Data(Self.kraken.utf8), dateiname: "appt-betragsregel.csv",
                                kontonummer: "KR-00003333", kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        return m
    }

    private static let betragsregeln = Handelsregeln(maxTagesverlust: 50, maxRisikoJeTrade: 50)

    /// Ohne Kurs kennt die App den Verlust in Euro nicht: kein Tagesverlust, kein Risikoverstoß.
    @Test func ohneKursKeinBetragsverstoss() throws {
        let m = try modell(kurse: false)
        #expect(m.trades.count == 2)
        #expect(m.waehrungsstand.ohneKurs == 1)
        try m.speichereRegeln(Self.betragsregeln)
        #expect(m.verstoesse.isEmpty)
        let disziplin = m.disziplin
        #expect(disziplin.punkte.count == 2)
        #expect(disziplin.regeltreu == 2)
        #expect(disziplin.verletzt == 0)
    }

    /// Gegenprobe mit Kurs: derselbe Verlust (−81,60 EUR) verletzt beide Betragsregeln.
    @Test func mitKursGreifenBeideBetragsregeln() throws {
        let m = try modell(kurse: true)
        #expect(m.waehrungsstand.ohneKurs == 0)
        try m.speichereRegeln(Self.betragsregeln)
        #expect(Set(m.verstoesse.map(\.art)) == [.risikoJeTrade, .tagesverlust])
        #expect(m.disziplin.verletzt == 2)
        #expect(m.disziplin.regeltreu == 0)
    }

    /// Anzahl-Regel „Stopp nach einem Verlust“: der Verlust ohne Kurs zählt, der BTC-Trade danach verstößt;
    /// in die Netto-Summen fließt nur der Euro-Betrag.
    @Test func ohneKursZaehltDerVerlustBeiDerAnzahlregel() throws {
        let m = try modell(kurse: false)
        try m.speichereRegeln(Handelsregeln(stoppNachVerlusten: 1))
        let euro = try #require(m.kontoTrades.first)
        #expect(m.kontoTrades.count == 1)
        #expect(m.verstoesse.map(\.trade) == [euro.id])
        let disziplin = m.disziplin
        #expect(disziplin.verletzt == 1)
        #expect(disziplin.regeltreu == 1)
        #expect(disziplin.nettoVerletzt == euro.netProfit)
        #expect(disziplin.nettoRegeltreu == 0)
    }
}

#if os(macOS)
/// Anzeigewährung im Export-Kopf (#203, Connector 0.14.0, Vierter Gegencheck H21): Claude bekommt die Währung der
/// App-Summen und die Kurse dafür; ein Wechsel stößt den Export an.
@Suite @MainActor struct ExportAnzeigewaehrungTests {
    private typealias T = AppTestdaten

    private func journalMitScalable() throws -> Journal {
        let journal = try Journal.imSpeicher()
        _ = try journal.importiereCSV(datei: Data(T.scalable.utf8), dateiname: "appt-scalable-anzeige.csv",
                                      kontonummer: "DE0012345678", kontowaehrung: "EUR", zeitzone: T.berlin)
        return journal
    }

    @Test func anzeigewaehrungStehtImKopf() throws {
        let journal = try journalMitScalable()
        let export = try ExportOrdner.export(journal, zeitzone: T.berlin, anzeigewaehrung: " usd ")
        #expect(export.anzeigewaehrung == "USD")
        let wurzel = try #require(try JSONSerialization.jsonObject(with: try export.json()) as? [String: Any])
        #expect(wurzel["anzeigewaehrung"] as? String == "USD")
        #expect(try JournalExport.lese(try export.json()).anzeigewaehrung == "USD")
    }

    @Test func ohneAnzeigewaehrungKeinEintrag() throws {
        let journal = try journalMitScalable()
        #expect(try ExportOrdner.export(journal, zeitzone: T.berlin).anzeigewaehrung == nil)
        #expect(try ExportOrdner.export(journal, zeitzone: T.berlin, anzeigewaehrung: "  ").anzeigewaehrung == nil)
    }

    /// Euro-Trades auf einem Euro-Konto brauchen keinen Kurs; mit Anzeigewährung GBP kommt nur der GBP-Kurs mit.
    @Test func kursauszugEnthaeltDieAnzeigewaehrung() throws {
        let export = try ExportOrdner.export(try journalMitScalable(), zeitzone: T.berlin)
        let kurse = Referenzkurse(kurse: [T.tag(2026, 4, 2): ["USD": T.d("1.25"), "GBP": T.d("0.8")]])
        #expect(JournalExport.referenzkursauszug(kurse, fuer: export.konten).isEmpty)
        let auszug = JournalExport.referenzkursauszug(kurse, fuer: export.konten, anzeigewaehrung: "gbp")
        #expect(auszug.map(\.tag) == [T.tag(2026, 4, 2)])
        #expect(auszug.first?.kurse == ["GBP": T.d("0.8")])
    }

    @Test func wechselDerAnzeigewaehrungStoesstExportAn() throws {
        let m = AppModell(journal: try journalMitScalable(), nebenwirkungen: false)
        var vorher = m.exportAnstoesse
        m.anzeigewaehrung = "USD"
        #expect(m.exportAnstoesse > vorher)
        vorher = m.exportAnstoesse
        m.anzeigewaehrung = "USD"
        #expect(m.exportAnstoesse == vorher)
        m.anzeigewaehrung = nil
        #expect(m.exportAnstoesse > vorher)
    }
}
#endif
