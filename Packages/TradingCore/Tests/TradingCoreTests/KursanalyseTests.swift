import Foundation
import Testing
@testable import TradingCore

/// Kursanalyse für „Frag Henry“ (Doc 38, Paket A2). Erfundene Kerzen, Sollwerte von Hand,
/// Schwankung mit Python statistics.stdev gegengerechnet (02.10.2026).
private func kerze(_ tag: String, _ close: Decimal, hoch: Decimal? = nil, tief: Decimal? = nil,
                   laufend: Bool = false) -> Kerze {
    Kerze(tag: Journaltag(tag)!, open: close, high: hoch ?? close, low: tief ?? close, close: close, laufend: laufend)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

@Test func kursanalyseBoersenreihe() throws {
    // Nur Werktage (Mo 29.09.2025, Mo 31.08., Mi 23.09., Mo 28.09., Mi 30.09.2026), unsortiert übergeben.
    let kerzen = [
        kerze("2026-09-28", 125, hoch: 125, tief: 120),
        kerze("2025-09-29", 50),
        kerze("2026-09-23", 100, hoch: 110),
        kerze("2026-08-31", 80),
        kerze("2026-09-30", 100, tief: 90),
    ]
    let a = try #require(Kursanalyse(kerzen: kerzen))
    #expect(a.letzterTag == Journaltag("2026-09-30")! && a.letzterSchluss == 100 && a.anzahlKerzen == 5)
    // Woche: Ziel 23.09. → 100, ±0. Monat: Ziel 31.08. → 80, +25 %. Jahr: Ziel 30.09.2025 → 50 (29.09.), +100 %.
    // Quartal: Ziel 01.07.2026, davor nur der 29.09.2025, mehr als 7 Tage Lücke → fehlt.
    #expect(a.veraenderung == [.woche: 0, .monat: dez("0.25"), .jahr: 1])
    #expect(a.handelstageJeJahr == 252)
    // Renditen 0,6 / 0,25 / 0,25 / −0,2 → Stichproben-Std.-Abw. 0,32787 × √252 = 5,2048.
    #expect(a.schwankungJahr == dez("5.2048"))
    // 52 Wochen ab 01.10.2025: Hoch 125 (28.09.), Tief 80 (31.08.).
    #expect(a.abstandHoch52W == dez("-0.2"))
    #expect(a.abstandTief52W == dez("0.25"))
    // Schlüsse 50, 80, 100, 125, 100: Rückgang 1 − 100/125.
    #expect(a.groessterRueckgang == dez("0.2"))
    #expect(a.atr14 == nil && a.atr14Anteil == nil && a.aktuellerKurs == nil)
}

@Test func kursanalyseKryptoMitATRUndLaufenderKerze() throws {
    // 01.03.2026 ist ein Sonntag: Wochenende in der Reihe → 365 Handelstage.
    var kerzen = (1...14).map { kerze(String(format: "2026-03-%02d", $0), 100, hoch: 102, tief: 98) }
    kerzen.append(kerze("2026-03-15", 125, hoch: 125, tief: 111))
    kerzen.append(kerze("2026-03-16", 130, hoch: 131, tief: 124, laufend: true))
    let a = try #require(Kursanalyse(kerzen: kerzen))
    // Die laufende Kerze zählt nicht mit, sie liefert nur den aktuellen Kurs.
    #expect(a.letzterTag == Journaltag("2026-03-15")! && a.anzahlKerzen == 15 && a.aktuellerKurs == 130)
    #expect(a.handelstageJeJahr == 365)
    // True Ranges: 13 × 4 (102 − 98), am 15.03. max(14, |125 − 100|, |111 − 100|) = 25 → (52 + 25) / 14 = 5,5.
    #expect(a.atr14 == dez("5.5"))
    #expect(a.atr14Anteil == dez("0.044"))
    // 13 Renditen 0, eine 0,25 → Std.-Abw. 0,066815 × √365 = 1,2765.
    #expect(a.schwankungJahr == dez("1.2765"))
    #expect(a.groessterRueckgang == 0)
    #expect(a.veraenderung == [.woche: dez("0.25")])

    // Bis 14.03.: nur 14 Kerzen, kein ATR; Vorgabe 252 Handelstage gilt.
    let bis = try #require(Kursanalyse(kerzen: kerzen, bis: Journaltag("2026-03-14")!, handelstageJeJahr: 252))
    #expect(bis.anzahlKerzen == 14 && bis.atr14 == nil && bis.handelstageJeJahr == 252 && bis.aktuellerKurs == nil)
    #expect(bis.schwankungJahr == 0)
}

@Test func kursanalyseLeerOderNurLaufend() {
    #expect(Kursanalyse(kerzen: []) == nil)
    #expect(Kursanalyse(kerzen: [kerze("2026-03-02", 100, laufend: true)]) == nil)
    #expect(Kursanalyse(kerzen: [kerze("2026-03-02", 0)]) == nil)
    let eine = Kursanalyse(kerzen: [kerze("2026-03-02", 100), kerze("2026-03-02", 90)])
    // Je Tag zählt die zuletzt übergebene Kerze; mit einer Kerze gibt es weder Schwankung noch Rückgang.
    #expect(eine?.letzterSchluss == 90 && eine?.anzahlKerzen == 1)
    #expect(eine?.schwankungJahr == nil && eine?.groessterRueckgang == nil && eine?.veraenderung == [:])
}

@Test func kerzeCodableMitKursenAlsText() throws {
    let k = Kerze(tag: Journaltag("2026-10-01")!, open: dez("101.25"), high: dez("102.5"), low: dez("100.05"),
                  close: dez("0.1"), volumen: dez("1234.5678"))
    let ohne = Kerze(tag: Journaltag("2026-10-02")!, open: 1, high: 1, low: 1, close: 1, laufend: true)
    let daten = try JSONEncoder().encode([k, ohne])
    #expect(try JSONDecoder().decode([Kerze].self, from: daten) == [k, ohne])
    let text = String(decoding: daten, as: UTF8.self)
    #expect(text.contains("\"open\":\"101.25\"") && text.contains("\"close\":\"0.1\""))
    #expect(text.contains("\"tag\":\"2026-10-01\""))
    #expect(text.components(separatedBy: "volumen").count == 2)
    #expect(text.components(separatedBy: "laufend").count == 2)
}
