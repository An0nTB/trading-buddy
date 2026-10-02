import Foundation
import Testing
@testable import TradingCore

/// Umrechnung mit Tageskursen (Doc 22, Lücke USD/USDT). Kurse erfunden, EZB-Notation (USD je 1 Euro);
/// Sollwerte von Hand (02.10.2026).
private func kursDez(_ text: String) -> Decimal { Decimal(string: text)! }

private func kursZeit(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private let beispielKurse = Referenzkurse(kurse: [
    Journaltag("2026-03-02")!: ["usd": kursDez("1.6")],
    Journaltag("2026-03-06")!: ["USD": kursDez("1.25"), "CHF": 0],
    Journaltag("2026-03-09")!: ["USD": 1],
])

@Test func referenzkurseLetzterKursAmOderVorDemTag() {
    let k = beispielKurse
    // Samstag: Kurs vom Freitag.
    #expect(k.inEuro(125, waehrung: "USD", am: kursZeit("2026-03-07T12:00:00Z")) == 100)
    #expect(k.inEuro(10, waehrung: "usdt", am: kursZeit("2026-03-09T10:00:00Z")) == 10)
    #expect(k.inEuro(50, waehrung: "EUR", am: kursZeit("2020-01-01T00:00:00Z")) == 50)
    // 23:30 UTC ist in Berlin schon Montag, in UTC noch Sonntag.
    #expect(k.inEuro(10, waehrung: "USD", am: kursZeit("2026-03-08T23:30:00Z")) == 10)
    #expect(k.inEuro(10, waehrung: "USD", am: kursZeit("2026-03-08T23:30:00Z"), zeitzone: TimeZone(secondsFromGMT: 0)!) == 8)
    // Mehr als sieben Tage ohne Kurs, unbekannte Währung, Kurs 0.
    #expect(k.inEuro(10, waehrung: "USD", am: kursZeit("2026-03-20T10:00:00Z")) == nil)
    #expect(k.inEuro(10, waehrung: "GBP", am: kursZeit("2026-03-09T10:00:00Z")) == nil)
    #expect(k.inEuro(10, waehrung: "CHF", am: kursZeit("2026-03-06T10:00:00Z")) == nil)
}

@Test func toepfeMitKursenInUSDKonto() throws {
    func t(_ id: String, _ schluss: String, _ profit: Decimal) -> Trade {
        Trade(id: id, symbol: id, side: .buy, lots: 1, openTime: kursZeit(schluss), closeTime: kursZeit(schluss),
              openPrice: 1, closePrice: 1, profit: profit, produktart: .cfd)
    }
    let trades = [t("C1", "2026-03-06T10:00:00Z", 125), t("C2", "2026-03-09T10:00:00Z", -20),
                  t("C3", "2026-03-25T10:00:00Z", 50)]
    let summen = Steuerorientierung.toepfe(trades, kontowaehrung: "USD", jahr: 2026, kurse: beispielKurse)
    let s = try #require(summen.first)
    #expect(summen.count == 1 && s.topf == .allgemein)
    #expect(s.gewinne == 100 && s.verluste == -20 && s.davonCFD == 80)
    #expect(s.anzahl == 3 && s.ohneEuro == 1)
    // Ohne Kurse wie bisher: nichts summiert.
    #expect(Steuerorientierung.toepfe(trades, kontowaehrung: "USD", jahr: 2026).first?.ohneEuro == 3)
}

@Test func kryptoHaltefristMitKursen() throws {
    func a(_ id: String, _ seite: Side, _ zeit: String, _ betrag: String, _ gebuehr: String) -> Ausfuehrung {
        Ausfuehrung(id: id, zeit: kursZeit(zeit), kennung: "BTC/USD", name: "BTC", seite: seite, menge: 1,
                    preis: 1, betrag: kursDez(betrag), gebuehr: kursDez(gebuehr), waehrung: "USD",
                    produktart: .krypto)
    }
    let ausfuehrungen = [a("K", .buy, "2026-03-02T10:00:00Z", "-160", "-0.32"),
                         a("V", .sell, "2026-03-06T10:00:00Z", "250", "-2.5")]
    let j = KryptoHaltefrist.jahr(2026, ausfuehrungen: ausfuehrungen, kurse: beispielKurse)
    let los = try #require(j.lose.first)
    // Einstand 160,32 / 1,6 = 100,2; Erlös 247,5 / 1,25 = 198.
    #expect(los.einstand == kursDez("100.2") && los.erloes == 198)
    #expect(j.steuerpflichtig == kursDez("97.8") && j.ohneEuro == 0)
    #expect(KryptoHaltefrist.jahr(2026, ausfuehrungen: ausfuehrungen).ohneEuro == 1)
}
