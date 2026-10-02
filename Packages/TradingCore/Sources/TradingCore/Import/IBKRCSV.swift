import Foundation

/// Kontoauszug von Interactive Brokers als CSV („Performance & Reports → Statements → Activity → Download CSV“).
/// Aufbau nach der IBKR-Hilfe zu Activity Statements und veröffentlichten Beispielen: Jede Zeile beginnt mit
/// dem Abschnitt und der Zeilenart (`Header`, `Data`, `SubTotal`, `Total`), jeder Abschnitt hat eigene Spalten.
/// Gelesen werden „Account Information“, „Trades“ (Zeilen `Order`), „Deposits & Withdrawals“, „Dividends“,
/// „Withholding Tax“, „Interest“ und „Fees“. Devisentausch (Forex) zählt nicht als Trade.
/// Der Auszug hat keine Ausführungsnummer; die Kennung setzt sich aus Symbol, Zeit, Menge und Preis zusammen,
/// damit derselbe Trade aus einem zweiten Auszug als bekannt gilt.
/// Zeitzone der Ausführungszeiten: Vorgabe US-Ostküste (Annahme, in den Kontoeinstellungen änderbar).
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist (Stand 02.10.2026).
public enum IBKRCSV {
    static let handelsspalten = ["DataDiscriminator", "Asset Category", "Currency", "Symbol", "Date/Time",
                                 "Quantity", "T. Price", "Proceeds", "Comm/Fee"]

    public static func erkennt(_ text: String) -> Bool {
        let tabelle = CSVTabelle(text: text)
        return tabelle.kopf.prefix(2) == ["Statement", "Header"]
            && tabelle.zeilen.contains { $0.first == "Account Information" || $0.first == "Trades" }
    }

    /// Kontonummer und Basiswährung aus „Account Information“, soweit vorhanden.
    public static func konto(_ text: String) -> (nummer: String?, waehrung: String?) {
        var nummer: String?, waehrung: String?
        for z in CSVTabelle(text: text).zeilen where z.count >= 4 && z[0] == "Account Information" && z[1] == "Data" {
            switch z[2] {
            case "Account": nummer = z[3].trimmingCharacters(in: .whitespaces)
            case "Base Currency": waehrung = z[3].trimmingCharacters(in: .whitespaces)
            default: break
            }
        }
        return (nummer, waehrung)
    }

    public static func lies(_ text: String, zeitzone: TimeZone = TimeZone(identifier: "America/New_York")!) throws
        -> Kontobewegungen {
        guard erkennt(text) else { throw CSVImportFehler.unbekanntesFormat(kopf: CSVTabelle(text: text).kopf) }
        let tabelle = CSVTabelle(text: text)
        var ergebnis = Kontobewegungen()
        var koepfe: [String: [String]] = [:]
        for (n, z) in ([tabelle.kopf] + tabelle.zeilen).enumerated() where z.count >= 2 {
            let zeile = n + 1, abschnitt = z[0]
            if z[1] == "Header" {
                koepfe[abschnitt] = Array(z.dropFirst(2))
                continue
            }
            guard z[1] == "Data", let kopf = koepfe[abschnitt] else { continue }
            let werte = Array(z.dropFirst(2))
            func feld(_ name: String) -> String {
                guard let i = kopf.firstIndex(of: name), i < werte.count else { return "" }
                return werte[i].trimmingCharacters(in: .whitespaces)
            }
            func zahl(_ name: String) throws -> Decimal {
                try CSVWerte.zahl(feld(name).replacingOccurrences(of: ",", with: ""), .punkt, zeile: zeile)
            }
            switch abschnitt {
            case "Trades":
                try handel(kopf: kopf, feld: feld, zahl: zahl, z: z, zeile: zeile, zeitzone: zeitzone,
                           in: &ergebnis)
            case "Deposits & Withdrawals", "Dividends", "Withholding Tax", "Interest", "Fees", "Other Fees":
                let waehrung = feld("Currency")
                // Summenzeilen stehen als Data mit „Total …“ in der Währungsspalte.
                guard !waehrung.isEmpty, !waehrung.hasPrefix("Total") else { continue }
                let datum = feld(kopf.contains("Settle Date") ? "Settle Date" : "Date")
                let betrag = try zahl("Amount")
                let beschreibung = feld("Description")
                let art: Geldbewegung.Art = switch abschnitt {
                case "Deposits & Withdrawals": betrag < 0 ? .auszahlung : .einzahlung
                case "Dividends": .dividende
                case "Withholding Tax": .steuer
                case "Interest": .zinsen
                default: .gebuehr
                }
                ergebnis.geldbewegungen.append(Geldbewegung(
                    id: [abschnitt, datum, beschreibung, feld("Amount")].joined(separator: "|"),
                    zeit: try CSVWerte.zeit(datum: datum, uhrzeit: "00:00:00", zeitzone: zeitzone, zeile: zeile),
                    nurDatum: true, art: art, betrag: betrag, waehrung: waehrung,
                    kennung: kennung(beschreibung), rohzeile: z))
            default:
                continue
            }
        }
        return ergebnis
    }

    private static func handel(kopf: [String], feld: (String) -> String, zahl: (String) throws -> Decimal,
                               z: [String], zeile: Int, zeitzone: TimeZone,
                               in ergebnis: inout Kontobewegungen) throws {
        // „Order“ ist die Summe einer Order; „Trade“ und „ClosedLot“ sind Einzelheiten dazu.
        guard feld("DataDiscriminator") == "Order" else { return }
        let kategorie = feld("Asset Category"), symbol = feld("Symbol")
        // Devisentausch hat eigene Spalten („Comm in EUR“) und ist kein Trade.
        guard kategorie != "Forex" else {
            ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: "Forex \(symbol)", folge: .nichtVerbucht))
            return
        }
        if let fehlt = handelsspalten.first(where: { !kopf.contains($0) }) {
            throw CSVImportFehler.fehlendeSpalte(fehlt)
        }
        let menge = try zahl("Quantity"), preis = try zahl("T. Price")
        guard menge != 0 else { return }
        let zeitpunkt = feld("Date/Time")
        let zeit = try CSVWerte.zeit(datum: String(zeitpunkt.prefix(10)),
                                     uhrzeit: String(zeitpunkt.suffix(8)), zeitzone: zeitzone, zeile: zeile)
        ergebnis.ausfuehrungen.append(Ausfuehrung(
            id: [symbol, zeitpunkt, feld("Quantity"), feld("T. Price")].joined(separator: "|"),
            zeit: zeit, kennung: symbol, name: symbol, seite: menge > 0 ? .buy : .sell, menge: abs(menge),
            preis: preis, betrag: try zahl("Proceeds"), gebuehr: try zahl("Comm/Fee"), waehrung: feld("Currency"),
            produktart: produktart(kategorie), rohzeile: z))
    }

    static func produktart(_ kategorie: String) -> Produktart {
        switch kategorie.lowercased() {
        case "stocks": .aktie
        case "equity and index options", "options on futures", "futures", "warrants": .derivat
        case "bonds": .anleihe
        case "cfds": .cfd
        case "crypto", "cryptocurrency": .krypto
        case "mutual funds": .fonds
        default: .unbekannt
        }
    }

    /// ISIN aus „AAPL(US0378331005) Cash Dividend …“, sonst das Symbol vor der Klammer; `nil` ohne beides.
    static func kennung(_ beschreibung: String) -> String? {
        guard let auf = beschreibung.firstIndex(of: "("), let zu = beschreibung[auf...].firstIndex(of: ")") else {
            return nil
        }
        let innen = beschreibung[beschreibung.index(after: auf)..<zu]
        if innen.count == 12, innen.prefix(2).allSatisfy({ $0.isASCII && $0.isLetter }) { return String(innen) }
        let symbol = beschreibung[..<auf].trimmingCharacters(in: .whitespaces)
        return symbol.isEmpty ? nil : symbol
    }
}
