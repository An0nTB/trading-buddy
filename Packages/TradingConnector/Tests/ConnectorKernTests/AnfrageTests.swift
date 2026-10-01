import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

private let berlin = TimeZone(identifier: "Europe/Berlin")!

private func zeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: iso + "Z")!
}

private func trade(_ id: String, schluss: String, netto: Decimal) -> Trade {
    Trade(id: id, symbol: "de40", side: .buy, lots: 1, openTime: zeit(schluss).addingTimeInterval(-600),
          closeTime: zeit(schluss), openPrice: 100, closePrice: 100 + netto, profit: netto)
}

private let export = JournalExport(
    konten: [
        .init(broker: "GBE brokers Ltd.", kontonummer: "100001", waehrung: "EUR",
              trades: [trade("1", schluss: "2025-04-30T21:30:00", netto: 5),   // 30.04. 23:30 in Berlin
                       trade("2", schluss: "2025-04-30T22:30:00", netto: -2)]), // 01.05. 00:30 in Berlin
        .init(broker: "XTB", kontonummer: "777002", waehrung: "EUR", trades: [])
    ],
    zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))

@Test func kontoWirdEindeutigGewaehlt() throws {
    #expect(throws: AnfrageFehler.kontoUnklar(["GBE brokers Ltd. …0001", "XTB …7002"])) {
        try Anfrage.lies([:], export: export)
    }
    #expect(try Anfrage.lies(["konto": "0001", "monat": "2025-05"], export: export).konto.broker == "GBE brokers Ltd.")
    #expect(try Anfrage.lies(["konto": "xtb", "monat": "2025-05"], export: export).konto.kontonummer == "777002")
    #expect(throws: AnfrageFehler.kontoUnbekannt("9999", ["GBE brokers Ltd. …0001", "XTB …7002"])) {
        try Anfrage.lies(["konto": "9999"], export: export)
    }
    #expect(throws: AnfrageFehler.keineTrades("XTB …7002")) { try Anfrage.lies(["konto": "XTB"], export: export) }
}

@Test func zeitraumAusArgumenten() throws {
    let mai = try Anfrage.lies(["konto": "GBE", "monat": "2025-05"], export: export)
    #expect(mai.zeitraum == Zeitspanne.monat(jahr: 2025, monat: 5, zeitzone: berlin) && mai.vorgabe == nil)
    #expect(mai.auswertung().trades.map(\.id) == ["2"])
    #expect(mai.auswertung().kennzahlenVorzeitraum.netto == 5)

    let tage = try Anfrage.lies(["konto": "GBE", "von": "2025-04-30", "bis": "2025-05-01"], export: export)
    #expect(tage.auswertung().trades.count == 2)
    let woche = try Anfrage.lies(["konto": "GBE", "woche": "2025-05-01"], export: export)
    #expect(woche.zeitraum == Zeitspanne.woche(mit: zeit("2025-05-01T10:00:00"), zeitzone: berlin))

    // Ohne Zeitraum: Monat des letzten Trades in der Zeitzone des Nutzers, hier Mai.
    let vorgabe = try Anfrage.lies(["konto": "GBE"], export: export)
    #expect(vorgabe.zeitraum == mai.zeitraum && vorgabe.vorgabe != nil)
}

@Test func ungueltigeArgumenteWerdenGemeldet() {
    let gbe = ["konto": "GBE"]
    #expect(throws: AnfrageFehler.ungueltigerMonat("2025-13")) {
        try Anfrage.lies(gbe.merging(["monat": "2025-13"]) { $1 }, export: export)
    }
    #expect(throws: AnfrageFehler.ungueltigerMonat("Mai")) {
        try Anfrage.lies(gbe.merging(["monat": "Mai"]) { $1 }, export: export)
    }
    #expect(throws: AnfrageFehler.vonOhneBis) {
        try Anfrage.lies(gbe.merging(["von": "2025-05-01"]) { $1 }, export: export)
    }
    #expect(throws: AnfrageFehler.ungueltigesDatum("1.5.2025")) {
        try Anfrage.lies(gbe.merging(["woche": "1.5.2025"]) { $1 }, export: export)
    }
    #expect(throws: AnfrageFehler.bisVorVon("2025-05-10", "2025-05-01")) {
        try Anfrage.lies(gbe.merging(["von": "2025-05-10", "bis": "2025-05-01"]) { $1 }, export: export)
    }
    #expect(AnfrageFehler.vonOhneBis.text.contains("von"))
}
