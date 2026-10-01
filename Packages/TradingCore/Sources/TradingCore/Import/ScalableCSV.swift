import Foundation

/// Transaktionsexport von Scalable Capital (CSV mit Semikolon, deutsches Zahlenformat; R2).
/// Datum und Uhrzeit gelten als deutsche Ortszeit (Annahme aus R2, nicht belegt).
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum ScalableCSV {
    static let pflichtspalten = ["date", "time", "status", "reference", "description", "assetType", "type",
                                 "isin", "shares", "price", "amount", "fee", "tax", "currency"]

    public static func erkennt(_ text: String) -> Bool {
        let tabelle = CSVTabelle(text: text)
        return tabelle.kopf.contains("assetType") && (try? tabelle.spalten(pflichtspalten)) != nil
    }

    public static func lies(_ text: String, zeitzone: TimeZone = TimeZone(identifier: "Europe/Berlin")!) throws
        -> Kontobewegungen {
        let tabelle = CSVTabelle(text: text)
        let spalten = try tabelle.spalten(pflichtspalten)
        var ergebnis = Kontobewegungen()
        for (n, z) in tabelle.zeilen.enumerated() {
            let zeile = n + 2
            func feld(_ name: String) -> String {
                let i = spalten[name]!
                return i < z.count ? z[i] : ""
            }
            func zahl(_ name: String) throws -> Decimal { try CSVWerte.zahl(feld(name), .komma, zeile: zeile) }
            // Nur ausgeführte Vorgänge zählen; stornierte Orders bleiben als verworfen erhalten (Regel 5).
            guard feld("status") == "Executed" else {
                ergebnis.verworfen.append(feld("reference"))
                continue
            }
            let zeit = try CSVWerte.zeit(datum: feld("date"), uhrzeit: feld("time"), zeitzone: zeitzone, zeile: zeile)
            let nurDatum = feld("time").hasPrefix("00:00:00")
            let art = feld("type"), isin = feld("isin")
            switch (feld("assetType"), art) {
            case ("Security", "Order"), ("Security", "Sparplanausführung"):
                let stueck = try zahl("shares")
                ergebnis.ausfuehrungen.append(Ausfuehrung(
                    id: feld("reference"), zeit: zeit, nurDatum: nurDatum, kennung: isin, name: feld("description"),
                    seite: stueck < 0 ? .sell : .buy, menge: abs(stueck), preis: try zahl("price"),
                    betrag: try zahl("amount"), gebuehr: try zahl("fee"), steuer: try zahl("tax"),
                    waehrung: feld("currency"), sparplan: art == "Sparplanausführung", rohzeile: z))
            case ("Security", "Ausschüttung"), ("Security", "Dividende"), ("Cash", _):
                let betrag = try zahl("amount")
                let geldart: Geldbewegung.Art = switch art {
                case "Ausschüttung", "Dividende": .dividende
                case "Ein-/Auszahlung": betrag < 0 ? Geldbewegung.Art.auszahlung : .einzahlung
                case "Steuer": .steuer
                case "Zinsen": .zinsen
                default: .sonstiges
                }
                ergebnis.geldbewegungen.append(Geldbewegung(
                    id: feld("reference"), zeit: zeit, nurDatum: nurDatum, art: geldart, betrag: betrag,
                    steuer: try zahl("tax"), waehrung: feld("currency"), kennung: isin.isEmpty ? nil : isin,
                    rohzeile: z))
            default:
                throw CSVImportFehler.unbekannteArt(zeile: zeile, art: "\(feld("assetType")) \(art)")
            }
        }
        return ergebnis
    }
}
