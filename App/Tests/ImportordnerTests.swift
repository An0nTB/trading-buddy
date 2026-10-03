#if os(macOS)
import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Synthetische Auszüge wie in den TradingStore-Tests (Aufbau aus MT5- und IBKR-Hilfe, kein echtes Konto).
private let mt5HTML = """
<html><head><title>12345678: Muster - Trade History Report</title></head><body>
<table>
<tr align="center"><th colspan="13"><div><b>Trade History Report</b></div></th></tr>
<tr align="left"><th colspan="3">Name:</th><th colspan="10"><b>Max Muster</b></th></tr>
<tr align="left"><th colspan="3">Account:</th><th colspan="10"><b>12345678&nbsp;(USD, Beispiel-Server, real, Hedge)</b></th></tr>
<tr align="left"><th colspan="3">Company:</th><th colspan="10"><b>Beispiel Broker Ltd.</b></th></tr>
<tr align="left"><th colspan="3">Date:</th><th colspan="10"><b>2025.06.01 12:00</b></th></tr>
<tr><td colspan="13" style="height: 10px"></td></tr>
<tr align="center"><th colspan="13"><div><b>Positions</b></div></th></tr>
<tr align="center" bgcolor="#E5F0FC"><td><b>Time</b></td><td><b>Position</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td class="hidden" colspan="8"></td><td><b>Volume</b></td><td><b>Price</b></td><td><b>S / L</b></td><td><b>T / P</b></td><td><b>Time</b></td><td><b>Price</b></td><td><b>Commission</b></td><td><b>Swap</b></td><td><b>Profit</b></td></tr>
<tr bgcolor="#FFFFFF" align="right"><td>2025.05.02 10:15:30</td><td>1001</td><td>EURUSD</td><td>buy</td><td class="hidden" colspan="8"></td><td>0.10</td><td>1.12000</td><td>1.11500</td><td></td><td>2025.05.02 11:00:00</td><td>1.12300</td><td>-0.70</td><td>0.00</td><td>30.00</td></tr>
<tr bgcolor="#F7F7F7" align="right"><td>2025.05.05 09:00:00</td><td>1002</td><td>XAUUSD</td><td>sell</td><td class="hidden" colspan="8"></td><td>0.05 / 0.10</td><td>3 250.00</td><td>0</td><td>3 200.00</td><td>2025.05.06 15:30:00</td><td>3 260.00</td><td>-1.00</td><td>-2.50</td><td>-50.00</td></tr>
<tr align="right"><td colspan="10"></td><td>-1.70</td><td>-2.50</td><td>-20.00</td></tr>
<tr><td colspan="13" style="height: 10px"></td></tr>
<tr align="center"><th colspan="13"><div><b>Orders</b></div></th></tr>
<tr align="center"><td><b>Open Time</b></td><td><b>Order</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td><b>State</b></td></tr>
<tr align="right"><td>2025.05.02 10:15:30</td><td>5001</td><td>EURUSD</td><td>buy</td><td>filled</td></tr>
<tr align="center"><th colspan="13"><div><b>Deals</b></div></th></tr>
<tr align="center"><td><b>Time</b></td><td><b>Deal</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td><b>Direction</b></td><td><b>Volume</b></td><td><b>Price</b></td><td><b>Order</b></td><td><b>Commission</b></td><td><b>Fee</b></td><td><b>Swap</b></td><td><b>Profit</b></td><td><b>Balance</b></td><td><b>Comment</b></td></tr>
<tr align="right"><td>2025.05.01 08:00:00</td><td>9001</td><td></td><td>balance</td><td></td><td></td><td></td><td></td><td>0.00</td><td>0.00</td><td>0.00</td><td>1 000.00</td><td>1 000.00</td><td>Deposit</td></tr>
<tr align="right"><td>2025.05.02 10:15:30</td><td>9002</td><td>EURUSD</td><td>buy</td><td>in</td><td>0.10</td><td>1.12000</td><td>5001</td><td>-0.35</td><td>0.00</td><td>0.00</td><td>0.00</td><td>999.65</td><td></td></tr>
<tr align="right"><td>2025.05.20 12:00:00</td><td>9003</td><td></td><td>credit</td><td></td><td></td><td></td><td></td><td>0.00</td><td>0.00</td><td>0.00</td><td>50.00</td><td>1 029.65</td><td>Bonus</td></tr>
<tr align="right"><td colspan="8"></td><td>-0.35</td><td>0.00</td><td>0.00</td><td>1 050.00</td><td>1 029.65</td></tr>
<tr align="center"><th colspan="13"><div><b>Results</b></div></th></tr>
<tr align="right"><td>Total Net Profit:</td><td>-24.20</td></tr>
</table></body></html>
"""

private let ibkrCSV = """
\u{FEFF}Statement,Header,Field Name,Field Value
Statement,Data,BrokerName,Interactive Brokers Ireland Limited
Account Information,Header,Field Name,Field Value
Account Information,Data,Name,Max Muster
Account Information,Data,Account,U1234567
Account Information,Data,Base Currency,EUR
Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,Proceeds,Comm/Fee,Basis,Realized P/L,MTM P/L,Code
Trades,Data,Order,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
Trades,Data,Order,Stocks,USD,AAPL,"2025-05-09, 15:59:01",-10,180,180,1800,-1.02,-1706,92.98,0,C
Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,,Proceeds,Comm in EUR,,,MTM in EUR,Code
Trades,Data,Order,Forex,USD,EUR.USD,"2025-05-02, 10:00:00",-1600,1.12,,1792,-1.7,,,0,
Deposits & Withdrawals,Header,Currency,Settle Date,Description,Amount
Deposits & Withdrawals,Data,EUR,2025-05-01,Electronic Fund Transfer,2000
Dividends,Header,Currency,Date,Description,Amount
Dividends,Data,USD,2025-05-15,AAPL(US0378331005) Cash Dividend USD 0.25 per Share (Ordinary Dividend),2.5
"""

/// Import-Ordner (Doc 45): wann die App still importiert und wann sie nachfragt, gegen ein Journal im
/// Arbeitsspeicher und einen Ordner unter `temporaryDirectory`.
@Suite @MainActor struct ImportordnerTests {
    private typealias T = AppTestdaten

    private func entscheide(_ text: String, _ name: String, _ konten: [Konto], journal: Journal? = nil,
                            zeitzone: TimeZone? = nil) -> Importordnerregel.Entscheidung {
        entscheide(Data(text.utf8), name, konten, journal: journal, zeitzone: zeitzone)
    }

    private func entscheide(_ daten: Data, _ name: String, _ konten: [Konto], journal: Journal? = nil,
                            zeitzone: TimeZone? = nil) -> Importordnerregel.Entscheidung {
        Importordnerregel.entscheide(daten: daten, dateiname: name, konten: konten, zeitzone: { _ in zeitzone },
                                     vorgaenge: { konto in
                                         guard let b = try? journal?.kontobewegungen(konto: konto) else { return [] }
                                         return Set(b.ausfuehrungen.map(\.id) + b.geldbewegungen.map(\.id))
                                     })
    }

    /// Kraken-Export, der den Export „A“ enthält und zwei neue Zeilen „B“ anhängt: ein Folgeexport.
    private static var krakenFolgeexport: String {
        let neu = T.kraken(kennung: "B").split(separator: "\n").dropFirst().joined(separator: "\n")
        return T.kraken(kennung: "A") + neu + "\n"
    }

    /// Journal wie nach einem Import von Hand: Scalable „Depot“, dazu `kraken` Kraken-Konten.
    private func journal(kraken: Int) throws -> Journal {
        let journal = try Journal.imSpeicher()
        _ = try journal.importiereCSV(datei: Data(T.scalable.utf8), dateiname: "appt-scalable.csv",
                                      kontonummer: "DE0012345678", kontowaehrung: "EUR", zeitzone: T.berlin)
        for nr in 0..<kraken {
            _ = try journal.importiereCSV(datei: Data(T.kraken(kennung: "K\(nr)").utf8), dateiname: "kraken-\(nr).csv",
                                          kontonummer: "Spot \(nr)", kontowaehrung: "USD", zeitzone: .gmt)
        }
        return journal
    }

    private func konten(kraken: Int) throws -> [Konto] { try journal(kraken: kraken).konten() }

    /// G21 (Tim 02.10.2026, Option 2): still nur bei genau einem Konto und Überschneidung mit dessen Vorgängen.
    @Test func csvMitEinemKontoUndUeberschneidungGehtStill() throws {
        let j = try journal(kraken: 0)
        _ = try j.importiereCSV(datei: Data(T.kraken(kennung: "A").utf8), dateiname: "kraken-a.csv",
                                kontonummer: "Spot", kontowaehrung: "USD", zeitzone: .gmt)
        let alle = try j.konten()
        let depot = try #require(alle.first { $0.broker == "Scalable Capital" })
        #expect(entscheide(T.scalable, "scalable.csv", alle, journal: j) == .csv(.scalable, depot))
        let spot = try #require(alle.first { $0.broker == "Kraken" })
        #expect(entscheide(Self.krakenFolgeexport, "kraken.csv", alle, journal: j) == .csv(.kraken, spot))
    }

    /// G21: Ein Export ohne gemeinsamen Vorgang (Zweitdepot, Partner) geht nicht still ins einzige Konto.
    @Test func csvOhneUeberschneidungFragtNach() throws {
        let j = try journal(kraken: 1)
        if case .rueckfrage = entscheide(T.kraken(kennung: "fremd"), "kraken.csv", try j.konten(), journal: j) {} else {
            Issue.record("fremder Export still")
        }
    }

    @Test func csvOhneOderMitMehrerenKontenFragtNach() throws {
        if case .rueckfrage = entscheide(T.scalable, "scalable.csv", []) {} else { Issue.record("ohne Konto still") }
        let zwei = try konten(kraken: 2)
        #expect(zwei.count == 3)
        if case .rueckfrage = entscheide(T.kraken(kennung: "neu"), "kraken.csv", zwei) {} else {
            Issue.record("zwei Konten still")
        }
    }

    /// In Excel neu gespeicherte CSV (Windows-1252): erkannt wie das UTF-8-Original, nicht „Format nicht erkannt“.
    @Test func csvInWindows1252WirdErkannt() throws {
        let j = try journal(kraken: 0)
        let depot = try #require(try j.konten().first { $0.broker == "Scalable Capital" })
        let text = T.scalable.replacingOccurrences(of: "Testwert AG", with: "Testwert Müller AG")
        let daten = try #require(text.data(using: .windowsCP1252))
        #expect(String(data: daten, encoding: .utf8) == nil)
        #expect(entscheide(daten, "scalable-excel.csv", try j.konten(), journal: j) == .csv(.scalable, depot))
    }

    @Test func unbekanntesFormatFragtNach() {
        if case .rueckfrage = entscheide("Hallo Welt", "notiz.txt", []) {} else { Issue.record("Text still") }
        if case .rueckfrage = entscheide("kein Excel", "liste.xlsx", []) {} else { Issue.record("xlsx still") }
    }

    @Test func nurPassendeEndungenKommenInFrage() {
        #expect(Importordnerregel.kommtInFrage("auszug.CSV"))
        #expect(Importordnerregel.kommtInFrage("Statement.htm"))
        #expect(!Importordnerregel.kommtInFrage("auszug.csv.download"))
        #expect(!Importordnerregel.kommtInFrage(".auszug.csv"))
        #expect(!Importordnerregel.kommtInFrage("~$kontohistorie.xlsx"))
        #expect(!Importordnerregel.kommtInFrage("bild.png"))
    }

    /// Ganzer Lauf: bekannte Datei erledigt, Kraken ohne Konto in der Liste, nach Anlage des Kontos
    /// importiert die App eine neue Kraken-Datei still und vergisst die erledigten nicht.
    @Test func ordnerLaufImportiertStillUndFragtNach() async throws {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "importordner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let speicher = try #require(UserDefaults(suiteName: "importordner-\(UUID().uuidString)"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        try Data(T.scalable.utf8).write(to: ordner.appending(path: "scalable.csv"))
        try Data(T.kraken(kennung: "A").utf8).write(to: ordner.appending(path: "kraken-a.csv"))
        let spaeter = Date.now.addingTimeInterval(60)

        let beobachtung = Importordner(speicher: speicher)
        await beobachtung.pruefeTestweise(ordner, modell: m, jetzt: spaeter)
        #expect(beobachtung.rueckfragen.map(\.dateiname) == ["kraken-a.csv"])
        #expect(m.importe.count == 1)

        // Kraken-Konto einmal von Hand, dann kommt eine weitere Kraken-Datei.
        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "A").utf8), dateiname: "kraken-a.csv",
                                kontonummer: "Spot", kontoname: "Spot", waehrung: "USD", zeitzone: .gmt)
        try Data(Self.krakenFolgeexport.utf8).write(to: ordner.appending(path: "kraken-b.csv"))
        await beobachtung.pruefe(jetzt: spaeter)
        #expect(beobachtung.rueckfragen.isEmpty)
        #expect(m.importe.count == 3)
        #expect(beobachtung.zuletzt.first?.dateiname == "kraken-b.csv")
        #expect(m.konten.count == 2)

        // Zweiter Lauf ändert nichts.
        await beobachtung.pruefe(jetzt: spaeter)
        #expect(m.importe.count == 3)
        #expect(beobachtung.zuletzt.count == 1)
    }

    /// A4: Mitteilung nur nach stillem Speichern; wartende Dateien stehen im Text, lösen allein aber keine aus.
    @Test func mitteilungNennenDateiUndWartende() throws {
        #expect(Importordner.mitteilungstext([], offen: 2) == nil)
        let eine = Importordner.Meldung(dateiname: "kraken-b.csv", text: "1 neue Ausführungen", zeit: .now)
        let text = try #require(Importordner.mitteilungstext([eine], offen: 0)).text
        #expect(text == "kraken-b.csv: 1 neue Ausführungen")
        let zwei = try #require(Importordner.mitteilungstext([eine, eine], offen: 1)).text
        #expect(zwei.contains("kraken-b.csv"))
        #expect(zwei.contains("2"))
        #expect(zwei.contains(" · "))
    }

    /// G20: Nach einem Wiederherstellen (hier: frisches Journal) fehlt der Import; die gemerkte Datei gilt
    /// nicht mehr als erledigt und wird erneut still importiert.
    @Test func nachWiederherstellenWirdErneutImportiert() async throws {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "importordner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let speicher = try #require(UserDefaults(suiteName: "importordner-\(UUID().uuidString)"))
        func modellMitKraken() throws -> AppModell {
            let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
            _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "A").utf8), dateiname: "kraken-a.csv",
                                    kontonummer: "Spot", kontoname: "Spot", waehrung: "USD", zeitzone: .gmt)
            return m
        }
        try Data(Self.krakenFolgeexport.utf8).write(to: ordner.appending(path: "kraken-b.csv"))
        let spaeter = Date.now.addingTimeInterval(60)
        let beobachtung = Importordner(speicher: speicher)

        let vorher = try modellMitKraken()
        await beobachtung.pruefeTestweise(ordner, modell: vorher, jetzt: spaeter)
        #expect(vorher.importe.count == 2)

        let nachher = try modellMitKraken()
        await beobachtung.pruefeTestweise(ordner, modell: nachher, jetzt: spaeter)
        #expect(nachher.importe.count == 2)
        #expect(beobachtung.rueckfragen.isEmpty)
    }

    @Test func ignorierteDateiKommtNichtWieder() async throws {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "importordner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let speicher = try #require(UserDefaults(suiteName: "importordner-\(UUID().uuidString)"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        try Data("Hallo".utf8).write(to: ordner.appending(path: "notiz.txt"))
        let beobachtung = Importordner(speicher: speicher)
        await beobachtung.pruefeTestweise(ordner, modell: m, jetzt: Date.now.addingTimeInterval(60))
        let rueckfrage = try #require(beobachtung.rueckfragen.first)
        beobachtung.ignoriere(rueckfrage)
        await beobachtung.pruefe(jetzt: Date.now.addingTimeInterval(60))
        #expect(beobachtung.rueckfragen.isEmpty)
    }
    /// MetaTrader 5 speichert UTF-16 mit BOM.
    private static var mt5UTF16: Data {
        var datei = Data([0xFF, 0xFE])
        datei.append(mt5HTML.data(using: .utf16LittleEndian)!)
        return datei
    }

    /// MT5 wie MT4: still bei bekanntem Konto (Company + Account) und bekannter Serverzeit, sonst Rückfrage.
    @Test func mt5MitBekanntemKontoGehtStill() throws {
        let server = try #require(TimeZone(secondsFromGMT: 3 * 3600))
        if case .rueckfrage = entscheide(Self.mt5UTF16, "ReportHistory-12345678.html", [], zeitzone: server) {} else {
            Issue.record("MT5 ohne Konto still")
        }
        let j = try Journal.imSpeicher()
        _ = try j.importiereMT5(datei: Self.mt5UTF16, dateiname: "ReportHistory-12345678.html", serverZeitzone: server)
        let konto = try #require(try j.konten().first)
        #expect(entscheide(mt5HTML, "utf8.html", [konto], zeitzone: server) == .mt5(konto, serverZeitzone: server))
        #expect(entscheide(Self.mt5UTF16, "neu.html", [konto], zeitzone: server) == .mt5(konto, serverZeitzone: server))
        if case .rueckfrage = entscheide(Self.mt5UTF16, "neu.html", [konto]) {} else {
            Issue.record("MT5 ohne Serverzeit still")
        }
    }

    /// IBKR: Kontonummer steht im Auszug; still nur, wenn dieses Konto schon angelegt ist.
    @Test func ibkrMitBekanntemKontoGehtStill() throws {
        if case .rueckfrage = entscheide(ibkrCSV, "U1234567.csv", []) {} else { Issue.record("IBKR ohne Konto still") }
        let j = try Journal.imSpeicher()
        _ = try j.importiereCSV(datei: Data(ibkrCSV.utf8), dateiname: "U1234567.csv", kontonummer: "Depot")
        let konto = try #require(try j.konten().first)
        #expect(entscheide(ibkrCSV, "neu.csv", [konto]) == .ibkr(konto))
        let fremd = ibkrCSV.replacingOccurrences(of: "U1234567", with: "U7654321")
        if case .rueckfrage = entscheide(fremd, "fremd.csv", [konto]) {} else { Issue.record("fremdes IBKR-Konto still") }
    }

    /// Ganzer Lauf für IBKR: Folgeauszug (ohne BOM, anderer Hash) geht still ins bekannte Konto, nichts doppelt.
    @Test func ordnerLaufImportiertIBKRStill() async throws {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "importordner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let speicher = try #require(UserDefaults(suiteName: "importordner-\(UUID().uuidString)"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(ibkrCSV.utf8), dateiname: "U1234567.csv", kontonummer: "Depot",
                                kontoname: "IBKR", waehrung: "EUR", zeitzone: .gmt)
        try Data(String(ibkrCSV.dropFirst()).utf8).write(to: ordner.appending(path: "U1234567-neu.csv"))
        let beobachtung = Importordner(speicher: speicher)
        await beobachtung.pruefeTestweise(ordner, modell: m, jetzt: Date.now.addingTimeInterval(60))
        #expect(beobachtung.rueckfragen.isEmpty)
        #expect(m.importe.count == 2)
        #expect(m.konten.count == 1)
        #expect(beobachtung.zuletzt.first?.dateiname == "U1234567-neu.csv")
    }
}
#endif
