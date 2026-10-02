import Foundation
import Testing
@testable import TradingNews

let finanzenFeed = Feed(quelle: "finanzen.net", titel: "News",
                        adresse: URL(string: "https://www.finanzen.net/rss/news")!, bereich: .markt)

@Test func rssMitMindestabstandUndBedingtemAbruf() async {
    let laden = AufgezeichnetesLaden([
        "www.finanzen.net/rss/news": [
            Antwort(status: 200, kopf: ["ETag": "\"abc\"", "Last-Modified": "Tue, 29 Sep 2026 17:27:04 GMT"],
                    daten: Data(Beispiel.finanzenNet.utf8)),
            Antwort(status: 304)
        ]
    ])
    let abruf = Nachrichtenabruf(laden: laden, feeds: [finanzenFeed], budget: Abrufbudget(grenzeJeTag: 100, jetzt: jetzt))

    let erstes = await abruf.aktualisiere(begriffe: [], jetzt: jetzt)
    #expect(erstes.meldungen.map(\.titel) == ["DAX steigt etwas"])
    #expect(erstes.fehler.isEmpty)
    #expect(await laden.anfragen.first?.kopf["User-Agent"] == Nachrichtenabruf.kennung)

    // Fünf Minuten später: kein neuer Abruf.
    _ = await abruf.aktualisiere(begriffe: [], jetzt: jetzt.addingTimeInterval(5 * 60))
    #expect(await laden.anfragen.count == 1)

    // Zwanzig Minuten später: bedingter Abruf, 304 behält den Stand.
    let drittes = await abruf.aktualisiere(begriffe: [], jetzt: jetzt.addingTimeInterval(20 * 60))
    let anfragen = await laden.anfragen
    #expect(anfragen.count == 2)
    #expect(anfragen.last?.kopf["If-None-Match"] == "\"abc\"")
    #expect(anfragen.last?.kopf["If-Modified-Since"] == "Tue, 29 Sep 2026 17:27:04 GMT")
    #expect(drittes.meldungen.map(\.titel) == ["DAX steigt etwas"])
}

@Test func ausgefallenerFeedMeldetFehlerOhneAbbruch() async {
    let zweiter = Feed(quelle: "Börse Frankfurt", titel: "Nachrichten",
                       adresse: URL(string: "https://api.boerse-frankfurt.de/v1/feeds/news.rss")!, bereich: .markt)
    let laden = AufgezeichnetesLaden([
        "www.finanzen.net/rss/news": [Antwort(status: 503)],
        "api.boerse-frankfurt.de/v1/feeds/news.rss": [Antwort(status: 200, daten: Data(Beispiel.boerseFrankfurt.utf8))]
    ])
    let abruf = Nachrichtenabruf(laden: laden, feeds: [finanzenFeed, zweiter],
                                 budget: Abrufbudget(grenzeJeTag: 100, jetzt: jetzt))
    let ergebnis = await abruf.aktualisiere(begriffe: [], jetzt: jetzt)
    #expect(ergebnis.meldungen.map(\.titel) == ["Rohstoffe: Alles auf Gold"])
    #expect(ergebnis.fehler["finanzen.net News"] == "finanzen.net: Antwort 503")
}

@Test func alpacaNurMitSchluesselUndMitSymbolenDerMerkliste() async throws {
    let laden = AufgezeichnetesLaden([
        "data.alpaca.markets/v1beta1/news": [Antwort(status: 200, daten: Data(Beispiel.alpaca.utf8))]
    ])
    let abruf = Nachrichtenabruf(laden: laden, feeds: [],
                                 alpacaSchluessel: { AlpacaNewsSchluessel(schluesselID: "id", geheimnis: "geheim") },
                                 budget: Abrufbudget(grenzeJeTag: 100, jetzt: jetzt))
    let begriffe = [Merkbegriff(art: .symbol, text: "AAPL"), Merkbegriff(art: .name, text: "Apple")]
    let ergebnis = await abruf.aktualisiere(begriffe: begriffe, jetzt: jetzt)
    #expect(ergebnis.meldungen.first?.symbole == ["AAPL", "TSLA"])
    let anfrage = try #require(await laden.anfragen.first)
    #expect(parameter(anfrage)["symbols"] == "AAPL")

    // Ohne Schlüssel kein Abruf und kein Fehler.
    let ohne = AufgezeichnetesLaden([:])
    let abrufOhne = Nachrichtenabruf(laden: ohne, feeds: [], alpacaSchluessel: { nil },
                                     budget: Abrufbudget(grenzeJeTag: 100, jetzt: jetzt))
    let leer = await abrufOhne.aktualisiere(begriffe: begriffe, jetzt: jetzt)
    #expect(leer.meldungen.isEmpty)
    #expect(leer.fehler.isEmpty)
    #expect(await ohne.anfragen.isEmpty)
}

@Test func marketauxHaeltDasTagesbudget() async {
    let laden = AufgezeichnetesLaden([
        "api.marketaux.com/v1/news/all": [Antwort(status: 200, daten: Data(Beispiel.marketaux.utf8))]
    ])
    let abruf = Nachrichtenabruf(laden: laden, feeds: [], marketauxToken: { "geheimes-token" },
                                 budget: Abrufbudget(grenzeJeTag: 1, jetzt: jetzt))
    let begriffe = [Merkbegriff(art: .symbol, text: "TSLA"), Merkbegriff(art: .symbol, text: "SAP.DE"),
                    Merkbegriff(art: .isin, text: "DE0007164600")]
    let ergebnis = await abruf.aktualisiere(begriffe: begriffe, jetzt: jetzt)
    #expect(await laden.anfragen.count == 1)
    #expect(ergebnis.marketauxRest == 0)
    #expect(ergebnis.fehler["Marketaux"] == "Tagesgrenze von 1 Abrufen erreicht")
    #expect(ergebnis.meldungen.map(\.symbole) == [["TSLA"]])
    #expect(!ergebnis.fehler.values.contains { $0.contains("geheimes-token") })
}

@Test func marketauxFehlerTextOhneSchluessel() async {
    let laden = AufgezeichnetesLaden([
        "api.marketaux.com/v1/news/all": [Antwort(status: 402, daten: Data(Beispiel.marketauxFehler.utf8))]
    ])
    let abruf = Nachrichtenabruf(laden: laden, feeds: [], marketauxToken: { "geheimes-token" },
                                 budget: Abrufbudget(grenzeJeTag: 100, jetzt: jetzt))
    let ergebnis = await abruf.aktualisiere(begriffe: [Merkbegriff(art: .symbol, text: "TSLA")], jetzt: jetzt)
    #expect(ergebnis.fehler["Marketaux"] == "Marketaux usage_limit_reached: The usage limit for this account has been reached.")
    #expect(ergebnis.meldungen.isEmpty)
}

@Test func marketauxHTMLFehlerseiteZeigtStatus() async {
    let laden = AufgezeichnetesLaden([
        "api.marketaux.com/v1/news/all": [Antwort(status: 401, daten: Data("<html>nein</html>".utf8))]
    ])
    let abruf = Nachrichtenabruf(laden: laden, feeds: [], marketauxToken: { "t" },
                                 budget: Abrufbudget(grenzeJeTag: 100, jetzt: jetzt))
    let ergebnis = await abruf.aktualisiere(begriffe: [Merkbegriff(art: .symbol, text: "TSLA")], jetzt: jetzt)
    #expect(ergebnis.fehler["Marketaux"] == "Marketaux: Zugang abgelehnt (401), Schlüssel prüfen")
}
