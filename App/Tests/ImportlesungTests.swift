import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Logik der Import-Vorschau ohne Ansicht (`Importlesung`, AP11 #175): Erkennung am Inhalt, Importierbarkeit,
/// Maskierung, Summen je Währung. Geprüft werden Werte; Texte nur, wo sie einen Wert tragen (Anzahl, Brokername).
@Suite struct ImportlesungTests {
    private typealias T = AppTestdaten

    private func lies(_ text: String, _ name: String) -> Importlesung.Ergebnis {
        Importlesung.lies(Data(text.utf8), dateiname: name, serverzeit: .gmt, xtbZeit: T.berlin)
    }

    @Test func scalableWirdAlsCSVErkannt() throws {
        guard case .erkannt(.csv(let broker, let bewegungen)) = lies(T.scalable, "auszug.csv") else {
            Issue.record("Scalable nicht erkannt")
            return
        }
        #expect(broker == .scalable)
        #expect(bewegungen.ausfuehrungen.count == 2)
        #expect(bewegungen.geldbewegungen.count == 1)
        #expect(Importlesung.erkennung(broker, bewegungen).contains(CSVBroker.scalable.name))
        #expect(Importlesung.knopfText(.csv(broker, bewegungen)).contains("2"))
    }

    @Test func krakenWirdAlsKryptoErkannt() {
        guard case .erkannt(.csv(let broker, let bewegungen)) = lies(T.kraken(), "trades.csv") else {
            Issue.record("Kraken nicht erkannt")
            return
        }
        #expect(broker == .kraken)
        #expect(broker.istKrypto)
        #expect(bewegungen.ausfuehrungen.count == 2)
    }

    /// Unbekannter Text, Excel ohne XTB-Blatt und Binärdaten ergeben eine Meldung statt eines Imports.
    @Test func unlesbareDateienErgebenMeldung() {
        if case .fehler = lies("Hallo Welt", "notiz.txt") {} else { Issue.record("Text erkannt") }
        if case .fehler = lies("kein Excel", "liste.xlsx") {} else { Issue.record("xlsx erkannt") }
        let binaer = Importlesung.lies(Data([0xFF, 0xFE, 0x00, 0xD8]), dateiname: "a.csv", serverzeit: .gmt, xtbZeit: .gmt)
        if case .fehler(let text) = binaer { #expect(!text.isEmpty) } else { Issue.record("Binärdatei erkannt") }
    }

    /// CSV nur mit Inhalt und gültigem Konto; ohne Datei nie.
    @Test func importierbarNurMitGueltigemKonto() throws {
        guard case .erkannt(let erkannt) = lies(T.scalable, "auszug.csv") else {
            Issue.record("Scalable nicht erkannt")
            return
        }
        #expect(Importlesung.importierbar(erkannt, kontoGueltig: true, xtbNummer: ""))
        #expect(!Importlesung.importierbar(erkannt, kontoGueltig: false, xtbNummer: ""))
        #expect(!Importlesung.importierbar(nil, kontoGueltig: true, xtbNummer: "123"))
    }

    @Test func kontonummerBisAufVierStellenVerdeckt() {
        #expect(Importlesung.maskiert("DE0012345678") == "••••5678")
        #expect(Importlesung.maskiert("12") == "••••12")
        #expect(!Importlesung.maskiert("DE0012345678").contains("DE00"))
    }

    /// A4: Summen je Währung ohne Umrechnung, Kontowährung unabhängig von Groß- und Kleinschreibung.
    @Test func waehrungssummenTrennenFremdwaehrungen() {
        let summen = Waehrungssummen([("usd", T.d("10")), ("EUR", T.d("5")), ("USDT", T.d("1")), ("eur", T.d("2"))],
                                     kontowaehrung: "eur")
        #expect(summen.kontowaehrung == "EUR")
        #expect(summen.fremde == ["USD", "USDT"])
        let nurKonto = Waehrungssummen([("EUR", T.d("5"))], kontowaehrung: "EUR")
        #expect(nurKonto.fremde.isEmpty)
        #expect(nurKonto.zusatz("x") == "x")
    }

    @Test func pruefungStimmtNurBeiGleicherSumme() {
        #expect(Importlesung.Pruefung(id: "a", lautAuszug: T.d("1.50"), berechnet: T.d("1.5")).stimmt)
        #expect(!Importlesung.Pruefung(id: "b", lautAuszug: T.d("1.50"), berechnet: T.d("1.49")).stimmt)
    }

    @Test func fehlertextNenntDenWert() {
        #expect(Importlesung.fehlertext(SpeicherFehler.ungueltigerWert("APPT-WERT")).contains("APPT-WERT"))
        #expect(Importlesung.fehlertext(CSVImportFehler.fehlendeSpalte("APPT-SPALTE")).contains("APPT-SPALTE"))
    }
}
