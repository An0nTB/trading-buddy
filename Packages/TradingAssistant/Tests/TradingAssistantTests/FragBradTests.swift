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

@Test func tonBradHaengtDieTonbitteAn() throws {
    let brad = try #require(FragBrad.text(.setups, kontext: september, ton: .brad, zeitzone: berlin))
    let sachlich = try #require(FragBrad.text(.setups, kontext: september, ton: .sachlich, zeitzone: berlin))
    #expect(brad.hasSuffix(FragBrad.tonBrad))
    #expect(!sachlich.contains("Brad"))
}

@Test func jedeFrageTraegtDenRahmenOhneAnlageberatung() {
    let trade = FragBradTrade(symbol: "EURUSD", eroeffnet: zeit("2026-09-12 14:32"),
                              geschlossen: zeit("2026-09-12 15:05"), nurDatum: false)
    var kontext = september
    kontext.trade = trade
    kontext.tag = zeit("2026-09-12 12:00")
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
    #expect(FragBrad.text(.trade, kontext: september, ton: .brad, zeitzone: berlin) == nil)
}

@Test func wocheUebergehtDenMonatsfilter() throws {
    let text = try #require(FragBrad.text(.woche, kontext: september, ton: .sachlich, zeitzone: berlin))
    #expect(!text.contains("Zeitraum:"))
    #expect(text.contains("Konto: XTB …1234."))
}

@Test func eigeneFrageWirdBereinigtUndBegrenzt() throws {
    #expect(FragBrad.text(.frei, kontext: september, freieFrage: "  \n ", ton: .brad, zeitzone: berlin) == nil)
    let lang = String(repeating: "a", count: 5_000)
    let text = try #require(FragBrad.text(.frei, kontext: september, freieFrage: lang, ton: .brad, zeitzone: berlin))
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
    let text = try #require(FragBrad.text(.frei, kontext: kontext, freieFrage: frage, ton: .brad, zeitzone: berlin))
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
    #expect(FragBradVorlage.verfuegbar(mitTrade: true, mitTag: true).count == FragBradVorlage.allCases.count)
}
