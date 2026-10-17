import Foundation
import Testing
@testable import TradingQuotes

private func zuordnung(_ symbol: String) -> Kurszuordnung? {
    if case .zuordnung(let z) = Kurszuordner.vorschlag(fuer: symbol) { return z }
    return nil
}

private func grund(_ symbol: String) -> String? {
    if case .ohneQuelle(let g) = Kurszuordner.vorschlag(fuer: symbol) { return g }
    return nil
}

// MARK: Zuordnung

@Test func kryptoPaareGehenAnKraken() {
    let symbole = ["BTC/EUR", "BTC-EUR", "BTCEUR", "ETHUSDT", "eth/usd"]
    let quellSymbole = symbole.map { zuordnung($0)?.quellSymbol }
    #expect(quellSymbole == ["BTC/EUR", "BTC/EUR", "BTC/EUR", "ETH/USDT", "ETH/USD"])
    #expect(zuordnung("BTC/EUR")?.quelle == "kraken")
    #expect(zuordnung("BTC/EUR")?.naeherung == nil)
}

@Test func kryptoOhneGegenwaehrungInEuro() {
    #expect(zuordnung("SOL")?.quellSymbol == "SOL/EUR")
}

@Test func kryptoCFDAusMetaTraderIstNaeherung() {
    let z = zuordnung("btcusd")
    #expect(z?.quellSymbol == "BTC/USD")
    #expect(z?.naeherung == Kurszuordner.hinweisKryptoCFD)
}

@Test func usAktieMitEndungGehtAnAlpaca() {
    let z = zuordnung("AAPL.US")
    #expect(z?.quelle == "alpaca")
    #expect(z?.quellSymbol == "AAPL")
}

@Test func cfdUndDevisenOhneFreieQuelle() {
    for symbol in ["de40", "us100c", "xauusd", "eurgbpc"] {
        #expect(grund(symbol) == Kurszuordner.grundCFD, "\(symbol)")
    }
}

@Test func isinUndUnbekanntesOhneVorschlag() {
    #expect(grund("US0378331005") == Kurszuordner.grundISIN)
    #expect(grund("DE0007164600") == Kurszuordner.grundISIN)
    #expect(grund("Irgendwas AG") == Kurszuordner.grundUnbekannt)
}

@Test func zuordnungAlsJSON() throws {
    let z = Kurszuordnung(journalSymbol: "de40", quelle: "eigene", quellSymbol: "DAX", naeherung: "Basiswert")
    let zurueck = try JSONDecoder().decode(Kurszuordnung.self, from: JSONEncoder().encode(z))
    #expect(zurueck == z)
}

@Test func binanceZuordnungSpeichertGrossgeschriebenesQuellsymbol() throws {
    let z = Kurszuordnung(journalSymbol: "btceur", quelle: "binance", quellSymbol: "btceur", naeherung: "CFD")
    let zurueck = try JSONDecoder().decode(Kurszuordnung.self, from: JSONEncoder().encode(z))
    #expect(zurueck.quellSymbol == "BTCEUR")
    #expect(zurueck.journalSymbol == "btceur")
    #expect(zurueck.naeherung == "CFD")
    #expect(Kurszuordnung(journalSymbol: "X", quelle: "eigene", quellSymbol: "klein").quellSymbol == "klein")
}

// MARK: Beobachter

/// Quelle ohne Netz: meldet „verbunden“ und dann feste Kurse für die abonnierten Symbole.
struct FesteQuelle: Kursquelle {
    let id: String
    let name: String
    let verzoegerung = Verzoegerung.echtzeit
    let hoechstzahlSymbole: Int?
    let kurse: [Kurs]

    func beobachte(_ symbole: [String]) -> AsyncStream<Quellereignis> {
        let passend = kurse.filter { symbole.contains($0.symbol) }
        return AsyncStream { fortsetzung in
            fortsetzung.yield(.status(.verbunden))
            for kurs in passend { fortsetzung.yield(.kurs(kurs)) }
            fortsetzung.finish()
        }
    }
}

let btc = Kurs(symbol: "BTC/EUR", letzter: 58000, zeit: empfangen, quelle: "kraken")
let aapl = Kurs(symbol: "AAPL", letzter: 230, zeit: empfangen, quelle: "alpaca")

@Test func beobachterVerteiltKurseAufJournalSymbole() async {
    let beobachter = Kursbeobachter(quellen: [
        FesteQuelle(id: "kraken", name: "Kraken", hoechstzahlSymbole: nil, kurse: [btc]),
        FesteQuelle(id: "alpaca", name: "Alpaca (IEX)", hoechstzahlSymbole: 1, kurse: [aapl])
    ])
    let zuordnungen = [
        Kurszuordnung(journalSymbol: "BTC/EUR", quelle: "kraken", quellSymbol: "BTC/EUR"),
        Kurszuordnung(journalSymbol: "btceur", quelle: "kraken", quellSymbol: "BTC/EUR", naeherung: "CFD"),
        Kurszuordnung(journalSymbol: "AAPL.US", quelle: "alpaca", quellSymbol: "AAPL"),
        Kurszuordnung(journalSymbol: "MSFT.US", quelle: "alpaca", quellSymbol: "MSFT"),
        Kurszuordnung(journalSymbol: "SAP", quelle: "gettex", quellSymbol: "SAP")
    ]
    var stand = Kursstand()
    for await ereignis in beobachter.beobachte(zuordnungen) { stand.uebernimm(ereignis) }
    #expect(stand.kurse["BTC/EUR"]?.kurs == btc)
    #expect(stand.kurse["btceur"]?.naeherung == "CFD")
    #expect(stand.kurse["AAPL.US"]?.kurs == aapl)
    #expect(stand.ohneQuelle["MSFT.US"] == "Alpaca (IEX) liefert höchstens 1 Symbole gleichzeitig.")
    #expect(stand.ohneQuelle["SAP"] == "Quelle „gettex“ ist nicht eingerichtet.")
    #expect(stand.verbindungen == ["kraken": .verbunden, "alpaca": .verbunden])
}

private struct BinanceTestquelle: Kursquelle {
    let id = "binance"
    let name = "Binance"
    let verzoegerung = Verzoegerung.echtzeit
    let hoechstzahlSymbole: Int? = 1
    let antwortSymbol: String

    func beobachte(_ symbole: [String]) -> AsyncStream<Quellereignis> {
        #expect(symbole == ["BTCEUR"])
        #expect(BinanceLeser.adresse(symbole).absoluteString.hasSuffix("streams=btceur@ticker"))
        var leser = BinanceLeser()
        let text = #"{"stream":"btceur@ticker","data":{"e":"24hrTicker","s":""# + antwortSymbol + #"","c":"58000"}}"#
        let lesung = leser.lies(text, empfangen: empfangen)
        return AsyncStream { fortsetzung in
            for kurs in lesung.kurse { fortsetzung.yield(.kurs(kurs)) }
            fortsetzung.finish()
        }
    }
}

@Test(arguments: ["BTCEUR", "btceur"])
func binanceAltZuordnungenTeilenAboUndErhaltenAntwort(antwortSymbol: String) async throws {
    // Decodieren umgeht den Initialisierer, wie bei bereits gespeicherten Zuordnungen.
    let daten = Data(#"[{"journalSymbol":"btceur","quelle":"binance","quellSymbol":"btceur","naeherung":"CFD"},{"journalSymbol":"BTC/EUR","quelle":"binance","quellSymbol":"BTCEUR"}]"#.utf8)
    let zuordnungen = try JSONDecoder().decode([Kurszuordnung].self, from: daten)
    let beobachter = Kursbeobachter(quellen: [BinanceTestquelle(antwortSymbol: antwortSymbol)])
    let plan = beobachter.plane(zuordnungen)
    #expect(plan.abos["binance"]?.count == 1)
    #expect(plan.abos["binance"]?["BTCEUR"]?.count == 2)
    #expect(plan.ohneQuelle.isEmpty)
    var stand = Kursstand()
    for await ereignis in beobachter.beobachte(zuordnungen) { stand.uebernimm(ereignis) }
    #expect(stand.kurse.count == 2)
    #expect(stand.kurse["btceur"]?.kurs.preis == 58000)
    #expect(stand.kurse["btceur"]?.naeherung == "CFD")
    #expect(stand.kurse["BTC/EUR"]?.kurs.preis == 58000)
    #expect(stand.ohneQuelle.isEmpty)
}

@Test func kursstandMeldetVeralteteKurse() {
    var stand = Kursstand()
    let verzoegert = Kurs(symbol: "SAP", letzter: 200, zeit: empfangen, quelle: "test", verzoegerung: .verzoegert(minuten: 15))
    stand.uebernimm(.kurs(journalSymbol: "BTC/EUR", kurs: btc, naeherung: nil))
    stand.uebernimm(.kurs(journalSymbol: "SAP", kurs: verzoegert, naeherung: nil))
    #expect(stand.veraltet(jetzt: empfangen.addingTimeInterval(29)).isEmpty)
    #expect(stand.veraltet(jetzt: empfangen.addingTimeInterval(31)) == ["BTC/EUR"])
    #expect(stand.veraltet(jetzt: empfangen.addingTimeInterval(15 * 60 + 31)) == ["BTC/EUR", "SAP"])
}

@Test func bewertungskursJeSeite() {
    let kurs = Kurs(symbol: "X", letzter: 10, geld: 9, brief: 11, zeit: empfangen, quelle: "test")
    #expect(kurs.bewertungskurs(kaufposition: true) == 9)
    #expect(kurs.bewertungskurs(kaufposition: false) == 11)
    let nurBlatt = Kurs(symbol: "X", geld: 9, brief: 11, zeit: empfangen, quelle: "test")
    #expect(nurBlatt.preis == 10)
}

@Test func bewertungsalterOhneTeilzeitenBehaeltVerzoegerung() {
    let kurs = Kurs(symbol: "X", letzter: 10, geld: 9, brief: 11, zeit: empfangen,
                    quelle: "test", verzoegerung: .verzoegert(minuten: 15))
    for kaufposition in [true, false] {
        #expect(kurs.bewertungszeit(kaufposition: kaufposition) == empfangen)
        #expect(kurs.alter(jetzt: empfangen.addingTimeInterval(930), kaufposition: kaufposition) == 930)
        #expect(!kurs.istVeraltet(jetzt: empfangen.addingTimeInterval(930), kaufposition: kaufposition))
        #expect(kurs.istVeraltet(jetzt: empfangen.addingTimeInterval(931), kaufposition: kaufposition))
    }
}
