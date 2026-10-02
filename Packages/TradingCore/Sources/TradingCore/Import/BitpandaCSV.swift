import Foundation

/// Transaktionsverlauf von Bitpanda (Profil → Verlauf → Export, CSV; Bitpanda Support, Artikel 360000122759).
/// Aufbau laut CoinTaxman src/book.py und BittyTax parsers/bitpanda.py (beide GitHub, Abruf 01.10.2026):
/// sechs Hinweiszeilen, Kopf ab „Transaction ID“ in Zeile 7, 16 Spalten; neuere Dateien haben
/// zusätzlich „Tax Fiat“ (BittyTax 2026). Zeiten ISO 8601 mit Offset, „-“ steht für leer.
///
/// Annahme (zwei Zweitquellen, nicht von Bitpanda belegt): `Amount Fiat` ist bei buy und sell die
/// Kassenwirkung samt Gebühr, also beim Kauf bezahlt, beim Verkauf gutgeschrieben. CoinTaxman rechnet den
/// Preis als Amount Fiat durch Amount Asset, BittyTax bucht Amount Fiat ohne Gebühr als Gegenwert.
/// Der Spread steckt im Preis und wird nicht getrennt gebucht. Bei der Einzahlung ist Amount Fiat der
/// gutgeschriebene Betrag nach Gebühr, bei der Auszahlung kommt die Gebühr hinzu (BittyTax).
///
/// Hinweise statt Buchung: Gebühr in BEST oder in Krypto (Trade ohne Gebühr verbucht, Regel wie Binance), Steuer in „Tax Fiat“ (Wirkung auf Amount Fiat
/// unbelegt), Krypto-Ein- und -Auszahlung, transfer-Typen (Staking-Umbuchung, Airdrop), Fiat außerhalb
/// der Geldwährungen. Staking-Erträge („rewards“, vor dem 14.06.2022 „transfer“ eingehend; CoinTaxman
/// Issue 155) werden Kauf zum Marktwert plus Zinsen in gleicher Höhe.
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum BitpandaCSV {
    static let pflichtspalten = ["Transaction ID", "Timestamp", "Transaction Type", "In/Out", "Amount Fiat",
                                 "Fiat", "Amount Asset", "Asset", "Asset market price", "Asset class", "Fee",
                                 "Fee asset"]

    public static func erkennt(_ text: String) -> Bool {
        guard let ab = KryptoWerte.abKopf(text, erstesFeld: "Transaction ID") else { return false }
        return (try? CSVTabelle(text: ab.text).spalten(pflichtspalten)) != nil
    }

    public static func lies(_ text: String) throws -> Kontobewegungen {
        guard let ab = KryptoWerte.abKopf(text, erstesFeld: "Transaction ID") else {
            throw CSVImportFehler.fehlendeSpalte("Transaction ID")
        }
        let tabelle = CSVTabelle(text: ab.text)
        let spalten = try tabelle.spalten(pflichtspalten)
        let steuerSpalte = tabelle.kopf.firstIndex(of: "Tax Fiat")
        var ergebnis = Kontobewegungen()
        for (n, z) in tabelle.zeilen.enumerated() {
            let zeile = n + 2 + ab.versatz
            func feld(_ name: String) -> String {
                let i = spalten[name]!
                return i < z.count ? z[i].trimmingCharacters(in: .whitespaces) : ""
            }
            func zahl(_ name: String) throws -> Decimal { try KryptoWerte.zahl(feld(name), zeile: zeile) }
            func hinweis(_ vorgang: String) {
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: vorgang, folge: .nichtVerbucht))
            }
            let id = feld("Transaction ID")
            let typ = feld("Transaction Type").lowercased()
            let fiat = feld("Fiat").uppercased()
            let asset = feld("Asset").uppercased()
            let zeit = try KryptoWerte.iso(feld("Timestamp"), zeile: zeile)
            let betragFiat = try zahl("Amount Fiat")
            let fee = try zahl("Fee")

            let geld = KryptoWerte.geldwaehrungen.contains(fiat)
            let fiatKlasse = feld("Asset class") == "Fiat"
            let handel = typ == "buy" || typ == "sell"
            // Hinweise zu Handelszeilen wie bei Kraken und Binance: „PAAR SEITE …“.
            let paarSeite = "\(KryptoWerte.kennung(asset, fiat)) \(typ)"
            if (typ == "deposit" || typ == "withdrawal") && fiatKlasse {
                let einzahlung = typ == "deposit"
                ergebnis.geldbewegungen.append(Geldbewegung(
                    id: id, zeit: zeit, art: einzahlung ? .einzahlung : .auszahlung,
                    betrag: einzahlung ? betragFiat + abs(fee) : -betragFiat, gebuehr: -abs(fee),
                    waehrung: fiat, rohzeile: z))
            } else if handel && geld {
                let gebuehrInFiat = feld("Fee asset").uppercased() == fiat
                if fee != 0 && !gebuehrInFiat { hinweis("\(paarSeite) Gebühr \(feld("Fee asset").uppercased())") }
                let gebuehr = gebuehrInFiat ? -abs(fee) : 0
                let kauf = typ == "buy"
                ergebnis.ausfuehrungen.append(Ausfuehrung(
                    id: id, zeit: zeit, kennung: KryptoWerte.kennung(asset, fiat), name: asset,
                    seite: kauf ? .buy : .sell, menge: try zahl("Amount Asset"),
                    preis: try zahl("Asset market price"),
                    betrag: kauf ? -(betragFiat + gebuehr) : betragFiat - gebuehr, gebuehr: gebuehr,
                    waehrung: fiat, produktart: .krypto, rohzeile: z))
                if let i = steuerSpalte, i < z.count, try KryptoWerte.zahl(z[i], zeile: zeile) != 0 {
                    hinweis("\(paarSeite) Steuer \(z[i].trimmingCharacters(in: .whitespaces)) \(fiat)")
                }
            } else if (typ == "reward" || typ == "rewards") && geld && betragFiat > 0 {
                ergebnis.ausfuehrungen.append(Ausfuehrung(
                    id: id, zeit: zeit, kennung: KryptoWerte.kennung(asset, fiat), name: asset, seite: .buy,
                    menge: try zahl("Amount Asset"), preis: try zahl("Asset market price"),
                    betrag: -betragFiat, waehrung: fiat, produktart: .krypto, rohzeile: z))
                ergebnis.geldbewegungen.append(Geldbewegung(
                    id: "\(id)-ertrag", zeit: zeit, art: .zinsen, betrag: betragFiat, waehrung: fiat,
                    kennung: KryptoWerte.kennung(asset, fiat), rohzeile: z))
            } else if handel {
                hinweis(paarSeite)
            } else {
                hinweis("\(feld("Transaction Type")) \(asset)")
            }
        }
        return ergebnis
    }
}
