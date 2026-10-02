import Foundation
import Testing
@testable import TradingCore

/// Tageskerzen in der Exportdatei (AP12, A3, Doc 38).

private func kerze(_ tag: Journaltag, _ schluss: Decimal) -> Kerze {
    Kerze(tag: tag, open: schluss, high: schluss, low: schluss, close: schluss)
}

@Test func kursreiheSortiertBegrenztUndOhneDoppelteTage() throws {
    let start = try #require(Journaltag("2024-01-01"))
    let utc = TimeZone(secondsFromGMT: 0)!
    let tage = (0..<400).map { i in
        Journaltag(start.beginn(in: utc).addingTimeInterval(Double(i) * 86_400), zeitzone: utc)
    }
    // Rückwärts übergeben, der letzte Tag doppelt: je Tag gilt die zuletzt übergebene Kerze.
    let reihe = JournalExport.Kursreihe(symbol: "BTCUSD", quelle: "kraken", waehrung: "usd", stand: .distantPast,
                                        kerzen: tage.reversed().map { kerze($0, 1) } + [kerze(tage[399], 2)])
    #expect(reihe.waehrung == "USD" && reihe.kerzen.count == JournalExport.kerzenHoechstens)
    #expect(reihe.kerzen.first?.tag == tage[30] && reihe.kerzen.last?.close == 2)
    #expect(reihe.kerzen.map(\.tag) == reihe.kerzen.map(\.tag).sorted())
}

/// „W00“ bis „W69“, damit die Sortierung nach Symbol der Zahl folgt.
private func wert(_ nummer: Int) -> String {
    nummer < 10 ? "W0\(nummer)" : "W\(nummer)"
}

@Test func kursverlaufImExportNachSymbolUndHoechstens60() throws {
    let tag = try #require(Journaltag("2025-05-05"))
    let stand = Date(timeIntervalSince1970: 1_746_428_400)
    var reihen: [JournalExport.Kursreihe] = []
    for i in 0..<70 {
        let kerzen = [kerze(tag, Decimal(i))]
        reihen.append(JournalExport.Kursreihe(symbol: wert(69 - i), quelle: "alpaca", waehrung: "USD",
                                              stand: stand, kerzen: kerzen))
    }
    let leer = JournalExport.Kursreihe(symbol: "A", quelle: "alpaca", waehrung: "USD", stand: .distantPast, kerzen: [])
    let export = JournalExport(konten: [], zeitzone: TimeZone(identifier: "Europe/Berlin")!,
                               erstellt: Date(timeIntervalSince1970: 1_746_428_400), kursverlauf: reihen + [leer])
    #expect(export.kursverlauf?.count == JournalExport.kursreihenHoechstens)
    #expect(export.kursverlauf?.first?.symbol == "W00" && export.kursverlauf?.last?.symbol == "W59")
    let gelesen = try JournalExport.lese(try export.json())
    #expect(gelesen == export)
    let ohne = JournalExport(konten: [], zeitzone: .current, kursverlauf: [leer])
    let text = String(decoding: try ohne.json(), as: UTF8.self)
    #expect(ohne.kursverlauf == nil && !text.contains("kursverlauf"))
}
