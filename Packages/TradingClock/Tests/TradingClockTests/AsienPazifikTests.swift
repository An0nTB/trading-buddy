import Foundation
import Testing
@testable import TradingClock

/// TradingClock 0.5.0 (Wunsch Tim 05.10.2026): Asien-Pazifik und weitere Börsen. Sollwerte in UTC mit Python
/// zoneinfo gerechnet und gegen exchange_calendars 4.13.2 geprüft (05.10.2026). Ortszeiten ohne Sommerzeit
/// außer Sydney (ab 04.10.2026 UTC+11, im Juni UTC+10), Paris und Zürich (UTC+2 bis 25.10.2026), Toronto (UTC−4).
private func zeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    return formatter.date(from: iso + "Z")!
}

private func boerse(_ id: String) throws -> Boerse { try #require(try Boersenuhr.mitgeliefert()[id]) }

private struct Neue {
    let id: String
    let mic: String
    let name: String
    let zone: String
    let gueltigBis: String
}

private let neue: [Neue] = [
    Neue(id: "xtks", mic: "XTKS", name: "Tokio", zone: "Asia/Tokyo", gueltigBis: "2027-12-31"),
    Neue(id: "xhkg", mic: "XHKG", name: "Hongkong", zone: "Asia/Hong_Kong", gueltigBis: "2027-12-31"),
    Neue(id: "xshg", mic: "XSHG", name: "Shanghai", zone: "Asia/Shanghai", gueltigBis: "2026-12-31"),
    Neue(id: "xses", mic: "XSES", name: "Singapur", zone: "Asia/Singapore", gueltigBis: "2026-12-31"),
    Neue(id: "xkrx", mic: "XKRX", name: "Seoul", zone: "Asia/Seoul", gueltigBis: "2027-12-31"),
    Neue(id: "xtai", mic: "XTAI", name: "Taipeh", zone: "Asia/Taipei", gueltigBis: "2027-12-31"),
    Neue(id: "xbom", mic: "XBOM", name: "Mumbai (BSE)", zone: "Asia/Kolkata", gueltigBis: "2026-12-31"),
    Neue(id: "xasx", mic: "XASX", name: "Sydney (ASX)", zone: "Australia/Sydney", gueltigBis: "2027-12-31"),
    Neue(id: "xpar", mic: "XPAR", name: "Euronext Paris", zone: "Europe/Paris", gueltigBis: "2027-12-31"),
    Neue(id: "xswx", mic: "XSWX", name: "SIX Swiss Exchange", zone: "Europe/Zurich", gueltigBis: "2027-12-31"),
    Neue(id: "xtse", mic: "XTSE", name: "Toronto (TSX)", zone: "America/Toronto", gueltigBis: "2027-12-31"),
    Neue(id: "bvmf", mic: "BVMF", name: "São Paulo (B3)", zone: "America/Sao_Paulo", gueltigBis: "2027-12-31")
]

// MARK: Laden und Standardanzeige

@Test func neueBoersenLadenMitQuelleUndZeitraum() throws {
    let uhr = try Boersenuhr.mitgeliefert()
    #expect(uhr.boersen.count == 18)
    let abgerufen = try Kalendertag("2026-10-05")
    for e in neue {
        let b = try #require(uhr[e.id], "\(e.id)")
        let bis = try Kalendertag(e.gueltigBis)
        #expect(b.mic == e.mic, "\(e.id)")
        #expect(b.name == e.name, "\(e.id)")
        #expect(b.zeitzone == e.zone, "\(e.id)")
        #expect(b.datenGueltigBis == bis, "\(e.id)")
        #expect(b.quellen.first?.abgerufen == abgerufen, "\(e.id)")
        #expect(b.feiertage.contains { $0.datum.jahr == 2026 }, "\(e.id)")
        #expect(b.verfuegbareSitzungsarten == [.kern], "\(e.id)")
    }
}

@Test func neueBoersenErscheinenNurAufWunsch() throws {
    #expect(try Boersenuhr.mit(Boersenauswahl()).boersen.map(\.id) == Boersenuhr.standardAngezeigt)
    #expect(try Boersenuhr.verfuegbar().boersen.map(\.id) == Boersenuhr.standardReihenfolge)
    let gewaehlt = Boersenauswahl(angezeigt: ["xtks", "xetra", "xhkg"])
    #expect(try Boersenuhr.mit(gewaehlt).boersen.map(\.id) == ["xtks", "xetra", "xhkg"])
    // Eigene Börsen bleiben ohne Auswahl sichtbar wie bisher.
    let eigene = try Boerse.eigene(id: "meine", name: "Meine", zeitzone: "UTC",
                                   beginn: Uhrzeit("09:00"), ende: Uhrzeit("17:00"), stand: Kalendertag("2026-10-05"))
    let mitEigener = try Boersenuhr.mit(Boersenauswahl(eigene: [eigene])).boersen.map(\.id)
    #expect(mitEigener == Boersenuhr.standardAngezeigt + ["meine"])
}

// MARK: Je Börse ein gewöhnlicher Tag und ein Feiertag

private struct Tagesfall {
    let id: String
    let beginn: String
    let ende: String
    let sitzungen: Int
    let mitternacht: String
}

/// Mittwoch 14.10.2026: erster Beginn und letztes Ende in UTC, Zahl der Sitzungen, Ortsmitternacht in UTC.
private let tagesfaelle: [Tagesfall] = [
    Tagesfall(id: "xtks", beginn: "2026-10-14T00:00:00", ende: "2026-10-14T06:30:00", sitzungen: 2, mitternacht: "2026-10-13T15:00:00"),
    Tagesfall(id: "xhkg", beginn: "2026-10-14T01:30:00", ende: "2026-10-14T08:00:00", sitzungen: 2, mitternacht: "2026-10-13T16:00:00"),
    Tagesfall(id: "xshg", beginn: "2026-10-14T01:30:00", ende: "2026-10-14T07:00:00", sitzungen: 2, mitternacht: "2026-10-13T16:00:00"),
    Tagesfall(id: "xses", beginn: "2026-10-14T01:00:00", ende: "2026-10-14T09:00:00", sitzungen: 1, mitternacht: "2026-10-13T16:00:00"),
    Tagesfall(id: "xkrx", beginn: "2026-10-14T00:00:00", ende: "2026-10-14T06:30:00", sitzungen: 1, mitternacht: "2026-10-13T15:00:00"),
    Tagesfall(id: "xtai", beginn: "2026-10-14T01:00:00", ende: "2026-10-14T05:30:00", sitzungen: 1, mitternacht: "2026-10-13T16:00:00"),
    Tagesfall(id: "xbom", beginn: "2026-10-14T03:45:00", ende: "2026-10-14T10:00:00", sitzungen: 1, mitternacht: "2026-10-13T18:30:00"),
    Tagesfall(id: "xasx", beginn: "2026-10-13T23:00:00", ende: "2026-10-14T05:00:00", sitzungen: 1, mitternacht: "2026-10-13T13:00:00"),
    Tagesfall(id: "xpar", beginn: "2026-10-14T07:00:00", ende: "2026-10-14T15:30:00", sitzungen: 1, mitternacht: "2026-10-13T22:00:00"),
    Tagesfall(id: "xswx", beginn: "2026-10-14T07:00:00", ende: "2026-10-14T15:30:00", sitzungen: 1, mitternacht: "2026-10-13T22:00:00"),
    Tagesfall(id: "xtse", beginn: "2026-10-14T13:30:00", ende: "2026-10-14T20:00:00", sitzungen: 1, mitternacht: "2026-10-14T04:00:00"),
    Tagesfall(id: "bvmf", beginn: "2026-10-14T13:00:00", ende: "2026-10-14T21:00:00", sitzungen: 1, mitternacht: "2026-10-14T03:00:00")
]

@Test func neueBoersenOeffnenUndSchliessenAufDieSekunde() throws {
    let uhr = try Boersenuhr.mitgeliefert()
    for fall in tagesfaelle {
        let b = try #require(uhr[fall.id], "\(fall.id)")
        let beginn = zeit(fall.beginn)
        let ende = zeit(fall.ende)
        #expect(!b.istOffen(beginn.addingTimeInterval(-1)), "\(fall.id)")
        #expect(b.istOffen(beginn), "\(fall.id)")
        #expect(b.istOffen(ende.addingTimeInterval(-1)), "\(fall.id)")
        #expect(!b.istOffen(ende), "\(fall.id)")
        let tag = zeit(fall.mitternacht)
        let liste = b.sitzungen(von: tag, bis: tag.addingTimeInterval(86_400))
        #expect(liste.count == fall.sitzungen, "\(fall.id)")
        #expect(liste.first?.beginn == beginn, "\(fall.id)")
        #expect(liste.last?.ende == ende, "\(fall.id)")
    }
}

private struct Feiertagsfall {
    let id: String
    let zeitpunkt: String
    let name: String
    let naechsteOeffnung: String
}

private let feiertagsfaelle: [Feiertagsfall] = [
    Feiertagsfall(id: "xtks", zeitpunkt: "2026-11-03T01:00:00", name: "Culture Day", naechsteOeffnung: "2026-11-04T00:00:00"),
    Feiertagsfall(id: "xhkg", zeitpunkt: "2026-02-18T02:00:00", name: "Chinesisches Neujahr", naechsteOeffnung: "2026-02-20T01:30:00"),
    Feiertagsfall(id: "xshg", zeitpunkt: "2026-10-05T02:00:00", name: "Nationalfeiertag", naechsteOeffnung: "2026-10-08T01:30:00"),
    Feiertagsfall(id: "xses", zeitpunkt: "2026-05-27T02:00:00", name: "Hari Raya Haji", naechsteOeffnung: "2026-05-28T01:00:00"),
    Feiertagsfall(id: "xkrx", zeitpunkt: "2026-09-25T01:00:00", name: "Chuseok", naechsteOeffnung: "2026-09-28T00:00:00"),
    Feiertagsfall(id: "xtai", zeitpunkt: "2026-10-09T02:00:00", name: "National Day (Ersatztag)", naechsteOeffnung: "2026-10-12T01:00:00"),
    Feiertagsfall(id: "xbom", zeitpunkt: "2026-11-10T05:00:00", name: "Diwali Balipratipada", naechsteOeffnung: "2026-11-11T03:45:00"),
    Feiertagsfall(id: "xasx", zeitpunkt: "2026-06-08T01:00:00", name: "King's Birthday", naechsteOeffnung: "2026-06-09T00:00:00"),
    Feiertagsfall(id: "xpar", zeitpunkt: "2026-05-01T09:00:00", name: "Labour Day", naechsteOeffnung: "2026-05-04T07:00:00"),
    Feiertagsfall(id: "xswx", zeitpunkt: "2026-05-14T08:00:00", name: "Ascension Day", naechsteOeffnung: "2026-05-15T07:00:00"),
    Feiertagsfall(id: "xtse", zeitpunkt: "2026-10-12T15:00:00", name: "Thanksgiving", naechsteOeffnung: "2026-10-13T13:30:00"),
    Feiertagsfall(id: "bvmf", zeitpunkt: "2026-04-21T15:00:00", name: "Tiradentes", naechsteOeffnung: "2026-04-22T13:00:00")
]

@Test func jedeNeueBoerseSchliesstAnEinemFeiertag() throws {
    let uhr = try Boersenuhr.mitgeliefert()
    for fall in feiertagsfaelle {
        let b = try #require(uhr[fall.id], "\(fall.id)")
        let s = b.status(zeit(fall.zeitpunkt))
        #expect(!s.offen, "\(fall.id)")
        #expect(s.feiertag == fall.name, "\(fall.id)")
        #expect(s.naechsterWechsel == zeit(fall.naechsteOeffnung), "\(fall.id)")
        #expect(s.datenGueltig, "\(fall.id)")
    }
}

// MARK: Mittagspause

@Test func tokioInDerMittagspauseGeschlossen() throws {
    let t = try boerse("xtks")
    // 12:00 Tokio: Pause 11:30 bis 12:30
    let s = t.status(zeit("2026-10-14T03:00:00"))
    #expect(!s.offen)
    #expect(s.naechsterWechsel == zeit("2026-10-14T03:30:00"))
    #expect(s.feiertag == nil)
    #expect(t.istOffen(zeit("2026-10-14T02:29:59")))
    #expect(!t.istOffen(zeit("2026-10-14T02:30:00")))
    #expect(!t.istOffen(zeit("2026-10-14T03:29:59")))
    #expect(t.istOffen(zeit("2026-10-14T03:30:00")))
    #expect(t.naechsteSchliessung(nach: zeit("2026-10-14T01:00:00")) == zeit("2026-10-14T02:30:00"))
    #expect(t.naechsteOeffnung(nach: zeit("2026-10-14T02:30:00")) == zeit("2026-10-14T03:30:00"))
    // In der Pause ist die nächste Schließung das Ende des Nachmittags (15:30 seit 05.11.2024).
    #expect(t.naechsteSchliessung(nach: zeit("2026-10-14T03:00:00")) == zeit("2026-10-14T06:30:00"))
    #expect(t.sitzungsart(bei: zeit("2026-10-14T01:00:00")) == .kern)
    #expect(t.sitzungsart(bei: zeit("2026-10-14T03:00:00")) == nil)
}

@Test func tokioNachDerGoldenWeek2027() throws {
    // 29.04. Showa, 03. bis 05.05. Feiertage; Freitag 30.04. offen, dann Wochenende
    let t = try boerse("xtks")
    #expect(t.istOffen(zeit("2027-04-30T01:00:00")))
    #expect(t.naechsteOeffnung(nach: zeit("2027-04-30T07:00:00")) == zeit("2027-05-06T00:00:00"))
}

@Test func hongkongMittagspauseUndNachmittag() throws {
    let h = try boerse("xhkg")
    let pause = h.status(zeit("2026-10-14T04:30:00"))   // 12:30 Hongkong
    #expect(!pause.offen)
    #expect(pause.naechsterWechsel == zeit("2026-10-14T05:00:00"))
    let nachmittag = h.status(zeit("2026-10-14T06:00:00"))
    #expect(nachmittag.offen)
    #expect(nachmittag.naechsterWechsel == zeit("2026-10-14T08:00:00"))
}

@Test func hongkongHalberTagOhneNachmittag() throws {
    let h = try boerse("xhkg")
    // Heiligabend 2026: Schluss 12:00, kein Nachmittag; 25.12. Feiertag, dann Wochenende
    let s = h.status(zeit("2026-12-24T02:00:00"))
    #expect(s.offen)
    #expect(s.naechsterWechsel == zeit("2026-12-24T04:00:00"))
    #expect(s.verkuerzt == "Christmas Eve")
    let tag = h.sitzungen(von: zeit("2026-12-23T16:00:00"), bis: zeit("2026-12-24T16:00:00"))
    #expect(tag.count == 1)
    #expect(!h.istOffen(zeit("2026-12-24T05:30:00")))
    #expect(h.naechsteOeffnung(nach: zeit("2026-12-24T04:00:00")) == zeit("2026-12-28T01:30:00"))
}

@Test func hongkongChinesischesNeujahr2027() throws {
    let h = try boerse("xhkg")
    let s = h.status(zeit("2027-02-05T02:00:00"))
    #expect(s.verkuerzt == "Vorabend des Chinesischen Neujahrs")
    #expect(s.naechsterWechsel == zeit("2027-02-05T04:00:00"))
    #expect(h.naechsteOeffnung(nach: zeit("2027-02-05T04:00:00")) == zeit("2027-02-10T01:30:00"))
}

@Test func shanghaiMittagspauseUndFruehlingsfest() throws {
    let s = try boerse("xshg")
    let pause = s.status(zeit("2026-10-14T04:00:00"))   // 12:00 Shanghai, Pause 11:30 bis 13:00
    #expect(!pause.offen)
    #expect(pause.naechsterWechsel == zeit("2026-10-14T05:00:00"))
    #expect(s.naechsteSchliessung(nach: zeit("2026-10-14T02:00:00")) == zeit("2026-10-14T03:30:00"))
    // Frühlingsfest 16. bis 23.02.2026
    #expect(s.naechsteOeffnung(nach: zeit("2026-02-13T07:00:00")) == zeit("2026-02-24T01:30:00"))
}

@Test func shanghaiWarntNachDemGepflegtenJahr() throws {
    // exchange_calendars führt Shanghai, Singapur und Mumbai nur bis Ende 2026.
    let s = try boerse("xshg").status(zeit("2026-12-31T07:30:00"))
    #expect(!s.offen)
    #expect(!s.datenGueltig)
}

@Test func ohneMittagspauseMittagsOffen() throws {
    // Singapur, Seoul und Taipeh handeln durch: 12:30 Ortszeit ist offen.
    #expect(try boerse("xses").istOffen(zeit("2026-10-14T04:30:00")))
    #expect(try boerse("xkrx").istOffen(zeit("2026-10-14T03:30:00")))
    #expect(try boerse("xtai").istOffen(zeit("2026-10-14T04:30:00")))
    #expect(try boerse("xses").handelszeiten.count == 1)
}

// MARK: Verkürzte Tage und Feiertagsblöcke

@Test func seoulSeollal2027UndErsatztag() throws {
    let k = try boerse("xkrx")
    #expect(k.naechsteOeffnung(nach: zeit("2027-02-05T06:30:00")) == zeit("2027-02-10T00:00:00"))
    let s = k.status(zeit("2026-10-05T01:00:00"))
    #expect(s.feiertag == "National Foundation Day (Ersatztag)")
    #expect(s.naechsterWechsel == zeit("2026-10-06T00:00:00"))
}

@Test func sydneyUndParisSchliessenHeiligabendFrueher() throws {
    let a = try boerse("xasx")
    let s = a.status(zeit("2026-12-24T01:00:00"))   // 12:00 Sydney, Sommerzeit UTC+11
    #expect(s.offen)
    #expect(s.naechsterWechsel == zeit("2026-12-24T03:10:00"))
    #expect(s.verkuerzt == "Last Trading Day Before Christmas")
    // 25.12. Weihnachten, 28.12. Ersatztag für den Boxing Day
    #expect(a.naechsteOeffnung(nach: zeit("2026-12-24T03:10:00")) == zeit("2026-12-28T23:00:00"))
    let p = try boerse("xpar").status(zeit("2026-12-24T12:00:00"))
    #expect(p.naechsterWechsel == zeit("2026-12-24T13:05:00"))
    #expect(p.verkuerzt == "Christmas Eve")
}
