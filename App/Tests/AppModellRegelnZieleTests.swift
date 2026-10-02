import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Ziele, Handelsregeln mit Ampel, Playbook mit Checkliste, Steuer-Angaben und offene Positionen im `AppModell`,
/// gegen ein Journal im Arbeitsspeicher ohne Export und EZB-Abruf. Geprüft werden Werte, keine Texte.
@Suite @MainActor struct AppModellRegelnZieleTests {
    private typealias T = AppTestdaten

    /// Scalable mit Verlust: Kauf 10 zu 50, Verkauf 10 zu 40, Gebühren 2 × −1: netto −102 EUR.
    private static let scalableVerlust = """
        date;time;status;reference;description;assetType;type;isin;shares;price;amount;fee;tax;currency
        2026-04-01;09:00:00;Executed;APPT0011;Einzahlung;Cash;Ein-/Auszahlung;;;;2.000,00;0,00;0,00;EUR
        2026-04-01;10:00:00;Executed;APPT0012;Testwert AG;Security;Order;DE000TEST001;10;50,00;-500,00;-1,00;0,00;EUR
        2026-04-02;15:00:00;Executed;APPT0013;Testwert AG;Security;Order;DE000TEST001;-10;40,00;400,00;-1,00;0,00;EUR

        """

    private func modell() throws -> AppModell {
        AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
    }

    private func mitDepot(_ csv: String = AppTestdaten.scalable) throws -> AppModell {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(csv.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        return m
    }

    private func ziel(_ text: String, vonTagen: Int, bisTagen: Int) -> Reviewziel {
        let jetzt = Date()
        return Reviewziel(text: text, von: jetzt.addingTimeInterval(Double(vonTagen) * 86_400),
                          bis: jetzt.addingTimeInterval(Double(bisTagen) * 86_400))
    }

    // MARK: Review-Ziele

    @Test func zielOhneKontoWirdAbgelehnt() throws {
        let m = try modell()
        #expect(throws: Zielfehler.keinKonto) { try m.legeZielAn(ziel("Höchstens zwei Trades", vonTagen: 0, bisTagen: 7)) }
        #expect(m.ziele.isEmpty)
    }

    @Test func zielOhneTextOderDauerWirdAbgelehnt() throws {
        let m = try mitDepot()
        #expect(throws: SpeicherFehler.self) { try m.legeZielAn(ziel("  ", vonTagen: 0, bisTagen: 7)) }
        #expect(throws: SpeicherFehler.self) { try m.legeZielAn(ziel("Ziel", vonTagen: 7, bisTagen: 0)) }
        #expect(m.ziele.isEmpty)
    }

    /// Abhaken setzt Status und Ergebnis; Wiederöffnen verwirft das Ergebnis; Löschen entfernt das Ziel.
    @Test func zielAbhakenWiederoeffnenLoeschen() throws {
        let m = try mitDepot()
        try m.legeZielAn(ziel("Höchstens zwei Trades", vonTagen: 0, bisTagen: 7))
        var gespeichert = try #require(m.ziele.first)
        #expect(m.offeneZiele.count == 1)

        m.setzeZielstatus(gespeichert, .erreicht, ergebnis: "1 von 2")
        gespeichert = try #require(m.ziele.first)
        #expect(gespeichert.status == .erreicht)
        #expect(gespeichert.ergebnis == "1 von 2")
        #expect(m.offeneZiele.isEmpty)

        m.setzeZielstatus(gespeichert, .offen, ergebnis: "bleibt nicht")
        gespeichert = try #require(m.ziele.first)
        #expect(gespeichert.status == .offen)
        #expect(gespeichert.ergebnis == nil)

        m.loescheZiel(gespeichert)
        #expect(m.ziele.isEmpty)
        #expect(m.fehler == nil)
    }

    /// Abgelaufene offene Ziele werden „verfehlt“, laufende bleiben offen.
    @Test func abgelaufenesZielWirdVerfehlt() throws {
        let m = try mitDepot()
        try m.legeZielAn(ziel("Abgelaufen", vonTagen: -10, bisTagen: -3))
        try m.legeZielAn(ziel("Laufend", vonTagen: -1, bisTagen: 6))
        m.schliesseAbgelaufeneZiele()
        let alt = try #require(m.ziele.first { $0.text == "Abgelaufen" })
        let neu = try #require(m.ziele.first { $0.text == "Laufend" })
        #expect(alt.status == .verfehlt)
        #expect(alt.ergebnis?.isEmpty == false)
        #expect(neu.status == .offen)
        #expect(m.offeneZiele.count == 1)
    }

    // MARK: Handelsregeln und Ampel

    @Test func regelnOhneKontoUndUngueltigeGrenzen() throws {
        #expect(throws: Regelfehler.keinKonto) { try modell().speichereRegeln(Handelsregeln(maxTradesJeTag: 3)) }
        let m = try mitDepot()
        #expect(throws: SpeicherFehler.self) { try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 0)) }
        #expect(m.regeln.leer)
        try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 3))
        #expect(m.regeln.maxTradesJeTag == 3)
        try m.speichereRegeln(Handelsregeln())
        #expect(m.regeln.leer)
    }

    /// „Nicht regeltreu“ im Journal zählt als Verstoß der Art `manuell`, auch ohne gesetzte Grenze.
    @Test func journalNichtRegeltreuIstVerstoss() throws {
        let m = try mitDepot()
        let trade = try #require(m.trades.first)
        #expect(m.verstoesse.isEmpty)
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.regeltreue = false
        m.speichereJournal(eintrag)
        #expect(m.manuellVerletzt == [trade.id])
        #expect(m.verstoesse.map(\.art) == [.manuell])
        #expect(m.verstoesse.first?.trade == trade.id)
    }

    /// Der letzte Handelstag ist der Schlusstag des Verkaufs: kein neuer Trade, netto −102.
    @Test func letzterTagesstandIstDerSchlusstag() throws {
        let m = try mitDepot(Self.scalableVerlust)
        let stand = try #require(m.letzterTagesstand)
        #expect(stand.netto == T.d("-102"))
        #expect(stand.trades == 0)
        #expect(stand.verlusteInFolge == 1)
        m.zeitraum = .monat(T.zeit(2026, 2, 1))
        #expect(m.letzterTagesstand == nil)
    }

    /// Ampel Tagesverlust: 102 Verlust ist ab Grenze 100 rot, bei 120 gelb (ab 70 %), bei 200 grün.
    @Test func ampelTagesverlustNachGrenze() throws {
        let m = try mitDepot(Self.scalableVerlust)
        let stand = try #require(m.letzterTagesstand)
        func stufe(_ grenze: String) -> Ampelstufe? {
            Ampellampe.lampen(regeln: Handelsregeln(maxTagesverlust: T.d(grenze)), stand: stand, verstoesse: [],
                              trades: m.angeglicheneTrades, waehrung: "EUR")
                .first { $0.id == "tagesverlust" }?.stufe
        }
        #expect(stufe("100") == .rot)
        #expect(stufe("120") == .gelb)
        #expect(stufe("200") == .gruen)
    }

    /// Ampel Trades je Tag am Eröffnungstag: ein Trade bei Grenze 1 ist gelb, bei 2 grün; nur gesetzte Regeln leuchten.
    @Test func ampelTradesJeTagAmEroeffnungstag() throws {
        let m = try mitDepot()
        let staende = Regelpruefung.tagesstaende(m.angeglicheneTrades, regeln: Handelsregeln(maxTradesJeTag: 1),
                                                 zeitzone: m.zeitzone)
        let eroeffnung = try #require(staende.first)
        #expect(eroeffnung.trades == 1)
        func lampen(_ grenze: Int) -> [Ampellampe] {
            Ampellampe.lampen(regeln: Handelsregeln(maxTradesJeTag: grenze), stand: eroeffnung, verstoesse: [],
                              trades: m.angeglicheneTrades, waehrung: "EUR")
        }
        #expect(lampen(1).map(\.id) == ["tradesJeTag"])
        #expect(lampen(1).first?.stufe == .gelb)
        #expect(lampen(2).first?.stufe == .gruen)
    }

    // MARK: Playbook und Checkliste

    @Test func setupKarteUndZaehlungUeberJournal() throws {
        let m = try mitDepot()
        let trade = try #require(m.trades.first)
        let karte = try m.speichereSetup(Setup(name: "Ausbruch", kriterien: [Kriterium(id: "k1", text: "Trend")]))
        #expect(karte.id != nil)
        #expect(m.setupKarte("Ausbruch")?.kriterien.map(\.id) == ["k1"])
        #expect(m.setupKarte(nil) == nil)
        #expect(m.anzahlTrades(setup: "Ausbruch") == 0)

        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.setup = "Ausbruch"
        m.speichereJournal(eintrag)
        #expect(m.anzahlTrades(setup: "Ausbruch") == 1)
        #expect(m.bekannteSetups == ["Ausbruch"])
    }

    /// Umbenennen einer Karte zieht den Setup-Namen im Journal mit; doppelte Namen lehnt die Speicherung ab.
    @Test func setupUmbenennenZiehtJournalMit() throws {
        let m = try mitDepot()
        let trade = try #require(m.trades.first)
        var karte = try m.speichereSetup(Setup(name: "Ausbruch"))
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.setup = "Ausbruch"
        m.speichereJournal(eintrag)

        karte.name = "Rücklauf"
        try m.speichereSetup(karte)
        #expect(m.journaleintraege[trade.id]?.setup == "Rücklauf")
        #expect(m.anzahlTrades(setup: "Rücklauf") == 1)
        #expect(m.setupKarte("Ausbruch") == nil)
        #expect(throws: SpeicherFehler.self) { try m.speichereSetup(Setup(name: "Rücklauf")) }
        #expect(m.playbook.count == 1)
    }

    /// Die Checkliste schreibt das Setup ins Journal und speichert die Häkchen je Trade.
    @Test func checklisteSetztSetupUndHaekchen() throws {
        let m = try mitDepot()
        let trade = try #require(m.trades.first)
        try m.speichereSetup(Setup(name: "Ausbruch", kriterien: [Kriterium(id: "k1", text: "Trend"),
                                                                 Kriterium(id: "k2", text: "Volumen")]))
        m.setzeCheckliste(Checkliste(setup: "Ausbruch", erfuellt: ["k1"]), trade: trade)
        #expect(m.checklisten[trade.id]?.erfuellt == ["k1"])
        #expect(m.journaleintraege[trade.id]?.setup == "Ausbruch")
        #expect(m.anzahlTrades(setup: "Ausbruch") == 1)
        #expect(m.fehler == nil)
    }

    // MARK: Steuer-Angaben und offene Positionen

    @Test func steuerangabenJeBroker() throws {
        let depot = try mitDepot()
        #expect(depot.brokerFuehrtSteuerAb == true)
        #expect(depot.steuerjahre == [2026])
        #expect(depot.hatKrypto == false)
        #expect(depot.fremdwaehrungen.isEmpty)

        let kraken = try modell()
        #expect(kraken.brokerFuehrtSteuerAb == nil)
        _ = try kraken.importiereCSV(daten: Data(T.kraken().utf8), dateiname: "appt-kraken.csv", kontonummer: "KR-00001111",
                                     kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        #expect(kraken.brokerFuehrtSteuerAb == false)
        #expect(kraken.hatKrypto)
        #expect(kraken.fremdwaehrungen == ["USD"])
        #expect(kraken.steuerjahre == [2026])
    }

    /// Ein Kauf ohne Verkauf ist eine offene Position: Einstieg aus Betrag durch Menge, Währung der Ausführung.
    @Test func offenerKaufIstOffenePosition() throws {
        let m = try modell()
        let nurKauf = T.kraken().split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("\"sell\"") }.joined(separator: "\n")
        _ = try m.importiereCSV(daten: Data(nurKauf.utf8), dateiname: "appt-kraken-kauf.csv", kontonummer: "KR-00002222",
                                kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.trades.isEmpty)
        let position = try #require(m.offenePositionen.first)
        #expect(m.offenePositionen.count == 1)
        #expect(position.seite == .buy)
        #expect(position.menge == T.d("0.5"))
        #expect(position.einstieg == T.d("3000"))
        #expect(position.waehrung == "USD")
        #expect(position.auszugskurs == nil)
        #expect(position.ergebnisLautAuszug == nil)
    }
}
