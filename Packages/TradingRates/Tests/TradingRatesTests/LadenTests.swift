import Foundation
import Testing
import TradingCore
@testable import TradingRates

// MARK: Welche Datei wird geladen

@Test func leererSpeicherLaedtVerlauf() {
    #expect(EZBKurse.welcheDatei(letzterTag: nil, abgerufen: nil, jetzt: zeit("2026-10-02 10:00")) == .verlauf)
}

@Test func ruhezeitNachAbruf() {
    // Letzter Kurs vorgestern, Abruf vor zwei Stunden: nicht erneut fragen.
    #expect(EZBKurse.welcheDatei(letzterTag: tag("2026-09-30"), abgerufen: zeit("2026-10-02 08:00"),
                                 jetzt: zeit("2026-10-02 10:00")) == nil)
    // Nach sechs Stunden schon.
    #expect(EZBKurse.welcheDatei(letzterTag: tag("2026-10-01"), abgerufen: zeit("2026-10-02 08:00"),
                                 jetzt: zeit("2026-10-02 17:00")) == .heute)
}

@Test func kursVonHeuteReicht() {
    #expect(EZBKurse.welcheDatei(letzterTag: tag("2026-10-02"), abgerufen: zeit("2026-10-02 01:00"),
                                 jetzt: zeit("2026-10-02 20:00")) == nil)
}

@Test func nurWochenendeDazwischenNimmtTagesdatei() {
    // Freitag 25.09. bis Montag 28.09.: dazwischen nur Samstag und Sonntag.
    #expect(EZBKurse.welcheDatei(letzterTag: tag("2026-09-25"), abgerufen: zeit("2026-09-25 17:00"),
                                 jetzt: zeit("2026-09-28 17:00")) == .heute)
}

@Test func fehlenderWerktagNimmtNeunzigTage() {
    // Montag 28.09. bis Donnerstag 01.10.: Dienstag und Mittwoch fehlen.
    #expect(EZBKurse.welcheDatei(letzterTag: tag("2026-09-28"), abgerufen: zeit("2026-09-28 17:00"),
                                 jetzt: zeit("2026-10-01 17:00")) == .neunzigTage)
}

@Test func langePauseNimmtVerlauf() {
    #expect(EZBKurse.welcheDatei(letzterTag: tag("2026-06-01"), abgerufen: zeit("2026-06-01 17:00"),
                                 jetzt: zeit("2026-10-01 17:00")) == .verlauf)
}

@Test func adressenDerEZB() {
    #expect(EZBKurse.Datei.heute.url.absoluteString == "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    #expect(EZBKurse.Datei.verlauf.url.absoluteString == "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml")
}

// MARK: Zwischenspeicher

@Test func zwischenspeicherBehaeltAlleStellen() throws {
    let speicher = neuerSpeicher()
    #expect(speicher.lies() == nil)
    let genau = try #require(Decimal(string: "1.23456789", locale: Locale(identifier: "en_US_POSIX")))
    let inhalt = Kursspeicher.Inhalt(kurse: [tag("2026-09-29"): ["USD": genau, "JPY": 170]],
                                     abgerufen: Date(timeIntervalSince1970: 1_790_000_000))
    try speicher.schreibe(inhalt)
    #expect(speicher.lies() == inhalt)
    // Kurse stehen als Text in der Datei, nicht als JSON-Zahl.
    let text = String(decoding: try Data(contentsOf: speicher.datei), as: UTF8.self)
    #expect(text.contains("\"1.23456789\""))
}

@Test func kaputterZwischenspeicherGiltAlsLeer() throws {
    let speicher = neuerSpeicher()
    try FileManager.default.createDirectory(at: speicher.datei.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("kein json".utf8).write(to: speicher.datei)
    #expect(speicher.lies() == nil)
    #expect(EZBKurse(speicher: speicher, abruf: { _ in Data() }).zwischenspeicher().quelle == .keine)
}

// MARK: Laden mit aufgezeichneter Datei, ohne Netz

@Test func ersterAbrufLaedtVerlaufUndSchreibtDatei() async throws {
    let speicher = neuerSpeicher()
    let abruf = AufgezeichneterAbruf(try fixture("ezb-hist"))
    let jetzt = zeit("2026-09-30 10:00")
    let kurse = EZBKurse(speicher: speicher, abruf: abruf.abruf, jetzt: { jetzt })

    let stand = await kurse.laden()
    #expect(stand.quelle == .netz)
    #expect(stand.fehler == nil)
    #expect(stand.letzterTag == tag("2026-09-29"))
    #expect(stand.abgerufen == jetzt)
    #expect(stand.kurse.inEuro(118, waehrung: "USD", am: jetzt, zeitzone: berlin) == 100)
    #expect(await abruf.adressen == [EZBKurse.Datei.verlauf.url])
    #expect(speicher.lies()?.kurse.count == 3)

    // Gleich danach: Ruhezeit, kein zweiter Abruf, Kurse aus der Datei.
    let nochmal = await kurse.laden()
    #expect(nochmal.quelle == .zwischenspeicher)
    #expect(nochmal.kurse == stand.kurse)
    #expect(await abruf.adressen.count == 1)
}

@Test func neueTageErgaenzenDenSpeicher() async throws {
    let speicher = neuerSpeicher()
    try speicher.schreibe(Kursspeicher.Inhalt(kurse: try EZBKursdatei.lies(try fixture("ezb-hist")),
                                              abgerufen: zeit("2026-09-29 17:00")))
    // 30.09. fehlt, also 90-Tage-Datei; die Aufzeichnung liefert nur den 01.10.
    let abruf = AufgezeichneterAbruf(try fixture("ezb-daily"))
    let stand = await EZBKurse(speicher: speicher, abruf: abruf.abruf, jetzt: { zeit("2026-10-01 17:00") }).laden()
    #expect(await abruf.adressen == [EZBKurse.Datei.neunzigTage.url])
    #expect(stand.quelle == .netz)
    #expect(stand.letzterTag == tag("2026-10-01"))
    #expect(stand.kurse.kurse.count == 4)
    #expect(speicher.lies()?.kurse.count == 4)
}

@Test func ohneNetzGiltDerZwischenspeicher() async throws {
    let speicher = neuerSpeicher()
    try speicher.schreibe(Kursspeicher.Inhalt(kurse: try EZBKursdatei.lies(try fixture("ezb-hist")),
                                              abgerufen: zeit("2026-09-29 17:00")))
    let stand = await EZBKurse(speicher: speicher, abruf: AufgezeichneterAbruf(nil).abruf,
                               jetzt: { zeit("2026-10-01 17:00") }).laden()
    #expect(stand.quelle == .zwischenspeicher)
    #expect(stand.fehler != nil)
    #expect(stand.letzterTag == tag("2026-09-29"))
    #expect(stand.kurse.inEuro(118, waehrung: "USD", am: zeit("2026-10-01 12:00"), zeitzone: berlin) == 100)
    // Die Datei bleibt unverändert.
    #expect(speicher.lies()?.abgerufen == zeit("2026-09-29 17:00"))
}

@Test func ohneNetzUndOhneSpeicherBleibtAllesLuecke() async {
    let stand = await EZBKurse(speicher: neuerSpeicher(), abruf: AufgezeichneterAbruf(nil).abruf,
                               jetzt: { zeit("2026-10-01 17:00") }).laden()
    #expect(stand.quelle == .keine)
    #expect(stand.fehler != nil)
    #expect(stand.kurse.inEuro(100, waehrung: "USD", am: zeit("2026-10-01 12:00"), zeitzone: berlin) == nil)
}

@Test func fehlerseiteUeberschreibtNichts() async throws {
    let speicher = neuerSpeicher()
    try speicher.schreibe(Kursspeicher.Inhalt(kurse: try EZBKursdatei.lies(try fixture("ezb-hist")),
                                              abgerufen: zeit("2026-09-29 17:00")))
    let abruf = AufgezeichneterAbruf(Data("<html>Wartung</html>".utf8))
    let stand = await EZBKurse(speicher: speicher, abruf: abruf.abruf, jetzt: { zeit("2026-10-01 17:00") }).laden()
    #expect(stand.quelle == .zwischenspeicher)
    #expect(stand.fehler != nil)
    #expect(speicher.lies()?.kurse.count == 3)
}

@Test func alteJahreFallenWeg() async throws {
    let speicher = neuerSpeicher()
    let alt: Decimal = 1.1
    try speicher.schreibe(Kursspeicher.Inhalt(kurse: [tag("2010-06-01"): ["USD": alt], tag("2016-06-01"): ["USD": alt]],
                                              abgerufen: zeit("2016-06-01 17:00")))
    let stand = await EZBKurse(speicher: speicher, abruf: AufgezeichneterAbruf(try fixture("ezb-hist")).abruf,
                               jetzt: { zeit("2026-09-30 10:00") }).laden()
    // 2026 minus 10: ab 2016 bleibt, 2010 fällt weg.
    #expect(stand.kurse.kurse[tag("2016-06-01")] != nil)
    #expect(stand.kurse.kurse[tag("2010-06-01")] == nil)
    #expect(speicher.lies()?.kurse.count == 4)
}

@Test func abgebrochenerVerlaufWirdNichtGespeichert() async throws {
    // Erster Abruf bricht ab: nichts speichern, damit der nächste Start den ganzen Verlauf erneut lädt.
    let speicher = neuerSpeicher()
    let ganz = try fixture("ezb-hist")
    let abruf = AufgezeichneterAbruf(Data(ganz.prefix(ganz.count * 2 / 3)))
    let jetzt = zeit("2026-09-30 10:00")
    let stand = await EZBKurse(speicher: speicher, abruf: abruf.abruf, jetzt: { jetzt }).laden()
    #expect(stand.quelle == .keine)
    #expect(stand.fehler != nil)
    #expect(speicher.lies() == nil)
    #expect(EZBKurse.welcheDatei(letzterTag: speicher.lies()?.letzterTag, abgerufen: nil, jetzt: jetzt) == .verlauf)
}
