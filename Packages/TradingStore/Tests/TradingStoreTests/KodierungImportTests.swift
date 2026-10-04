import Foundation
import Testing
import TradingCore
@testable import TradingStore

/// Testdateien aus den TradingCore-Tests (synthetisch oder erfunden, nur gelesen).
private func kern(_ pfad: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/\(pfad)")
    return String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

/// Windows-1252 von Hand: Die Testtexte enthalten nur Zeichen bis U+00FF, dort gleich Latin-1.
private func windows1252(_ text: String) throws -> Data {
    Data(try text.unicodeScalars.map { s in
        guard s.value < 0x80 || (0xA0...0xFF).contains(s.value) else { throw SpeicherFehler.keinText }
        return UInt8(s.value)
    })
}

/// UTF-16 Little Endian mit Byte-Order-Mark, wie „Unicode-Text“ aus Excel oder ein MT5-Bericht.
private func utf16LE(_ text: String) -> Data {
    var bytes: [UInt8] = [0xFF, 0xFE]
    for einheit in text.utf16 { bytes += [UInt8(einheit & 0xFF), UInt8(einheit >> 8)] }
    return Data(bytes)
}

@Test func csvInWindows1252UndUtf16ErgibtDieselbenVorgaenge() throws {
    let text = try kern("R2/scalable_2026.csv")
    #expect(text.contains("ü"))
    let ansi = try windows1252(text)
    #expect(String(data: ansi, encoding: .utf8) == nil)

    let journal = try Journal.imSpeicher()
    let erster = try journal.importiereCSV(datei: ansi, dateiname: "scalable-ansi.csv", kontonummer: "Depot")
    #expect(erster.status == .gespeichert)
    #expect(erster.csv.ausfuehrungenNeu == 3)
    #expect(erster.csv.geldbewegungenNeu == 3)
    let konto = try #require(try journal.konten().first)
    let original = try ScalableCSV.lies(text)
    let gespeichert = try journal.kontobewegungen(konto: konto)
    #expect(gespeichert.ausfuehrungen.map(\.id).sorted() == original.ausfuehrungen.map(\.id).sorted())

    // Dieselben Vorgänge als UTF-16 und UTF-8: andere Datei, aber nichts Neues und keine Abweichung (Umlaute gleich).
    for (name, daten) in [("scalable-utf16.csv", utf16LE(text)), ("scalable.csv", Data(text.utf8))] {
        let weiterer = try journal.importiereCSV(datei: daten, dateiname: name, kontonummer: "Depot")
        #expect(weiterer.status == .gespeichert)
        #expect(weiterer.csv.ausfuehrungenNeu == 0 && weiterer.csv.ausfuehrungenBekannt == 3)
        #expect(weiterer.csv.geldbewegungenNeu == 0 && weiterer.csv.geldbewegungenBekannt == 3)
    }
    #expect(try journal.importe(konto: konto).count == 3)
}

@Test func mt4AuszugInUtf16UndBinaerdatei() throws {
    let html = try kern("MT4/beispiel-2026-05-13-daily.html")
    let utc = TimeZone(secondsFromGMT: 0)!
    let journal = try Journal.imSpeicher()
    let erster = try journal.importiereMT4(datei: utf16LE(html), dateiname: "a-utf16.html", serverZeitzone: utc)
    #expect(erster.status == .gespeichert)
    #expect(erster.geschlosseneNeu == 4)
    let zweiter = try journal.importiereMT4(datei: Data(html.utf8), dateiname: "a.html", serverZeitzone: utc)
    #expect(zweiter.geschlosseneNeu == 0 && zweiter.geschlosseneBekannt == 4)

    // Anfang einer ZIP- bzw. xlsx-Datei: kein Text.
    let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00, 0x08, 0x00, 0x00, 0x00])
    #expect(throws: SpeicherFehler.keinText) {
        try journal.importiereCSV(datei: zip, dateiname: "export.xlsx", kontonummer: "Depot")
    }
    #expect(throws: SpeicherFehler.keinText) {
        try journal.importiereMT4(datei: zip, dateiname: "export.xlsx", serverZeitzone: utc)
    }
}
