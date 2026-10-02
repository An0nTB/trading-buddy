import Foundation
import Testing
@testable import TradingNews

func tempDatei() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tradingnews-\(UUID().uuidString)")
        .appendingPathComponent("meldungen.json")
}

@Test func zwischenspeicherLeerOhneDatei() {
    #expect(Zwischenspeicher(datei: tempDatei()).lies(jetzt: jetzt).isEmpty)
}

@Test func zwischenspeicherErgaenztUndVerwirftAltes() throws {
    let speicher = Zwischenspeicher(datei: tempDatei())
    let alt = meldung("Alt", link: "https://example.org/alt", zeit: jetzt.addingTimeInterval(-15 * 24 * 3600))
    let eins = meldung("Eins", link: "https://example.org/1", zeit: jetzt.addingTimeInterval(-3600))
    try speicher.ergaenze([alt, eins], jetzt: jetzt)
    #expect(speicher.lies(jetzt: jetzt).map(\.titel) == ["Eins"])

    let zwei = meldung("Zwei", link: "https://example.org/2", zeit: jetzt)
    let einsDoppelt = meldung("Eins", link: "https://www.example.org/1?utm_source=x", zeit: jetzt.addingTimeInterval(-3600))
    let ergebnis = try speicher.ergaenze([zwei, einsDoppelt], jetzt: jetzt)
    #expect(ergebnis.map(\.titel) == ["Zwei", "Eins"])
    #expect(speicher.lies(jetzt: jetzt) == ergebnis)
}

@Test func zwischenspeicherUnlesbareDateiIstLeer() throws {
    let datei = tempDatei()
    try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("kaputt".utf8).write(to: datei)
    #expect(Zwischenspeicher(datei: datei).lies(jetzt: jetzt).isEmpty)
}
