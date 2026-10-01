import Foundation
import Testing
@testable import TradingCore

/// Synthetische XTB-Dateien aus `Fixtures/XTB/erzeuge.py` (siehe 00_LIESMICH.md).
/// Sollwerte unabhängig mit openpyxl nachgerechnet (01.10.2026).
private func datei(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/XTB/\(name).xlsx")
    return try Data(contentsOf: url)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func xmlLeserEntitiesUndLeereElemente() {
    let xml = "<?xml version=\"1.0\"?><x:a x:y='1 &amp; 2'><b/>&lt;&#228;&#xE4;</x:a>"
    #expect(XMLLeser.ereignisse(Data(xml.utf8)) == [
        .start(name: "a", attribute: ["y": "1 & 2"]), .start(name: "b", attribute: [:]), .ende(name: "b"),
        .text("<ää"), .ende(name: "a"),
    ])
}

@Test func xlsxMappeLiestGemeinsameTexteUndLuecken() throws {
    let mappe = try XLSXMappe(daten: datei("xtb_sonderfaelle"))
    #expect(mappe.blaetter.map(\.name) == ["OPEN POSITION 01102026", "CLOSED POSITION HISTORY",
                                           "CASH OPERATION HISTORY"])
    let kasse = try mappe.blatt(mit: ["cash", "operation"])
    #expect(kasse.zeilen.count == 30)
    // Lautschrift fällt weg, formatierte Textteile werden zusammengesetzt.
    #expect(kasse.zeilen[13][2] == "Deposit")
    #expect(kasse.zeilen[18][2] == "Withholding tax")
    // Zeile 20 fehlt in der Datei; die Zeilennummern danach bleiben richtig.
    #expect(kasse.zeilen[19].isEmpty)
    #expect(kasse.zeilen[20][1] == "800007")
    #expect(kasse.zeilen[26][5] == "SYN&CO.US")
    #expect(kasse.zeilen[6][8] == "100001")

    #expect(throws: XLSXFehler.fehlendesBlatt("pending")) { try mappe.blatt(mit: ["pending"]) }
    #expect(throws: XLSXFehler.keineXLSX) { try XLSXMappe(daten: Data("kein zip".utf8)) }
}

@Test func xtbWerte() throws {
    let rest = try XTBWerte.zahl("23.050000000000001", zeile: 1)
    let nullPunkt = try XTBWerte.zahl("-0.", zeile: 1)
    let exponent = try XTBWerte.zahl("1E-3", zeile: 1)
    #expect(rest == dez("23.05"))
    #expect(nullPunkt == 0)
    #expect(exponent == dez("0.001"))
    #expect(throws: CSVImportFehler.ungueltigeZahl(zeile: 3, text: "1,5")) { try XTBWerte.zahl("1,5", zeile: 3) }

    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let iso = try XTBWerte.zeit("2026-03-02 09:10:00", zeitzone: berlin, zeile: 1)
    #expect(iso == utc("2026-03-02T08:10:00Z"))
    #expect(throws: CSVImportFehler.ungueltigeZeit(zeile: 2, text: "31/02/2026 10:00:00")) {
        try XTBWerte.zeit("31/02/2026 10:00:00", zeitzone: berlin, zeile: 2)
    }
    #expect(XTBWerte.kassenart("Transfer", betrag: 200) == .geld(.einzahlung))
    #expect(XTBWerte.kassenart("Ações/ETF compra", betrag: -1) == .unbekannt)
}

@Test func xtbEinfacherAufbau() throws {
    let daten = try datei("xtb_einfach")
    #expect(XTBAuszug.erkennt(daten))
    #expect(!XTBAuszug.erkennt(Data("ID;Type;Time".utf8)))
    let a = try XTBAuszug.lies(daten)
    // Beschriftung links, Wert rechts.
    #expect(a.konto == "00000001")
    #expect(a.waehrung == "EUR")
    #expect(a.positionen.map(\.ticket) == ["920001", "920002"])
    let us100 = a.positionen[0]
    #expect(us100.side == .sell)
    #expect(us100.lots == dez("0.2"))
    #expect(us100.openTime == utc("2026-03-10T14:30:00Z"))
    #expect(us100.closeTime == utc("2026-03-10T15:05:10Z"))
    #expect(us100.stopLoss == dez("18560"))
    #expect(us100.takeProfit == nil)
    // 60 Punkte bis zum Stop, 4 € je Punkt.
    #expect(a.trades[0].risk == dez("240"))
    #expect(a.trades.map(\.netProfit) == [200, dez("-11.5")])
    #expect(a.positionenLautSumme == Totals(commission: dez("-1.5"), swap: 0, profit: 190))
    #expect(a.handelLautKasse == dez("188.5"))
    #expect(a.kasse.geldbewegungen.map(\.art) == [.einzahlung])
    #expect(a.kasseLautSumme == dez("688.5"))
    #expect(a.kassenwirkung == dez("688.5"))
    #expect(a.hinweise.isEmpty)
}

@Test func xtbAufbauWieXStation() throws {
    let a = try XTBAuszug.lies(datei("xtb_sonderfaelle"))
    // Beschriftung in Zeile 6, Wert darunter; das Blatt mit offenen Positionen wird übergangen.
    #expect(a.konto == "100001")
    #expect(a.waehrung == "EUR")
    #expect(a.positionen.map(\.ticket) == ["910001", "910002", "910003"])
    #expect(a.hinweise == [
        Importhinweis(zeile: 17, vorgang: "Position 910004 BUY LIMIT", folge: .nichtVerbucht),
        Importhinweis(zeile: 27, vorgang: "Spin off", folge: .alsSonstiges),
    ])

    // Excel-Datum in deutscher Ortszeit, auch über die Umstellung auf Sommerzeit (29.03.2026).
    let dax = a.positionen[0]
    #expect(dax.openTime == utc("2026-03-02T08:10:00Z"))
    #expect(dax.closeTime == utc("2026-03-02T10:45:30Z"))
    #expect(dax.openPrice == dez("22000.5"))
    let eurusd = a.positionen[1]
    #expect(eurusd.openTime == utc("2026-03-27T19:00:00Z"))
    #expect(eurusd.closeTime == utc("2026-03-30T06:00:00Z"))
    // Gleitkomma-Reste sind weg, Rollover zählt zum Swap.
    #expect(eurusd.closePrice == dez("1.08"))
    #expect(eurusd.profit == dez("23.05"))
    #expect(eurusd.swap == dez("-0.95"))
    #expect(a.positionenLautSumme == Totals(commission: 0, swap: dez("-0.95"), profit: dez("313.05")))
    #expect(a.trades.map(\.netProfit) == [250, dez("22.1"), 40])

    // Alle Positionen liegen im Zeitraum, also deckt sich der Handel in der Kasse mit ihnen.
    let summePositionen = a.trades.map(\.netProfit).reduce(0, +)
    #expect(a.handelLautKasse == dez("312.1"))
    #expect(a.handelLautKasse == summePositionen)
    #expect(a.kasse.geldbewegungen.map(\.art) == [.einzahlung, .dividende, .steuer, .zinsen, .steuer, .gebuehr,
                                                  .sonstiges, .auszahlung, .auszahlung])
    #expect(a.kasse.kassenwirkung == dez("755.82"))
    #expect(a.kassenwirkung == dez("1067.92"))
    #expect(a.kasseLautSumme == dez("1067.92"))

    let einzahlung = a.kasse.geldbewegungen[0]
    #expect(einzahlung.zeit == utc("2026-03-01T11:00:00Z"))
    #expect(!einzahlung.nurDatum)
    #expect(einzahlung.kennung == nil)
    let dividende = a.kasse.geldbewegungen[1]
    #expect(dividende.betrag == dez("4.4"))
    #expect(dividende.nurDatum)
    #expect(dividende.zeit == utc("2026-03-19T23:00:00Z"))
    #expect(dividende.kennung == "SAP.DE")
    #expect(dividende.waehrung == "EUR")
    #expect(a.kasse.geldbewegungen[6].kennung == "SYN&CO.US")
}
