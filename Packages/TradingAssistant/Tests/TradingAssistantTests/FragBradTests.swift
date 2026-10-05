import Foundation
import Testing
@testable import TradingAssistant

let berlin = TimeZone(identifier: "Europe/Berlin")!

/// Datum aus „JJJJ-MM-TT hh:mm“ in Berliner Zeit.
func zeit(_ text: String) -> Date {
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = berlin
    let z = text.split(whereSeparator: { "- :".contains($0) }).map { Int($0)! }
    return kalender.date(from: DateComponents(year: z[0], month: z[1], day: z[2], hour: z[3], minute: z[4]))!
}

let september = FragBradKontext(konto: "XTB …1234", von: zeit("2026-09-01 00:00"), bis: zeit("2026-09-30 00:00"))

@Test func monatMitZeitraumUndKonto() throws {
    let text = try #require(FragBrad.text(.monat, kontext: september, ton: .sachlich, zeitzone: berlin))
    #expect(text == """
        Werte den genannten Zeitraum nach deinem Rezept für die Monatsauswertung aus.

        Konto: XTB …1234. Zeitraum: 2026-09-01 bis 2026-09-30.

        \(FragBrad.rahmen)
        """)
}

@Test func ohneZeitraumNimmtDerConnectorDenLetztenMonat() throws {
    let text = try #require(FragBrad.text(.monat, kontext: FragBradKontext(), ton: .sachlich, zeitzone: berlin))
    #expect(text.hasPrefix("Werte den letzten Monat mit Trades"))
    #expect(!text.contains("Konto:"))
    #expect(!text.contains("Zeitraum:"))
}

@Test func tonHenryHaengtDieTonbitteAn() throws {
    let henry = try #require(FragBrad.text(.setups, kontext: september, ton: .henry, zeitzone: berlin))
    let sachlich = try #require(FragBrad.text(.setups, kontext: september, ton: .sachlich, zeitzone: berlin))
    #expect(henry.hasSuffix(FragBrad.tonHenry))
    #expect(!henry.contains("Alter") && !henry.contains("Bro"))
    // Der Rahmen nennt die „Henry-Werkzeuge“ (Doc 59, B10); die Tonbitte fehlt bei „Sachlich“.
    #expect(!sachlich.contains(FragBrad.tonHenry))
    #expect(!sachlich.contains("Ton von Henry"))
}

@Test func jedeFrageTraegtDenRahmenOhneAnlageberatung() {
    let trade = FragBradTrade(symbol: "EURUSD", eroeffnet: zeit("2026-09-12 14:32"),
                              geschlossen: zeit("2026-09-12 15:05"), nurDatum: false)
    var kontext = september
    kontext.trade = trade
    kontext.tag = zeit("2026-09-12 12:00")
    kontext.symbol = "BTCUSD"
    for vorlage in FragBradVorlage.allCases {
        for ton in FragBradTon.allCases {
            let text = FragBrad.text(vorlage, kontext: kontext, freieFrage: "Was lief gut?", ton: ton, zeitzone: berlin)
            #expect(text?.contains("ohne Kauf- oder Verkaufsempfehlungen und ohne Kursziele") == true, "\(vorlage)")
            #expect(text?.contains("Connectors Trading Buddy") == true, "\(vorlage)")
        }
    }
}

@Test func tradeMitUhrzeitUndTagAlsZeitraum() throws {
    var kontext = september
    kontext.instrument = "DAX"
    kontext.trade = FragBradTrade(symbol: "EURUSD", eroeffnet: zeit("2026-09-11 22:40"),
                                  geschlossen: zeit("2026-09-12 09:05"), nurDatum: false)
    let text = try #require(FragBrad.text(.trade, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(text.hasPrefix("Ordne meinen Trade EURUSD ein, eröffnet 11.09.2026 um 22:40, geschlossen 12.09.2026 um 09:05:"))
    // Der Connector ordnet Trades nach Schlusstag; der Monatsfilter und das Instrument gelten hier nicht.
    #expect(text.contains("Zeitraum: 2026-09-12 bis 2026-09-12."))
    #expect(!text.contains("2026-09-01"))
    #expect(!text.contains("DAX"))
}

@Test func tradeNurMitDatumNenntKeineUhrzeit() throws {
    var kontext = FragBradKontext(konto: "Trade Republic …9876")
    kontext.trade = FragBradTrade(symbol: "SAP", eroeffnet: zeit("2026-03-02 00:00"),
                                  geschlossen: zeit("2026-03-05 00:00"), nurDatum: true)
    let text = try #require(FragBrad.text(.trade, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(text.contains("geschlossen am 05.03.2026, ohne Uhrzeit (nur Datum)"))
    #expect(!text.contains("00:00"))
}

@Test func tradeVorlageOhneTradeLiefertNichts() {
    #expect(FragBrad.text(.trade, kontext: september, ton: .henry, zeitzone: berlin) == nil)
}

@Test func wocheUebergehtDenMonatsfilter() throws {
    let text = try #require(FragBrad.text(.woche, kontext: september, ton: .sachlich, zeitzone: berlin))
    #expect(!text.contains("Zeitraum:"))
    #expect(text.contains("Konto: XTB …1234."))
}

@Test func eigeneFrageWirdBereinigtUndBegrenzt() throws {
    #expect(FragBrad.text(.frei, kontext: september, freieFrage: "  \n ", ton: .henry, zeitzone: berlin) == nil)
    let lang = String(repeating: "a", count: 5_000)
    let text = try #require(FragBrad.text(.frei, kontext: september, freieFrage: lang, ton: .henry, zeitzone: berlin))
    #expect(text.hasPrefix(String(repeating: "a", count: FragBrad.freitextGrenze) + "\n\n"))
    #expect(text.count < 2_500)
}

@Test func linkKodiertSonderzeichenUndKommtUnveraendertZurueck() throws {
    let text = "Läuft's? 50 % & mehr + #1 / Größe?\n\nZeile „zwei“ …1234"
    let link = try #require(FragBrad.link(text))
    #expect(link.scheme == "claude")
    #expect(link.host == "claude.ai")
    #expect(link.path == "/new")
    let roh = link.absoluteString
    #expect(!roh.contains(" "))
    #expect(!roh.contains("&mehr") && !roh.contains("+") && !roh.contains("#"))
    let teile = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false))
    #expect(teile.queryItems?.count == 1)
    #expect(teile.queryItems?.first?.name == "q")
    #expect(teile.queryItems?.first?.value == text)
}

@Test func laengsterLinkBleibtUnterDerKuerzungsgrenze() throws {
    var kontext = september
    kontext.instrument = "EURUSD"
    let frage = String(repeating: "ä", count: 5_000)
    let text = try #require(FragBrad.text(.frei, kontext: kontext, freieFrage: frage, ton: .henry, zeitzone: berlin))
    // Anthropic kürzt den Text bei rund 14.000 Zeichen (Hilfe-Artikel, 30.06.2026).
    #expect(text.count < 14_000)
    #expect(FragBrad.link(text) != nil)
}

@Test func tagVorlageNenntDenTagAlsZeitraum() throws {
    var kontext = september
    kontext.tag = zeit("2026-09-17 15:00")
    let text = try #require(FragBrad.text(.tag, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(text.hasPrefix("Ordne meinen Handelstag am 17.09.2026 ein:"))
    #expect(text.contains("Zeitraum: 2026-09-17 bis 2026-09-17."))
    #expect(!text.contains("2026-09-01"))
    #expect(FragBrad.text(.tag, kontext: september, ton: .sachlich, zeitzone: berlin) == nil)
}

@Test func verfuegbareVorlagenJeEinstieg() {
    #expect(!FragBradVorlage.verfuegbar(mitTrade: false, mitTag: false).contains(.trade))
    #expect(!FragBradVorlage.verfuegbar(mitTrade: false, mitTag: false).contains(.tag))
    #expect(FragBradVorlage.verfuegbar(mitTrade: true, mitTag: false).contains(.trade))
    #expect(FragBradVorlage.verfuegbar(mitTrade: false, mitTag: true).contains(.tag))
    #expect(!FragBradVorlage.verfuegbar(mitTrade: true, mitTag: true).contains(.analyse))
    #expect(FragBradVorlage.verfuegbar(mitTrade: false, mitTag: false, mitSymbol: true).contains(.analyse))
    #expect(FragBradVorlage.verfuegbar(mitTrade: true, mitTag: true, mitSymbol: true).count
        == FragBradVorlage.allCases.count)
}

@Test func analyseNenntNurSymbolUndZwoelfMonate() throws {
    var kontext = september
    kontext.instrument = "DAX"
    kontext.symbol = " BTCUSD "
    let text = try #require(FragBrad.text(.analyse, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(text == """
        Beschreibe den Wert BTCUSD über die letzten 12 Monate: Kursverlauf, Schwankung, Abstand zu Hoch und Tief, \
        größter Rückgang, Nachrichten der letzten 7 Tage und meine eigenen Trades in diesem Wert. Nutze dafür \
        hole_kursanalyse und hole_nachrichten. Nur beschreiben, keine Prognose.

        Konto: XTB …1234.

        \(FragBrad.rahmen)
        """)
    // Monatsfilter und Instrument der Seite gelten für die Analyse nicht.
    #expect(!text.contains("Zeitraum:") && !text.contains("DAX"))
}

@Test func analyseOhneKursverlaufFragtNurNachNachrichtenUndTrades() throws {
    var kontext = FragBradKontext(symbol: "SAP", mitKursverlauf: false)
    kontext.konto = nil
    let text = try #require(FragBrad.text(.analyse, kontext: kontext, ton: .henry, zeitzone: berlin))
    #expect(text.hasPrefix("Beschreibe den Wert SAP über die letzten 12 Monate: Nachrichten der letzten 7 Tage"))
    #expect(!text.contains("Schwankung") && !text.contains("Hoch und Tief"))
    #expect(text.contains("Nur beschreiben, keine Prognose."))
    #expect(text.hasSuffix(FragBrad.tonHenry))
}

@Test func analyseOhneSymbolLiefertNichts() {
    #expect(FragBrad.text(.analyse, kontext: september, ton: .henry, zeitzone: berlin) == nil)
    let leer = FragBradKontext(symbol: "  ")
    #expect(FragBrad.text(.analyse, kontext: leer, ton: .henry, zeitzone: berlin) == nil)
}

@Test func nurDieAnalyseKopiertMitUndNenntInkognito() {
    #expect(FragBradVorlage.allCases.filter(\.kopiertMit) == [.analyse])
    for ton in FragBradTon.allCases {
        #expect(FragBrad.inkognitoHinweis(ton).contains("Inkognito einschalten"))
        #expect(FragBrad.inkognitoHinweis(ton).hasSuffix("Die Frage liegt zusätzlich in der Zwischenablage."))
    }
    #expect(FragBrad.inkognitoHinweis(.henry).hasPrefix("Solche Gespräche bleiben besser unter uns."))
}

@Test func emojiAusVielenCodepunktenSprengenDieGrenzeNicht() throws {
    // Familie aus vier Personen: ein Zeichen, elf UTF-16-Einheiten. Nach Zeichen gekürzt wären es 16.500 Einheiten,
    // dann schnitte Claude bei rund 14.000 den Rahmen ohne Anlageberatung ab (Gesamt-Gegencheck F2).
    let familie = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
    #expect(familie.count == 1 && familie.utf16.count == 11)
    let frage = String(repeating: familie, count: 3_000)
    let gekuerzt = FragBrad.bereinigt(frage)
    #expect(gekuerzt.utf16.count <= FragBrad.freitextGrenze)
    #expect(gekuerzt.utf16.count > FragBrad.freitextGrenze - 11)
    #expect(gekuerzt.allSatisfy { $0 == Character(familie) })
    let text = try #require(FragBrad.text(.frei, kontext: september, freieFrage: frage, ton: .henry, zeitzone: berlin))
    #expect(text.utf16.count < 2_500)
    #expect(text.hasSuffix(FragBrad.tonHenry))
}

// MARK: Doc 59 (05.10.2026): B5 Ticket, B7 Kalenderwoche, B10 Rahmen

@Test func tradeFrageNenntTicketFuerHoleTrades() throws {
    var kontext = september
    kontext.trade = FragBradTrade(symbol: "EURUSD", eroeffnet: zeit("2026-09-12 14:32"),
                                  geschlossen: zeit("2026-09-12 15:05"), nurDatum: false, ticket: "48151623")
    let text = try #require(FragBrad.text(.trade, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(text.hasPrefix("Ordne meinen Trade EURUSD (Ticket 48151623) ein, eröffnet 12.09.2026 um 14:32"))
    #expect(text.contains("Zeitraum: 2026-09-12 bis 2026-09-12. Ticket: 48151623; hole_trades mit ticket=48151623."))
    // Ohne Ticket wie bisher.
    kontext.trade?.ticket = nil
    let ohne = try #require(FragBrad.text(.trade, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(!ohne.contains("Ticket"))
}

@Test func wocheNenntDieKalenderwocheFuerHoleAuswertung() throws {
    let text = try #require(FragBrad.text(.woche, kontext: september, ton: .sachlich, zeitzone: berlin,
                                          heute: zeit("2026-10-05 12:00")))
    #expect(text.hasPrefix("Werte die letzte abgeschlossene Kalenderwoche (KW 40/2026)"))
    #expect(text.contains("hole_auswertung mit kw=2026-W40"))
    #expect(!text.contains("Zeitraum:"))
}

@Test func kalenderwocheUeberDenJahreswechsel() {
    // 05.01.2027: Vorwoche ist KW 53 des Jahres 2026 (ISO 8601, Woche gehört zum Jahr ihres Donnerstags).
    let kw = FragBrad.letzteKalenderwoche(heute: zeit("2027-01-05 09:00"), zeitzone: berlin)
    #expect(kw.jahr == 2026)
    #expect(kw.woche == 53)
}

@Test func rahmenNenntDieDatenDerHenryWerkzeuge() {
    #expect(FragBrad.rahmen.contains("nur aus den Daten der Henry-Werkzeuge"))
    #expect(!FragBrad.rahmen.contains("Journaldaten"))
}

@Test func tradeUndTagFragenEnthaltenReviewMitGrenze() throws {
    var kontext = september
    kontext.trade = FragBradTrade(symbol: "EURUSD", eroeffnet: zeit("2026-09-11 22:40"),
                                  geschlossen: zeit("2026-09-12 09:05"), nurDatum: false)
    kontext.tag = zeit("2026-09-17 15:00")
    let trade = try #require(FragBrad.text(.trade, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    let tag = try #require(FragBrad.text(.tag, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(trade.contains("Welches Fehlermuster zeigt der Trade, und woran sieht man das?"))
    #expect(trade.contains("beim nächsten ähnlichen Setup"))
    #expect(tag.contains("Welche Fehlermuster zeigt der Tag, und woran sieht man das?"))
    #expect(tag.contains("am nächsten Handelstag"))
    for text in [trade, tag] {
        #expect(text.contains("meinen Regeln, meinem Playbook, Plan und Stop und meinem Journal"))
        #expect(text.contains("keine Kauf- oder Verkaufsempfehlung, kein Kursziel, keine Marktprognose"))
    }
    // Andere Vorlagen bleiben ohne Review
    let monat = try #require(FragBrad.text(.monat, kontext: kontext, ton: .sachlich, zeitzone: berlin))
    #expect(!monat.contains("Review"))
}
