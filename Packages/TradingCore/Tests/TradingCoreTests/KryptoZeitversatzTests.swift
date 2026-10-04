import Foundation
import Testing
@testable import TradingCore

/// Zeitversatz in ISO-Zeiten (Coinbase, Bitpanda): kaputte Werte werfen einen Fehler statt überzulaufen.
@Test("ISO-Zeit mit gültigem Versatz wird gelesen")
func isoZeitGueltigerVersatz() throws {
    let datum = try KryptoWerte.iso("2026-03-30T10:00:00+02:00", zeile: 2)
    #expect(datum == Date(timeIntervalSince1970: 1_774_857_600))
}

@Test("ISO-Zeit mit riesigem oder unmöglichem Versatz wirft", arguments: [
    "2026-03-30T10:00:00+9223372036854775807:00",
    "2026-03-30T10:00:00-9223372036854775807:59",
    "2026-03-30T10:00:00+02:9223372036854775807",
    "2026-03-30T10:00:00+19:00",
    "2026-03-30T10:00:00+02:60",
])
func isoZeitKaputterVersatz(_ text: String) {
    #expect(throws: CSVImportFehler.ungueltigeZeit(zeile: 7, text: text)) {
        _ = try KryptoWerte.iso(text, zeile: 7)
    }
}
