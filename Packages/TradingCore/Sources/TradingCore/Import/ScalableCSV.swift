import Foundation

/// Transaktionsexport von Scalable Capital (CSV mit Semikolon, deutsches Zahlenformat; R2).
/// Belegte Zeilen nennen die Vorgangsart englisch („Buy“, „Sell“, „Savings plan“, „Distribution“,
/// „Deposit“, „Withdrawal“, „Taxes“) mit positiver Stückzahl auch beim Verkauf
/// (PP-Forum 2024, Ghostfolio-Exporter #272 2025). Deutsche Namen aus Acutic (2026) werden
/// ebenfalls gelesen. Datum und Uhrzeit sind deutsche Ortszeit: Buchungen ohne Uhrzeit stehen
/// als 01:00 oder 02:00, also Mitternacht UTC.
/// Format an einer echten Datei geprüft (Tim, 05.10.2026: 73 Ausführungen, Turbos, deutsches Zahlenformat).
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
        let format = zahlformat(tabelle, spalten: spalten)
        var ergebnis = Kontobewegungen()
        for (n, z) in tabelle.zeilen.enumerated() {
            let zeile = n + 2
            func feld(_ name: String) -> String {
                let i = spalten[name]!
                return i < z.count ? z[i] : ""
            }
            func zahl(_ name: String) throws -> Decimal {
                // Mit Punkt als Dezimalzeichen ist das Komma ein Tausendertrenner.
                let text = format == .punkt ? feld(name).replacingOccurrences(of: ",", with: "") : feld(name)
                return try CSVWerte.zahl(text, format, zeile: zeile)
            }
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
                // `assetType` sagt nur Security oder Cash; die Produktart bleibt `unbekannt`,
                // außer der Name zeigt ein Hebelprodukt („… Short 8.000,00 Turbo Open End …“).
                let preis = try zahl("price")
                ergebnis.ausfuehrungen.append(Ausfuehrung(
                    id: feld("reference"), zeit: zeit, nurDatum: nurDatum, kennung: isin, name: feld("description"),
                    seite: art == .kauf ? .buy : .sell, menge: menge,
                    preis: preis != 0 || menge == 0 ? preis : abs(betrag) / menge, betrag: betrag,
                    gebuehr: gebuehr, steuer: try zahl("tax"), waehrung: feld("currency"),
                    sparplan: typ.lowercased().contains("sparplan") || typ.lowercased() == "savings plan",
                    produktart: Hebelprodukt.erkenne(feld("description")) != nil ? .derivat : .unbekannt,
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

    /// Dezimalzeichen der Datei (Doc 52, H2): Scalable schreibt mit deutscher Oberfläche „1.000,00“,
    /// mit englischer vermutlich „1,000.00“ oder „12.34“ (R2: widersprüchlich belegt).
    /// Entscheidet das letzte Trennzeichen in einem Feld mit beiden, sonst ein Trennzeichen, dem nicht
    /// genau drei Ziffern folgen (dann kein Tausendertrenner). Ohne Hinweis bleibt es beim Komma.
    static func zahlformat(_ tabelle: CSVTabelle, spalten: [String: Int]) -> CSVWerte.Zahlformat {
        let indizes = ["shares", "price", "amount", "fee", "tax"].compactMap { spalten[$0] }
        var komma = false, punkt = false
        for z in tabelle.zeilen {
            for i in indizes where i < z.count {
                let wert = z[i].trimmingCharacters(in: .whitespaces)
                if let k = wert.lastIndex(of: ","), let p = wert.lastIndex(of: ".") { return p > k ? .punkt : .komma }
                for zeichen: Character in [",", "."] {
                    guard let stelle = wert.lastIndex(of: zeichen) else { continue }
                    let danach = wert[wert.index(after: stelle)...]
                    if danach.count != 3 && danach.allSatisfy(\.isNumber) {
                        if zeichen == "," { komma = true } else { punkt = true }
                    }
                }
            }
        }
        return punkt && !komma ? .punkt : .komma
    }
}
