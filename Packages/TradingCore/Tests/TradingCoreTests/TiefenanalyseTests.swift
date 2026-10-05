import Foundation
import Testing
@testable import TradingCore

/// Tiefenanalyse (Tim 05.10.2026): Heatmap, Tagesverlauf, Punktwolken, Verteilungen, Drawdown, Kosten je
/// Fehlermuster, Stärken und Schwächen, Anteile. Erfundene Trades; Sollwerte von Hand nachgerechnet.
/// Zeiten in UTC, ausgewertet in Europe/Berlin (Oktober bis 25.10. UTC+2, danach UTC+1).
private let tiefeZone = TimeZone(identifier: "Europe/Berlin")!

private func tiefeZeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    return formatter.date(from: iso + "Z")!
}

private func tiefeDez(_ text: String) -> Decimal { Decimal(string: text)! }

/// Kurs 100, Ergebnis = Kursbewegung, also Wert je Punkt 1: Mit Stop 90 (Kauf) ist 1 R = 10.
private func tiefeTrade(_ id: String, _ offen: String, _ zu: String, _ ergebnis: Decimal, stop: Decimal? = nil,
                        symbol: String = "DE40", side: Side = .buy, lots: Decimal = 1,
                        nurDatum: Bool = false) -> Trade {
    let schluss: Decimal = side == .buy ? 100 + ergebnis : 100 - ergebnis
    return Trade(id: id, symbol: symbol, side: side, lots: lots, openTime: tiefeZeit(offen),
                 closeTime: tiefeZeit(zu), openPrice: 100, closePrice: schluss, stopLoss: stop, profit: ergebnis,
                 nurDatum: nurDatum)
}

/// Montag 05.10.2026: A (09:00–09:30 Berlin, +20, 2 R), B (09:10–10:00, −10, −1 R), C (Verkauf, 10:05–10:20,
/// −15, ohne Stop, 2 Lots). Dienstag 06.10.: D (14:00–15:00, +5, Stop 95, 1 R), E nur Datum (+7, ohne Stop).
/// Schlussreihenfolge: A, B, C, E, D.
private let tiefeBasis: [Trade] = [
    tiefeTrade("A", "2026-10-05T07:00:00", "2026-10-05T07:30:00", 20, stop: 90),
    tiefeTrade("B", "2026-10-05T07:10:00", "2026-10-05T08:00:00", -10, stop: 90),
    tiefeTrade("C", "2026-10-05T08:05:00", "2026-10-05T08:20:00", -15, symbol: "US100", side: .sell, lots: 2),
    tiefeTrade("D", "2026-10-06T12:00:00", "2026-10-06T13:00:00", 5, stop: 95, symbol: "EURUSD"),
    tiefeTrade("E", "2026-10-06T00:00:00", "2026-10-06T00:00:00", 7, symbol: "AAPL", nurDatum: true),
]

/// Mittwoch 07.10.: F (+30), bringt das Konto über das alte Hoch.
private let tiefeF = tiefeTrade("F", "2026-10-07T08:00:00", "2026-10-07T09:00:00", 30, symbol: "DE40")

private func tiefeBefund(_ muster: Fehlermuster, _ ids: [String]) -> Befund {
    Befund(muster: muster, trades: ids, netto: 0, summeR: nil, wert: nil, stichprobe: 5)
}

// MARK: - Heatmap

@Test func tiefeHeatmapWochentagUndStundeInBerlin() {
    let karte = Tiefenanalyse.heatmap(tiefeBasis, zeitzone: tiefeZone)
    #expect(karte.zellen.map(\.wochentag) == [1, 1, 2])
    #expect(karte.zellen.map(\.stunde) == [9, 10, 14])  // Berliner Zeit, nicht UTC 7, 8, 12
    #expect(karte.ohneUhrzeit == 1)
    #expect(karte.mindestanzahl == 5)

    let montag9 = karte.zelle(wochentag: 1, stunde: 9)
    #expect(montag9?.anzahl == 2)
    #expect(montag9?.netto == 10)
    #expect(montag9?.trefferquote == tiefeDez("0.5"))
    #expect(montag9?.durchschnittR == tiefeDez("0.5"))  // (2 − 1) ÷ 2
    #expect(montag9?.anzahlMitR == 2)
    #expect(montag9?.tradeIDs == ["A", "B"])
    #expect(montag9?.belastbar == false)

    let montag10 = karte.zelle(wochentag: 1, stunde: 10)
    #expect(montag10?.netto == -15)
    #expect(montag10?.trefferquote == 0)
    #expect(montag10?.durchschnittR == nil)
    #expect(karte.zelle(wochentag: 2, stunde: 14)?.durchschnittR == 1)
    #expect(karte.zelle(wochentag: 3, stunde: 9) == nil)

    let locker = Tiefenanalyse.heatmap(tiefeBasis, zeitzone: tiefeZone, mindestanzahl: 2)
    #expect(locker.zellen.map(\.belastbar) == [true, false, false])
}

@Test func tiefeHeatmapLeerUndNurDatum() {
    let leer = Tiefenanalyse.heatmap([], zeitzone: tiefeZone)
    #expect(leer.zellen.isEmpty)
    #expect(leer.ohneUhrzeit == 0)
    let nurE = Tiefenanalyse.heatmap([tiefeBasis[4]], zeitzone: tiefeZone)
    #expect(nurE.zellen.isEmpty)
    #expect(nurE.ohneUhrzeit == 1)
}

// MARK: - Tagesverlauf

@Test func tiefeTagesverlaufMitPhasen() {
    let befunde = [tiefeBefund(.revancheTrade, ["C"]), tiefeBefund(.ueberhandeln, ["A", "B", "C"]),
                   tiefeBefund(.ohneStop, ["C", "E"])]
    let montag = Journaltag(jahr: 2026, monat: 10, tag: 5)!
    let verlauf = Tiefenanalyse.tagesverlauf(tiefeBasis, tag: montag, befunde: befunde, zeitzone: tiefeZone)
    #expect(verlauf.eintraege.map(\.tradeID) == ["A", "B", "C"])
    #expect(verlauf.eintraege.map(\.summeNachSchluss) == [20, 10, -5])
    #expect(verlauf.eintraege.map(\.ergebnis) == [.win, .loss, .loss])
    #expect(verlauf.eintraege[2].muster == [.revancheTrade, .ueberhandeln])  // ohneStop wird nicht markiert
    #expect(verlauf.eintraege[0].muster == [.ueberhandeln])
    #expect(verlauf.punkte.map(\.zeit) == [tiefeZeit("2026-10-05T07:30:00"), tiefeZeit("2026-10-05T08:00:00"),
                                           tiefeZeit("2026-10-05T08:20:00")])
    #expect(verlauf.netto == -5)
    #expect(verlauf.ohneUhrzeit.isEmpty)

    let erwartet = [
        Tiefenanalyse.Tagesverlauf.Phase(muster: .revancheTrade, von: tiefeZeit("2026-10-05T08:05:00"),
                                         bis: tiefeZeit("2026-10-05T08:20:00"), tradeIDs: ["C"]),
        Tiefenanalyse.Tagesverlauf.Phase(muster: .ueberhandeln, von: tiefeZeit("2026-10-05T07:00:00"),
                                         bis: tiefeZeit("2026-10-05T08:20:00"), tradeIDs: ["A", "B", "C"]),
    ]
    #expect(verlauf.phasen == erwartet)

    // A und C getrennt durch B: zwei Revanche-Phasen.
    let nurRevanche = [tiefeBefund(.revancheTrade, ["A", "C"])]
    let getrennt = Tiefenanalyse.tagesverlauf(tiefeBasis, tag: montag, befunde: nurRevanche, zeitzone: tiefeZone)
    #expect(getrennt.phasen.map(\.tradeIDs) == [["A"], ["C"]])
    #expect(getrennt.phasen[0].bis == tiefeZeit("2026-10-05T07:30:00"))
}

@Test func tiefeTagesverlaufOhneUhrzeitUndLeer() {
    let dienstag = Journaltag(jahr: 2026, monat: 10, tag: 6)!
    let verlauf = Tiefenanalyse.tagesverlauf(tiefeBasis, tag: dienstag, befunde: [], zeitzone: tiefeZone)
    #expect(verlauf.eintraege.map(\.tradeID) == ["D"])
    #expect(verlauf.eintraege.map(\.summeNachSchluss) == [5])
    #expect(verlauf.ohneUhrzeit == ["E"])
    #expect(verlauf.nettoOhneUhrzeit == 7)
    #expect(verlauf.netto == 12)
    #expect(verlauf.phasen.isEmpty)

    let leer = Tiefenanalyse.tagesverlauf([], tag: dienstag, befunde: [], zeitzone: tiefeZone)
    #expect(leer.eintraege.isEmpty)
    #expect(leer.punkte.isEmpty)
    #expect(leer.netto == 0)
}

// MARK: - Punktwolken

@Test func tiefeHaltedauerGegenNetto() {
    let punkte = Tiefenanalyse.haltedauerGegenNetto(tiefeBasis)
    #expect(punkte.map(\.tradeID) == ["A", "B", "C", "D"])  // E ohne Uhrzeit fehlt
    #expect(punkte.map(\.haltedauer) == [1800, 3000, 900, 3600])
    #expect(punkte.map(\.netto) == [20, -10, -15, 5])
    #expect(Tiefenanalyse.haltedauerGegenNetto([]).isEmpty)
}

@Test func tiefeTradesJeTagMitRegression() {
    let zweiTage = Tiefenanalyse.tradesJeTag(tiefeBasis, zeitzone: tiefeZone)
    #expect(zweiTage.punkte.map(\.trades) == [3, 2])
    #expect(zweiTage.punkte.map(\.netto) == [-5, 12])
    #expect(zweiTage.punkte[1].tradeIDs == ["E", "D"])
    #expect(zweiTage.punkte[1].tag == Journaltag(jahr: 2026, monat: 10, tag: 6))
    #expect(zweiTage.regression == nil)  // unter 3 Tagen

    // Mittwoch mit einem Trade (+3): Punkte (3; −5), (2; 12), (1; 3).
    // x̄ = 2, ȳ = 10/3, Sxx = 2, Sxy = −25/3 + 1/3 = −8: Steigung −4, Achsenabschnitt 10/3 + 8 = 34/3.
    let mittwoch = tiefeTrade("W", "2026-10-07T08:00:00", "2026-10-07T09:00:00", 3)
    let dreiTage = Tiefenanalyse.tradesJeTag(tiefeBasis + [mittwoch], zeitzone: tiefeZone)
    let gerade = dreiTage.regression
    #expect(gerade != nil)
    #expect(abs((gerade?.steigung ?? 0) + 4) < 1e-9)
    #expect(abs((gerade?.achsenabschnitt ?? 0) - 34.0 / 3.0) < 1e-9)
    #expect(Tiefenanalyse.tradesJeTag([], zeitzone: tiefeZone).punkte.isEmpty)
}

@Test func tiefeRegressionUndTeilverkaeufe() {
    // x̄ = 2, ȳ = 13/3, Sxx = 2, Sxy = 5: Steigung 2,5, Achsenabschnitt 13/3 − 5 = −2/3.
    let gerade = Tiefenanalyse.regression(x: [1, 2, 3], y: [2, 4, 7])
    #expect(abs((gerade?.steigung ?? 0) - 2.5) < 1e-9)
    #expect(abs((gerade?.achsenabschnitt ?? 0) + 2.0 / 3.0) < 1e-9)
    #expect(Tiefenanalyse.regression(x: [2, 2, 2], y: [1, 2, 3]) == nil)  // Varianz 0
    #expect(Tiefenanalyse.regression(x: [1, 2], y: [1, 2]) == nil)

    // Zwei Teilverkäufe derselben Eröffnung zählen als ein Trade.
    let teil1 = tiefeTrade("T1", "2026-10-08T08:00:00", "2026-10-08T08:30:00", 4)
    let teil2 = tiefeTrade("T2", "2026-10-08T08:00:00", "2026-10-08T09:00:00", 6)
    let tag = Tiefenanalyse.tradesJeTag([teil1, teil2], zeitzone: tiefeZone)
    #expect(tag.punkte.map(\.trades) == [1])
    #expect(tag.punkte.map(\.netto) == [10])
}

// MARK: - Verteilungen

@Test func tiefeRVerteilungInHalbenR() {
    let v = Tiefenanalyse.rVerteilung(tiefeBasis)
    #expect(v.ohneRisiko == 2)  // C ohne Stop, E ohne Stop
    #expect(v.breite == tiefeDez("0.5"))
    let halb = tiefeDez("0.5")
    let unten: [Decimal?] = [-1, -halb, 0, halb, 1, 1 + halb, 2]
    let oben: [Decimal?] = [-halb, 0, halb, 1, 1 + halb, 2, 2 + halb]
    #expect(v.klassen.map(\.untergrenze) == unten)
    #expect(v.klassen.map(\.obergrenze) == oben)
    #expect(v.klassen.map(\.anzahl) == [1, 0, 0, 0, 1, 0, 1])
    #expect(v.klassen.map(\.tradeIDs) == [["B"], [], [], [], ["D"], [], ["A"]])

    // Zwei Klassen je Seite: alles ab 1 R in der offenen Randklasse.
    let eng = Tiefenanalyse.rVerteilung(tiefeBasis, klassenJeSeite: 2)
    #expect(eng.klassen.map(\.anzahl) == [1, 0, 0, 0, 2])
    #expect(eng.klassen.last?.untergrenze == 1)
    #expect(eng.klassen.last?.obergrenze == nil)
    #expect(eng.klassen.last?.tradeIDs == ["A", "D"])

    let leer = Tiefenanalyse.rVerteilung([])
    #expect(leer.klassen.isEmpty)
    #expect(leer.ohneRisiko == 0)
}

@Test func tiefeRVerteilungNegativeKlassenUndRundung() {
    // X: −12 bei 1 R = 10 ergibt −1,2 R, also [−1,5; −1).
    let x = tiefeTrade("X", "2026-10-05T07:00:00", "2026-10-05T07:30:00", -12, stop: 90)
    // Y: Stop 3 Punkte, Wert je Punkt 10/3: 1 R = 9,999…, R = −1,000…; gerundet −1, also [−1; −0,5).
    let y = Trade(id: "Y", symbol: "DE40", side: .buy, lots: 1, openTime: tiefeZeit("2026-10-05T08:00:00"),
                  closeTime: tiefeZeit("2026-10-05T08:30:00"), openPrice: 100, closePrice: 97, stopLoss: 97,
                  profit: -10)
    let v = Tiefenanalyse.rVerteilung([x, y])
    let unten: [Decimal?] = [tiefeDez("-1.5"), -1]
    #expect(v.klassen.map(\.untergrenze) == unten)
    #expect(v.klassen.map(\.tradeIDs) == [["X"], ["Y"]])
}

@Test func tiefeBetragsverteilung() {
    // Größter Betrag 20, 10 Klassen je Seite: 2 → nächste runde Stufe darüber 5.
    let auto = Tiefenanalyse.betragsverteilung(tiefeBasis)
    #expect(auto.breite == 5)
    let autoUnten: [Decimal?] = [-15, -10, -5, 0, 5, 10, 15, 20]
    #expect(auto.klassen.map(\.untergrenze) == autoUnten)
    #expect(auto.klassen.map(\.anzahl) == [1, 1, 0, 0, 2, 0, 0, 1])
    #expect(auto.klassen[4].tradeIDs == ["E", "D"])

    let zehn = Tiefenanalyse.betragsverteilung(tiefeBasis, breite: 10)
    let zehnUnten: [Decimal?] = [-20, -10, 0, 10, 20]
    #expect(zehn.klassen.map(\.untergrenze) == zehnUnten)
    #expect(zehn.klassen.map(\.anzahl) == [1, 1, 2, 0, 1])

    #expect(Tiefenanalyse.runderSchritt(ueber: 2) == 5)
    #expect(Tiefenanalyse.runderSchritt(ueber: 10) == 20)
    #expect(Tiefenanalyse.runderSchritt(ueber: 1) == 2)
    #expect(Tiefenanalyse.runderSchritt(ueber: tiefeDez("0.9")) == 1)
    #expect(Tiefenanalyse.runderSchritt(ueber: tiefeDez("0.003")) == tiefeDez("0.005"))
    #expect(Tiefenanalyse.runderSchritt(ueber: 0) == 1)
    #expect(Tiefenanalyse.betragsverteilung([]).klassen.isEmpty)
    #expect(Tiefenanalyse.abgerundet(tiefeDez("-2.4")) == -3)
    #expect(Tiefenanalyse.abgerundet(tiefeDez("2.4")) == 2)
    #expect(Tiefenanalyse.abgerundet(-2) == -2)
}

// MARK: - R-Kennzahlen

@Test func tiefeRKennzahlen() {
    let basis = RKennzahlen(trades: tiefeBasis)
    #expect(basis.anzahlMitR == 3)
    #expect(basis.anzahlGewinnerMitR == 2)
    #expect(basis.anzahlVerliererMitR == 1)
    #expect(basis.durchschnittGewinnR == tiefeDez("1.5"))
    #expect(basis.durchschnittVerlustR == -1)
    #expect(basis.erwartungswertR == Decimal(2) / Decimal(3))
    #expect(basis.groessterVerlustR == -1)
    #expect(basis.verlusteUeber1R == 0)  // −1 R ist nicht über 1 R
    #expect(basis.anteilVerlusteUeber1R == 0)

    // R: −2; −1,5; −0,5; −1; +3, dazu ein Trade ohne Stop.
    let ergebnisse: [Decimal] = [-20, -15, -5, -10, 30]
    var trades: [Trade] = []
    for (i, e) in ergebnisse.enumerated() {
        trades.append(tiefeTrade("R\(i)", "2026-10-05T07:00:00", "2026-10-05T08:00:00", e, stop: 90))
    }
    trades.append(tiefeTrade("ohne", "2026-10-05T07:00:00", "2026-10-05T08:00:00", -50))
    let r = RKennzahlen(trades: trades)
    #expect(r.anzahlMitR == 5)
    #expect(r.durchschnittGewinnR == 3)
    #expect(r.durchschnittVerlustR == tiefeDez("-1.25"))
    #expect(r.erwartungswertR == tiefeDez("-0.4"))
    #expect(r.groessterVerlustR == -2)
    #expect(r.verlusteUeber1R == 2)
    #expect(r.anteilVerlusteUeber1R == tiefeDez("0.5"))

    let leer = RKennzahlen(trades: [])
    #expect(leer.anzahlMitR == 0)
    #expect(leer.durchschnittGewinnR == nil)
    #expect(leer.groessterVerlustR == nil)
    #expect(leer.anteilVerlusteUeber1R == nil)
}

// MARK: - Drawdown

@Test func tiefeDrawdownOhneErholung() {
    let dd = Tiefenanalyse.drawdown(tiefeBasis)
    #expect(dd.punkte.map(\.tradeID) == ["A", "B", "C", "E", "D"])
    #expect(dd.punkte.map(\.kapital) == [20, 10, -5, 2, 7])
    #expect(dd.punkte.map(\.abstand) == [0, 10, 25, 18, 13])
    #expect(dd.maxDrawdown == 25)
    #expect(dd.hochVorMaxDrawdown == tiefeZeit("2026-10-05T07:30:00"))
    #expect(dd.tiefpunkt == tiefeZeit("2026-10-05T08:20:00"))
    #expect(dd.erholt == nil)
    #expect(dd.dauerBisErholung == nil)
    #expect(dd.laengsteVerlustserie.anzahl == 2)
    #expect(dd.laengsteVerlustserie.summe == -25)
    #expect(dd.laengsteVerlustserie.tradeIDs == ["B", "C"])
    #expect(dd.laengsteGewinnserie.anzahl == 2)
    #expect(dd.laengsteGewinnserie.summe == 12)
    #expect(dd.laengsteGewinnserie.von == tiefeZeit("2026-10-06T00:00:00"))
    #expect(dd.laengsteGewinnserie.bis == tiefeZeit("2026-10-06T13:00:00"))
    // Gleiche Zahlen wie der vorhandene Kapitalverlauf.
    let kv = Kapitalverlauf(trades: tiefeBasis)
    #expect(dd.punkte.map(\.kapital) == kv.punkte)
    #expect(dd.laengsteVerlustserie.anzahl == kv.laengsteVerlustserie)

    let mitStart = Tiefenanalyse.drawdown(tiefeBasis, startkapital: 100)
    #expect(mitStart.punkte.map(\.kapital) == [120, 110, 95, 102, 107])
    #expect(mitStart.punkte.map(\.hoch) == [120, 120, 120, 120, 120])
}

@Test func tiefeDrawdownMitErholungUndRaender() {
    let dd = Tiefenanalyse.drawdown(tiefeBasis + [tiefeF])
    #expect(dd.erholt == tiefeZeit("2026-10-07T09:00:00"))
    #expect(dd.dauerBisErholung == 175_200)  // 05.10. 08:20 bis 07.10. 09:00 UTC: 2 Tage und 40 Minuten
    #expect(dd.laengsteGewinnserie.anzahl == 3)
    #expect(dd.laengsteGewinnserie.summe == 42)

    // Erster Trade ein Verlust: Das Hoch ist das Startkapital.
    let verlust = tiefeTrade("V", "2026-10-05T07:00:00", "2026-10-05T08:00:00", -10)
    let start = Tiefenanalyse.drawdown([verlust])
    #expect(start.maxDrawdown == 10)
    #expect(start.hochVorMaxDrawdown == nil)
    #expect(start.tiefpunkt == tiefeZeit("2026-10-05T08:00:00"))

    let leer = Tiefenanalyse.drawdown([])
    #expect(leer.punkte.isEmpty)
    #expect(leer.maxDrawdown == 0)
    #expect(leer.tiefpunkt == nil)
    #expect(leer.laengsteVerlustserie.anzahl == 0)
    #expect(leer.laengsteGewinnserie.von == nil)
}

// MARK: - Kosten je Fehlermuster

@Test func tiefeFehlermusterKostenAusAuswertung() {
    // Echte Erkennung: C ist Revanche (5 Min. nach Verlust B, 2 Lots bei Median 1); C und E ohne Stop.
    let oktober = Zeitspanne.monat(jahr: 2026, monat: 10, zeitzone: tiefeZone)!
    let auswertung = Auswertung(trades: tiefeBasis, zeitraum: oktober, zeitzone: tiefeZone)
    #expect(auswertung.befunde.map(\.muster) == [.revancheTrade, .ohneStop])
    let kosten = Tiefenanalyse.fehlermusterKosten(auswertung)
    #expect(kosten.map(\.muster) == [.revancheTrade, .ohneStop])
    #expect(kosten.map(\.netto) == [-15, -8])
    #expect(kosten.map(\.anzahl) == [1, 2])
    #expect(kosten.map(\.tradeIDs) == [["C"], ["C", "E"]])
    #expect(kosten.map(\.anzahlMitR) == [0, 0])
    #expect(kosten[0].summeR == nil)
    #expect(kosten.map(\.istRegelbruch) == [true, true])
    // Netto gesamt 7; ohne C 22, ohne C und E 15.
    let nettoOhne: [Decimal?] = [22, 15]
    #expect(kosten.map(\.nettoOhne) == nettoOhne)

    let leer = Auswertung(trades: [], zeitraum: oktober, zeitzone: tiefeZone)
    #expect(Tiefenanalyse.fehlermusterKosten(leer).isEmpty)
}

// MARK: - Stärken und Schwächen

@Test func tiefeStaerkenUndSchwaechen() {
    let setups = ["A": "Ausbruch", "B": "Ausbruch", "D": "Pullback"]
    let alle = Tiefenanalyse.staerkenUndSchwaechen(tiefeBasis, zeitzone: tiefeZone, setups: setups, mindestanzahl: 1)
    // Positiv: Dienstag 12; je 10 Stunde 9, DE40, Ausbruch (Reihenfolge der Dimensionen).
    #expect(alle.staerkste.map(\.dimension) == [.wochentag, .stunde, .symbol])
    #expect(alle.staerkste.map(\.schluessel) == ["2", "9", "DE40"])
    #expect(alle.staerkste.map(\.netto) == [12, 10, 10])
    #expect(alle.staerkste[0].tradeIDs == ["E", "D"])
    #expect(alle.staerkste[0].trefferquote == 1)
    #expect(alle.staerkste[0].durchschnittR == 1)  // nur D hat ein Risiko
    #expect(alle.staerkste[1].r.durchschnittVerlustR == -1)
    // Negativ: −15 Stunde 10 und US100, dann −5 Montag vor Haltedauer unter 1 Stunde.
    #expect(alle.schwaechste.map(\.dimension) == [.stunde, .symbol, .wochentag])
    #expect(alle.schwaechste.map(\.schluessel) == ["10", "US100", "1"])
    #expect(alle.schwaechste[2].trefferquote == Decimal(1) / Decimal(3))
    #expect(alle.schwaechste[2].durchschnittR == tiefeDez("0.5"))

    // Ab 3 Trades: Montag, Haltedauer unter 1 Stunde (E ohne Uhrzeit zählt nicht) und der Monat Oktober.
    let drei = Tiefenanalyse.staerkenUndSchwaechen(tiefeBasis, zeitzone: tiefeZone, setups: setups, mindestanzahl: 3)
    #expect(drei.staerkste.map(\.schluessel) == ["2026-10"])
    #expect(drei.staerkste.first?.anzahl == 5)
    #expect(drei.schwaechste.map(\.dimension) == [.wochentag, .haltedauer])
    #expect(drei.schwaechste.map(\.schluessel) == ["1", Haltedauerklasse.unter1Stunde.rawValue])

    let standard = Tiefenanalyse.staerkenUndSchwaechen(tiefeBasis, zeitzone: tiefeZone)
    #expect(standard.staerkste.isEmpty)
    #expect(standard.schwaechste.isEmpty)
    #expect(standard.mindestanzahl == 10)
    let ohneSetup = Tiefenanalyse.gruppenbefunde(tiefeBasis, zeitzone: tiefeZone, setups: [:])
    #expect(!ohneSetup.contains { $0.dimension == .setup })
    #expect(Tiefenanalyse.gruppenbefunde([], zeitzone: tiefeZone, setups: [:]).isEmpty)
}

@Test func tiefeMonateNachSchlussInBerlin() {
    // 31.10. 23:30 UTC ist in Berlin (UTC+1) schon der 1. November.
    let spaet = tiefeTrade("N", "2026-10-31T22:00:00", "2026-10-31T23:30:00", -4)
    let monate = Tiefenanalyse.monate(tiefeBasis + [spaet], zeitzone: tiefeZone)
    #expect(monate.map(\.monat) == [10, 11])
    #expect(monate.map(\.jahr) == [2026, 2026])
    #expect(monate.map(\.netto) == [7, -4])
    #expect(monate.map(\.anzahl) == [5, 1])
    #expect(monate[1].tradeIDs == ["N"])
    #expect(monate[0].trefferquote == tiefeDez("0.6"))
    #expect(Tiefenanalyse.monate([], zeitzone: tiefeZone).isEmpty)
}

// MARK: - Anteile

@Test func tiefeAnteileErgebnisRichtungSymbolSetup() {
    let ergebnis = Tiefenanalyse.anteileErgebnis(tiefeBasis)
    #expect(ergebnis.map(\.schluessel) == ["gewinner", "verlierer", "breakeven"])
    #expect(ergebnis.map(\.wert) == [3, 2, 0])
    #expect(ergebnis.map(\.anteil) == [tiefeDez("0.6"), tiefeDez("0.4"), 0])
    #expect(ergebnis[0].tradeIDs == ["A", "E", "D"])

    let richtung = Tiefenanalyse.anteileRichtung(tiefeBasis)
    #expect(richtung.map(\.schluessel) == ["buy", "sell"])
    #expect(richtung.map(\.anteil) == [tiefeDez("0.8"), tiefeDez("0.2")])

    // DE40 2; AAPL, EURUSD, US100 je 1, nach Name: AAPL vorn, der Rest nach Schlusszeit C, D.
    let symbole = Tiefenanalyse.anteileSymbole(tiefeBasis, top: 2)
    #expect(symbole.map(\.schluessel) == ["DE40", "AAPL", ""])
    #expect(symbole.map(\.art) == [.eintrag, .eintrag, .rest])
    #expect(symbole.map(\.anteil) == [tiefeDez("0.4"), tiefeDez("0.2"), tiefeDez("0.4")])
    #expect(symbole[2].tradeIDs == ["C", "D"])
    #expect(Tiefenanalyse.anteileSymbole(tiefeBasis).map(\.art).contains(.rest) == false)

    let setups = Tiefenanalyse.anteileSetups(tiefeBasis, setups: ["A": "Ausbruch", "B": "Ausbruch",
                                                                    "D": "Pullback", "C": ""])
    #expect(setups.map(\.schluessel) == ["Ausbruch", "Pullback", ""])
    #expect(setups.map(\.art) == [.eintrag, .eintrag, .ohne])
    #expect(setups.map(\.wert) == [2, 1, 2])
    #expect(setups[2].tradeIDs == ["C", "E"])

    #expect(Tiefenanalyse.anteileErgebnis([]).isEmpty)
    #expect(Tiefenanalyse.anteileRichtung([]).isEmpty)
    #expect(Tiefenanalyse.anteileSymbole([]).isEmpty)
    #expect(Tiefenanalyse.anteileSetups([], setups: [:]).isEmpty)
}

@Test func tiefeAnteileVerlusteJeMuster() {
    // C (−15) ist Revanche und Überhandeln: zählt nur bei Revanche (früher in allCases). B (−10) nur Überhandeln.
    // „Verlierer laufen lassen“ ist kein Regelbruch je Trade und bleibt außen vor.
    let befunde = [tiefeBefund(.revancheTrade, ["C"]), tiefeBefund(.ueberhandeln, ["A", "B", "C"]),
                   tiefeBefund(.verliererLaufenLassen, ["B", "C"])]
    let anteile = Tiefenanalyse.anteileVerlusteJeMuster(tiefeBasis, befunde: befunde)
    #expect(anteile.map(\.schluessel) == [Fehlermuster.revancheTrade.rawValue, Fehlermuster.ueberhandeln.rawValue])
    #expect(anteile.map(\.wert) == [15, 10])
    #expect(anteile.map(\.anteil) == [tiefeDez("0.6"), tiefeDez("0.4")])
    #expect(anteile.map(\.tradeIDs) == [["C"], ["B"]])

    let ohne = Tiefenanalyse.anteileVerlusteJeMuster(tiefeBasis, befunde: [])
    #expect(ohne.map(\.art) == [.ohne])
    #expect(ohne.map(\.wert) == [25])
    #expect(ohne.map(\.anteil) == [1])
    #expect(ohne[0].tradeIDs == ["B", "C"])
    #expect(Tiefenanalyse.anteileVerlusteJeMuster([], befunde: befunde).isEmpty)
}
