import SwiftUI
import TradingCore
import TradingStore

/// Serverzeitzone eines MT4-Auszugs. Sie steht nicht in der Datei; die App fragt sie ab
/// (Entscheidung 14: Vorgabe UTC+3 im Sommer, UTC+2 im Winter).
enum Serverzeit: String, CaseIterable, Identifiable {
    case osteuropa = "Europe/Athens"
    case mitteleuropa = "Europe/Berlin"
    case london = "Europe/London"
    case utc = "UTC"
    case newYork = "America/New_York"

    static let vorgabe = Serverzeit.osteuropa

    var id: String { rawValue }
    var zeitzone: TimeZone { TimeZone(identifier: rawValue) ?? .gmt }

    var name: LocalizedStringKey {
        switch self {
        case .osteuropa: "UTC+2 Winter / UTC+3 Sommer (Vorgabe, viele MT4-Broker)"
        case .mitteleuropa: "UTC+1 / UTC+2 (Mitteleuropa)"
        case .london: "UTC+0 / UTC+1 (London)"
        case .utc: "UTC ohne Sommerzeit"
        case .newYork: "UTC−5 / UTC−4 (New York)"
        }
    }

    /// Ohne den MT4-Zusatz, für den XTB-Auszug (dort ist deutsche Ortszeit die Vorgabe, eine Annahme).
    var kurzname: LocalizedStringKey {
        switch self {
        case .osteuropa: "UTC+2 / UTC+3 (Osteuropa)"
        case .mitteleuropa: "UTC+1 / UTC+2 (Mitteleuropa, Vorgabe)"
        case .london: "UTC+0 / UTC+1 (London)"
        case .utc: "UTC ohne Sommerzeit"
        case .newYork: "UTC−5 / UTC−4 (New York)"
        }
    }
}

/// Gelesene Datei vor dem Speichern: Grundlage des Import-Blatts.
struct ImportVorschau: Identifiable {
    let id = UUID()
    let daten: Data
    let dateiname: String
}

/// Importer, die noch gegen keine echte Datei liefen, nur gegen öffentliche Beispiele (Stand-Doc 16,
/// Entscheidung 01.10.2026): Die App kennzeichnet sie als „ungeprüft“, bis eine echte Datei durchlief.
enum Importer {
    static let ungeprueft: Set<String> = [Journal.tradeRepublicImporter, Journal.scalableImporter, Journal.xtbImporter,
                                          Journal.krakenImporter, Journal.binanceImporter, Journal.coinbaseImporter,
                                          Journal.bitpandaImporter, Journal.mt5Importer, Journal.ibkrImporter]
    /// Broker-Name der XTB-Konten, wie `Journal.importiereXTB` ihn speichert.
    static let xtbBroker = "XTB"

    static func istUngeprueft(_ name: String) -> Bool { ungeprueft.contains(name) }
}

/// Broker und Kryptobörsen, deren CSV-Export die App liest. Namen wie in `Konto.broker` der Speicherung
/// (`Journal.importiereCSV` erkennt dieselben Köpfe).
enum CSVBroker {
    case tradeRepublic, scalable, kraken, binance, coinbase, bitpanda, ibkr

    var name: String {
        switch self {
        case .tradeRepublic: "Trade Republic"
        case .scalable: "Scalable Capital"
        case .kraken: "Kraken"
        case .binance: "Binance"
        case .coinbase: "Coinbase"
        case .bitpanda: "Bitpanda"
        case .ibkr: "Interactive Brokers"
        }
    }

    /// Kryptobörse: Paare gegen Geldwährung oder Stablecoin werden Trades, der Rest Hinweise (Doc 19).
    var istKrypto: Bool {
        switch self {
        case .tradeRepublic, .scalable, .ibkr: false
        case .kraken, .binance, .coinbase, .bitpanda: true
        }
    }

    /// Bezeichnung des Exports, wie die Börse ihn nennt.
    var exportName: String {
        switch self {
        case .tradeRepublic, .scalable: String(localized: "Transaktionsexport (CSV)")
        case .kraken: String(localized: "Trade-Export (CSV)")
        case .binance: String(localized: "Spot-Trade-Export (CSV)")
        case .coinbase: String(localized: "Transaktionsbericht (CSV)")
        case .bitpanda: String(localized: "Transaktionsverlauf (CSV)")
        case .ibkr: String(localized: "Activity Statement (CSV)")
        }
    }

    /// Zeitzone der Zeiten in der Datei (Stand-Doc 16, Doc 19): Scalable schreibt deutsche Ortszeit,
    /// alle anderen UTC oder Zeiten mit Versatz; die Speicherung nutzt den Wert nur für Scalable.
    var zeitzone: TimeZone {
        switch self {
        case .scalable: TimeZone(identifier: "Europe/Berlin") ?? .current
        case .ibkr: TimeZone(identifier: "America/New_York") ?? .gmt
        case .tradeRepublic, .kraken, .binance, .coinbase, .bitpanda: .gmt
        }
    }

    var zeitzoneText: LocalizedStringKey {
        switch self {
        case .scalable: "Deutsche Ortszeit laut Datei"
        case .ibkr: "US-Ostküste (Annahme, in den IBKR-Einstellungen änderbar); die App zeigt deine Zeitzone"
        case .bitpanda: "Zeit mit Zeitzonen-Versatz laut Datei; die App zeigt deine Zeitzone"
        case .tradeRepublic, .kraken, .binance, .coinbase: "UTC laut Datei; die App zeigt deine Zeitzone"
        }
    }

    /// Zeile „Kosten“ im Import-Blatt.
    var kostenText: LocalizedStringKey {
        switch self {
        case .tradeRepublic, .scalable:
            "Gebühr und Steuer je Vorgang aus dem Export; im Trade anteilig aus seinen Käufen"
        case .kraken, .coinbase:
            "Gebühr je Vorgang in der Gegenwährung aus dem Export; im Trade anteilig aus seinen Käufen"
        case .binance:
            "Gebühr in der Gegenwährung oder im Coin (zum Kurs umgerechnet); Gebühr in BNB wird nicht verbucht und steht als Hinweis"
        case .bitpanda:
            "Spread steckt im Preis; Gebühr in BEST oder Krypto wird nicht verbucht und steht als Hinweis"
        case .ibkr:
            "Kommission je Order aus dem Auszug; im Trade anteilig aus seinen Käufen; Devisentausch steht als Hinweis"
        }
    }

    /// Vorgabe für die Bezeichnung eines neuen Kontos, wenn die Datei keines nennt.
    var kontoVorgabe: String {
        istKrypto ? String(localized: "Spot") : String(localized: "Depot")
    }
}

/// Was die App in der gewählten Datei erkannt hat. Erkannt wird am Inhalt, nicht am Dateinamen.
enum ErkannteDatei {
    case mt4(MT4Statement)
    case csv(CSVBroker, Kontobewegungen)
    case xtb(XTBAuszug)
    case mt5(MT5Bericht)
}

/// Summen je Währung für die Import-Vorschau (Gegencheck A4): Kontowährung zuerst, Fremdwährungen alphabetisch,
/// nichts umgerechnet. Vorher wurden USD, USDT und EUR einer Kraken- oder Binance-Datei als Kontowährung addiert.
struct Waehrungssummen {
    let kontowaehrung: String
    private var summen: [String: Decimal] = [:]

    init(_ posten: [(String, Decimal)], kontowaehrung: String) {
        self.kontowaehrung = kontowaehrung.uppercased()
        for (waehrung, betrag) in posten { summen[waehrung.uppercased(), default: 0] += betrag }
    }

    /// Fremdwährungen mit Posten, alphabetisch.
    var fremde: [String] { summen.keys.filter { $0 != kontowaehrung }.sorted() }

    /// Summe in Kontowährung, 0 ohne Posten darin.
    var kontowaehrungText: String { Format.betrag(summen[kontowaehrung] ?? 0, kontowaehrung) }

    /// Summen der Fremdwährungen als Text, leer ohne Fremdwährung.
    private var fremdeText: String {
        fremde.map { Format.betrag(summen[$0] ?? 0, $0) }.joined(separator: ", ")
    }

    /// Alle Summen in einer Zeile, Kontowährung zuerst.
    var alleText: String {
        fremde.isEmpty ? kontowaehrungText : kontowaehrungText + " · " + fremdeText
    }

    /// Zusatz einer Kachel: der gegebene Text, bei Fremdwährungen ergänzt um deren Summen.
    func zusatz(_ text: String) -> String {
        if fremde.isEmpty { return text }
        let dazu = fremdeText
        return text + " · " + String(localized: "dazu \(dazu)")
    }
}

/// Logik der Import-Vorschau ohne Ansicht (Paket A1 e, Doc 44): Format erkennen, Erkennungszeile, Summenprüfungen,
/// Knopftext und Importierbarkeit. `ImportBlatt` ruft sie auf; die App-Tests prüfen sie ohne SwiftUI.
enum Importlesung {
    /// Ergebnis des Lesens: erkannte Datei oder Meldung für den Nutzer.
    enum Ergebnis {
        case erkannt(ErkannteDatei)
        case fehler(String)
    }

    /// Summe laut Datei gegen die Summe der gelesenen Zeilen.
    struct Pruefung: Identifiable {
        let id: String
        let lautAuszug: Decimal
        let berechnet: Decimal
        var stimmt: Bool { lautAuszug == berechnet }
    }

    /// Erkennt das Format am Inhalt: erst XTB (Excel), dann die CSV-Köpfe von Trade Republic, Scalable,
    /// Kraken, Binance, Coinbase und Bitpanda (dieselbe Reihenfolge wie `Journal.importiereCSV`),
    /// sonst MetaTrader 4 (HTML).
    static func lies(_ daten: Data, dateiname: String, serverzeit: TimeZone, xtbZeit: TimeZone) -> Ergebnis {
        do {
            if XTBAuszug.erkennt(daten) {
                return .erkannt(.xtb(try XTBAuszug.lies(daten, zeitzone: xtbZeit)))
            }
            if dateiname.lowercased().hasSuffix(".xlsx") {
                return .fehler(String(localized: "Excel-Datei ohne Blatt „Closed Position History“: kein XTB-Kontoauszug aus xStation 5."))
            }
            // MetaTrader 5 speichert meist UTF-16; vor dem UTF-8-Text und vor dem MT4-Rückfall (Doc 48).
            if let text = MT5Bericht.text(daten), MT5Bericht.erkennt(text) {
                return .erkannt(.mt5(try MT5Bericht.lies(text, serverZeitzone: serverzeit)))
            }
            guard let text = Importtext.lies(daten) else {
                return .fehler(String(localized: "Die Datei ist weder lesbarer Text noch eine Excel-Datei."))
            }
            if TradeRepublicCSV.erkennt(text) {
                return .erkannt(.csv(.tradeRepublic, try TradeRepublicCSV.lies(text)))
            }
            if ScalableCSV.erkennt(text) {
                return .erkannt(.csv(.scalable, try ScalableCSV.lies(text, zeitzone: CSVBroker.scalable.zeitzone)))
            }
            if IBKRCSV.erkennt(text) {
                return .erkannt(.csv(.ibkr, try IBKRCSV.lies(text, zeitzone: CSVBroker.ibkr.zeitzone)))
            }
            if KrakenCSV.erkennt(text) {
                return .erkannt(.csv(.kraken, try KrakenCSV.lies(text)))
            }
            if BinanceCSV.erkennt(text) {
                return .erkannt(.csv(.binance, try BinanceCSV.lies(text)))
            }
            if BinanceCSV.istTransaktionsverlauf(text) {
                return .fehler(String(localized: "Binance-Transaktionsverlauf (Assets → Transaction History): Den liest die App nicht. Exportiere unter Orders → Spot Order → Trade History."))
            }
            if CoinbaseCSV.erkennt(text) {
                return .erkannt(.csv(.coinbase, try CoinbaseCSV.lies(text)))
            }
            if BitpandaCSV.erkennt(text) {
                return .erkannt(.csv(.bitpanda, try BitpandaCSV.lies(text)))
            }
            return .erkannt(.mt4(try MT4Statement.parse(html: text, serverZeitzone: serverzeit)))
        } catch MT4ImportFehler.keinMT4Auszug {
            return .fehler(String(localized: "Format nicht erkannt: kein MetaTrader-Auszug (MT4: HTML aus der Broker-Mail, nicht der Bericht aus dem Terminal; MT5: Handelsbericht), kein CSV-Export von Trade Republic, Scalable, Interactive Brokers, Kraken, Binance, Coinbase oder Bitpanda und keine XTB-Kontohistorie (Excel)."))
        } catch {
            return .fehler(fehlertext(error))
        }
    }

    /// Kontonummer bis auf die letzten vier Stellen verdeckt.
    static func maskiert(_ nummer: String) -> String {
        "••••" + String(nummer.suffix(4))
    }

    static func erkennung(_ auszug: MT4Statement) -> String {
        let art = auszug.kind == .daily ? String(localized: "Tagesauszug") : String(localized: "Monatsauszug")
        let nummer = maskiert(auszug.accountNumber)
        return String(localized: "Erkannt: MetaTrader 4 \(art) · \(auszug.broker) · Konto \(nummer) · Stichtag \(Format.datum(auszug.reportTime))")
    }

    static func erkennung(_ broker: CSVBroker, _ bewegungen: Kontobewegungen) -> String {
        let zeiten = bewegungen.ausfuehrungen.map(\.zeit) + bewegungen.geldbewegungen.map(\.zeit)
            + bewegungen.kapitalmassnahmen.map(\.zeit)
        var text = String(localized: "Erkannt: \(broker.name) \(broker.exportName)")
        if let von = zeiten.min(), let bis = zeiten.max() {
            text += " · " + String(localized: "\(Format.datum(von)) bis \(Format.datum(bis))")
        }
        return text
    }

    static func erkennung(_ auszug: XTBAuszug) -> String {
        let zeiten = auszug.positionen.map(\.closeTime) + auszug.kasse.geldbewegungen.map(\.zeit)
        var text = String(localized: "Erkannt: XTB Kontohistorie (Excel)")
        if let konto = auszug.konto {
            text += " · " + String(localized: "Konto \(maskiert(konto))")
        }
        if let von = zeiten.min(), let bis = zeiten.max() {
            text += " · " + String(localized: "\(Format.datum(von)) bis \(Format.datum(bis))")
        }
        return text
    }

    static func erkennung(_ bericht: MT5Bericht) -> String {
        let zeiten = bericht.positionen.map(\.closeTime) + bericht.kasse.geldbewegungen.map(\.zeit)
        var text = String(localized: "Erkannt: MetaTrader 5 Handelsbericht (HTML)")
        if let broker = bericht.broker, !broker.isEmpty { text += " · " + broker }
        if let konto = bericht.konto {
            text += " · " + String(localized: "Konto \(maskiert(konto))")
        }
        if let von = zeiten.min(), let bis = zeiten.max() {
            text += " · " + String(localized: "\(Format.datum(von)) bis \(Format.datum(bis))")
        }
        return text
    }

    /// Broker eines MT5-Kontos, wie die Speicherung ihn ablegt: „Company“ aus dem Bericht, sonst „MetaTrader 5“.
    static func broker(_ bericht: MT5Bericht) -> String {
        bericht.broker.flatMap { $0.isEmpty ? nil : $0 } ?? Journal.mt5BrokerVorgabe
    }

    /// Summenzeile unter „Positions“ gegen die gelesenen Positionen.
    static func pruefungen(_ bericht: MT5Bericht) -> [Pruefung] {
        guard let summe = bericht.positionenLautSumme else { return [] }
        let p = bericht.positionen
        return [
            Pruefung(id: String(localized: "Kommission gesamt"), lautAuszug: summe.commission,
                     berechnet: p.reduce(Decimal(0)) { $0 + $1.commission }),
            Pruefung(id: String(localized: "Swap gesamt"), lautAuszug: summe.swap,
                     berechnet: p.reduce(Decimal(0)) { $0 + $1.swap }),
            Pruefung(id: String(localized: "Ergebnis gesamt (Gross P/L)"), lautAuszug: summe.profit,
                     berechnet: p.reduce(Decimal(0)) { $0 + $1.profit }),
        ]
    }

    /// Summen des MT4-Auszugs gegen die gelesenen Zeilen; der Kontostand nur mit Vortagssaldo.
    static func pruefungen(_ auszug: MT4Statement) -> [Pruefung] {
        var liste = [
            Pruefung(id: String(localized: "Closed Trade P/L"),
                     lautAuszug: auszug.closedTradePL,
                     berechnet: auszug.closedPositions.reduce(Decimal(0)) { $0 + $1.netProfit }),
            Pruefung(id: String(localized: "Kommission gesamt"),
                     lautAuszug: auszug.closedTotals.commission,
                     berechnet: auszug.closedPositions.reduce(Decimal(0)) { $0 + $1.commission }),
        ]
        if let vortag = auszug.summary.previousBalance {
            liste.append(Pruefung(id: String(localized: "Kontostand"),
                                  lautAuszug: auszug.summary.balance,
                                  berechnet: vortag + auszug.summary.closedTradePL + auszug.summary.depositWithdrawal))
        }
        return liste
    }

    /// Summenzeilen „Total“ der XTB-Datei gegen die gelesenen Zeilen, wie die Speicherung sie prüft.
    static func pruefungen(_ auszug: XTBAuszug) -> [Pruefung] {
        var liste: [Pruefung] = []
        if let summe = auszug.positionenLautSumme {
            let p = auszug.positionen
            liste.append(Pruefung(id: String(localized: "Kommission gesamt"), lautAuszug: summe.commission,
                                  berechnet: p.reduce(Decimal(0)) { $0 + $1.commission }))
            liste.append(Pruefung(id: String(localized: "Swap gesamt"), lautAuszug: summe.swap,
                                  berechnet: p.reduce(Decimal(0)) { $0 + $1.swap }))
            liste.append(Pruefung(id: String(localized: "Ergebnis gesamt (Gross P/L)"), lautAuszug: summe.profit,
                                  berechnet: p.reduce(Decimal(0)) { $0 + $1.profit }))
        }
        if let kasse = auszug.kasseLautSumme {
            liste.append(Pruefung(id: String(localized: "Kasse gesamt"), lautAuszug: kasse, berechnet: auszug.kassenwirkung))
        }
        return liste
    }

    static func knopfText(_ erkannt: ErkannteDatei?) -> String {
        switch erkannt {
        case .mt4(let auszug)?: String(localized: "\(auszug.closedPositions.count) Trades importieren")
        case .csv(_, let bewegungen)?: String(localized: "\(bewegungen.ausfuehrungen.count) Ausführungen importieren")
        case .xtb(let auszug)?: String(localized: "\(auszug.positionen.count) Trades importieren")
        case .mt5(let bericht)?: String(localized: "\(bericht.positionen.count) Trades importieren")
        case nil: String(localized: "Importieren")
        }
    }

    /// Darf gespeichert werden? MT4 nur ohne Prüffehler, CSV nur mit Inhalt und gültigem Konto, XTB nur mit Inhalt,
    /// Kontonummer (aus der Datei oder eingegeben) und stimmenden Summen; MT5 wie XTB mit `mt5Nummer`.
    static func importierbar(_ erkannt: ErkannteDatei?, kontoGueltig: Bool, xtbNummer: String,
                             mt5Nummer: String = "") -> Bool {
        switch erkannt {
        case .mt4(let auszug)?:
            auszug.pruefe().isEmpty
        case .csv(_, let bewegungen)?:
            (bewegungen.ausfuehrungen.count + bewegungen.geldbewegungen.count + bewegungen.kapitalmassnahmen.count) > 0
                && kontoGueltig
        case .xtb(let auszug)?:
            (auszug.positionen.count + auszug.kasse.geldbewegungen.count) > 0
                && !xtbNummer.isEmpty && pruefungen(auszug).allSatisfy(\.stimmt)
        case .mt5(let bericht)?:
            (bericht.positionen.count + bericht.kasse.geldbewegungen.count) > 0
                && !mt5Nummer.isEmpty && pruefungen(bericht).allSatisfy(\.stimmt)
        case nil:
            false
        }
    }

    /// Fehlermeldung für Lesen und Speichern, in Alltagssprache.
    static func fehlertext(_ error: any Error) -> String {
        if let fehler = error as? SpeicherFehler {
            switch fehler {
            case .keinText:
                return String(localized: "Die Datei ist kein lesbarer Text.")
            case .auszugWidersprichtSeinenSummen(let liste):
                return String(localized: "Der Auszug widerspricht seinen eigenen Summen: \(liste.joined(separator: ", "))")
            case .andereKontowaehrung(let gespeichert, let angegeben):
                return String(localized: "Das Konto ist mit \(gespeichert) angelegt, nicht mit \(angegeben).")
            case .abweichenderDatensatz(let tickets):
                // Höchstens fünf Tickets nennen; häufigste Ursache bei MetaTrader und XTB ist eine andere Serverzeit (Doc 52 H5).
                let rest = tickets.count - 5
                let liste = tickets.prefix(5).joined(separator: ", ")
                let vorgaenge = rest > 0 ? String(localized: "\(liste) und \(rest) weitere") : liste
                return String(localized: "Vorgänge mit anderen Werten als beim früheren Import: \(vorgaenge). Bei MetaTrader und XTB: Stimmt die Serverzeit mit dem letzten Import überein?")
            case .unbekannterWert(let wert):
                return String(localized: "Unbekannter Wert in der Datenbank: \(wert)")
            case .ungueltigerWert(let wert):
                return String(localized: "Eingabe außerhalb des erlaubten Bereichs: \(wert)")
            }
        }
        if let fehler = error as? CSVImportFehler {
            switch fehler {
            case .unbekanntesFormat(let kopf):
                return String(localized: "CSV-Format nicht erkannt. Spalten der Datei: \(kopf.prefix(6).joined(separator: ", "))")
            case .fehlendeSpalte(let name):
                return String(localized: "Spalte fehlt in der Datei: \(name)")
            case .ungueltigeZahl(let zeile, let text):
                return String(localized: "Ungültige Zahl in Zeile \(zeile): \(text)")
            case .ungueltigeZeit(let zeile, let text):
                return String(localized: "Ungültige Zeit in Zeile \(zeile): \(text)")
            }
        }
        if let fehler = error as? XLSXFehler {
            switch fehler {
            case .keineXLSX:
                return String(localized: "Die Datei ist kein Excel-Archiv (XLSX).")
            case .fehlenderTeil(let name):
                return String(localized: "Die Excel-Datei ist unvollständig, es fehlt: \(name)")
            case .fehlendesBlatt(let name):
                return String(localized: "Blatt fehlt in der Excel-Datei: \(name)")
            }
        }
        if let fehler = error as? MT4ImportFehler {
            switch fehler {
            case .keinMT4Auszug:
                return String(localized: "Kein MetaTrader-4-Auszug: weder „Daily Confirmation“ noch „Monthly Statement“ im Titel.")
            case .unbekannteZeile(let abschnitt, let ticket, _):
                return String(localized: "Unbekannte Zeile im Abschnitt \(abschnitt), Ticket \(ticket).")
            case .unerwarteteSpalten(let abschnitt, let gefunden):
                return String(localized: "Unerwartete Spalten im Abschnitt \(abschnitt): \(gefunden.joined(separator: ", "))")
            case .ungueltigeZahl(let text):
                return String(localized: "Ungültige Zahl: \(text)")
            case .ungueltigeZeit(let text):
                return String(localized: "Ungültige Zeit: \(text)")
            case .unbekannteAuftragsart(let text):
                return String(localized: "Unbekannte Auftragsart: \(text)")
            case .fehlenderWert(let name):
                return String(localized: "Fehlender Wert: \(name)")
            }
        }
        return error.localizedDescription
    }
}
