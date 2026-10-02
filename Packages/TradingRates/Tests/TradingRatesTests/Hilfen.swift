import Foundation
import Testing
import TradingCore
@testable import TradingRates

let berlin = TimeZone(identifier: "Europe/Berlin")!

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func tag(_ text: String) -> Journaltag { Journaltag(text)! }

/// Zeitpunkt in Berliner Zeit, z. B. `zeit("2026-09-26 12:00")`.
func zeit(_ text: String) -> Date {
    let teile = text.split(separator: " ")
    let t = tag(String(teile[0]))
    let uhr = teile[1].split(separator: ":").map { Int($0)! }
    var k = Calendar(identifier: .gregorian)
    k.timeZone = berlin
    return k.date(from: DateComponents(year: t.jahr, month: t.monat, day: t.tag, hour: uhr[0], minute: uhr[1]))!
}

/// Eigene Datei je Test im temporären Ordner.
func neuerSpeicher() -> Kursspeicher {
    Kursspeicher(datei: FileManager.default.temporaryDirectory
        .appendingPathComponent("tradingrates-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("ezb-referenzkurse.json"))
}

/// Liefert eine aufgezeichnete Datei oder einen Fehler und merkt sich die abgerufenen Adressen.
actor AufgezeichneterAbruf {
    private let antwort: Data?
    private(set) var adressen: [URL] = []

    init(_ antwort: Data?) { self.antwort = antwort }

    struct KeinNetz: Error {}

    func lade(_ url: URL) throws -> Data {
        adressen.append(url)
        guard let antwort else { throw KeinNetz() }
        return antwort
    }

    nonisolated var abruf: EZBKurse.Abruf { { url in try await self.lade(url) } }
}
