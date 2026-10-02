import Foundation

/// Transaktionsexport von Trade Republic (CSV, seit 04/2026; R2). Zwei Varianten sind belegt:
/// Komma mit Anführungszeichen und `mcc_code`, älter Semikolon mit `value_date`.
/// Zeiten stehen in UTC. Zuordnung der Vorgangsarten nach den Testdateien und dem
/// TradeRepublicCSVExtractor von Portfolio Performance (Stand 30.09.2026).
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum TradeRepublicCSV {
    static let pflichtspalten = ["datetime", "category", "type", "name", "symbol", "shares", "price", "amount",
                                 "fee", "tax", "currency", "description", "transaction_id"]

    /// Geldbewegungen mit fester Bedeutung (Kategorie CASH).
    static let geldarten: [String: Geldbewegung.Art] = [
        "DIVIDEND": .dividende, "DISTRIBUTION": .dividende, "DIVIDEND_EQUIVALENT_PAYMENT": .dividende,
        "INTEREST_PAYMENT": .zinsen, "TAX_OPTIMIZATION": .steuer, "EARNINGS": .steuer,
        "PRE_DETERMINED_TAX_BASE": .steuer, "SEC_ACCOUNT": .steuer, "TAX": .steuer,
        "FEE": .gebuehr, "CARD_ORDERING_FEE": .gebuehr,
        "BENEFITS_SAVEBACK": .sonstiges, "BONUS": .sonstiges, "REFERRAL": .sonstiges,
    ]
    /// Geld rein oder raus, Richtung nach Vorzeichen. Kartenzahlungen zählen als Auszahlung.
    static let einAuszahlungen: Set<String> = [
        "CUSTOMER_INBOUND", "CUSTOMER_INPAYMENT", "CUSTOMER_OUTBOUND_REQUEST", "CUSTOMER_INPAYMENT_REVERSAL",
        "TRANSFER_IN", "TRANSFER_OUT", "TRANSFER_INBOUND", "TRANSFER_OUTBOUND", "TRANSFER_INSTANT_INBOUND",
        "TRANSFER_INSTANT_OUTBOUND", "TRANSFER_DIRECT_DEBIT_INBOUND", "VIBAN_TRANSFER_INBOUND",
        "VIBAN_TRANSFER_OUTBOUND", "GENERAL_INBOUND", "MANUAL_CASH_TRANSFER", "PAYMENT", "GIFT",
        "CARD_TRANSACTION", "CARD_TRANSACTION_INTERNATIONAL", "CARD_TRANSACTION_REFUND",
        "CARD_TRANSACTION_REFUND_REVERSAL",
    ]
    /// Geldzeilen mit Stückzahl, die ein Wertpapier ins Depot bringen oder schließen.
    static let kaeufe: Set<String> = ["PRIVATE_MARKET_BUY"]
    static let verkaeufe: Set<String> = ["PRIVATE_MARKET_SELL", "FINAL_MATURITY", "TILG"]
    /// Ausbuchung ohne Geld; den Erlös bringt eine eigene Zeile `FINAL_MATURITY` oder `TILG`.
    static let ausbuchungen: Set<String> = ["REDEMPTION", "FINAL_MATURITY", "WARRANT_EXERCISE"]

    /// Erkennt den Export am Kopf, nicht am Dateinamen (Regel 1).
    public static func erkennt(_ text: String) -> Bool {
        let tabelle = CSVTabelle(text: text)
        return tabelle.kopf.contains("account_type") && (try? tabelle.spalten(pflichtspalten)) != nil
    }

    public static func lies(_ text: String) throws -> Kontobewegungen {
        let tabelle = CSVTabelle(text: text)
        let spalten = try tabelle.spalten(pflichtspalten)
        // Optional: ältere Exporte ohne `asset_class` ergeben Produktart `unbekannt`.
        let klasse = tabelle.kopf.firstIndex(of: "asset_class")
        var ergebnis = Kontobewegungen()
        for (n, z) in tabelle.zeilen.enumerated() {
            let zeile = n + 2
            func feld(_ name: String) -> String {
                let i = spalten[name]!
                return i < z.count ? z[i] : ""
            }
            func zahl(_ name: String) throws -> Decimal { try CSVWerte.zahl(feld(name), .punkt, zeile: zeile) }
            let (zeit, nurDatum) = try zeitpunkt(feld("datetime"), zeile: zeile)
            let kategorie = feld("category"), art = feld("type")
            let betrag = try zahl("amount"), menge = abs(try zahl("shares"))

            func ausfuehrung(_ seite: Side) throws -> Ausfuehrung {
                let preis = try zahl("price")
                let beschreibung = feld("description")
                return Ausfuehrung(
                    id: feld("transaction_id"), zeit: zeit, nurDatum: nurDatum, kennung: feld("symbol"),
                    name: feld("name"), seite: seite, menge: menge,
                    preis: preis != 0 || menge == 0 ? preis : abs(betrag) / menge, betrag: betrag,
                    gebuehr: try zahl("fee"), steuer: try zahl("tax"), waehrung: feld("currency"),
                    sparplan: beschreibung.hasPrefix("Savings plan") || beschreibung.contains("Sparplan"),
                    produktart: Produktart(tradeRepublic: klasse.map { $0 < z.count ? z[$0] : "" } ?? ""),
                    rohzeile: z)
            }
            func geld(_ geldart: Geldbewegung.Art) throws -> Geldbewegung {
                let kennung = feld("symbol")
                return Geldbewegung(
                    id: feld("transaction_id"), zeit: zeit, nurDatum: nurDatum, art: geldart, betrag: betrag,
                    gebuehr: try zahl("fee"), steuer: try zahl("tax"), waehrung: feld("currency"),
                    kennung: kennung.isEmpty ? nil : kennung, rohzeile: z)
            }
            func hinweis(_ folge: Importhinweis.Folge) {
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: "\(kategorie) \(art)", folge: folge))
            }

            switch kategorie {
            case "TRADING" where art == "BUY" || art == "SELL":
                ergebnis.ausfuehrungen.append(try ausfuehrung(art == "BUY" ? .buy : .sell))
            case "CASH" where (kaeufe.contains(art) || verkaeufe.contains(art)) && menge > 0:
                ergebnis.ausfuehrungen.append(try ausfuehrung(kaeufe.contains(art) ? .buy : .sell))
            case "CASH" where geldarten[art] != nil:
                ergebnis.geldbewegungen.append(try geld(geldarten[art]!))
            case "CASH" where einAuszahlungen.contains(art):
                ergebnis.geldbewegungen.append(try geld(betrag < 0 ? .auszahlung : .einzahlung))
            case "CORPORATE_ACTION":
                let massnahme: Kapitalmassnahme.Art = art == "SPLIT" ? .split
                    : ausbuchungen.contains(art) ? .ausbuchung : .unbekannt
                ergebnis.kapitalmassnahmen.append(Kapitalmassnahme(
                    id: feld("transaction_id"), zeit: zeit, art: massnahme, vorgang: art, kennung: feld("symbol"),
                    menge: try zahl("shares"), rohzeile: z))
                if massnahme == .unbekannt { hinweis(.nichtVerbucht) }
            default:
                // Unbekannt: Geld bleibt als „sonstiges“ erhalten, Wertpapierzeilen werden nicht geraten.
                if kategorie != "TRADING" && betrag != 0 {
                    ergebnis.geldbewegungen.append(try geld(.sonstiges))
                    hinweis(.alsSonstiges)
                } else {
                    hinweis(.nichtVerbucht)
                }
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
