import Foundation

/// Transaktionsexport von Scalable Capital (CSV mit Semikolon, deutsches Zahlenformat; R2).
/// Belegte Zeilen nennen die Vorgangsart englisch („Buy“, „Sell“, „Savings plan“, „Distribution“,
/// „Deposit“, „Withdrawal“, „Taxes“) mit positiver Stückzahl auch beim Verkauf
/// (PP-Forum 2024, Ghostfolio-Exporter #272 2025). Deutsche Namen aus Acutic (2026) werden
/// ebenfalls gelesen. Datum und Uhrzeit sind deutsche Ortszeit: Buchungen ohne Uhrzeit stehen
/// als 01:00 oder 02:00, also Mitternacht UTC.
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum ScalableCSV {
    static let pflichtspalten = ["date", "time", "status", "reference", "description", "assetType", "type",
                                 "isin", "shares", "price", "amount", "fee", "tax", "currency"]

    enum Vorgang: Equatable {
        case kauf, verkauf, geld(Geldbewegung.Art), kapitalmassnahme, unbekannt
    }

    /// Bedeutung der Spalte `type`; „Order“ ohne Richtung entscheidet das Vorzeichen des Betrags.
    static func vorgang(_ typ: String, betrag: Decimal) -> Vorgang {
        switch typ.lowercased() {
        case "buy", "savings plan", "sparplanausführung", "kauf": .kauf
        case "sell", "verkauf": .verkauf
        case "order": betrag < 0 ? .kauf : .verkauf
        case "distribution", "dividend", "ausschüttung", "dividende": .geld(.dividende)
        case "deposit", "einzahlung": .geld(.einzahlung)
        case "withdrawal", "auszahlung": .geld(.auszahlung)
        case "ein-/auszahlung": .geld(betrag < 0 ? Geldbewegung.Art.auszahlung : .einzahlung)
        case "taxes", "tax", "steuer", "steuern": .geld(.steuer)
        case "interest", "zinsen": .geld(.zinsen)
        case "fee", "fees", "gebühr", "gebühren": .geld(.gebuehr)
        case "corporate action", "kapitalmaßnahme", "security transfer", "wertpapierübertrag": .kapitalmassnahme
        default: .unbekannt
        }
    }

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
            guard feld("status").lowercased() == "executed" else {
                ergebnis.verworfen.append(feld("reference"))
                continue
            }
            let zeit = try CSVWerte.zeit(datum: feld("date"), uhrzeit: feld("time"), zeitzone: zeitzone, zeile: zeile)
            let nurDatum = feld("time").hasPrefix("00:00:00") || CSVWerte.istMitternachtUTC(zeit)
            let typ = feld("type"), isin = feld("isin")
            let betrag = try zahl("amount"), menge = abs(try zahl("shares"))
            // Gebühr ist immer ein Abzug; Quellen zeigen sie mal mit, mal ohne Minus.
            let gebuehr = -abs(try zahl("fee"))
            let art = vorgang(typ, betrag: betrag)

            switch art {
            case .kauf, .verkauf:
                // Produktart bleibt `unbekannt`: `assetType` sagt nur Security oder Cash.
                let preis = try zahl("price")
                ergebnis.ausfuehrungen.append(Ausfuehrung(
                    id: feld("reference"), zeit: zeit, nurDatum: nurDatum, kennung: isin, name: feld("description"),
                    seite: art == .kauf ? .buy : .sell, menge: menge,
                    preis: preis != 0 || menge == 0 ? preis : abs(betrag) / menge, betrag: betrag,
                    gebuehr: gebuehr, steuer: try zahl("tax"), waehrung: feld("currency"),
                    sparplan: typ.lowercased().contains("sparplan") || typ.lowercased() == "savings plan",
                    rohzeile: z))
            case .geld(let geldart):
                ergebnis.geldbewegungen.append(Geldbewegung(
                    id: feld("reference"), zeit: zeit, nurDatum: nurDatum, art: geldart, betrag: betrag,
                    gebuehr: gebuehr, steuer: try zahl("tax"), waehrung: feld("currency"),
                    kennung: isin.isEmpty ? nil : isin, rohzeile: z))
            case .kapitalmassnahme:
                // Richtung und Verhältnis sind nicht belegt; nur festhalten und melden.
                ergebnis.kapitalmassnahmen.append(Kapitalmassnahme(
                    id: feld("reference"), zeit: zeit, art: .unbekannt, vorgang: typ, kennung: isin,
                    menge: try zahl("shares"), rohzeile: z))
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: typ, folge: .nichtVerbucht))
            case .unbekannt:
                if betrag != 0 {
                    ergebnis.geldbewegungen.append(Geldbewegung(
                        id: feld("reference"), zeit: zeit, nurDatum: nurDatum, art: .sonstiges, betrag: betrag,
                        gebuehr: gebuehr, steuer: try zahl("tax"), waehrung: feld("currency"),
                        kennung: isin.isEmpty ? nil : isin, rohzeile: z))
                }
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: "\(feld("assetType")) \(typ)",
                                                       folge: betrag != 0 ? .alsSonstiges : .nichtVerbucht))
            }
        }
        return ergebnis
    }
}
