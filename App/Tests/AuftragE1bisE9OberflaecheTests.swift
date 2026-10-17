import Foundation
import Testing
import TradingCore
import TradingStore
import TradingRates
@testable import Trading_Buddy

/// Oberfläche zum Auftrag E1 bis E9 (Tim 17.10.2026): Kontoart, Prozentgrenzen in der Ampel, Setup-Grenzen und
/// offene Positionen in der Regelprüfung des `AppModell`, Kill-Kriterium über Konten, Statusdatei der Erweiterung.
/// Journal im Speicher, Hand-Trades erfunden. Geprüft werden Werte, keine Texte.
@MainActor @Suite struct AuftragE1bisE9OberflaecheTests {
    private typealias T = AppTestdaten

    /// Hand-Trade über 10 Stück zu 100 mit 50 Risiko; geschlossen zu 95 (−50 brutto, −1 Gebühr) oder offen.
    private func entwurf(stunde: Int, tag: Int = 2, offen: Bool = false, setup: String = "Day-DE") -> TradeEntwurf {
        var e = TradeEntwurf(jetzt: T.zeit(2026, 3, tag, stunde))
        e.einstieg = T.zeit(2026, 3, tag, stunde)
        e.ausstieg = T.zeit(2026, 3, tag, stunde, 30)
        e.offen = offen
        e.symbol = "Testindex"
        e.groesse = 10
        e.einstiegskurs = 100
        e.ausstiegskurs = offen ? nil : 95
        e.gebuehren = 1
        e.risiko = 50
        e.setup = setup
        e.neuerKontoname = "Testkonto"
        return e
    }

    @discardableResult
    private func speichere(_ e: TradeEntwurf, in m: AppModell) throws -> String {
        let wahl: TradeEntwurf.Kontowahl = m.konto?.id.map { .bestehend($0) } ?? .neu
        return try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: wahl,
                                             neuerKontoname: e.neuerKontoname, waehrung: "EUR")
    }

    private func modell() throws -> AppModell {
        AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
    }

    // MARK: E1 Kontoart

    @Test func kontoLaesstSichAlsDemoMarkieren() throws {
        let m = try modell()
        try speichere(entwurf(stunde: 9), in: m)
        let konto = try #require(m.konto)
        #expect(konto.kontoart == .echt)
        m.setzeKontoart(.demo, konto: konto)
        #expect(m.konto?.kontoart == .demo)
        #expect(m.fehler == nil)
    }

    // MARK: E2 Prozentgrenzen in der Ampel

    /// 1,5 % von 1.200 sind 18: ein Tagesverlust von 51 ist rot; bei 10.000 Kontostand (Grenze 150) grün.
    /// Ohne Kontostand ruht die Prozentgrenze, die Ampel meldet das gelb.
    @Test func prozentgrenzeRechnetMitDemKontostand() throws {
        let m = try modell()
        try speichere(entwurf(stunde: 9), in: m)
        let stand = try #require(m.letzterTagesstand)
        #expect(stand.netto == -51)
        let regeln = Handelsregeln(maxTagesverlustProzent: T.d("1.5"))
        func lampen(_ kontostand: Decimal?, mitBezug: Bool = true) -> [Ampellampe] {
            var r = regeln
            r.kontostand = mitBezug ? Kontostandbezug(betrag: kontostand ?? 0, seit: T.zeit(2026, 1, 1)) : nil
            var bezug = Ampelbezug()
            bezug.kontostand = kontostand
            return Ampellampe.lampen(regeln: r, stand: stand, verstoesse: [], trades: [], waehrung: "EUR", bezug: bezug)
        }
        #expect(lampen(1200).first { $0.id == "tagesverlust" }?.stufe == .rot)
        #expect(lampen(10_000).first { $0.id == "tagesverlust" }?.stufe == .gruen)
        let ohne = lampen(nil, mitBezug: false)
        #expect(ohne.first { $0.id == "tagesverlust" } == nil)
        #expect(ohne.first { $0.id == "kontostand" }?.stufe == .gelb)
    }

    /// Der Bezug der Ampel schreibt den Kontostand mit den Ergebnissen fort: 1.200 am 01.03., ein Verlust von 51
    /// am 02.03. zählt erst ab dem Folgetag.
    @Test func ampelbezugSchreibtKontostandFort() throws {
        let m = try modell()
        try speichere(entwurf(stunde: 9), in: m)
        try m.speichereRegeln(Handelsregeln(maxMonatsverlust: 40,
                                            kontostand: Kontostandbezug(betrag: 1200, seit: T.zeit(2026, 3, 1))))
        let stand = try #require(m.letzterTagesstand)
        let bezug = m.ampelbezug(stand)
        #expect(bezug.kontostand == 1200)
        #expect(bezug.monatsstand == 1200)
        #expect(bezug.monatsnetto == -51)
        let monat = Ampellampe.lampen(regeln: m.regeln, stand: stand, verstoesse: [], trades: [], waehrung: "EUR",
                                      bezug: bezug).first { $0.id == "monatsverlust" }
        #expect(monat?.stufe == .rot)
    }

    // MARK: E4, E5 Setup-Grenzen

    /// Karte Day-DE mit höchstens 3 Trades am Tag: der vierte ist ein Verstoß, die Ampel zählt 4 von 3.
    @Test func setupGrenzeZaehltJeTag() throws {
        let m = try modell()
        for stunde in 9...12 { try speichere(entwurf(stunde: stunde), in: m) }
        try speichere(entwurf(stunde: 13, setup: "Day-US"), in: m)
        try m.speichereSetup(Setup(name: "Day-DE", maxTradesJeTag: 3))
        try m.speichereSetup(Setup(name: "Day-US", maxTradesJeTag: 3))
        let verstoesse = m.verstoesse.filter { $0.art == .tradesJeSetup }
        #expect(verstoesse.count == 1)
        let stand = try #require(m.letzterTagesstand)
        let zaehlung = m.ampelbezug(stand).setupTrades
        #expect(zaehlung.first { $0.setup == "Day-DE" }?.anzahl == 4)
        #expect(zaehlung.first { $0.setup == "Day-US" }?.anzahl == 1)
        #expect(m.regeln.leer)
        #expect(m.ampellampen(stand).first { $0.id == "setup-day-de" }?.stufe == .rot)
    }

    /// Reine Datumsangaben bleiben in New York am Eröffnungstag, auch beim Risiko der Ampel.
    @Test func setupAmpelZaehltDatumseintragAmErstenOktober() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false, testZeitzone: zone)
        let csv = T.scalable.replacingOccurrences(of: "2026-04-01", with: "2026-10-01")
            .replacingOccurrences(of: "2026-04-02", with: "2026-10-02")
            .replacingOccurrences(of: "10:00:00", with: "00:00:00")
            .replacingOccurrences(of: "15:00:00", with: "00:00:00")
        _ = try m.importiereCSV(daten: Data(csv.utf8), dateiname: "appt-setup-datum.csv", kontonummer: "APPT-DATUM",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.utc)
        let trade = try #require(m.trades.first)
        #expect(trade.nurDatum)
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.setup = "Day-DE"
        m.speichereJournal(eintrag)
        try m.speichereSetup(Setup(name: "Day-DE", maxTradesJeTag: 1))
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zone
        let tag = try #require(kalender.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let staende = Regelpruefung.tagesstaende(m.angleich, regeln: m.regeln, zeitzone: zone,
                                                 setups: m.setupsJeTicket, playbook: m.playbook)
        let stand = try #require(staende.first { $0.tag == tag })
        #expect(stand.trades == 1)
        #expect(m.ampelbezug(stand).setupTrades.first?.anzahl == 1)
        #expect(m.ampellampen(stand).first { $0.id == "setup-day-de" }?.stufe == .gelb)
        #expect(m.trades(eroeffnetAm: tag).map(\.id) == [trade.id])
        #expect(m.trades(eroeffnetAm: kalender.date(byAdding: .day, value: -1, to: tag)!).isEmpty)
    }

    /// Ein offener Day-Trade vom 02.03. verletzt „gleicher Tag“, weil die Prüfung bis jetzt zählt.
    @Test func offenerDaytradeUeberNachtVerletztHaltedauer() throws {
        let m = try modell()
        let ticket = try speichere(entwurf(stunde: 9, offen: true), in: m)
        try m.speichereSetup(Setup(name: "Day-DE", haltedauer: .gleicherTag))
        #expect(m.verstoesse.contains { $0.art == .haltedauer && $0.trade == ticket })
        #expect(m.alleTrades.isEmpty && m.regeln.leer)
        #expect(m.letzterTagesstand == nil)
        #expect(m.ampellampen(m.letzterTagesstand).first { $0.id == "haltedauer" }?.stufe == .rot)
    }

    // MARK: E6 Offene Positionen

    /// Vier offene Hand-Trades bei Grenze 3: der vierte verstößt. Risiko je Position 50 aus dem eingetragenen Risiko;
    /// ab der dritten liegt das offene Risiko über 120.
    @Test func offeneHandtradesZaehlenBeiOffenenPositionen() throws {
        let m = try modell()
        var tickets: [String] = []
        for stunde in 9...12 { tickets.append(try speichere(entwurf(stunde: stunde, offen: true), in: m)) }
        try m.speichereRegeln(Handelsregeln(maxOffenePositionen: 3, maxOffenesRisiko: 120))
        let offene = m.offeneRegelpositionen
        #expect(offene.count == 4)
        #expect(offene.allSatisfy { $0.risiko == 50 })
        let positionen = m.verstoesse.filter { $0.art == .offenePositionen }.map(\.trade)
        #expect(positionen == [tickets[3]])
        let risiko = Set(m.verstoesse.filter { $0.art == .offenesRisiko }.map(\.trade))
        #expect(risiko == Set(tickets[2...]))
        #expect(m.alleTrades.isEmpty && m.letzterTagesstand == nil)
        let lampen = m.ampellampen(m.letzterTagesstand)
        #expect(lampen.first { $0.id == "offenePositionen" }?.stufe == .rot)
        #expect(lampen.first { $0.id == "offenesRisiko" }?.stufe == .rot)
    }

    /// Der Monatsfilter wählt historische Tagesstände; offene Warnungen gelten weiterhin jetzt.
    @Test func offeneWarnungenBleibenBeiLeeremMonatsfilterSichtbar() throws {
        let m = try modell()
        try speichere(entwurf(stunde: 8), in: m)
        try speichere(entwurf(stunde: 9, offen: true), in: m)
        try speichere(entwurf(stunde: 10, offen: true), in: m)
        try m.speichereRegeln(Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 80))
        try m.speichereSetup(Setup(name: "Day-DE", haltedauer: .gleicherTag))
        #expect(m.letzterTagesstand != nil)
        m.zeitraum = .monat(T.zeit(2026, 2, 1))
        #expect(m.letzterTagesstand == nil)
        let lampen = m.ampellampen(m.letzterTagesstand)
        #expect(lampen.first { $0.id == "offenePositionen" }?.stufe == .rot)
        #expect(lampen.first { $0.id == "offenesRisiko" }?.stufe == .rot)
        #expect(lampen.first { $0.id == "haltedauer" }?.stufe == .rot)
        #expect(lampen.first { $0.id == "tradesJeTag" } == nil)
    }

    @Test func ohneKontoOderRegelnBleibtDieAmpelLeer() throws {
        let m = try modell()
        #expect(m.ampellampen(m.letzterTagesstand).isEmpty)
        try speichere(entwurf(stunde: 9, offen: true), in: m)
        #expect(m.ampellampen(m.letzterTagesstand).isEmpty)
    }

    @Test func ampelOffenePositionenJetzt() {
        let regeln = Handelsregeln(maxOffenePositionen: 3)
        func stufe(_ anzahl: Int) -> Ampelstufe? {
            var bezug = Ampelbezug()
            bezug.offene = (0..<anzahl).map { OffenerTrade(id: "o\($0)", openTime: T.zeit(2026, 3, 2, 9 + $0)) }
            return Ampellampe.erweiterteLampen(regeln: regeln, verstoesse: [], waehrung: "EUR", bezug: bezug)
                .first { $0.id == "offenePositionen" }?.stufe
        }
        #expect(stufe(2) == .gruen)
        #expect(stufe(3) == .gelb)
        #expect(stufe(4) == .rot)
    }

    @Test func gleicheEroeffnungszeitVerbindetKeineGetrenntenHandtickets() throws {
        let m = try modell()
        let erster = try speichere(entwurf(stunde: 9, offen: true), in: m)
        let zweiter = try speichere(entwurf(stunde: 9, offen: true), in: m)
        try m.speichereRegeln(Handelsregeln(maxOffenePositionen: 1))
        #expect(erster != zweiter && m.offeneRegelpositionen.count == 2)
        let verstoesse = m.verstoesse.filter { $0.art == .offenePositionen }
        #expect(verstoesse.count == 1)
        #expect(verstoesse.first?.trade == [erster, zweiter].sorted().last)
    }

    @Test func teilverkaufMitOffenemRestZaehltEinmal() throws {
        let m = try modell()
        let csv = T.scalable.replacingOccurrences(of: "-10;55,00;550,00", with: "-4;55,00;220,00")
        _ = try m.importiereCSV(daten: Data(csv.utf8), dateiname: "appt-teilverkauf.csv",
                                kontonummer: "TEST0000", kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        try m.speichereRegeln(Handelsregeln(maxOffenePositionen: 1))
        #expect(m.alleTrades.count == 1 && m.offeneRegelpositionen.count == 1)
        #expect(m.verstoesse.isEmpty)
    }

    @Test func ampelbezugZaehltDatumsschlussNichtVorMonatsbeginn() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false, testZeitzone: zone)
        let csv = T.scalable.replacingOccurrences(of: "2026-04-01", with: "2026-09-30")
            .replacingOccurrences(of: "2026-04-02", with: "2026-10-01")
            .replacingOccurrences(of: "15:00:00", with: "00:00:00")
        _ = try m.importiereCSV(daten: Data(csv.utf8), dateiname: "appt-datum-regeln.csv",
                                kontonummer: "TEST0000", kontoname: "Depot", waehrung: "EUR", zeitzone: T.utc)
        try m.speichereRegeln(Handelsregeln(maxTagesverlustProzent: 1, maxMonatsverlustProzent: 1,
                                            kontostand: Kontostandbezug(betrag: 1000, seit: T.zeit(2026, 9, 1))))
        let stand = try #require(m.letzterTagesstand)
        let bezug = m.ampelbezug(stand)
        #expect(stand.netto == 48)
        #expect(bezug.kontostand == 1000 && bezug.monatsstand == 1000)
        #expect(bezug.monatsnetto == 48)
    }

    @Test func pdfBerichtNutztSetupgrenzenUndOffenePositionen() throws {
        let m = try modell()
        try speichere(entwurf(stunde: 8, offen: true, setup: "Swing"), in: m)
        try speichere(entwurf(stunde: 9), in: m)
        let zweiter = try speichere(entwurf(stunde: 10), in: m)
        try m.speichereSetup(Setup(name: "Day-DE", maxTradesJeTag: 1))
        let nurSetup = m.monatsbericht(T.zeit(2026, 3, 2), jetzt: T.zeit(2026, 3, 3))
        #expect(nurSetup.kontext.regelnHinterlegt)
        #expect(nurSetup.bericht.regelverstoesse.map(\.trade) == [zweiter])
        #expect(nurSetup.bericht.disziplin.regeltreu == 1 && nurSetup.bericht.disziplin.verletzt == 1)
        try m.speichereRegeln(Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 75))
        let b = m.monatsbericht(T.zeit(2026, 3, 2), jetzt: T.zeit(2026, 3, 3)).bericht
        #expect(b.anzahl(.tradesJeSetup) == 1)
        #expect(b.anzahl(.offenePositionen) == 2 && b.anzahl(.offenesRisiko) == 2)
        #expect(b.regelverstoesse == m.verstoesse)
        #expect(b.disziplin.verletzt == 2 && b.disziplin.regeltreu == 0)
    }

    // MARK: E7 Kill-Kriterium

    /// Gleichnamige Beispieltrades verändern weder Anzahl noch R oder Fälligkeit echter Setups.
    @Test(arguments: [1, 2])
    func killKriteriumIgnoriertBeispielkonto(schwelle: Int) throws {
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        let namen = [String(localized: "Ausbruch"), String(localized: "Rücksetzer")]
        for (n, name) in namen.enumerated() {
            try speichere(entwurf(stunde: 9 + n, setup: name), in: m)
            try m.speichereSetup(Setup(name: name, pruefungNachTrades: schwelle))
        }
        let vorher = m.setuppruefungen()
        try m.legeBeispieldatenAn(heute: T.zeit(2026, 9, 15, 12))
        #expect(m.beispielkonto?.kontoart == .echt)
        #expect(m.journaleintraege.values.contains { $0.setup == namen[0] })
        #expect(m.journaleintraege.values.contains { $0.setup == namen[1] })
        let nachher = m.setuppruefungen()
        #expect(nachher == vorher)
        #expect(nachher.count == 2)
        for pruefung in nachher {
            #expect(pruefung.anzahl == 1 && pruefung.anzahlMitR == 1)
            #expect(pruefung.erwartungswertR == T.d("-1.02"))
            #expect(pruefung.faellig == (schwelle == 1))
            #expect(pruefung.nichtBestanden == (schwelle == 1))
        }
        let export = try ExportOrdner.export(journal, zeitzone: m.zeitzone)
        #expect(nachher == export.setuppruefungen(m.playbook))
        #expect(m.fehler == nil)
    }

    /// 43,90 USD / 1,25 = 35,12 EUR; mit 20 EUR geplantem Risiko sind das 1,756 R. Ohne Kurs bleibt R unbekannt.
    @Test(arguments: [true, false])
    func killKriteriumGleichtFremdwaehrungWieExportAn(mitKurs: Bool) throws {
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        let kurse = [JournalExport.Tageskurse(tag: T.tag(2026, 4, 3), kurse: ["USD": T.d("1.25")])]
        if mitKurs { m.ezb.kurse = Referenzkurse(kurse: [T.tag(2026, 4, 3): ["USD": T.d("1.25")]]) }
        _ = try m.importiereCSV(daten: Data(T.kraken().utf8), dateiname: "appt-setup-usd.csv", kontonummer: "APPT-USD",
                                kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        let trade = try #require(m.trades.first)
        #expect(trade.stopLoss == nil && trade.waehrung == "USD")
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.setup = "Day-US"
        eintrag.risikoEinstieg = 20
        m.speichereJournal(eintrag)
        try m.speichereSetup(Setup(name: "Day-US", pruefungNachTrades: 1))
        let pruefung = try #require(m.setuppruefungen().first)
        #expect(pruefung.anzahl == 1 && pruefung.faellig)
        #expect(pruefung.anzahlMitR == (mitKurs ? 1 : 0))
        #expect(pruefung.anzahlRAngenommen == (mitKurs ? 1 : 0))
        #expect(pruefung.erwartungswertR == (mitKurs ? T.d("1.756") : nil))
        #expect(pruefung.nichtBestanden == !mitKurs)
        var export = try ExportOrdner.export(journal, zeitzone: m.zeitzone)
        export.referenzkurse = mitKurs ? kurse : nil
        #expect([pruefung] == export.setuppruefungen(m.playbook))
        #expect(m.fehler == nil)
    }

    /// Zwei Day-DE-Trades bei Prüfung nach 2: fällig, Erwartungswert −1,02 R (−51 bei 50 Risiko), nicht bestanden.
    /// Nach dem Umschalten auf Demo zählen sie als Demo.
    @Test func killKriteriumTrenntEchtgeldUndDemo() throws {
        let m = try modell()
        try speichere(entwurf(stunde: 9), in: m)
        try speichere(entwurf(stunde: 10), in: m)
        try m.speichereSetup(Setup(name: "Day-DE", pruefungNachTrades: 2))
        let echt = try #require(m.setuppruefungen().first)
        #expect(echt.kontoart == Kontoart.echt.rawValue)
        #expect(echt.anzahl == 2)
        #expect(echt.faellig)
        #expect(echt.nichtBestanden)
        #expect(echt.erwartungswertR == T.d("-1.02"))
        m.setzeKontoart(.demo, konto: try #require(m.konto))
        #expect(m.setuppruefungen().map(\.kontoart) == [Kontoart.demo.rawValue])
    }

    // MARK: E9 Statusdatei der Erweiterung

    @Test func eingerichteterExportOhneVersionsnachweisWarntBeimUpgrade() throws {
        // 0.18.1 schreibt keine Statusdatei; nach dem Upgrade darf das nicht als passend gelten.
        let hinweis = try #require(Erweiterungsstatus.hinweis(
            exportEingerichtet: true, stand: nil, gemeldet: nil))
        #expect(hinweis == .ungeprueft)
        #expect(Erweiterungsstatus.hinweis(
            exportEingerichtet: true, stand: nil, gemeldet: hinweis.meldeschluessel) == nil)
        #expect(Erweiterungsstatus.hinweis(
            exportEingerichtet: true, stand: nil, gemeldet: "ungeprueft|0.26.1") == .ungeprueft)
    }

    @Test func ohneEingerichtetenExportKeinErweiterungshinweis() {
        #expect(Erweiterungsstatus.hinweis(exportEingerichtet: false, stand: nil, gemeldet: nil) == nil)
    }

    @Test func passenderVersionsnachweisLoestUngeprueftenStandAb() {
        let stand = Erweiterungsstand(erweiterung: "0.20.0")
        #expect(Erweiterungsstatus.hinweis(
            exportEingerichtet: true, stand: stand,
            gemeldet: Erweiterungsstatus.Hinweis.ungeprueft.meldeschluessel) == nil)
    }

    @Test func abweichenderRechenkernWirdWeiterhinEinmalGemeldet() throws {
        let stand = Erweiterungsstand(erweiterung: "0.20.0", rechenkern: "0.26.1")
        let hinweis = try #require(Erweiterungsstatus.hinweis(
            exportEingerichtet: true, stand: stand,
            gemeldet: Erweiterungsstatus.Hinweis.ungeprueft.meldeschluessel))
        #expect(hinweis == .abweichend(stand))
        #expect(hinweis.meldeschluessel == stand.meldeschluessel)
        #expect(Erweiterungsstatus.hinweis(
            exportEingerichtet: true, stand: stand, gemeldet: hinweis.meldeschluessel) == nil)
    }

    @Test func statusdateiVergleichtRechenkern() throws {
        let gleich = try Erweiterungsstand(erweiterung: "0.20.0", geschrieben: T.zeit(2026, 10, 17, 16)).json()
        let alt = Erweiterungsstand(erweiterung: "0.18.1", rechenkern: "0.26.1")
        let s1 = try Erweiterungsstand.lese(gleich)
        #expect(s1.passtZurApp)
        #expect(s1.geschrieben == T.zeit(2026, 10, 17, 16))
        #expect(!alt.passtZurApp)
        #expect(alt.meldeschluessel != s1.meldeschluessel)
        #expect(alt.hinweistext.contains("0.26.1"))
    }
}
