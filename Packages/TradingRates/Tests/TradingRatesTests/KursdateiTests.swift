import Foundation
import Testing
import TradingCore
@testable import TradingRates

@Test func tagesdateiWirdGelesen() throws {
    let kurse = try EZBKursdatei.lies(try fixture("ezb-daily"))
    #expect(kurse.count == 1)
    let tageskurse = try #require(kurse[tag("2026-10-01")])
    #expect(tageskurse.count == 4)
    #expect(tageskurse["USD"] == Decimal(string: "1.2", locale: Locale(identifier: "en_US_POSIX")))
    #expect(tageskurse["GBP"] == Decimal(string: "0.875", locale: Locale(identifier: "en_US_POSIX")))
}

@Test func verlaufMitMehrerenTagen() throws {
    let kurse = try EZBKursdatei.lies(try fixture("ezb-hist"))
    #expect(Set(kurse.keys) == [tag("2026-09-25"), tag("2026-09-28"), tag("2026-09-29")])
    #expect(kurse[tag("2026-09-28")]?["JPY"] == Decimal(string: "169.8", locale: Locale(identifier: "en_US_POSIX")))
    // „1,5“ ist keine EZB-Zahl und fällt weg, der Rest des Tages bleibt.
    #expect(kurse[tag("2026-09-25")]?["XXX"] == nil)
    #expect(kurse[tag("2026-09-25")]?.count == 3)
}

@Test func htmlStattXMLIstEinFehler() {
    let html = Data("<html><body>Wartung</body></html>".utf8)
    #expect(throws: EZBKursdatei.Fehler.keineKurse) { try EZBKursdatei.lies(html) }
    #expect(throws: EZBKursdatei.Fehler.keineKurse) { try EZBKursdatei.lies(Data()) }
}

@Test func abgebrocheneDateiIstEinFehler() throws {
    // Verbindung bricht mitten im Verlauf ab: die ersten Tage wären lesbar, gelten aber nicht.
    let ganz = try fixture("ezb-hist")
    let halb = ganz.prefix(ganz.count * 2 / 3)
    #expect(throws: EZBKursdatei.Fehler.unvollstaendig) { try EZBKursdatei.lies(Data(halb)) }
}

@Test func schlussTagDerWurzel() {
    #expect(EZBKursdatei.endetMitSchlussTag(Data("<a><b/></a>\n  ".utf8), wurzel: "a"))
    #expect(EZBKursdatei.endetMitSchlussTag(Data("<g:E><b/></g:E>".utf8), wurzel: "g:E"))
    #expect(!EZBKursdatei.endetMitSchlussTag(Data("<a><b/>".utf8), wurzel: "a"))
    #expect(!EZBKursdatei.endetMitSchlussTag(Data("<a></a>".utf8), wurzel: nil))
}

@Test func zahlenNurMitPunkt() {
    #expect(EZBKursdatei.zahl("1.1708") == Decimal(string: "1.1708", locale: Locale(identifier: "en_US_POSIX")))
    #expect(EZBKursdatei.zahl("1,1708") == nil)
    #expect(EZBKursdatei.zahl("0") == nil)
    #expect(EZBKursdatei.zahl("") == nil)
    #expect(EZBKursdatei.zahl("-1.2") == nil)
}

// MARK: Umrechnung mit den gelesenen Kursen (Referenzkurse aus TradingCore)

@Test func wochenendeNimmtFreitag() throws {
    let kurse = Referenzkurse(kurse: try EZBKursdatei.lies(try fixture("ezb-hist")))
    // Samstag und Sonntag ohne Kurs: Freitag 1,17 USD je Euro.
    #expect(kurse.inEuro(117, waehrung: "USD", am: zeit("2026-09-26 12:00"), zeitzone: berlin) == 100)
    #expect(kurse.inEuro(117, waehrung: "USD", am: zeit("2026-09-27 23:30"), zeitzone: berlin) == 100)
    // Montag hat einen eigenen Kurs.
    #expect(kurse.inEuro(117.5, waehrung: "USD", am: zeit("2026-09-28 09:00"), zeitzone: berlin) == 100)
}

@Test func siebenTageGrenze() throws {
    let kurse = Referenzkurse(kurse: try EZBKursdatei.lies(try fixture("ezb-hist")))
    // Letzter Kurs Dienstag 29.09.: sieben Tage später noch gültig, acht Tage später nicht.
    #expect(kurse.inEuro(118, waehrung: "USD", am: zeit("2026-10-06 12:00"), zeitzone: berlin) == 100)
    #expect(kurse.inEuro(118, waehrung: "USD", am: zeit("2026-10-07 12:00"), zeitzone: berlin) == nil)
}

@Test func usdtWieUSD() throws {
    let kurse = Referenzkurse(kurse: try EZBKursdatei.lies(try fixture("ezb-hist")))
    #expect(kurse.inEuro(118, waehrung: "USDT", am: zeit("2026-09-29 15:00"), zeitzone: berlin) == 100)
    #expect(kurse.inEuro(118, waehrung: "usdt", am: zeit("2026-09-29 15:00"), zeitzone: berlin) == 100)
    #expect(EZBKurse.istNaeherung("USDT"))
    #expect(!EZBKurse.istNaeherung("USD"))
}

@Test func unbekannteWaehrungErgibtNil() throws {
    let kurse = Referenzkurse(kurse: try EZBKursdatei.lies(try fixture("ezb-hist")))
    #expect(kurse.inEuro(100, waehrung: "XYZ", am: zeit("2026-09-29 15:00"), zeitzone: berlin) == nil)
    // USDC setzt der Kern nicht gleich; bleibt Lücke.
    #expect(kurse.inEuro(100, waehrung: "USDC", am: zeit("2026-09-29 15:00"), zeitzone: berlin) == nil)
    #expect(kurse.inEuro(100, waehrung: "EUR", am: zeit("2026-09-29 15:00"), zeitzone: berlin) == 100)
}
