import Foundation
import Testing
@testable import TradingQuotes

/// Nachrichten aus den Beispielen der Anbieter-Dokus (gelesen 02.10.2026) oder, wo die Doku kein
/// vollständiges Beispiel hat, synthetisch nach ihrem Schema. Kein Netz.
func zeit(_ iso: String) -> Date { Zeitstempel.lies(iso)! }
func d(_ text: String) -> Decimal { Decimal(string: text)! }
let empfangen = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: Kraken

@Test func krakenAboText() {
    let text = KrakenLeser(symbole: ["BTC/EUR"]).start()
    #expect(text == [#"{"method":"subscribe","params":{"channel":"ticker","symbol":["BTC/EUR"]}}"#])
}

@Test func krakenSnapshotAusDerDoku() throws {
    var leser = KrakenLeser(symbole: ["ALGO/USD"])
    let nachricht = #"{"channel":"ticker","type":"snapshot","data":[{"symbol":"ALGO/USD","bid":0.10025,"bid_qty":740.0,"ask":0.10036,"ask_qty":1361.44813783,"last":0.10035,"volume":997038.98383185,"vwap":0.10148,"low":0.09979,"high":0.10285,"change":-0.00017,"change_pct":-0.17,"timestamp":"2023-09-25T09:04:31.742648Z"}]}"#
    let kursLesung = leser.lies(nachricht, empfangen: empfangen)
    let kurs = try #require(kursLesung.kurse.first)
    #expect(kurs.symbol == "ALGO/USD")
    #expect(kurs.geld == d("0.10025"))
    #expect(kurs.brief == d("0.10036"))
    #expect(kurs.letzter == d("0.10035"))
    #expect(kurs.zeit == zeit("2023-09-25T09:04:31.742Z"))
    #expect(kurs.quelle == "kraken")
}

@Test func krakenStatusUndHerzschlagErgebenNichts() {
    var leser = KrakenLeser(symbole: ["BTC/EUR"])
    let status = #"{"channel":"status","type":"update","data":[{"api_version":"v2","connection_id":1,"system":"online","version":"2.0.0"}]}"#
    let herzschlag = #"{"channel":"heartbeat"}"#
    let bestaetigung = #"{"method":"subscribe","result":{"channel":"ticker","symbol":"BTC/EUR"},"success":true}"#
    for text in [status, herzschlag, bestaetigung, "kein json"] {
        let lesung = leser.lies(text, empfangen: empfangen)
        #expect(lesung == Lesung())
    }
}

// MARK: Coinbase

@Test func coinbaseAboMitHerzschlag() {
    let text = CoinbaseLeser(symbole: ["BTC-EUR"]).start()
    #expect(text == [#"{"channel":"ticker","product_ids":["BTC-EUR"],"type":"subscribe"}"#,
                     #"{"channel":"heartbeats","product_ids":["BTC-EUR"],"type":"subscribe"}"#])
}

@Test func coinbaseTickerNachSchema() throws {
    var leser = CoinbaseLeser(symbole: ["BTC-EUR"])
    // Synthetisch nach dem Schema der Doku (Preise als Text, Zeit mit neun Nachkommastellen).
    let nachricht = #"{"channel":"ticker","client_id":"","timestamp":"2026-10-02T08:15:01.123456789Z","sequence_num":3,"events":[{"type":"update","tickers":[{"type":"ticker","product_id":"BTC-EUR","price":"58123.45","volume_24_h":"1234.5","best_bid":"58123.40","best_bid_quantity":"0.1","best_ask":"58123.50","best_ask_quantity":"0.2"}]}]}"#
    let kursLesung = leser.lies(nachricht, empfangen: empfangen)
    let kurs = try #require(kursLesung.kurse.first)
    #expect(kurs.symbol == "BTC-EUR")
    #expect(kurs.letzter == d("58123.45"))
    #expect(kurs.geld == d("58123.40"))
    #expect(kurs.brief == d("58123.50"))
    #expect(kurs.zeit == zeit("2026-10-02T08:15:01.123Z"))
}

@Test func coinbaseFehlerBeendet() {
    var leser = CoinbaseLeser(symbole: ["XYZ-EUR"])
    let lesung = leser.lies(#"{"type":"error","message":"Failed to subscribe"}"#, empfangen: empfangen)
    #expect(lesung.abbruch == "Coinbase: Failed to subscribe")
}

// MARK: Binance

@Test func binanceAdresseMitStroemen() {
    let url = BinanceLeser.adresse(["BTCEUR", "ETHEUR"])
    #expect(url.absoluteString == "wss://data-stream.binance.vision/stream?streams=btceur@ticker/etheur@ticker")
}

@Test func binanceTickerAusDerDoku() throws {
    var leser = BinanceLeser()
    let daten = #"{"e":"24hrTicker","E":1672515782136,"s":"BNBBTC","p":"0.0015","P":"250.00","w":"0.0018","x":"0.0009","c":"0.0025","Q":"10","b":"0.0024","B":"10","a":"0.0026","A":"100","o":"0.0010","h":"0.0025","l":"0.0010","v":"10000","q":"18","O":0,"C":1675216573749,"F":0,"L":18150,"n":18151}"#
    let kursLesung = leser.lies(#"{"stream":"bnbbtc@ticker","data":"# + daten + "}", empfangen: empfangen)
    let kurs = try #require(kursLesung.kurse.first)
    #expect(kurs.symbol == "BNBBTC")
    #expect(kurs.letzter == d("0.0025"))
    #expect(kurs.geld == d("0.0024"))
    #expect(kurs.brief == d("0.0026"))
    #expect(kurs.zeit == Date(timeIntervalSince1970: 1_672_515_782.136))
}

// MARK: Alpaca

let testSchluessel = AlpacaSchluessel(schluesselID: "TEST-ID", geheimnis: "TEST-GEHEIM")

@Test func alpacaMeldetSichNachConnectedAnUndAbonniertNachAuthenticated() {
    var leser = AlpacaLeser(symbole: ["AAPL"], schluessel: testSchluessel)
    #expect(leser.start().isEmpty)
    let anmeldung = leser.lies(#"[{"T":"success","msg":"connected"}]"#, empfangen: empfangen)
    #expect(anmeldung.senden == [#"{"action":"auth","key":"TEST-ID","secret":"TEST-GEHEIM"}"#])
    let abo = leser.lies(#"[{"T":"success","msg":"authenticated"}]"#, empfangen: empfangen)
    #expect(abo.senden == [#"{"action":"subscribe","quotes":["AAPL"],"trades":["AAPL"]}"#])
}

@Test func alpacaFuehrtAbschlussUndKursblattZusammen() throws {
    var leser = AlpacaLeser(symbole: ["AAPL"], schluessel: testSchluessel)
    let abschluss = #"[{"T":"t","S":"AAPL","i":96921,"x":"D","p":126.55,"s":1,"c":["@","I"],"t":"2021-02-22T15:51:44.208Z","z":"C"}]"#
    let blatt = #"[{"T":"q","S":"AAPL","bx":"U","bp":126.54,"bs":1,"ax":"Q","ap":126.56,"as":4,"t":"2021-02-22T15:51:45.335689322Z","c":["R"],"z":"C"}]"#
    let ersterLesung = leser.lies(abschluss, empfangen: empfangen)
    let erster = try #require(ersterLesung.kurse.first)
    #expect(erster.letzter == d("126.55"))
    #expect(erster.geld == nil)
    let zweiterLesung = leser.lies(blatt, empfangen: empfangen)
    let zweiter = try #require(zweiterLesung.kurse.first)
    #expect(zweiter.letzter == d("126.55"))
    #expect(zweiter.geld == d("126.54"))
    #expect(zweiter.brief == d("126.56"))
    #expect(zweiter.zeit == zeit("2021-02-22T15:51:45.335Z"))
}

@Test func alpacaFehlerCodes() {
    var leser = AlpacaLeser(symbole: ["AAPL"], schluessel: testSchluessel)
    let falsch = leser.lies(#"[{"T":"error","code":402,"msg":"auth failed"}]"#, empfangen: empfangen)
    #expect(falsch.abbruch == "Alpaca 402: auth failed")
    let langsam = leser.lies(#"[{"T":"error","code":407,"msg":"slow client"}]"#, empfangen: empfangen)
    #expect(langsam.abbruch == nil)
}

@Test func alpacaSchluesselErscheintNieImText() {
    #expect("\(testSchluessel)" == "AlpacaSchluessel(***)")
}

// MARK: Hilfen

@Test func zeitstempelMitNeunNachkommastellen() {
    #expect(Zeitstempel.lies("2021-02-22T15:51:45.335689322Z") == Zeitstempel.lies("2021-02-22T15:51:45.335Z"))
    #expect(Zeitstempel.lies("2021-02-22T15:51:45Z") != nil)
    #expect(Zeitstempel.lies("2021-02-22T15:51:45.5+01:00") == Zeitstempel.lies("2021-02-22T14:51:45.500Z"))
}
