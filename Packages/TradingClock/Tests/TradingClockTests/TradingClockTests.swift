import Foundation
import Testing
@testable import TradingClock

/// Sollwerte in UTC, unabhängig mit Python zoneinfo gerechnet (01.10.2026).
/// Sommerzeit: EU ab 29.03.2026, USA ab 08.03.2026, beide bis Ende Oktober beziehungsweise 01.11.2026.
private func zeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    return formatter.date(from: iso + "Z")!
}

private func uhr() throws -> Boersenuhr { try Boersenuhr.mitgeliefert() }

private func boerse(_ id: String) throws -> Boerse { try #require(try uhr()[id]) }

// MARK: Mitgelieferte Daten

@Test func alleSechsBoersenLadenInFesterReihenfolge() throws {
    #expect(try uhr().boersen.map(\.id) == ["xetra", "nyse", "nasdaq", "lse", "forex", "krypto"])
}

@Test func boersenMitFeiertagenSindBis2027Gepflegt() throws {
    let ende = try Kalendertag("2027-12-31")
    for id in ["xetra", "nyse", "nasdaq", "lse"] {
        let b = try boerse(id)
        #expect(b.datenGueltigBis == ende, "\(id)")
        #expect(b.feiertage.contains { $0.datum.jahr == 2026 }, "\(id)")
        #expect(b.feiertage.contains { $0.datum.jahr == 2027 }, "\(id)")
        #expect(!b.quellen.isEmpty, "\(id)")
    }
}

@Test func feiertageLiegenNichtAufWochenenden() throws {
    for b in try uhr().boersen {
        for feiertag in b.feiertage {
            #expect(![Wochentag.samstag, .sonntag].contains(feiertag.datum.wochentag), "\(b.id) \(feiertag.datum)")
        }
    }
}

// MARK: Xetra

@Test func xetraIstMittwochsVormittagsOffen() throws {
    let s = try boerse("xetra").status(zeit("2026-10-07T08:00:00"))   // 10:00 Berlin
    #expect(s.offen)
    #expect(s.naechsterWechsel == zeit("2026-10-07T15:30:00"))      // 17:30 Berlin
    #expect(s.feiertag == nil)
    #expect(s.datenGueltig)
}

@Test func xetraGrenzenGenau() throws {
    let x = try boerse("xetra")
    #expect(!x.istOffen(zeit("2026-10-07T06:59:59")))
    #expect(x.istOffen(zeit("2026-10-07T07:00:00")))
    #expect(x.istOffen(zeit("2026-10-07T15:29:59")))
    #expect(!x.istOffen(zeit("2026-10-07T15:30:00")))
}

@Test func xetraAmWochenendeZuBisMontag() throws {
    let s = try boerse("xetra").status(zeit("2026-10-03T12:00:00"))   // Samstag
    #expect(!s.offen)
    #expect(s.naechsterWechsel == zeit("2026-10-05T07:00:00"))
}

@Test func xetraUeberOsternGeschlossen() throws {
    let x = try boerse("xetra")
    let s = x.status(zeit("2026-04-03T10:00:00"))
    #expect(!s.offen)
    #expect(s.feiertag == "Karfreitag")
    #expect(s.naechsterWechsel == zeit("2026-04-07T07:00:00"))      // Dienstag nach Ostermontag
    #expect(x.naechsteSchliessung(nach: zeit("2026-04-03T10:00:00")) == zeit("2026-04-07T15:30:00"))
}

@Test func xetraJahreswechselMitVerkuerztemTag() throws {
    let x = try boerse("xetra")
    let offen = x.status(zeit("2026-12-30T12:00:00"))                 // 13:00 Berlin, Winterzeit
    #expect(offen.offen)
    #expect(offen.naechsterWechsel == zeit("2026-12-30T13:00:00"))    // 14:00 Berlin
    #expect(offen.verkuerzt == "Letzter Handelstag des Jahres")

    let zu = x.status(zeit("2026-12-30T13:00:00"))
    #expect(!zu.offen)
    #expect(zu.naechsterWechsel == zeit("2027-01-04T08:00:00"))       // 31.12. und 01.01. zu, dann Wochenende
    #expect(zu.verkuerzt == nil)
}

@Test func sitzungenLiefertEineWocheXetra() throws {
    let liste = try boerse("xetra").sitzungen(von: zeit("2026-10-05T00:00:00"), bis: zeit("2026-10-12T00:00:00"))
    #expect(liste.count == 5)
    #expect(liste.first?.beginn == zeit("2026-10-05T07:00:00"))
    #expect(liste.last?.ende == zeit("2026-10-09T15:30:00"))
}

// MARK: USA und London

@Test func nyseRechnetMitAmerikanischerSommerzeit() throws {
    // Zwischen 08.03. und 29.03.2026 liegen New York und Berlin nur fünf statt sechs Stunden auseinander.
    let n = try boerse("nyse")
    #expect(!n.istOffen(zeit("2026-03-16T13:29:59")))
    #expect(n.istOffen(zeit("2026-03-16T13:30:00")))
    #expect(n.naechsteSchliessung(nach: zeit("2026-03-16T13:30:00")) == zeit("2026-03-16T20:00:00"))
}

@Test func nyseSchliesstNachThanksgivingFrueher() throws {
    let s = try boerse("nyse").status(zeit("2026-11-27T17:00:00"))    // 12:00 New York, Winterzeit
    #expect(s.offen)
    #expect(s.naechsterWechsel == zeit("2026-11-27T18:00:00"))
    #expect(s.verkuerzt == "Tag nach Thanksgiving")
}

@Test func nasdaqFolgtDemUSKalender() throws {
    let s = try boerse("nasdaq").status(zeit("2026-07-03T15:00:00"))
    #expect(!s.offen)
    #expect(s.feiertag == "Independence Day (Ersatztag)")
    #expect(s.naechsterWechsel == zeit("2026-07-06T13:30:00"))
}

@Test func lseHeiligabendBisMittag() throws {
    let l = try boerse("lse")
    #expect(l.naechsteSchliessung(nach: zeit("2026-12-24T09:00:00")) == zeit("2026-12-24T12:30:00"))
    // 25.12. Freitag, Wochenende, 28.12. Ersatztag: weiter am Dienstag
    #expect(l.naechsteOeffnung(nach: zeit("2026-12-24T12:30:00")) == zeit("2026-12-29T08:00:00"))
}

// MARK: Forex und Krypto

@Test func forexLaeuftVonSonntagBisFreitagDurch() throws {
    let f = try boerse("forex")
    // Die Tagesgrenze 17:00 New York ist keine Schließung.
    #expect(f.istOffen(zeit("2026-10-07T21:00:00")))
    #expect(f.naechsteSchliessung(nach: zeit("2026-10-07T12:00:00")) == zeit("2026-10-09T21:00:00"))
    #expect(!f.istOffen(zeit("2026-10-10T12:00:00")))                  // Samstag
    #expect(f.naechsteOeffnung(nach: zeit("2026-10-10T12:00:00")) == zeit("2026-10-11T21:00:00"))
    // Im Winter eine Stunde später in UTC
    #expect(f.naechsteOeffnung(nach: zeit("2026-11-07T12:00:00")) == zeit("2026-11-08T22:00:00"))
}

@Test func kryptoIstImmerOffen() throws {
    let k = try boerse("krypto")
    let s = k.status(zeit("2026-12-25T03:00:00"))
    #expect(s.offen)
    #expect(s.naechsterWechsel == nil)
    #expect(k.naechsteOeffnung(nach: zeit("2026-12-25T03:00:00")) == nil)
    #expect(k.naechsteSchliessung(nach: zeit("2026-12-25T03:00:00")) == nil)
}

@Test func nachDemGepflegtenZeitraumWarntDieUhr() throws {
    let s = try boerse("xetra").status(zeit("2028-01-05T10:00:00"))
    #expect(s.offen)
    #expect(!s.datenGueltig)
    #expect(try boerse("xetra").status(zeit("2027-12-31T10:00:00")).datenGueltig == false)  // nächste Öffnung 2028
}

// MARK: Eigene Börsen und Fehler

private func json(_ text: String) -> Data { Data(text.utf8) }

private let eigeneBoerse = """
{ "format": 1, "id": "tse", "name": "Tokio", "mic": "XTKS", "zeitzone": "Asia/Tokyo", "stand": "2026-10-01",
  "handelszeiten": [ { "tage": ["Mo","Di","Mi","Do","Fr"], "beginn": "09:00", "ende": "11:30" },
                     { "tage": ["Mo","Di","Mi","Do","Fr"], "beginn": "12:30", "ende": "15:30" } ] }
"""

@Test func eigeneBoerseMitMittagspause() throws {
    let tokio = try Boerse.lade(json: json(eigeneBoerse))
    let uhr = try Boersenuhr.mitgeliefert(zusaetzlich: [tokio])
    #expect(uhr.boersen.last?.id == "tse")
    // 12:00 Tokio = 03:00 UTC, keine Sommerzeit
    let s = tokio.status(zeit("2026-10-07T03:00:00"))
    #expect(!s.offen)
    #expect(s.naechsterWechsel == zeit("2026-10-07T03:30:00"))
    #expect(s.datenGueltig)  // ohne datenGueltigBis keine Warnung
}

@Test func dateiUeberstehtRundreiseUnveraendert() throws {
    for b in try uhr().boersen {
        let zurueck = try Boerse.lade(json: JSONEncoder().encode(b))
        #expect(zurueck == b)
    }
}

@Test func fehlerhafteDateienWerdenAbgelehnt() throws {
    let basis = #"{ "format": 1, "id": "x", "name": "X", "stand": "2026-10-01", "#
    #expect(throws: BoersenuhrFehler.unbekannteZeitzone(id: "x", zeitzone: "Mond/Basis")) {
        try Boerse.lade(json: json(basis + #""zeitzone": "Mond/Basis", "durchgehend": true }"#))
    }
    #expect(throws: BoersenuhrFehler.unbekanntesFormat(id: "x", format: 2)) {
        try Boerse.lade(json: json(#"{ "format": 2, "id": "x", "name": "X", "stand": "2026-10-01", "zeitzone": "UTC", "durchgehend": true }"#))
    }
    #expect(throws: BoersenuhrFehler.keineHandelszeiten(id: "x")) {
        try Boerse.lade(json: json(basis + #""zeitzone": "UTC" }"#))
    }
    #expect(throws: BoersenuhrFehler.self) {
        try Boerse.lade(json: json(basis + #""zeitzone": "UTC", "handelszeiten": [ { "tage": ["Mo"], "beginn": "17:00", "ende": "09:00" } ] }"#))
    }
    #expect(throws: DecodingError.self) {
        try Boerse.lade(json: json(basis + #""zeitzone": "UTC", "durchgehend": true, "feiertage": [ { "datum": "2026-02-30", "name": "Falsch" } ] }"#))
    }
    #expect(throws: DecodingError.self) {
        try Boerse.lade(json: json(basis + #""zeitzone": "UTC", "handelszeiten": [ { "tage": ["Montag"], "beginn": "09:00", "ende": "17:00" } ] }"#))
    }
    let krypto = try boerse("krypto")
    #expect(throws: BoersenuhrFehler.doppelteBoerse(id: "krypto")) {
        try Boersenuhr(boersen: [krypto, krypto])
    }
}

@Test func grundtypenPruefenIhreWerte() throws {
    #expect(throws: BoersenuhrFehler.ungueltigesDatum("2027-02-29")) { try Kalendertag("2027-02-29") }
    #expect(try Kalendertag("2028-02-29").plus(tage: 1) == Kalendertag("2028-03-01"))
    #expect(try Kalendertag("2026-10-01").wochentag == .donnerstag)
    #expect(throws: BoersenuhrFehler.ungueltigeUhrzeit("24:00")) { try Uhrzeit("24:00") }
    #expect(try Uhrzeit("09:30") < Uhrzeit("16:00"))
}

// MARK: Freie Wahl (Tim, 01.10.2026)

@Test func auswahlZeigtNurGewaehlteBoersenInEigenerReihenfolge() throws {
    let auswahl = Boersenauswahl(angezeigt: ["krypto", "xetra", "gibtsnicht", "xetra"])
    #expect(try Boersenuhr.mit(auswahl).boersen.map(\.id) == ["krypto", "xetra"])
    #expect(try Boersenuhr.mit(Boersenauswahl()).boersen.count == 6)
}

@Test func angepassteZeitenBehaltenFeiertage() throws {
    let lang = Handelszeit(tage: [.montag, .dienstag, .mittwoch, .donnerstag, .freitag],
                           beginn: try Uhrzeit("08:00"), ende: try Uhrzeit("22:00"))
    let uhr = try Boersenuhr.mit(Boersenauswahl(angepassteZeiten: ["xetra": [lang]]))
    let x = try #require(uhr["xetra"])
    #expect(x.istOffen(zeit("2026-10-07T19:59:59")))                  // 21:59:59 Berlin
    #expect(!x.istOffen(zeit("2026-10-07T20:00:00")))
    #expect(x.status(zeit("2026-04-03T10:00:00")).feiertag == "Karfreitag")
    #expect(!x.istOffen(zeit("2026-04-03T10:00:00")))
    let nyseBeginn = try Uhrzeit("09:30")
    #expect(uhr["nyse"]?.handelszeiten.first?.beginn == nyseBeginn)   // andere unverändert
}

@Test func eigeneBoerseAusDemFormular() throws {
    let tokio = try Boerse.eigene(id: "tse", name: "Tokio", zeitzone: "Asia/Tokyo",
                                  beginn: Uhrzeit("09:00"), ende: Uhrzeit("15:30"), stand: Kalendertag("2026-10-01"))
    let auswahl = Boersenauswahl(angezeigt: ["tse", "xetra"], eigene: [tokio])
    let uhr = try Boersenuhr.mit(auswahl)
    #expect(uhr.boersen.map(\.id) == ["tse", "xetra"])
    #expect(uhr["tse"]?.istOffen(zeit("2026-10-07T01:00:00")) == true)   // 10:00 Tokio
    #expect(try Boersenuhr.verfuegbar(auswahl).boersen.count == 7)
}

@Test func auswahlUeberstehtSpeichernUndLaden() throws {
    let tokio = try Boerse.eigene(id: "tse", name: "Tokio", zeitzone: "Asia/Tokyo",
                                  beginn: Uhrzeit("09:00"), ende: Uhrzeit("15:30"), stand: Kalendertag("2026-10-01"))
    let lang = Handelszeit(tage: [.montag], beginn: try Uhrzeit("08:00"), ende: try Uhrzeit("22:00"))
    let auswahl = Boersenauswahl(angezeigt: ["tse"], angepassteZeiten: ["xetra": [lang]], eigene: [tokio])
    let zurueck = try JSONDecoder().decode(Boersenauswahl.self, from: JSONEncoder().encode(auswahl))
    #expect(zurueck == auswahl)
    #expect(try JSONDecoder().decode(Boersenauswahl.self, from: Data("{}".utf8)) == Boersenauswahl())
}

@Test func fehlerhafteAuswahlLegtDieUhrNichtLahm() throws {
    // Review 01.10.2026: Ein einzelner kaputter Eintrag darf nicht alle Anzeigen leeren.
    let verkehrt = Handelszeit(tage: [.montag], beginn: try Uhrzeit("17:00"), ende: try Uhrzeit("09:00"))
    let krypto = try boerse("krypto")
    var kaputt = try Boerse.eigene(id: "x", name: "X", zeitzone: "UTC", beginn: Uhrzeit("09:00"), ende: Uhrzeit("17:00"),
                                   stand: Kalendertag("2026-10-01"))
    kaputt.zeitzone = "Mond/Basis"
    let auswahl = Boersenauswahl(angepassteZeiten: ["xetra": [verkehrt]], eigene: [krypto, kaputt])
    let uhr = try Boersenuhr.mit(auswahl)
    #expect(uhr.boersen.map(\.id) == ["xetra", "nyse", "nasdaq", "lse", "forex", "krypto"])
    let neun = try Uhrzeit("09:00")
    #expect(uhr["xetra"]?.handelszeiten.first?.beginn == neun)   // Anpassung verworfen
    let probleme = try auswahl.probleme()
    #expect(probleme.count == 3)
    #expect(probleme.contains(.doppelteBoerse(id: "krypto")))
    #expect(probleme.contains(.unbekannteZeitzone(id: "x", zeitzone: "Mond/Basis")))
    #expect(try Boersenauswahl().probleme().isEmpty)
    // Auch eine nachträglich verbogene Zeitzone bringt die Uhr nicht zum Absturz.
    #expect(kaputt.timeZone.identifier == TimeZone(secondsFromGMT: 0)!.identifier)
    _ = kaputt.status(zeit("2026-10-07T12:00:00"))
}

// MARK: Eigene Feiertagskalender (Tim, 01.10.2026)

private let kalenderA = """
{ "format": 1, "id": "a", "name": "Kalender A", "land": "CH", "stand": "2026-10-01", "datenGueltigBis": "2026-12-31",
  "feiertage": [ { "datum": "2026-10-07", "name": "Testtag A" } ],
  "verkuerzteTage": [ { "datum": "2026-10-09", "ende": "12:00", "name": "Kurz A" } ] }
"""

private func zweiKalender() throws -> [Feiertagskalender] {
    let a = try Feiertagskalender.lade(json: json(kalenderA))
    let b = try Feiertagskalender(id: "b", name: "Kalender B",
                                  feiertage: [Feiertag(datum: Kalendertag("2026-10-08"), name: "Testtag B")],
                                  verkuerzteTage: [VerkuerzterTag(datum: Kalendertag("2026-10-09"), ende: Uhrzeit("13:00"), name: "Kurz B")],
                                  stand: Kalendertag("2026-10-01"))
    return [a, b]
}

@Test func mehrereKalenderGeltenZusaetzlich() throws {
    let auswahl = Boersenauswahl(kalender: try zweiKalender(), kalenderJeBoerse: ["xetra": ["a", "b", "geloescht"]])
    let uhr = try Boersenuhr.mit(auswahl)
    let x = try #require(uhr["xetra"])
    let s = x.status(zeit("2026-10-07T08:00:00"))
    #expect(!s.offen)
    #expect(s.feiertag == "Testtag A (Kalender A)")
    #expect(s.naechsterWechsel == zeit("2026-10-09T07:00:00"))       // 08.10. zu durch Kalender B
    #expect(s.verkuerzt == "Kurz A")                                  // frühester Schluss gewinnt
    #expect(x.naechsteSchliessung(nach: zeit("2026-10-09T08:00:00")) == zeit("2026-10-09T10:00:00"))
    #expect(x.istOffen(zeit("2026-04-03T10:00:00")) == false)          // eigene Feiertage bleiben
    let grenze = try Kalendertag("2026-12-31")
    #expect(x.datenGueltigBis == grenze)
    #expect(!x.status(zeit("2027-01-05T10:00:00")).datenGueltig)
    #expect(uhr["nyse"]?.istOffen(zeit("2026-10-07T14:00:00")) == true)  // ohne Zuordnung unberührt
}

@Test func feiertagSchlaegtVerkuerztenTag() throws {
    let kurz = try Feiertagskalender(id: "k", name: "K",
                                     feiertage: [],
                                     verkuerzteTage: [VerkuerzterTag(datum: Kalendertag("2026-04-03"), ende: Uhrzeit("12:00"), name: "Kurz")],
                                     stand: Kalendertag("2026-10-01"))
    let x = try boerse("xetra").mitKalendern([kurz])
    let karfreitag = try Kalendertag("2026-04-03")
    #expect(!x.verkuerzteTage.contains { $0.datum == karfreitag })
    #expect(x.status(zeit("2026-04-03T09:00:00")).feiertag == "Karfreitag")
}

@Test func kalenderAuchFuerEigeneBoerse() throws {
    let tokio = try Boerse.eigene(id: "tse", name: "Tokio", zeitzone: "Asia/Tokyo",
                                  beginn: Uhrzeit("09:00"), ende: Uhrzeit("15:30"), stand: Kalendertag("2026-10-01"))
    let auswahl = Boersenauswahl(angezeigt: ["tse"], eigene: [tokio], kalender: try zweiKalender(),
                                 kalenderJeBoerse: ["tse": ["b"]])
    let t = try #require(try Boersenuhr.mit(auswahl)["tse"])
    #expect(t.status(zeit("2026-10-08T01:00:00")).feiertag == "Testtag B (Kalender B)")
    #expect(t.datenGueltigBis == nil)
}

@Test func auswahlMitKalendernUeberstehtSpeichernUndLaden() throws {
    let auswahl = Boersenauswahl(kalender: try zweiKalender(), kalenderJeBoerse: ["lse": ["a"]])
    let zurueck = try JSONDecoder().decode(Boersenauswahl.self, from: JSONEncoder().encode(auswahl))
    #expect(zurueck == auswahl)
}

@Test func doppelteKalenderUndFalscheFormateWerdenAbgelehnt() throws {
    let a = try zweiKalender()[0]
    let doppelt = Boersenauswahl(kalender: [a, a], kalenderJeBoerse: ["xetra": ["a"]])
    #expect(try doppelt.probleme() == [.doppelterKalender(id: "a")])
    #expect(try Boersenuhr.mit(doppelt)["xetra"]?.status(zeit("2026-10-07T08:00:00")).feiertag == "Testtag A (Kalender A)")
    #expect(throws: BoersenuhrFehler.leereKennungOderName(id: "")) {
        try Feiertagskalender(id: "", name: "Leer", feiertage: [], stand: Kalendertag("2026-10-01"))
    }
    #expect(throws: BoersenuhrFehler.unbekanntesFormat(id: "z", format: 9)) {
        try Feiertagskalender.lade(json: json(#"{ "format": 9, "id": "z", "name": "Z", "stand": "2026-10-01" }"#))
    }
}

// MARK: Befunde aus dem Review (01.10.2026)

@Test func forexSchliesstAmFeiertagDesKalenders() throws {
    let weihnachten = try Feiertagskalender(id: "fx", name: "Forex-Broker",
                                            feiertage: [Feiertag(datum: Kalendertag("2026-12-25"), name: "Weihnachten")],
                                            stand: Kalendertag("2026-10-01"))
    let f = try boerse("forex").mitKalendern([weihnachten])
    // Die Sitzung Donnerstag 17:00 bis Freitag 17:00 New York gehört zum Freitag und entfällt.
    #expect(f.istOffen(zeit("2026-12-24T21:59:59")))
    #expect(!f.istOffen(zeit("2026-12-25T15:00:00")))
    #expect(f.naechsteSchliessung(nach: zeit("2026-12-24T12:00:00")) == zeit("2026-12-24T22:00:00"))
    #expect(f.naechsteOeffnung(nach: zeit("2026-12-25T15:00:00")) == zeit("2026-12-27T22:00:00"))
}

@Test func umstellungstageDerSommerzeit() throws {
    // EU zurück auf Winterzeit am 25.10.2026, USA erst am 01.11.2026.
    #expect(try boerse("xetra").naechsteOeffnung(nach: zeit("2026-10-25T12:00:00")) == zeit("2026-10-26T08:00:00"))
    #expect(try boerse("nyse").naechsteOeffnung(nach: zeit("2026-10-25T12:00:00")) == zeit("2026-10-26T13:30:00"))
    #expect(try boerse("forex").naechsteOeffnung(nach: zeit("2026-10-31T12:00:00")) == zeit("2026-11-01T22:00:00"))
    // EU auf Sommerzeit am 29.03.2026
    #expect(try boerse("xetra").naechsteOeffnung(nach: zeit("2026-03-28T12:00:00")) == zeit("2026-03-30T07:00:00"))
    #expect(try boerse("lse").naechsteOeffnung(nach: zeit("2026-06-30T20:00:00")) == zeit("2026-07-01T07:00:00"))
}

@Test func rundUmDieUhrUeberHandelszeitenMeldetKeineSchliessung() throws {
    let alleTage = Wochentag.allCases
    let b = try Boerse.eigene(id: "rund", name: "Rund", zeitzone: "Europe/Berlin", tage: alleTage,
                              beginn: Uhrzeit("00:00"), ende: Uhrzeit("00:00"), endeNachTagen: 1,
                              stand: Kalendertag("2026-10-01"))
    let s = b.status(zeit("2026-10-01T12:00:00"))
    #expect(s.offen)
    #expect(s.naechsterWechsel == nil)
    #expect(b.naechsteSchliessung(nach: zeit("2026-10-01T12:00:00")) == nil)
}

@Test func fruehesterSchlussGiltAuchInnerhalbEinerBoerse() throws {
    var x = try boerse("xetra")
    x.verkuerzteTage += [VerkuerzterTag(datum: try Kalendertag("2026-10-07"), ende: try Uhrzeit("15:00"), name: "Spät"),
                         VerkuerzterTag(datum: try Kalendertag("2026-10-07"), ende: try Uhrzeit("12:00"), name: "Früh")]
    #expect(x.naechsteSchliessung(nach: zeit("2026-10-07T08:00:00")) == zeit("2026-10-07T10:00:00"))
    // Reihenfolge der Einträge spielt keine Rolle
    x.verkuerzteTage.reverse()
    #expect(x.naechsteSchliessung(nach: zeit("2026-10-07T08:00:00")) == zeit("2026-10-07T10:00:00"))
}

@Test func leereKennungWirdAbgelehnt() throws {
    #expect(throws: BoersenuhrFehler.leereKennungOderName(id: " ")) {
        try Boerse.eigene(id: " ", name: "X", zeitzone: "UTC", beginn: Uhrzeit("09:00"), ende: Uhrzeit("17:00"),
                          stand: Kalendertag("2026-10-01"))
    }
}
