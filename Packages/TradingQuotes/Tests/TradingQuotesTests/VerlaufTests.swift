import Foundation
import Testing
@testable import TradingQuotes

/// Tageskerzen (Paket A1, Doc 38). Antworten aus den Doku-Beispielen (gelesen 02.10.2026) oder nach ihrem Schema.
/// Kein Netz: Abrufe gehen an eine aufgezeichnete Antwortliste.
actor Abrufmitschnitt {
    var anfragen: [Abrufanfrage] = []
    var antworten: [(status: Int, daten: Data)]
    init(_ antworten: [(Int, String)]) { self.antworten = antworten.map { (status: $0.0, daten: Data($0.1.utf8)) } }
    func naechste(_ anfrage: Abrufanfrage) -> (status: Int, daten: Data) {
        anfragen.append(anfrage)
        return antworten.isEmpty ? (500, Data()) : antworten.removeFirst()
    }
}

func testabruf(_ mitschnitt: Abrufmitschnitt) -> Abruf {
    { anfrage in await mitschnitt.naechste(anfrage) }
}

struct MitSchluessel: AlpacaSchluesselquelle {
    func alpacaSchluessel() async throws -> AlpacaSchluessel? { testSchluessel }
}

let tag0 = Date(timeIntervalSince1970: 1_700_006_400)   // 2023-11-15 00:00 UTC
let krakenDoku = #"{"error":[],"result":{"XXBTZUSD":[[1688671200,"30306.1","30306.2","30305.7","30305.7","30306.1","3.39243896",23]],"last":1688672160}}"#

// MARK: Kraken

@Test func krakenVerlaufAnfrage() {
    let anfrage = KrakenVerlauf.anfrage("BTC/EUR", seit: Date(timeIntervalSince1970: 1_700_000_000))
    #expect(anfrage.url.absoluteString
            == "https://api.kraken.com/0/public/OHLC?pair=BTC/EUR&interval=1440&since=1700000000&assetVersion=1")
    #expect(anfrage.kopf.isEmpty)
}

@Test func krakenVerlaufAusDerDoku() throws {
    let kerzen = try KrakenVerlauf.lies(Data(krakenDoku.utf8), seit: .distantPast, jetzt: empfangen)
    let kerze = try #require(kerzen.first)
    #expect(kerzen.count == 1)
    #expect(kerze.zeit == Date(timeIntervalSince1970: 1_688_671_200))
    #expect(kerze.eroeffnung == d("30306.1"))
    #expect(kerze.hoch == d("30306.2"))
    #expect(kerze.tief == d("30305.7"))
    #expect(kerze.schluss == d("30305.7"))
    #expect(kerze.volumen == d("3.39243896"))
    #expect(kerze.abgeschlossen)
}

@Test func krakenVerlaufSortiertUndMarkiertDenLaufendenTag() throws {
    let text = #"{"error":[],"result":{"BTC/EUR":[[1700092800,"2","3","1","2.5","2","10",5],[1700006400,"1","2","0.5","1.5","1","9",4]],"last":1700006400}}"#
    let jetzt = Date(timeIntervalSince1970: 1_700_100_000)
    let kerzen = try KrakenVerlauf.lies(Data(text.utf8), seit: tag0, jetzt: jetzt)
    #expect(kerzen.map(\.zeit) == [tag0, tag0.addingTimeInterval(86_400)])
    #expect(kerzen.map(\.abgeschlossen) == [true, false])
}

@Test func krakenVerlaufFehlerUndKaputteAntwort() {
    let fehler = #"{"error":["EQuery:Unknown asset pair"]}"#
    #expect(throws: Verlaufsfehler.anbieter("Kraken: EQuery:Unknown asset pair")) {
        try KrakenVerlauf.lies(Data(fehler.utf8), seit: .distantPast, jetzt: empfangen)
    }
    #expect(throws: Verlaufsfehler.format) {
        try KrakenVerlauf.lies(Data("kein json".utf8), seit: .distantPast, jetzt: empfangen)
    }
}

// MARK: Alpaca

@Test func alpacaVerlaufAnfrageMitSchluesselImKopf() {
    let anfrage = AlpacaVerlauf.anfrage("AAPL", seit: empfangen, seite: "abc", schluessel: testSchluessel)
    #expect(anfrage.url.absoluteString == "https://data.alpaca.markets/v2/stocks/AAPL/bars?timeframe=1Day"
            + "&start=2027-01-15&feed=iex&adjustment=split&limit=10000&page_token=abc")
    #expect(anfrage.kopf == ["APCA-API-KEY-ID": "TEST-ID", "APCA-API-SECRET-KEY": "TEST-GEHEIM"])
}

@Test func alpacaVerlaufLiestListeUndObjektJeSymbol() throws {
    let liste = #"{"bars":[{"t":"2024-01-15T05:00:00Z","o":150.25,"h":151.8,"l":150.1,"c":151.5,"v":2500000,"n":15000,"vw":150.95}],"symbol":"AAPL","next_page_token":"seite2"}"#
    let jeSymbol = #"{"bars":{"AAPL":[{"t":"2024-01-15T05:00:00Z","o":150.25,"h":151.8,"l":150.1,"c":151.5,"v":2500000}]},"next_page_token":null}"#
    let erste = try AlpacaVerlauf.lies(Data(liste.utf8), symbol: "AAPL", jetzt: empfangen)
    let zweite = try AlpacaVerlauf.lies(Data(jeSymbol.utf8), symbol: "AAPL", jetzt: empfangen)
    #expect(erste.weiter == "seite2")
    #expect(zweite.weiter == nil)
    #expect(erste.kerzen == zweite.kerzen)
    let kerze = try #require(erste.kerzen.first)
    #expect(kerze.zeit == zeit("2024-01-15T05:00:00Z"))
    #expect(kerze.schluss == d("151.5"))
    #expect(kerze.volumen == d("2500000"))
}

@Test func alpacaVerlaufBlaettertWeiter() async throws {
    let seite1 = #"{"bars":[{"t":"2024-01-16T05:00:00Z","o":2,"h":2,"l":2,"c":2}],"next_page_token":"x"}"#
    let seite2 = #"{"bars":[{"t":"2024-01-15T05:00:00Z","o":1,"h":1,"l":1,"c":1}],"next_page_token":null}"#
    let mitschnitt = Abrufmitschnitt([(200, seite1), (200, seite2)])
    let quelle = Kursverlaeufe.alpaca(schluessel: MitSchluessel(), abruf: testabruf(mitschnitt))
    let kerzen = try await quelle.tageskerzen("AAPL", seit: tag0, jetzt: empfangen)
    #expect(kerzen.map(\.schluss) == [1, 2])
    let anfragen = await mitschnitt.anfragen
    #expect(anfragen.count == 2)
    #expect(anfragen.last?.url.query?.hasSuffix("page_token=x") == true)
}

@Test func alpacaVerlaufFehler() async {
    let ohne = Kursverlaeufe.alpaca(schluessel: OhneSchluessel(), abruf: testabruf(Abrufmitschnitt([])))
    await #expect(throws: Verlaufsfehler.schluesselFehlt) {
        try await ohne.tageskerzen("AAPL", seit: tag0, jetzt: empfangen)
    }
    let verboten = Abrufmitschnitt([(403, #"{"message":"forbidden."}"#)])
    let quelle = Kursverlaeufe.alpaca(schluessel: MitSchluessel(), abruf: testabruf(verboten))
    await #expect(throws: Verlaufsfehler.anbieter("Alpaca 403: forbidden.")) {
        try await quelle.tageskerzen("AAPL", seit: tag0, jetzt: empfangen)
    }
}

// MARK: Lader und Speicher

@Test func laderTeiltAbrufeUndBehaeltAltenVerlaufBeiFehler() async {
    let kraken = #"{"error":[],"result":{"BTC/EUR":[[1799884800,"1","2","0.5","1.5","1","9",4]]}}"#
    let mitschnitt = Abrufmitschnitt([(200, kraken), (502, "")])
    let pausen = Mitschnitt()
    let lader = Verlaufslader(quellen: [Kursverlaeufe.kraken(abruf: testabruf(mitschnitt))],
                              warte: { _ in await pausen.neueVerbindung() })
    let alt = Kursverlauf(journalSymbol: "ETH", quelle: "kraken", quellSymbol: "ETH/EUR", kerzen: [], geladen: tag0)
    let bisher = Verlaufsstand(verlaeufe: ["ETH": alt], fehler: [:], geladen: tag0)
    let zuordnungen = [Kurszuordnung(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/EUR"),
                       Kurszuordnung(journalSymbol: "btcusd", quelle: "kraken", quellSymbol: "BTC/EUR", naeherung: "N"),
                       Kurszuordnung(journalSymbol: "ETH", quelle: "kraken", quellSymbol: "ETH/EUR"),
                       Kurszuordnung(journalSymbol: "X", quelle: "unbekannt", quellSymbol: "X")]
    let stand = await lader.lade(zuordnungen, bisher: bisher, jetzt: empfangen)
    let abrufe = await mitschnitt.anfragen.count
    let pausenzahl = await pausen.verbindungen
    #expect(abrufe == 2)
    #expect(pausenzahl == 1)
    #expect(stand.verlaeufe["BTC"]?.kerzen.count == 1)
    #expect(stand.verlaeufe["btcusd"]?.naeherung == "N")
    #expect(stand.verlaeufe["ETH"] == alt)
    #expect(stand.fehler["ETH"] == "HTTP 502")
    #expect(stand.fehler["X"] != nil)
    #expect(stand.istAktuell(fuer: ["BTC", "ETH", "X"], jetzt: empfangen.addingTimeInterval(3600)))
    #expect(!stand.istAktuell(fuer: ["BTC", "SOL"], jetzt: empfangen))
    #expect(!stand.istAktuell(fuer: ["BTC"], jetzt: empfangen.addingTimeInterval(21 * 3600)))
}

@Test func speicherSchreibtPreiseAlsTextUndLiestSieZurueck() throws {
    let kerze = Tageskerze(zeit: tag0, eroeffnung: d("0.1"), hoch: d("58123.45"), tief: d("0.000001"),
                           schluss: d("1.5"), volumen: nil, abgeschlossen: false)
    let verlauf = Kursverlauf(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/EUR",
                              kerzen: [kerze], geladen: tag0)
    let stand = Verlaufsstand(verlaeufe: ["BTC": verlauf], fehler: ["X": "HTTP 502"], geladen: tag0)
    let datei = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent("kursverlaeufe.json")
    let speicher = Verlaufsspeicher(datei: datei)
    #expect(speicher.lies() == nil)
    try speicher.schreibe(stand)
    #expect(speicher.lies() == stand)
    let text = try String(contentsOf: datei, encoding: .utf8)
    #expect(text.contains(#""hoch":"58123.45""#))
    try? FileManager.default.removeItem(at: datei.deletingLastPathComponent())
}

@Test func handelstagUndWaehrungFuerDenExport() {
    let kraken = Tageskerze(zeit: tag0, eroeffnung: 1, hoch: 1, tief: 1, schluss: 1)
    let alpaca = Tageskerze(zeit: zeit("2024-01-15T05:00:00Z"), eroeffnung: 1, hoch: 1, tief: 1, schluss: 1)
    #expect(kraken.handelstag == "2023-11-15")
    #expect(alpaca.handelstag == "2024-01-15")
    func verlauf(_ quelle: String, _ symbol: String) -> Kursverlauf {
        Kursverlauf(journalSymbol: symbol, quelle: quelle, quellSymbol: symbol, kerzen: [], geladen: tag0)
    }
    #expect(verlauf("kraken", "BTC/USDT").waehrung == "USDT")
    #expect(verlauf("alpaca", "AAPL").waehrung == "USD")
    #expect(verlauf("kraken", "BTCEUR").waehrung == nil)
}
