import Foundation
import Testing
@testable import TradingCore

/// Steuer-Orientierung (P3, Doc 22) mit erfundenen Werten; Sollwerte von Hand und in Python gerechnet (02.10.2026).
private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

private func trade(_ id: String, _ art: Produktart, _ schluss: String, profit: String, kommission: String = "0",
                   swap: String = "0", steuer: String = "0") -> Trade {
    Trade(id: id, symbol: id, side: .buy, lots: 1, openTime: utc(schluss), closeTime: utc(schluss), openPrice: 1,
          closePrice: 1, commission: dez(kommission), swap: dez(swap), profit: dez(profit), taxes: dez(steuer),
          produktart: art)
}

private func krypto(_ id: String, _ coin: String, _ gegen: String, _ seite: Side, _ zeit: String, menge: String,
                    betrag: String, gebuehr: String, art: Produktart = .krypto) -> Ausfuehrung {
    Ausfuehrung(id: id, zeit: utc(zeit), kennung: "\(coin)/\(gegen)", name: coin, seite: seite, menge: dez(menge),
                preis: 1, betrag: dez(betrag), gebuehr: dez(gebuehr), waehrung: gegen, produktart: art)
}

@Test func verlusttopfJeProduktart() {
    let toepfe: [Verlusttopf] = Produktart.allCases.map { Verlusttopf($0) }
    #expect(toepfe == [.aktien, .allgemein, .allgemein, .allgemein, .allgemein, .krypto, .nichtZugeordnet,
                       .nichtZugeordnet])
}

@Test func toepfeNachJahrInDeutscherZeit() {
    let trades = [
        trade("A1", .aktie, "2026-05-01T10:00:00Z", profit: "500", kommission: "-5"),
        trade("A2", .aktie, "2026-06-01T10:00:00Z", profit: "-200", kommission: "-5", steuer: "-10"),
        trade("C1", .cfd, "2026-03-01T10:00:00Z", profit: "100", kommission: "-2", swap: "-3"),
        trade("C2", .cfd, "2026-04-01T10:00:00Z", profit: "-50"),
        trade("F1", .fonds, "2026-07-01T10:00:00Z", profit: "30"),
        trade("U1", .unbekannt, "2026-08-01T10:00:00Z", profit: "10"),
        // 23:30 UTC am 31.12.2025 ist in Berlin schon 2026, 22:30 UTC noch 2025.
        trade("A3", .aktie, "2025-12-31T23:30:00Z", profit: "1"),
        trade("A4", .aktie, "2025-12-31T22:30:00Z", profit: "1000"),
    ]
    let summen = Steuerorientierung.toepfe(trades, kontowaehrung: "EUR", jahr: 2026)
    let reihenfolge: [Verlusttopf] = summen.map(\.topf)
    #expect(reihenfolge == [.aktien, .allgemein, .nichtZugeordnet])
    let aktien = summen[0]
    #expect(aktien.gewinne == dez("496"))
    #expect(aktien.verluste == dez("-205"))
    #expect(aktien.saldo == dez("291"))
    #expect(aktien.anzahl == 3)
    let allgemein = summen[1]
    #expect(allgemein.gewinne == dez("125"))
    #expect(allgemein.verluste == dez("-50"))
    #expect(allgemein.davonCFD == dez("45"))
    #expect(allgemein.anzahl == 3)
    #expect(summen[2].gewinne == 10)
    let vorjahr = Steuerorientierung.toepfe(trades, kontowaehrung: "EUR", jahr: 2025)
    #expect(vorjahr.map(\.anzahl) == [1])
}

@Test func toepfeOhneEuroZaehlenNurMit() {
    let trades = [trade("C1", .cfd, "2026-03-01T10:00:00Z", profit: "100")]
    let summen = Steuerorientierung.toepfe(trades, kontowaehrung: "usd", jahr: 2026)
    #expect(summen.count == 1)
    #expect(summen[0].ohneEuro == 1)
    #expect(summen[0].saldo == 0)
}

@Test func steuerfreiAbNachJahrestag() {
    // Kauf 01.03.2025 11:00 Berlin: steuerfrei ab 02.03.2026 00:00 Berlin = 01.03.2026 23:00 UTC.
    #expect(KryptoHaltefrist.steuerfreiAb(utc("2025-03-01T10:00:00Z")) == utc("2026-03-01T23:00:00Z"))
    // Schaltjahr: Kauf 29.02.2024, Jahrestag 28.02.2025, steuerfrei ab 01.03.2025 00:00 Berlin.
    #expect(KryptoHaltefrist.steuerfreiAb(utc("2024-02-29T12:00:00Z")) == utc("2025-02-28T23:00:00Z"))
    // Sommerzeit: Kauf 10.07.2025, steuerfrei ab 11.07.2026 00:00 Berlin = 10.07.2026 22:00 UTC.
    #expect(KryptoHaltefrist.steuerfreiAb(utc("2025-07-10T08:00:00Z")) == utc("2026-07-10T22:00:00Z"))
}

private let kryptoKonto = [
    krypto("K1", "BTC", "EUR", .buy, "2025-03-01T10:00:00Z", menge: "0.02", betrag: "-1000", gebuehr: "-2"),
    krypto("K2", "BTC", "USDT", .buy, "2025-11-15T10:00:00Z", menge: "0.01", betrag: "-800", gebuehr: "-1"),
    krypto("K3", "ETH", "EUR", .buy, "2026-01-10T10:00:00Z", menge: "1", betrag: "-3000", gebuehr: "-3"),
    krypto("X1", "SAP", "EUR", .buy, "2026-01-11T10:00:00Z", menge: "5", betrag: "-900", gebuehr: "-1", art: .aktie),
    // 01.03.2026 Berlin: noch in der Frist.
    krypto("V1", "BTC", "EUR", .sell, "2026-03-01T10:00:00Z", menge: "0.015", betrag: "1500", gebuehr: "-1.5"),
    // 23:30 UTC ist in Berlin schon der 02.03.2026: Rest von K1 steuerfrei, Teil aus K2 nicht.
    krypto("V2", "BTC", "EUR", .sell, "2026-03-01T23:30:00Z", menge: "0.01", betrag: "1100", gebuehr: "-1.1"),
    krypto("V3", "ETH", "EUR", .sell, "2026-06-01T10:00:00Z", menge: "0.5", betrag: "1400", gebuehr: "-1.4"),
    krypto("V4", "SOL", "EUR", .sell, "2026-07-01T10:00:00Z", menge: "3", betrag: "300", gebuehr: "0"),
]

@Test func kryptoHaltefristUndFreigrenze() throws {
    let hinweis = Importhinweis(zeile: 5, vorgang: "ETHBTC BUY", folge: .nichtVerbucht)
    let j = KryptoHaltefrist.jahr(2026, ausfuehrungen: kryptoKonto, importhinweise: [hinweis])
    let coins: [String] = j.lose.map(\.coin)
    #expect(coins == ["BTC", "BTC", "BTC", "ETH"])
    let mengen: [Decimal] = j.lose.map(\.menge)
    #expect(mengen == [dez("0.015"), dez("0.005"), dez("0.005"), dez("0.5")])
    let frei: [Bool] = j.lose.map(\.steuerfrei)
    #expect(frei == [false, true, false, false])
    let gewinne: [Decimal?] = j.lose.map(\.gewinn)
    #expect(gewinne == [dez("747"), dez("298.95"), nil, dez("-102.9")])
    #expect(j.steuerpflichtig == dez("644.1"))
    #expect(j.steuerfrei == dez("298.95"))
    #expect(j.unterFreigrenze)
    #expect(j.ohneEuro == 1)
    let ohne: [String] = j.ohneAnschaffung.map(\.id)
    #expect(ohne == ["V4"])
    #expect(j.ohneAnschaffung.first?.menge == 3)
    #expect(j.importhinweise == 1)
    #expect(!j.vollstaendig)
    let offen: [String] = j.offen.map { "\($0.coin) \($0.menge)" }
    #expect(offen == ["BTC 0.005", "ETH 0.5"])
    #expect(j.offen.map(\.steuerfreiAb) == [utc("2026-11-15T23:00:00Z"), utc("2027-01-10T23:00:00Z")])
}

@Test func kryptoVorjahrUndFreigrenzeUeberschritten() {
    let vorjahr = KryptoHaltefrist.jahr(2025, ausfuehrungen: kryptoKonto)
    #expect(vorjahr.lose.isEmpty)
    #expect(vorjahr.steuerpflichtig == 0)
    #expect(vorjahr.vollstaendig)
    let gross = [
        krypto("K1", "BTC", "EUR", .buy, "2026-01-05T10:00:00Z", menge: "0.1", betrag: "-5000", gebuehr: "0"),
        krypto("V1", "BTC", "EUR", .sell, "2026-02-05T10:00:00Z", menge: "0.1", betrag: "6000", gebuehr: "0"),
    ]
    let j = KryptoHaltefrist.jahr(2026, ausfuehrungen: gross)
    #expect(j.steuerpflichtig == 1000)
    #expect(!j.unterFreigrenze)
    #expect(j.vollstaendig)
}
