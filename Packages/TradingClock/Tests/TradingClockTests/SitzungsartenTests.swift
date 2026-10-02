import Foundation
import Testing
@testable import TradingClock

/// Sitzungsarten und Nasdaq-Nacht ab 06.12.2026 (Nasdaq-FAQ 2026). Sollwerte in UTC mit Python zoneinfo
/// gerechnet (02.10.2026); New York ist im Dezember und Januar UTC−5, Ende November ebenfalls.
private func zeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    return formatter.date(from: iso + "Z")!
}

private func nasdaq(_ arten: Set<Sitzungsart> = Set(Sitzungsart.allCases)) throws -> Boerse {
    try #require(try Boersenuhr.mitgeliefert()["nasdaq"]).mitSitzungsarten(arten)
}

@Test func standardRechnetNurKernhandel() throws {
    let b = try #require(try Boersenuhr.mitgeliefert()["nasdaq"])
    #expect(b.sitzungsarten == [.kern])
    // Di 08.12.2026 07:00 New York: vorbörslich, aber nicht zugeschaltet
    #expect(!b.istOffen(zeit("2026-12-08T12:00:00")))
    #expect(b.naechsteOeffnung(nach: zeit("2026-12-08T12:00:00")) == zeit("2026-12-08T14:30:00"))
}

@Test func verfuegbareSitzungsarten() throws {
    let uhr = try Boersenuhr.mitgeliefert()
    #expect(try #require(uhr["nasdaq"]).verfuegbareSitzungsarten == [.kern, .vorboerslich, .nachboerslich, .nacht])
    #expect(try #require(uhr["xetra"]).verfuegbareSitzungsarten == [.kern])
    #expect(try nasdaq([]).sitzungsarten == [.kern])   // leer heißt Kernhandel
}

@Test func nachtBeginntSonntag06Dezember() throws {
    let b = try nasdaq([.kern, .nacht])
    // So 06.12.2026 21:30 New York, Nacht bis Mo 04:00
    let s = b.status(zeit("2026-12-07T02:30:00"))
    #expect(s.offen)
    #expect(s.naechsterWechsel == zeit("2026-12-07T09:00:00"))
    #expect(b.sitzungsart(bei: zeit("2026-12-07T02:30:00")) == .nacht)
    // Eine Woche vorher gilt die Nacht noch nicht: So 29.11. 21:30 geschlossen, nächste Öffnung Mo 09:30
    #expect(!b.istOffen(zeit("2026-11-30T02:30:00")))
    #expect(b.naechsteOeffnung(nach: zeit("2026-11-30T02:30:00")) == zeit("2026-11-30T14:30:00"))
}

@Test func alleSitzungenVerschmelzenBisZurPause() throws {
    let b = try nasdaq()
    // Di 08.12.2026 07:00 New York: vorbörslich; durchgehend seit Mo 21:00 bis Di 20:00
    #expect(b.sitzungsart(bei: zeit("2026-12-08T12:00:00")) == .vorboerslich)
    #expect(b.naechsteSchliessung(nach: zeit("2026-12-08T12:00:00")) == zeit("2026-12-09T01:00:00"))
    #expect(b.sitzungsart(bei: zeit("2026-12-08T15:00:00")) == .kern)
    #expect(b.sitzungsart(bei: zeit("2026-12-08T22:00:00")) == .nachboerslich)
    // Pause 20:00 bis 21:00
    #expect(b.sitzungsart(bei: zeit("2026-12-09T01:30:00")) == nil)
    #expect(b.naechsteOeffnung(nach: zeit("2026-12-09T01:30:00")) == zeit("2026-12-09T02:00:00"))
}

@Test func wocheEndetFreitag20UhrUndBeginntSonntag21Uhr() throws {
    let b = try nasdaq()
    // Fr 11.12.2026 19:00 New York: nachbörslich bis 20:00, dann erst wieder So 13.12. 21:00
    #expect(b.naechsteSchliessung(nach: zeit("2026-12-12T00:00:00")) == zeit("2026-12-12T01:00:00"))
    #expect(b.naechsteOeffnung(nach: zeit("2026-12-12T00:00:00")) == zeit("2026-12-14T02:00:00"))
}

@Test func feiertageNachNasdaqRegel() throws {
    let b = try nasdaq()
    // Do 24.12.2026 verkürzt bis 13:00, Nacht auf Fr 25.12. (Feiertag) entfällt, weiter So 27.12. 21:00
    #expect(b.naechsteSchliessung(nach: zeit("2026-12-24T17:00:00")) == zeit("2026-12-24T18:00:00"))
    #expect(b.naechsteOeffnung(nach: zeit("2026-12-24T17:00:00")) == zeit("2026-12-28T02:00:00"))
    // Mo 18.01.2027 (Feiertag): geschlossen, Nacht beginnt am Abend des Feiertags um 21:00
    let s = b.status(zeit("2027-01-18T12:00:00"))
    #expect(!s.offen)
    #expect(s.feiertag != nil)
    #expect(s.naechsterWechsel == zeit("2027-01-19T02:00:00"))
}

@Test func verkuerzterTagOhneNachboerseUndNachtErstAb06Dezember() throws {
    let b = try nasdaq()
    // Fr 27.11.2026 13:30 New York: Schluss war 13:00, nachbörslich entfällt (Annahme), Nacht gilt noch nicht
    #expect(!b.istOffen(zeit("2026-11-27T18:30:00")))
    #expect(b.naechsteOeffnung(nach: zeit("2026-11-27T18:30:00")) == zeit("2026-11-30T09:00:00"))
}

@Test func auswahlSpeichertSitzungsartenUndUeberspringtUnbekannte() throws {
    let json = Data(#"{ "sitzungsartenJeBoerse": { "nasdaq": ["kern", "nacht", "mond"] } }"#.utf8)
    let auswahl = try JSONDecoder().decode(Boersenauswahl.self, from: json)
    #expect(auswahl.sitzungsartenJeBoerse["nasdaq"] == [.kern, .nacht])
    let uhr = try Boersenuhr.mit(auswahl)
    #expect(uhr["nasdaq"]?.sitzungsarten == [.kern, .nacht])
    #expect(uhr["nyse"]?.sitzungsarten == [.kern])
    let zurueck = try JSONDecoder().decode(Boersenauswahl.self, from: JSONEncoder().encode(auswahl))
    #expect(zurueck == auswahl)
}

@Test func handelszeitMitArtUndGueltigAbUeberstehtJSON() throws {
    let h = Handelszeit(tage: [.sonntag], beginn: try Uhrzeit("21:00"), ende: try Uhrzeit("04:00"), endeNachTagen: 1,
                        art: .nacht, gueltigAb: try Kalendertag("2026-12-06"))
    let zurueck = try JSONDecoder().decode(Handelszeit.self, from: JSONEncoder().encode(h))
    #expect(zurueck == h)
    let alt = try JSONDecoder().decode(Handelszeit.self, from: Data(#"{ "tage": ["Mo"], "beginn": "09:00", "ende": "17:00" }"#.utf8))
    #expect(alt.art == .kern && alt.gueltigAb == nil)
}
