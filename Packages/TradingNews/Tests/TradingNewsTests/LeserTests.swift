import Foundation
import Testing
@testable import TradingNews

// MARK: Zeit und Text

@Test func zeitRFC822MitVersatzUndGMT() {
    #expect(Zeitleser.lies("Tue, 29 Sep 2026 19:25:00 +0200") == zeit("2026-09-29T17:25:00Z"))
    #expect(Zeitleser.lies("Thu, 01 Oct 2026 07:35:04 GMT") == zeit("2026-10-01T07:35:04Z"))
    #expect(Zeitleser.lies("quatsch") == nil)
    #expect(Zeitleser.lies("") == nil)
}

@Test func zeitISOMitSechsNachkommastellen() {
    let mitMikro = Zeitleser.lies("2024-11-08T01:24:00.000000Z")
    let ohne = Zeitleser.lies("2024-11-08T01:24:00Z")
    #expect(mitMikro != nil)
    #expect(mitMikro == ohne)
    #expect(Zeitleser.lies("2026-10-02T06:00:00.5Z") == zeit("2026-10-02T06:00:00Z").addingTimeInterval(0.5))
}

@Test func marketauxZeitOhneZone() {
    #expect(Zeitleser.utcOhneZone(zeit("2026-10-01T06:00:00Z")) == "2026-10-01T06:00:00")
}

@Test func anrissOhneHTMLMitEntitaeten() {
    #expect(Text.anriss("<p>Der <b>DAX</b> &amp; SAP&#8209;Aktie &auml;ndert&nbsp;sich.</p>")
            == "Der DAX & SAP\u{2011}Aktie ändert sich.")
    #expect(Text.anriss("   ") == nil)
    #expect(Text.anriss(nil) == nil)
    #expect(Text.entitaetenAufgeloest("A & B &unbekannt; &#x41;") == "A & B &unbekannt; A")
}

@Test func anrissWirdAnWortgrenzeGekuerzt() throws {
    let lang = String(repeating: "wort ", count: 100)
    let anriss = try #require(Text.anriss(lang))
    #expect(anriss.hasSuffix("wort…"))
    #expect(anriss.count <= Text.anrissLaenge + 1)
}

// MARK: RSS

@Test func rssWieFinanzenNet() throws {
    let meldungen = RSSLeser.lies(Data(Beispiel.finanzenNet.utf8), quelle: "finanzen.net", jetzt: jetzt)
    // „Ohne Link“ und der Eintrag ohne Überschrift fallen weg.
    #expect(meldungen.count == 1)
    let m = try #require(meldungen.first)
    #expect(m.titel == "DAX steigt etwas")
    #expect(m.anriss == "Der DAX legte zu & SAP gewann. mehr")
    #expect(m.link.absoluteString == "https://www.finanzen.net/nachricht/aktien/dax-aktuell-1")
    #expect(m.zeit == zeit("2026-09-29T17:25:00Z"))
    #expect(m.quelle == "finanzen.net")
    #expect(m.herkunft == .rss)
    #expect(m.symbole.isEmpty)
    #expect(m.id == "https://finanzen.net/nachricht/aktien/dax-aktuell-1")
}

@Test func rssWieBoerseFrankfurtMitMedien() throws {
    let meldungen = RSSLeser.lies(Data(Beispiel.boerseFrankfurt.utf8), quelle: "Börse Frankfurt", jetzt: jetzt)
    let m = try #require(meldungen.first)
    #expect(meldungen.count == 1)
    #expect(m.titel == "Rohstoffe: Alles auf Gold")
    #expect(m.anriss == "Die starken Bewegungen an den Rohstoffmärkten setzen sich fort.")
    #expect(m.zeit == zeit("2026-10-01T07:35:04Z"))
}

@Test func atomOhneVolltext() throws {
    let meldungen = RSSLeser.lies(Data(Beispiel.atom.utf8), quelle: "Beispiel", jetzt: jetzt)
    let m = try #require(meldungen.first)
    #expect(m.titel == "Zinsen & Anleihen")
    #expect(m.link.absoluteString == "https://example.org/zinsen")
    #expect(m.anriss == "Kurz eingeordnet.")
    #expect(m.zeit == zeit("2026-10-02T06:00:00Z"))
}

@Test func kaputtesXMLLiefertNichtsOderDieVollstaendigenEintraege() {
    #expect(RSSLeser.lies(Data("kein xml".utf8), quelle: "x", jetzt: jetzt).isEmpty)
    let abgebrochen = """
    <rss><channel><item><title>Eins</title><link>https://example.org/1</link></item><item><title>Zw
    """
    let meldungen = RSSLeser.lies(Data(abgebrochen.utf8), quelle: "x", jetzt: jetzt)
    #expect(meldungen.map(\.titel) == ["Eins"])
    #expect(meldungen.first?.zeit == jetzt)
}

// MARK: Alpaca

@Test func alpacaAnfrageMitSymbolenOhneVolltext() {
    let schluessel = AlpacaNewsSchluessel(schluesselID: "id-123", geheimnis: "geheim-456")
    let anfrage = AlpacaNews.anfrage(symbole: ["aapl", "TSLA", ""], seit: zeit("2026-10-01T00:00:00Z"),
                                     limit: 80, schluessel: schluessel)
    #expect(anfrage.url.host == "data.alpaca.markets")
    #expect(anfrage.url.path == "/v1beta1/news")
    let p = parameter(anfrage)
    #expect(p["symbols"] == "AAPL,TSLA")
    #expect(p["limit"] == "50")
    #expect(p["include_content"] == "false")
    #expect(p["sort"] == "desc")
    #expect(p["start"] == "2026-10-01T00:00:00Z")
    #expect(anfrage.kopf["APCA-API-KEY-ID"] == "id-123")
    #expect(anfrage.kopf["APCA-API-SECRET-KEY"] == "geheim-456")
    #expect(!"\(anfrage)".contains("geheim"))
    #expect("\(schluessel)" == "AlpacaNewsSchluessel(***)")
}

@Test func alpacaOhneSymboleHoltAllgemeineNachrichten() {
    let anfrage = AlpacaNews.anfrage(symbole: [], seit: nil,
                                     schluessel: AlpacaNewsSchluessel(schluesselID: "a", geheimnis: "b"))
    #expect(parameter(anfrage)["symbols"] == nil)
    #expect(parameter(anfrage)["start"] == nil)
}

@Test func alpacaAntwortLesen() throws {
    let seite = try AlpacaNews.lies(Data(Beispiel.alpaca.utf8), jetzt: jetzt)
    #expect(seite.naechsteSeite == "MTY0MjAwNDM1Njc1NjAwMDAwMHwyNDg0MzE3MQ==")
    let m = try #require(seite.meldungen.first)
    #expect(m.titel == "Apple & Tesla rally")
    #expect(m.anriss == "Shares rose.")
    #expect(m.quelle == "Benzinga")
    #expect(m.symbole == ["AAPL", "TSLA"])
    #expect(m.zeit == zeit("2026-10-01T16:19:16Z"))
    #expect(m.herkunft == .alpaca)
}

// MARK: Marketaux

@Test func marketauxAnfrageSymbol() throws {
    let anfrage = try #require(Marketaux.anfrage(fuer: Merkbegriff(art: .symbol, text: "sap.de"), token: "tok",
                                                 seit: zeit("2026-10-01T06:00:00Z")))
    #expect(anfrage.url.host == "api.marketaux.com")
    #expect(anfrage.url.path == "/v1/news/all")
    let p = parameter(anfrage)
    #expect(p["symbols"] == "SAP.DE")
    #expect(p["filter_entities"] == "true")
    #expect(p["language"] == "de,en")
    #expect(p["limit"] == "3")
    #expect(p["api_token"] == "tok")
    #expect(p["published_after"] == "2026-10-01T06:00:00")
    #expect(!"\(anfrage)".contains("tok"))
}

@Test func marketauxAnfrageStichwortMitUnd() throws {
    let anfrage = try #require(Marketaux.anfrage(fuer: Merkbegriff(art: .stichwort, text: "Nvidia Zölle"),
                                                 token: "tok", seit: nil))
    #expect(parameter(anfrage)["search"] == "Nvidia + Zölle")
    let roh = URLComponents(url: anfrage.url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
    #expect(roh.contains("%2B"))
    #expect(!roh.contains("+"))
}

@Test func marketauxAnfrageNameUndISIN() throws {
    let name = try #require(Marketaux.anfrage(fuer: Merkbegriff(art: .name, text: "Deutsche Bank"), token: "t", seit: nil))
    #expect(parameter(name)["search"] == "\"Deutsche Bank\"")
    #expect(Marketaux.anfrage(fuer: Merkbegriff(art: .isin, text: "DE0005140008"), token: "t", seit: nil) == nil)
    #expect(Marketaux.anfrage(fuer: Merkbegriff(art: .symbol, text: "  "), token: "t", seit: nil) == nil)
}

@Test func marketauxSuchtIndexCFDsUeberDenNamen() throws {
    let anfrage = try #require(Marketaux.anfrage(fuer: Merkbegriff(art: .symbol, text: "US500.cash"), token: "t", seit: nil))
    let p = parameter(anfrage)
    #expect(p["search"] == "\"s&p 500\"")
    #expect(p["symbols"] == nil)
    #expect(p["filter_entities"] == nil)
    let roh = URLComponents(url: anfrage.url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
    #expect(roh.contains("%26"))
}

@Test func marketauxAntwortAusDerDoku() throws {
    let meldungen = try Marketaux.lies(Data(Beispiel.marketaux.utf8), jetzt: jetzt)
    let m = try #require(meldungen.first)
    #expect(m.titel == "Trump wins 2024, markets surge globally")
    #expect(m.anriss == "Global markets experience a significant surge following Trump's victory")
    #expect(m.quelle == "killerstartups.com")
    #expect(m.symbole == ["TSLA"])
    #expect(m.zeit == zeit("2024-11-08T01:24:00Z"))
    #expect(m.herkunft == .marketaux)
}

@Test func marketauxFehlerWirdGeworfen() {
    #expect(throws: Marketaux.Fehler(code: "usage_limit_reached",
                                     nachricht: "The usage limit for this account has been reached.")) {
        try Marketaux.lies(Data(Beispiel.marketauxFehler.utf8), jetzt: jetzt)
    }
}
