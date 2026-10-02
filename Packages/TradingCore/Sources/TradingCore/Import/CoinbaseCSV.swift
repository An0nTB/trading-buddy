import Foundation

/// Transaktionsbericht von Coinbase (Statements → Transaction history, CSV; Coinbase Help 2026).
/// Köpfe laut CoinTaxman src/book.py (GitHub, 2026): v4 ab 2023/2024 mit `ID` und Vorspann aus Leerzeile,
/// „Transactions“ und Nutzerzeile; v2/v3 ab Ende 2021 mit `Spot Price Currency`; v1 bis Mitte 2021 mit
/// „EUR“ im Spaltennamen. Zeit in UTC („2026-03-02 09:00:00 UTC“, vor v4 „2021-05-01T10:00:00Z“).
/// Beträge mit „€“ und in v4 teils negativ, deshalb gilt der Betrag ohne Vorzeichen; die Richtung kommt aus der
/// Vorgangsart. Alle Werte stehen in `Price Currency`, auch bei Advanced Trade gegen USDC (Annahme, ungeprüft).
/// Convert nennt die Zielmenge nur in `Notes` („Converted 0.01 ETH to 24.63 USDC“).
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum CoinbaseCSV {
    /// Spalten je Bedeutung, neuester Name zuerst.
    static let namen: [(rolle: String, kandidaten: [String])] = [
        ("zeit", ["Timestamp"]), ("typ", ["Transaction Type"]), ("asset", ["Asset"]),
        ("menge", ["Quantity Transacted"]),
        ("preis", ["Price at Transaction", "Spot Price at Transaction", "EUR Spot Price at Transaction"]),
        ("wert", ["Subtotal", "EUR Subtotal"]), ("gebuehr", ["Fees and/or Spread", "Fees", "EUR Fees"]),
        ("notiz", ["Notes"]),
    ]
    static let waehrungsspalten = ["Price Currency", "Spot Price Currency"]
    /// Echte Fiat-Währungen für Ein- und Auszahlungen; Stablecoins kommen als Send und Receive.
    static let fiat: Set<String> = ["EUR", "USD", "CHF", "GBP"]
    static let kaeufe: Set<String> = ["Buy", "Advanced Trade Buy"]
    static let verkaeufe: Set<String> = ["Sell", "Advanced Trade Sell"]
    static let ertraege: [String: Geldbewegung.Art] = [
        "Staking Income": .zinsen, "Rewards Income": .zinsen, "Inflation Reward": .zinsen,
        "Learning Reward": .sonstiges, "Coinbase Earn": .sonstiges,
    ]

    struct Spalten {
        var index: [String: Int]
        /// `nil` bei v1: Dort steht die Währung nur im Spaltennamen und ist immer EUR.
        var waehrung: Int?
        /// `nil` vor v4.
        var id: Int?
    }

    static func tabelle(_ text: String) -> (tabelle: CSVTabelle, versatz: Int)? {
        for erstes in ["ID", "Timestamp"] {
            if let kopf = KryptoWerte.abKopf(text, erstesFeld: erstes) {
                return (CSVTabelle(text: kopf.text), kopf.versatz)
            }
        }
        return nil
    }

    static func spalten(_ kopf: [String]) throws -> Spalten {
        var index: [String: Int] = [:]
        for (rolle, kandidaten) in namen {
            guard let i = kandidaten.compactMap({ kopf.firstIndex(of: $0) }).first
            else { throw CSVImportFehler.fehlendeSpalte(kandidaten[0]) }
            index[rolle] = i
        }
        let waehrung = waehrungsspalten.compactMap { kopf.firstIndex(of: $0) }.first
        if waehrung == nil && !kopf.contains("EUR Subtotal") {
            throw CSVImportFehler.fehlendeSpalte(waehrungsspalten[0])
        }
        return Spalten(index: index, waehrung: waehrung, id: kopf.firstIndex(of: "ID"))
    }

    public static func erkennt(_ text: String) -> Bool {
        guard let t = tabelle(text) else { return false }
        return (try? spalten(t.tabelle.kopf)) != nil
    }

    public static func lies(_ text: String) throws -> Kontobewegungen {
        guard let t = tabelle(text) else { throw CSVImportFehler.unbekanntesFormat(kopf: CSVTabelle(text: text).kopf) }
        let s = try spalten(t.tabelle.kopf)
        var ergebnis = Kontobewegungen()
        for (n, z) in t.tabelle.zeilen.enumerated() {
            // Kopf ist Zeile 1 der Tabelle, davor liegt der Vorspann.
            try lies(Zeile(z: z, nummer: n + 2 + t.versatz, s: s), in: &ergebnis)
        }
        return ergebnis
    }

    struct Zeile {
        let z: [String]
        let nummer: Int
        let s: Spalten

        func feld(_ i: Int?) -> String {
            guard let i, i < z.count else { return "" }
            return z[i].trimmingCharacters(in: .whitespaces)
        }
        func feld(_ rolle: String) -> String { feld(s.index[rolle]) }
        func zahl(_ rolle: String) throws -> Decimal { abs(try KryptoWerte.zahl(feld(rolle), zeile: nummer)) }
        var waehrung: String { s.waehrung == nil ? "EUR" : feld(s.waehrung).uppercased() }
        /// v4 liefert eine ID; ältere Berichte nicht, dann ergibt die Zeile selbst die Kennung.
        var id: String {
            let roh = feld(s.id)
            return roh.isEmpty ? "coinbase-\(feld("zeit"))-\(feld("typ"))-\(feld("asset"))-\(feld("menge"))" : roh
        }
        func zeit() throws -> Date {
            let t = feld("zeit")
            // Vor v4 ISO mit „T“ und „Z“, ab v4 Leerzeichen und „UTC“ (das selbst ein T enthält).
            return t.contains(" ") ? try KryptoWerte.utc(t, zeile: nummer) : try KryptoWerte.iso(t, zeile: nummer)
        }
    }

    static func lies(_ r: Zeile, in e: inout Kontobewegungen) throws {
        let typ = r.feld("typ"), asset = r.feld("asset").uppercased(), gegen = r.waehrung
        func hinweis() {
            e.hinweise.append(Importhinweis(zeile: r.nummer, vorgang: "\(typ) \(asset)", folge: .nichtVerbucht))
        }
        let menge = try r.zahl("menge"), preis = try r.zahl("preis"), gebuehr = try r.zahl("gebuehr")
        let zwischensumme = try r.zahl("wert")
        // Alte Zeilen ohne Subtotal: Wert aus Menge mal Preis (wie CoinTaxman).
        let wert = zwischensumme != 0 ? zwischensumme : menge * preis

        if typ == "Deposit" || typ == "Withdrawal" {
            guard fiat.contains(asset), gebuehr == 0 || gegen == asset else { return hinweis() }
            e.geldbewegungen.append(Geldbewegung(
                id: r.id, zeit: try r.zeit(), art: typ == "Deposit" ? .einzahlung : .auszahlung,
                betrag: typ == "Deposit" ? menge : -menge, gebuehr: -gebuehr, waehrung: asset, rohzeile: r.z))
            return
        }
        guard KryptoWerte.geldwaehrungen.contains(gegen), !fiat.contains(asset) else { return hinweis() }
        let zeit = try r.zeit()
        func ausfuehrung(_ id: String, _ basis: String, _ seite: Side, menge: Decimal, preis: Decimal,
                         betrag: Decimal, gebuehr: Decimal) -> Ausfuehrung {
            Ausfuehrung(id: id, zeit: zeit, kennung: KryptoWerte.kennung(basis, gegen), name: basis, seite: seite,
                        menge: menge, preis: preis, betrag: betrag, gebuehr: gebuehr, waehrung: gegen,
                        rohzeile: r.z)
        }

        if kaeufe.contains(typ) || verkaeufe.contains(typ) {
            let kauf = kaeufe.contains(typ)
            e.ausfuehrungen.append(ausfuehrung(r.id, asset, kauf ? .buy : .sell, menge: menge, preis: preis,
                                               betrag: kauf ? -wert : wert, gebuehr: -gebuehr))
        } else if let art = ertraege[typ] {
            // Ertrag als Kauf zum Marktwert plus Gutschrift in gleicher Höhe: Kassenwirkung netto 0.
            e.ausfuehrungen.append(ausfuehrung(r.id, asset, .buy, menge: menge, preis: preis, betrag: -wert,
                                               gebuehr: -gebuehr))
            e.geldbewegungen.append(Geldbewegung(
                id: "\(r.id)-ertrag", zeit: zeit, art: art, betrag: wert, waehrung: gegen,
                kennung: KryptoWerte.kennung(asset, gegen), rohzeile: r.z))
        } else if typ == "Convert" {
            guard let ziel = umtausch(r.feld("notiz"), von: asset), !fiat.contains(ziel.asset), wert > gebuehr
            else { return hinweis() }
            let zielwert = wert - gebuehr
            e.ausfuehrungen.append(ausfuehrung(r.id, asset, .sell, menge: menge, preis: preis, betrag: wert,
                                               gebuehr: -gebuehr))
            e.ausfuehrungen.append(ausfuehrung("\(r.id)-ziel", ziel.asset, .buy, menge: ziel.menge,
                                               preis: zielwert / ziel.menge, betrag: -zielwert, gebuehr: 0))
        } else {
            // Send, Receive und Unbekanntes: Krypto ohne Gegenwert in Geld.
            hinweis()
        }
    }

    /// „Converted 0.01 ETH to 24.63 USDC“ → (24.63, "USDC"). `nil`, wenn der Text anders lautet,
    /// das Ausgangs-Asset nicht passt oder die Zielmenge mehrdeutig ist.
    static func umtausch(_ notiz: String, von asset: String) -> (menge: Decimal, asset: String)? {
        let w = notiz.split(separator: " ").map(String.init)
        guard w.count == 6, w[0] == "Converted", w[3] == "to", w[2].uppercased() == asset,
              let menge = notizzahl(w[4]), menge > 0
        else { return nil }
        return (menge, w[5].uppercased())
    }

    /// Zahl im Freitext: „1,234.5“ hat Tausenderkommas; ein einzelnes Komma ohne Punkt ist laut CoinTaxman
    /// ein Dezimalkomma („0,123“). „1,234“ bleibt mehrdeutig und wird nicht geraten.
    static func notizzahl(_ text: String) -> Decimal? {
        var t = text
        let kommas = t.filter { $0 == "," }.count
        if t.contains(".") || kommas > 1 {
            t.removeAll { $0 == "," }
        } else if kommas == 1 {
            guard t.split(separator: ",", omittingEmptySubsequences: false).last?.count != 3 else { return nil }
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        return try? CSVWerte.zahl(t, .punkt, zeile: 0)
    }
}
