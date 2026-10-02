import Foundation
import Testing
import TradingCore
import TradingStore
import TradingRates
@testable import Trading_Buddy

/// Anzeigewährung der Summen (Entscheidung B4: „Standard Euro, andere Währung per Klick“) gegen ein Journal im
/// Arbeitsspeicher. EZB-Kurse kommen synthetisch über `ezb.kurse`, nie aus dem Netz; der Wechsel der
/// Anzeigewährung rechnet neu. Mit `nebenwirkungen: false` bleibt die gespeicherte Wahl des Nutzers unberührt.
@Suite @MainActor struct AnzeigewaehrungTests {
    private typealias T = AppTestdaten

    /// Einheiten je Euro am Schlusstag des Kraken-Trades (03.04.2026) und am Schlusstag des Scalable-Trades (02.04.).
    private static let kurse = Referenzkurse(kurse: [T.tag(2026, 4, 2): ["USD": T.d("1.25"), "GBP": T.d("0.8")],
                                                     T.tag(2026, 4, 3): ["USD": T.d("1.25"), "GBP": T.d("0.8")]])

    private func modell(kraken: Bool, kurse: Bool) throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        if kurse { m.ezb.kurse = Self.kurse }
        if kraken {
            _ = try m.importiereCSV(daten: Data(T.kraken().utf8), dateiname: "appt-kraken.csv", kontonummer: "KR-00001111",
                                    kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        } else {
            _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv",
                                    kontonummer: "DE0012345678", kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        }
        return m
    }

    /// USD-Trade auf EUR-Konto mit Kurs: 43,90 USD / 1,25 = 35,12 EUR, als umgerechnet gezählt.
    @Test func usdTradeMitKursWirdInKontowaehrungGezaehlt() throws {
        let m = try modell(kraken: true, kurse: true)
        #expect(m.summenwaehrung == "EUR")
        let trade = try #require(m.angeglicheneTrades.first)
        #expect(trade.netProfit == T.d("35.12"))
        #expect(m.kontoTrades.map(\.netProfit) == [T.d("35.12")])
        #expect(m.waehrungsstand.umgerechnet == 1)
        #expect(m.waehrungsstand.ohneKurs == 0)
        // Die Liste bleibt in Originalwährung (W1).
        #expect(m.trades.first?.netProfit == T.d("43.9"))
    }

    /// Anzeige in USD: der USD-Trade braucht keinen Kurs, die Regel-Seite bleibt in Kontowährung (ohne Kurs leer).
    @Test func anzeigeInTradewaehrungBrauchtKeinenKurs() throws {
        let m = try modell(kraken: true, kurse: false)
        #expect(m.angeglicheneTrades.isEmpty)
        m.anzeigewaehrung = "USD"
        #expect(m.summenwaehrung == "USD")
        #expect(m.angeglicheneTrades.map(\.netProfit) == [T.d("43.9")])
        #expect(m.waehrungsstand.leer)
        #expect(m.kontoTrades.isEmpty)
    }

    /// Anzeige in GBP über den Euro: 43,90 / 1,25 × 0,8 = 28,096; Kontowährungstrade 48 × 0,8 = 38,4.
    @Test func anzeigeInDritterWaehrungRechnetUeberDenEuro() throws {
        let kraken = try modell(kraken: true, kurse: true)
        kraken.anzeigewaehrung = "gbp"
        #expect(kraken.summenwaehrung == "GBP")
        #expect(kraken.angeglicheneTrades.map(\.netProfit) == [T.d("28.096")])

        let depot = try modell(kraken: false, kurse: true)
        depot.anzeigewaehrung = "GBP"
        #expect(depot.angeglicheneTrades.map(\.netProfit) == [T.d("38.4")])
        #expect(depot.waehrungsstand.umgerechnet == 1)
        // Regeln bleiben in Kontowährung.
        #expect(depot.kontoTrades.map(\.netProfit) == [T.d("48")])
    }

    /// Ohne Kurs fehlt der EUR-Trade in USD-Summen; zurück zur Kontowährung ist er wieder da.
    @Test func anzeigeOhneKursUndZurueckZurKontowaehrung() throws {
        let m = try modell(kraken: false, kurse: false)
        m.anzeigewaehrung = "USD"
        #expect(m.angeglicheneTrades.isEmpty)
        #expect(m.waehrungsstand.ohneKurs == 1)
        m.anzeigewaehrung = nil
        #expect(m.summenwaehrung == "EUR")
        #expect(m.angeglicheneTrades.map(\.netProfit) == [T.d("48")])
        #expect(m.waehrungsstand.leer)
    }

    @Test func waehlbareAnzeigewaehrungen() throws {
        let m = try modell(kraken: true, kurse: false)
        let liste = m.anzeigewaehrungen
        #expect(liste == liste.sorted())
        #expect(Set(["EUR", "USD", "GBP", "CHF", "JPY"]).isSubset(of: Set(liste)))
        #expect(!liste.contains("USDT"))
        #expect(Set(liste).count == liste.count)
    }

    /// Im Testbetrieb schreibt der Wechsel nicht in die Einstellungen des Nutzers.
    @Test func testbetriebSchreibtKeineEinstellung() throws {
        let vorher = UserDefaults.standard.string(forKey: AppModell.anzeigewaehrungSchluessel)
        let m = try modell(kraken: false, kurse: false)
        #expect(m.anzeigewaehrung == nil)
        m.anzeigewaehrung = vorher == "JPY" ? "CHF" : "JPY"
        #expect(UserDefaults.standard.string(forKey: AppModell.anzeigewaehrungSchluessel) == vorher)
    }
}

/// Erkennung der CSV-Köpfe und Dateien, die gar nicht lesbar sind (Ergänzung zu `ImportordnerTests`).
@Suite struct ImportordnerErkennungTests {
    private typealias T = AppTestdaten

    @Test func csvKoepfeWerdenDemBrokerZugeordnet() {
        #expect(Importordnerregel.csvBroker(T.scalable) == .scalable)
        #expect(Importordnerregel.csvBroker(T.kraken()) == .kraken)
        #expect(Importordnerregel.csvBroker("a;b;c\n1;2;3\n") == nil)
    }

    @Test func binaereDateiOhneExcelFragtNach() {
        let daten = Data([0xFF, 0xFE, 0x00, 0xD8, 0x00, 0xDC])
        let entscheidung = Importordnerregel.entscheide(daten: daten, dateiname: "auszug.csv", konten: [],
                                                         zeitzone: { _ in nil })
        if case .rueckfrage = entscheidung {} else { Issue.record("Binärdatei still entschieden") }
    }
}

#if os(macOS)
/// Spiegel der Screenshots in der Datensicherung: kopiert nur fehlende, gültige Bilder, überschreibt nichts.
/// Arbeitet nur in einem eigenen Ordner unter `temporaryDirectory`.
@Suite struct SicherungBilderspiegelTests {
    private func ordner() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "appt-sicherung-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func schreibe(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func kopiertNurFehlendeGueltigeBilder() throws {
        let basis = try ordner()
        defer { try? FileManager.default.removeItem(at: basis) }
        let quelle = basis.appending(path: "quelle", directoryHint: .isDirectory)
        let ziel = basis.appending(path: "ziel", directoryHint: .isDirectory)
        try schreibe("a", quelle.appending(path: "2026-10/a.png"))
        try schreibe("b", quelle.appending(path: "2026-10/b.JPG"))
        try schreibe("n", quelle.appending(path: "2026-10/notiz.txt"))
        try schreibe("l", quelle.appending(path: "lose.png"))

        #expect(Sicherungsdienst.kopiereFehlende(von: quelle, nach: ziel) == 2)
        #expect(FileManager.default.fileExists(atPath: ziel.appending(path: "2026-10/a.png").path))
        #expect(FileManager.default.fileExists(atPath: ziel.appending(path: "2026-10/b.JPG").path))
        #expect(!FileManager.default.fileExists(atPath: ziel.appending(path: "2026-10/notiz.txt").path))
        #expect(!FileManager.default.fileExists(atPath: ziel.appending(path: "lose.png").path))
        #expect(Sicherungsdienst.kopiereFehlende(von: quelle, nach: ziel) == 0)
    }

    @Test func vorhandenesBildImZielBleibtUnveraendert() throws {
        let basis = try ordner()
        defer { try? FileManager.default.removeItem(at: basis) }
        let quelle = basis.appending(path: "quelle", directoryHint: .isDirectory)
        let ziel = basis.appending(path: "ziel", directoryHint: .isDirectory)
        try schreibe("neu", quelle.appending(path: "2026-09/x.png"))
        try schreibe("alt", ziel.appending(path: "2026-09/x.png"))

        #expect(Sicherungsdienst.kopiereFehlende(von: quelle, nach: ziel) == 0)
        let inhalt = try Data(contentsOf: ziel.appending(path: "2026-09/x.png"))
        #expect(String(decoding: inhalt, as: UTF8.self) == "alt")
    }

    @Test func fehlendeQuelleKopiertNichts() throws {
        let basis = try ordner()
        defer { try? FileManager.default.removeItem(at: basis) }
        #expect(Sicherungsdienst.kopiereFehlende(von: basis.appending(path: "gibtsnicht"),
                                                 nach: basis.appending(path: "ziel")) == 0)
    }
}
#endif
