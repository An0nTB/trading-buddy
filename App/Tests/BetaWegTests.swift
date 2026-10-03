import Foundation
import Testing
import TradingCore
import TradingStore
import TradingRates
@testable import Trading_Buddy

/// Der Weg eines Beta-Testers als Ganzes (Beta-Prüfliste 03.10.2026, Punkte 4, 5, 7, 8, 10, 16):
/// einlesen, auswerten, sichern, ändern, wiederherstellen, gleiche Zahlen. Journal im Arbeitsspeicher,
/// Sicherungen in einem eigenen Ordner unter `temporaryDirectory`. Der `Sicherungsdienst` selbst bleibt außen vor,
/// weil er Einstellungen, Bilderordner und „Vor Wiederherstellung“ des Nutzers anfasst; geprüft wird derselbe
/// Ablauf wie in `DatensicherungView`: Store sichert und spielt ein, danach `laden()`.
@Suite @MainActor struct BetaWegTests {
    private typealias T = AppTestdaten

    private static let kurse = Referenzkurse(kurse: [T.tag(2026, 4, 2): ["USD": T.d("1.25")],
                                                     T.tag(2026, 4, 3): ["USD": T.d("1.25")]])

    private func ordner() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "appt-beta-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func importiereKraken(_ m: AppModell, _ kennung: String) throws -> ImportErgebnis {
        try m.importiereCSV(daten: Data(T.kraken(kennung: kennung).utf8), dateiname: "appt-kraken-\(kennung).csv",
                            kontonummer: "KR-00001111", kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
    }

    /// Was der Tester auf der Übersicht sieht, plus Regeln, Ziele und Journal.
    private struct Stand: Equatable {
        var kennzahlen: Kennzahlen
        var tradeIDs: [String]
        var summenwaehrung: String
        var regeln: Handelsregeln
        var ziele: [Reviewziel]
        var journal: [String: Journaleintrag]
    }

    private func stand(_ m: AppModell) -> Stand {
        Stand(kennzahlen: m.kennzahlen, tradeIDs: m.trades.map(\.id).sorted(), summenwaehrung: m.summenwaehrung,
              regeln: m.regeln, ziele: m.ziele, journal: m.journaleintraege)
    }

    /// Einlesen → Übersicht in Euro → Sicherung → Änderungen → Wiederherstellen → derselbe Stand.
    @Test func sicherungUndWiederherstellenErgebenDieselbenZahlen() throws {
        let basis = try ordner()
        defer { try? FileManager.default.removeItem(at: basis) }
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        m.ezb.kurse = Self.kurse
        _ = try importiereKraken(m, "A")
        _ = try importiereKraken(m, "B")
        try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 3))
        let jetzt = Date()
        try m.legeZielAn(Reviewziel(text: "Testziel", von: jetzt.addingTimeInterval(-86_400),
                                    bis: jetzt.addingTimeInterval(6 * 86_400)))
        var eintrag = try #require(m.journaleintrag(try #require(m.trades.first)))
        eintrag.regeltreue = false
        m.speichereJournal(eintrag)
        // Punkt 8: zwei USD-Trades auf dem Euro-Konto, Summe in Euro (2 × 43,90 USD / 1,25).
        #expect(m.summenwaehrung == "EUR")
        #expect(m.kennzahlen.netto == T.d("70.24"))
        #expect(m.waehrungsstand.umgerechnet == 2)
        m.laden()
        let vorher = stand(m)

        let datei = try journal.sichereInOrdner(basis, jetzt: T.zeit(2026, 10, 3, 3), zeitzone: .gmt)
        let pruefung = Journal.pruefeSicherung(datei)
        #expect(pruefung.zustand == .aktuell)
        #expect(pruefung.konten == 1)

        // Danach ändert der Tester weiter: dritter Trade, Regeln weg.
        _ = try importiereKraken(m, "C")
        try m.speichereRegeln(Handelsregeln())
        #expect(m.trades.count == 3)
        #expect(stand(m) != vorher)

        let ergebnis = try journal.stelleWiederHer(aus: datei)
        #expect(ergebnis.zustand == .aktuell)
        m.laden()
        #expect(stand(m) == vorher)
        #expect(m.manuellVerletzt == [eintrag.ticket])
    }

    /// Wiederherstellen eines Stands von vor dem ersten Import: kein Konto, keine Trades, keine alten Zahlen.
    @Test func wiederherstellenVorDemErstenImportLeertDieUebersicht() throws {
        let basis = try ordner()
        defer { try? FileManager.default.removeItem(at: basis) }
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        let leer = try journal.sichereInOrdner(basis, jetzt: T.zeit(2026, 10, 3, 3), zeitzone: .gmt)
        _ = try importiereKraken(m, "A")
        #expect(m.konto != nil)
        #expect(m.trades.count == 1)

        try journal.stelleWiederHer(aus: leer)
        m.laden()
        #expect(m.konten.isEmpty)
        #expect(m.konto == nil)
        #expect(m.trades.isEmpty)
        #expect(m.kennzahlen.anzahl == 0)
        #expect(m.importe.isEmpty)
    }

    /// Eine kaputte Datei wird abgelehnt; der Stand bleibt, wie er war.
    @Test func beschaedigteSicherungAendertNichts() throws {
        let basis = try ordner()
        defer { try? FileManager.default.removeItem(at: basis) }
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        _ = try importiereKraken(m, "A")
        m.laden()
        let vorher = stand(m)
        let kaputt = basis.appending(path: "Journal-Sicherung-kaputt.sqlite")
        try Data("keine Datenbank".utf8).write(to: kaputt)

        #expect(Journal.pruefeSicherung(kaputt).zustand == .beschaedigt)
        #expect(throws: (any Error).self) { try journal.stelleWiederHer(aus: kaputt) }
        m.laden()
        #expect(stand(m) == vorher)
    }

    /// Punkt 5: Dieselbe Datei zweimal einlesen ergibt keine doppelten Trades.
    @Test func zweimalDieselbeDateiGibtKeineDoppeltenTrades() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        let erstes = try importiereKraken(m, "A")
        #expect(erstes.status == .gespeichert)
        let zweites = try importiereKraken(m, "A")
        #expect(zweites.status == .dateiBereitsImportiert)
        #expect(m.trades.count == 1)
        #expect(m.importe.count == 1)
    }

    /// Erststart: leeres Journal, keine Zahlen, Ziele und Regeln ohne Konto abgelehnt.
    @Test func erststartOhneKonto() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        #expect(m.konten.isEmpty)
        #expect(m.konto == nil)
        #expect(m.trades.isEmpty)
        #expect(m.importe.isEmpty)
        #expect(m.offenePositionen.isEmpty)
        #expect(m.kennzahlen.anzahl == 0)
        #expect(m.waehrungsstand.leer)
        #expect(m.fehler == nil)
        #expect(throws: Zielfehler.keinKonto) {
            try m.legeZielAn(Reviewziel(text: "Testziel", von: Date(), bis: Date().addingTimeInterval(86_400)))
        }
        #expect(throws: Regelfehler.keinKonto) { try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 3)) }
    }
}

/// Punkt 20: Die Sprachwahl landet als `AppleLanguages` in den Einstellungen; „Wie System“ entfernt den Eintrag.
/// Geprüft gegen eine eigene Suite. Dazu: Die App bringt englische Texte mit.
@Suite struct SprachwahlTests {
    @Test func spracheWirdAlsAppleLanguagesGemerkt() throws {
        let name = "appt-sprache-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let ablage = try #require(UserDefaults(suiteName: name))
        Sprache.englisch.anwenden(ablage)
        #expect(ablage.stringArray(forKey: "AppleLanguages") == ["en"])
        Sprache.deutsch.anwenden(ablage)
        #expect(ablage.stringArray(forKey: "AppleLanguages") == ["de"])
        Sprache.system.anwenden(ablage)
        #expect(ablage.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    }

    @Test func kennungenUndGespeicherteWerte() {
        #expect(Sprache.allCases.map(\.kennung) == [nil, "de", "en"])
        #expect(Sprache(rawValue: "englisch") == .englisch)
        #expect(Sprache(rawValue: "") == nil)
    }

    /// Das App-Bündel enthält englische Texte: ein paar feste Schlüssel sind übersetzt (Wert ungleich Schlüssel).
    @Test func appBringtEnglischeTexteMit() throws {
        let pfad = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let englisch = try #require(Bundle(path: pfad))
        for schluessel in ["Übersicht", "Einstellungen", "Wiederherstellen", "Summe"] {
            #expect(englisch.localizedString(forKey: schluessel, value: nil, table: nil) != schluessel)
        }
    }
}
