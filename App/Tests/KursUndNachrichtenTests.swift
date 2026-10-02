import Foundation
import Testing
import TradingCore
import TradingQuotes
import TradingStore
@testable import Trading_Buddy

/// Eigene Einstellungen je Test: eine `UserDefaults`-Suite, die am Ende gelöscht wird.
private struct Testeinstellungen {
    let name = "appt-einstellungen-\(UUID().uuidString)"
    var speicher: UserDefaults { UserDefaults(suiteName: name)! }
    func aufraeumen() { UserDefaults.standard.removePersistentDomain(forName: name) }
}

/// Kursdienst mit Schlüsselbund-Fake (Paket A7), Fake-Abruf und eigener Datei im temporären Ordner.
/// Kein Test startet den Kursbeobachter: Kurse sind aus oder es werden keine Symbole beobachtet.
@Suite @MainActor struct KursdienstTests {
    private typealias T = AppTestdaten

    private func dienst(_ einstellungen: Testeinstellungen) -> Kursdienst {
        Kursdienst(speicher: einstellungen.speicher, schluesselbund: Schluesselbund(ablage: SpeicherSchluesselablage()),
                   abruf: { _ in Issue.record("Abruf ohne Erwartung"); return (500, Data()) },
                   verlaufsdatei: FileManager.default.temporaryDirectory
                       .appendingPathComponent("appt-verlaeufe-\(UUID().uuidString).json"))
    }

    private func krakenTrade() throws -> Trade {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.kraken().utf8), dateiname: "appt-kraken.csv", kontonummer: "KR-00001111",
                                kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        return try #require(m.trades.first)
    }

    /// Eigene Zuordnung überstimmt den Vorschlag, bleibt über einen Neustart und lässt sich entfernen.
    @Test func eigeneZuordnungWirdGespeichertUndEntfernt() {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let erster = dienst(einstellungen)
        erster.setzeZuordnung(Kurszuordnung(journalSymbol: "APPT/TEST", quelle: "alpaca", quellSymbol: "APPT"))
        guard case .eigene(let eigen) = erster.zuordnung(fuer: "APPT/TEST") else {
            Issue.record("keine eigene Zuordnung")
            return
        }
        #expect(eigen.quellSymbol == "APPT")

        let zweiter = dienst(einstellungen)
        #expect(zweiter.eigene.map(\.journalSymbol) == ["APPT/TEST"])
        zweiter.entferneZuordnung(symbol: "APPT/TEST")
        #expect(zweiter.eigene.isEmpty)
        #expect(dienst(einstellungen).eigene.isEmpty)
    }

    /// Ein zweites Setzen für dasselbe Symbol ersetzt die Zuordnung statt sie zu verdoppeln.
    @Test func zuordnungFuerDasselbeSymbolWirdErsetzt() {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        d.setzeZuordnung(Kurszuordnung(journalSymbol: "APPT/TEST", quelle: "alpaca", quellSymbol: "ALT"))
        d.setzeZuordnung(Kurszuordnung(journalSymbol: "APPT/TEST", quelle: "alpaca", quellSymbol: "NEU"))
        #expect(d.eigene.map(\.quellSymbol) == ["NEU"])
    }

    /// Der Schalter bleibt über einen Neustart; ohne beobachtete Symbole läuft dabei nichts.
    @Test func schalterKurseWirdGespeichert() {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        #expect(!d.aktiv)
        d.setzeAktiv(true)
        #expect(d.symbole.isEmpty)
        #expect(dienst(einstellungen).aktiv)
        d.setzeAktiv(false)
        #expect(!dienst(einstellungen).aktiv)
    }

    @Test func quellenUndQuellenname() {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        let kennungen = d.quellen.map { $0.id }
        #expect(kennungen.contains("kraken"))
        #expect(kennungen.contains("alpaca"))
        #expect(d.quellenname("appt-unbekannt") == "appt-unbekannt")
        #expect(!d.quellenname("kraken").isEmpty)
    }

    /// Minutenkerzen nur bei eingeschalteten Kursen; Fenster noch nicht vorbei → später; ohne Minutenquelle → gezählt.
    /// In keinem Fall geht ein Abruf hinaus.
    @Test func minutenkerzenOhneAbruf() async throws {
        let trade = try krakenTrade()
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        d.setzeZuordnung(Kurszuordnung(journalSymbol: trade.symbol, quelle: "alpaca", quellSymbol: "APPT"))
        let aus = await d.ladeMinutenkerzen(fuer: [trade], jetzt: trade.closeTime)
        #expect(aus == Minutenabruf())

        d.setzeAktiv(true)
        let offen = await d.ladeMinutenkerzen(fuer: [trade], jetzt: trade.closeTime)
        #expect(offen.nochOffen == 1)
        #expect(offen.geladen == 0)

        d.setzeZuordnung(Kurszuordnung(journalSymbol: trade.symbol, quelle: "appt-ohne-minuten", quellSymbol: "APPT"))
        let ohne = await d.ladeMinutenkerzen(fuer: [trade], jetzt: trade.closeTime.addingTimeInterval(86_400))
        #expect(ohne.ohneQuelle == 1)
        #expect(ohne.fehler.isEmpty)
        d.setzeAktiv(false)
    }
}

/// Nachrichtendienst ohne Abruf: Quellen-Schalter, „gesehen bis“ und Merkliste gegen ein Journal im Arbeitsspeicher.
/// `setzeAktiv` bleibt außen vor, weil das Ausschalten den Export für den Connector neu schreibt.
@Suite @MainActor struct NachrichtendienstTests {
    private func dienst(_ einstellungen: Testeinstellungen) -> Nachrichtendienst {
        Nachrichtendienst(speicher: einstellungen.speicher, schluesselbund: Schluesselbund(ablage: SpeicherSchluesselablage()))
    }

    @Test func quellenSchalterBleibtGespeichert() {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        #expect(!d.aktiv)
        #expect(d.aktiveQuellen == d.quellen.count)
        d.setzeQuelle(Nachrichtendienst.alpaca, an: false)
        #expect(!d.istAn(Nachrichtendienst.alpaca))
        #expect(d.aktiveQuellen == d.quellen.count - 1)

        let zweiter = dienst(einstellungen)
        #expect(!zweiter.istAn(Nachrichtendienst.alpaca))
        zweiter.setzeQuelle(Nachrichtendienst.alpaca, an: true)
        #expect(dienst(einstellungen).aktiveQuellen == d.quellen.count)
    }

    @Test func gesehenBisBleibtGespeichert() {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        #expect(d.gesehenBis == nil)
        let zeit = AppTestdaten.zeit(2026, 10, 1, 12)
        d.markiereGesehen(jetzt: zeit)
        #expect(dienst(einstellungen).gesehenBis == zeit)
    }

    /// Von Hand: leer abgelehnt, doppelt nur einmal, Entfernen löscht.
    @Test func merklisteVonHand() throws {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        d.verbinde(try Journal.imSpeicher())
        #expect(!d.fuegeHinzu("   "))
        #expect(d.fuegeHinzu("Testwert AG"))
        #expect(d.fuegeHinzu("  Testwert   AG "))
        #expect(d.aktiveEintraege.count == 1)
        #expect(d.begriffe.count == 1)
        let id = try #require(d.aktiveEintraege.first?.id)
        d.entferne(id)
        #expect(d.merkliste.isEmpty)
        #expect(d.merklisteFehler == nil)
    }

    /// Vorschläge aus offenen Positionen werden nicht still aktiv; abgelehnte kommen nicht wieder.
    @Test func vorschlaegeAusOffenenPositionen() throws {
        let einstellungen = Testeinstellungen()
        defer { einstellungen.aufraeumen() }
        let d = dienst(einstellungen)
        d.verbinde(try Journal.imSpeicher())
        let jetzt = AppTestdaten.zeit(2026, 10, 1, 12)
        d.ergaenzeVorschlaege(trades: [], offeneSymbole: ["APPT/USD"], jetzt: jetzt)
        #expect(d.vorschlaege.count == 1)
        #expect(d.aktiveEintraege.isEmpty)

        let vorschlag = try #require(d.vorschlaege.first)
        d.entferne(vorschlag.id)
        #expect(d.vorschlaege.isEmpty)
        #expect(d.merkliste.first?.status == .abgelehnt)
        d.ergaenzeVorschlaege(trades: [], offeneSymbole: ["APPT/USD"], jetzt: jetzt)
        #expect(d.vorschlaege.isEmpty)
        #expect(d.merkliste.count == 1)
    }
}
