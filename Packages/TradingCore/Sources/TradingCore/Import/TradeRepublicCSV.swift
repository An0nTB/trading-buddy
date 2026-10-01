import Foundation

/// Transaktionsexport von Trade Republic (CSV, seit 04/2026; R2). Zwei Varianten sind belegt:
/// Komma mit Anführungszeichen und `mcc_code`, älter Semikolon mit `value_date`.
/// Zeiten stehen in UTC. Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum TradeRepublicCSV {
    static let pflichtspalten = ["datetime", "category", "type", "name", "symbol", "shares", "price", "amount",
                                 "fee", "tax", "currency", "description", "transaction_id"]

    /// Erkennt den Export am Kopf, nicht am Dateinamen (Regel 1).
    public static func erkennt(_ text: String) -> Bool {
        let tabelle = CSVTabelle(text: text)
        return tabelle.kopf.contains("account_type") && (try? tabelle.spalten(pflichtspalten)) != nil
    }

    public static func lies(_ text: String) throws -> Kontobewegungen {
        let tabelle = CSVTabelle(text: text)
        let spalten = try tabelle.spalten(pflichtspalten)
        var ergebnis = Kontobewegungen()
        for (n, z) in tabelle.zeilen.enumerated() {
            let zeile = n + 2
            func feld(_ name: String) -> String {
                let i = spalten[name]!
                return i < z.count ? z[i] : ""
            }
            func zahl(_ name: String) throws -> Decimal { try CSVWerte.zahl(feld(name), .punkt, zeile: zeile) }
            let (zeit, nurDatum) = try zeitpunkt(feld("datetime"), zeile: zeile)
            let art = feld("type")
            switch feld("category") {
            case "TRADING":
                guard art == "BUY" || art == "SELL" else { throw CSVImportFehler.unbekannteArt(zeile: zeile, art: art) }
                let beschreibung = feld("description")
                ergebnis.ausfuehrungen.append(Ausfuehrung(
                    id: feld("transaction_id"), zeit: zeit, nurDatum: nurDatum, kennung: feld("symbol"),
                    name: feld("name"), seite: art == "BUY" ? .buy : .sell, menge: abs(try zahl("shares")),
                    preis: try zahl("price"), betrag: try zahl("amount"), gebuehr: try zahl("fee"),
                    steuer: try zahl("tax"), waehrung: feld("currency"),
                    sparplan: beschreibung.hasPrefix("Savings plan") || beschreibung.contains("Sparplan"),
                    rohzeile: z))
            case "CASH":
                let geldart: Geldbewegung.Art = switch art {
                case "CUSTOMER_INPAYMENT": .einzahlung
                case "CUSTOMER_OUTPAYMENT": .auszahlung
                case "DIVIDEND": .dividende
                case "INTEREST_PAYMENT": .zinsen
                case "TAX_OPTIMIZATION": .steuer
                default: .sonstiges
                }
                let kennung = feld("symbol")
                ergebnis.geldbewegungen.append(Geldbewegung(
                    id: feld("transaction_id"), zeit: zeit, nurDatum: nurDatum, art: geldart,
                    betrag: try zahl("amount"), steuer: try zahl("tax"), waehrung: feld("currency"),
                    kennung: kennung.isEmpty ? nil : kennung, rohzeile: z))
            default:
                throw CSVImportFehler.unbekannteArt(zeile: zeile, art: feld("category"))
            }
        }
        return ergebnis
    }

    /// „2026-03-02T09:15:12.120Z“ in UTC; Uhrzeit 00:00:00 heißt „nur Datum“ (Regel 4).
    static func zeitpunkt(_ text: String, zeile: Int) throws -> (Date, Bool) {
        let teile = text.split(separator: "T")
        guard teile.count == 2, text.hasSuffix("Z") else {
            throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: text)
        }
        let uhrzeit = String(teile[1].dropLast())
        let zeit = try CSVWerte.zeit(datum: String(teile[0]), uhrzeit: uhrzeit,
                                     zeitzone: TimeZone(secondsFromGMT: 0)!, zeile: zeile)
        return (zeit, uhrzeit.hasPrefix("00:00:00"))
    }
}
