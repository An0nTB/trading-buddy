import Foundation
import Testing
import TradingCore
@testable import TradingQuotes

/// Minutenkerzen (Paket B2, Doc 39). Antworten nach dem Schema der Doku (gelesen 02.10.2026), ohne Netz.
let minute0 = Date(timeIntervalSince1970: 1_799_937_000)   // 2027-01-14 14:30 UTC

func minute(_ n: Int) -> Date { minute0.addingTimeInterval(Double(n) * 60) }

func binanceZeile(_ n: Int, _ close: String = "100.5") -> String {
    let ms = Int64(minute(n).timeIntervalSince1970) * 1000
    return #"[\#(ms),"100.1","101.0","99.5","\#(close)","12.3",\#(ms + 59_999),"1234.5",10,"1.0","2.0","0"]"#
}

func minutenkerze(_ n: Int, close: Decimal = 100) -> Zeitkerze {
    Zeitkerze(beginn: minute(n), dauer: 60, open: 100, high: 101, low: 99, close: close)
}

/// Quelle mit fester Kerzenliste; merkt sich das angefragte Fenster.
actor Fenstermitschnitt {
    var fenster: [(von: Date, bis: Date)] = []
    func merke(_ von: Date, _ bis: Date) { fenster.append((von, bis)) }
}

struct FesteMinuten: Minutenquelle {
    let id: String
    let kerzen: [Zeitkerze]
    let mitschnitt: Fenstermitschnitt
    func minutenkerzen(_ quellSymbol: String, von: Date, bis: Date) async throws -> [Zeitkerze] {
        await mitschnitt.merke(von, bis)
        return kerzen
    }
}

// MARK: Binance

@Test func binanceMinutenAnfrage() {
    let anfrage = BinanceMinuten.anfrage("btceur", von: minute(0), bis: minute(10))
    #expect(anfrage.url.absoluteString == "https://data-api.binance.vision/api/v3/klines?symbol=BTCEUR&interval=1m"
            + "&startTime=1799937000000&endTime=1799937599999&limit=1000")
    #expect(anfrage.kopf.isEmpty)
}

@Test func binanceMinutenLiestZeilen() throws {
    let kerzen = try BinanceMinuten.lies(Data(("[" + binanceZeile(0) + "," + binanceZeile(1, "100.75") + "]").utf8))
    #expect(kerzen == [Zeitkerze(beginn: minute(0), dauer: 60, open: d("100.1"), high: 101, low: d("99.5"), close: d("100.5")),
                       Zeitkerze(beginn: minute(1), dauer: 60, open: d("100.1"), high: 101, low: d("99.5"), close: d("100.75"))])
    #expect(throws: Verlaufsfehler.format) { try BinanceMinuten.lies(Data(#"{"x":1}"#.utf8)) }
}

@Test func binanceMinutenBlaettertNachTausendKerzen() async throws {
    let voll = "[" + (0..<1_000).map { binanceZeile($0) }.joined(separator: ",") + "]"
    let rest = "[" + binanceZeile(1_000) + "," + binanceZeile(1_001) + "]"
    let mitschnitt = Abrufmitschnitt([(200, voll), (200, rest)])
    let quelle = BinanceMinuten(abruf: testabruf(mitschnitt))
    let kerzen = try await quelle.minutenkerzen("BTCEUR", von: minute(0), bis: minute(1_100))
    #expect(kerzen.count == 1_002)
    let anfragen = await mitschnitt.anfragen
    #expect(anfragen.count == 2)
    #expect(anfragen.last?.url.absoluteString.contains("startTime=1799997000000") == true)
}

@Test func binanceMinutenFehler() async {
    let mitschnitt = Abrufmitschnitt([(400, #"{"code":-1121,"msg":"Invalid symbol."}"#), (503, "")])
    let quelle = BinanceMinuten(abruf: testabruf(mitschnitt))
    await #expect(throws: Verlaufsfehler.anbieter("Binance 400: Invalid symbol.")) {
        try await quelle.minutenkerzen("XYZEUR", von: minute(0), bis: minute(5))
    }
    await #expect(throws: Verlaufsfehler.http(503)) {
        try await quelle.minutenkerzen("BTCEUR", von: minute(0), bis: minute(5))
    }
}

// MARK: Alpaca

@Test func alpacaMinutenAnfrageUndSeiten() async throws {
    let seite1 = #"{"bars":[{"t":"2027-01-14T14:31:00Z","o":200.5,"h":201,"l":200,"c":200.75,"v":300}],"symbol":"AAPL","next_page_token":"abc"}"#
    let seite2 = #"{"bars":{"AAPL":[{"t":"2027-01-14T14:30:00Z","o":200,"h":200.5,"l":199.5,"c":200.5,"v":100}]},"next_page_token":null}"#
    let mitschnitt = Abrufmitschnitt([(200, seite1), (200, seite2)])
    let quelle = AlpacaMinuten(schluessel: MitSchluessel(), abruf: testabruf(mitschnitt))
    let kerzen = try await quelle.minutenkerzen("AAPL", von: minute(0), bis: minute(60))
    #expect(kerzen.map(\.beginn) == [minute(0), minute(1)])
    #expect(kerzen.last?.close == d("200.75"))
    #expect(kerzen.allSatisfy { $0.dauer == 60 })
    let anfragen = await mitschnitt.anfragen
    #expect(anfragen.first?.url.absoluteString == "https://data.alpaca.markets/v2/stocks/AAPL/bars?timeframe=1Min"
            + "&start=2027-01-14T14:30:00Z&end=2027-01-14T15:30:00Z&feed=iex&adjustment=raw&limit=10000")
    #expect(anfragen.last?.url.absoluteString.hasSuffix("&page_token=abc") == true)
    #expect(anfragen.first?.kopf["APCA-API-KEY-ID"] != nil)
}

@Test func alpacaMinutenOhneSchluesselUndMitFehler() async {
    let ohne = AlpacaMinuten(schluessel: OhneSchluessel(), abruf: testabruf(Abrufmitschnitt([])))
    await #expect(throws: Verlaufsfehler.schluesselFehlt) {
        try await ohne.minutenkerzen("AAPL", von: minute(0), bis: minute(5))
    }
    let mitschnitt = Abrufmitschnitt([(403, #"{"message":"forbidden"}"#)])
    let quelle = AlpacaMinuten(schluessel: MitSchluessel(), abruf: testabruf(mitschnitt))
    await #expect(throws: Verlaufsfehler.anbieter("Alpaca 403: forbidden")) {
        try await quelle.minutenkerzen("AAPL", von: minute(0), bis: minute(5))
    }
}

// MARK: Lader

@Test func minutenladerSchneidetZuUndLaesstLaufendeKerzenWeg() async throws {
    let mitschnitt = Fenstermitschnitt()
    let kerzen = [minutenkerze(3), minutenkerze(-1), minutenkerze(1, close: 99), minutenkerze(1, close: 102),
                  minutenkerze(10), minutenkerze(8)]
    let lader = Minutenlader(quellen: [FesteMinuten(id: "binance", kerzen: kerzen, mitschnitt: mitschnitt)])
    let z = Kurszuordnung(journalSymbol: "BTC/EUR", quelle: "binance", quellSymbol: "BTCEUR")
    // Jetzt ist 14:38:30: Die Kerze ab 14:38 läuft noch, das Fenster reicht bis 14:40.
    let geladen = try await lader.lade(z, von: minute(0), bis: minute(10), jetzt: minute(8).addingTimeInterval(30))
    #expect(geladen.map(\.beginn) == [minute(1), minute(3)])
    #expect(geladen.first?.close == 102)
    let fenster = await mitschnitt.fenster
    #expect(fenster.first?.bis == minute(8).addingTimeInterval(30))
}

@Test func minutenladerGrenzen() async throws {
    let mitschnitt = Fenstermitschnitt()
    let lader = Minutenlader(quellen: [FesteMinuten(id: "alpaca", kerzen: [], mitschnitt: mitschnitt)])
    let aapl = Kurszuordnung(journalSymbol: "AAPL.US", quelle: "alpaca", quellSymbol: "AAPL")
    let leer = try await lader.lade(aapl, von: minute(10), bis: minute(0), jetzt: minute(100))
    #expect(leer.isEmpty)
    let zukunft = try await lader.lade(aapl, von: minute(200), bis: minute(300), jetzt: minute(100))
    #expect(zukunft.isEmpty)
    let abgefragt = await mitschnitt.fenster
    #expect(abgefragt.isEmpty)
    await #expect(throws: Verlaufsfehler.anbieter("Zeitfenster länger als 31 Tage")) {
        try await lader.lade(aapl, von: minute(0), bis: minute(32 * 1_440), jetzt: minute(40 * 1_440))
    }
    let kraken = Kurszuordnung(journalSymbol: "BTC/EUR", quelle: "kraken", quellSymbol: "BTC/EUR")
    await #expect(throws: Verlaufsfehler.anbieter("Für kraken gibt es keine Minutenkerzen.")) {
        try await lader.lade(kraken, von: minute(0), bis: minute(5), jetzt: minute(100))
    }
}

@Test func minutenfensterUmEinenTrade() throws {
    let trade = Trade(id: "t1", symbol: "BTC/EUR", side: .buy, lots: 1, openTime: minute(0).addingTimeInterval(30),
                      closeTime: minute(5).addingTimeInterval(20), openPrice: 100, closePrice: 101, profit: 1)
    let fenster = try #require(Minutenlader.fenster(trade))
    #expect(fenster.von == minute(-1))
    #expect(fenster.bis == minute(66))
    var ohneUhrzeit = trade
    ohneUhrzeit.nurDatum = true
    #expect(Minutenlader.fenster(ohneUhrzeit) == nil)
}

@Test func minutenzuordnung() {
    #expect(Minutenlader.zuordnung(fuer: "BTC/EUR")
            == Kurszuordnung(journalSymbol: "BTC/EUR", quelle: "binance", quellSymbol: "BTCEUR"))
    #expect(Minutenlader.zuordnung(fuer: "ETH")?.quellSymbol == "ETHEUR")
    #expect(Minutenlader.zuordnung(fuer: "AAPL.US")
            == Kurszuordnung(journalSymbol: "AAPL.US", quelle: "alpaca", quellSymbol: "AAPL"))
    let cfd = Minutenlader.zuordnung(fuer: "btcusd")
    #expect(cfd?.quellSymbol == "BTCUSDT")
    #expect(cfd?.naeherung == "Krypto-CFD des Brokers, Kurs von Binance als Näherung. Kurs in USDT statt USD (Binance führt kein USD).")
    #expect(Minutenlader.zuordnung(fuer: "de40") == nil)
    #expect(Minutenlader.zuordnung(fuer: "US0378331005") == nil)
    let coinbase = Kurszuordnung(journalSymbol: "ETH-EUR", quelle: "coinbase", quellSymbol: "ETH-EUR")
    #expect(Minutenlader.zuordnung(aus: coinbase)?.quellSymbol == "ETHEUR")
    #expect(Minutenlader.zuordnung(aus: Kurszuordnung(journalSymbol: "X", quelle: "eigen", quellSymbol: "X")) == nil)
}
