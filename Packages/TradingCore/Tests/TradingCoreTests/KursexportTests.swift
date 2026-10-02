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

@Test func kursverlaufImExportNachSymbolUndHoechstens60() throws {
    let tag = try #require(Journaltag("2025-05-05"))
    let reihen = (0..<70).map { i in
        JournalExport.Kursreihe(symbol: "W" + (69 - i < 10 ? "0" : "") + String(69 - i), quelle: "alpaca", waehrung: "USD",
                                stand: Date(timeIntervalSince1970: 1_746_428_400), kerzen: [kerze(tag, Decimal(i))])
    }
    let leer = JournalExport.Kursreihe(symbol: "A", quelle: "alpaca", waehrung: "USD", stand: .distantPast, kerzen: [])
    let export = JournalExport(konten: [], zeitzone: TimeZone(identifier: "Europe/Berlin")!,
                               erstellt: Date(timeIntervalSince1970: 1_746_428_400), kursverlauf: reihen + [leer])
    #expect(export.kursverlauf?.count == JournalExport.kursreihenHoechstens)
    #expect(export.kursverlauf?.first?.symbol == "W00" && export.kursverlauf?.last?.symbol == "W59")
    #expect(try JournalExport.lese(try export.json()) == export)
    let ohne = JournalExport(konten: [], zeitzone: .current, kursverlauf: [leer])
    #expect(ohne.kursverlauf == nil && !String(decoding: try ohne.json(), as: UTF8.self).contains("kursverlauf"))
}
