import Foundation

/// Spot-Trade-Export von Binance (Orders → Spot Order → Trade History → Export, CSV).
/// Kopf „Date(UTC),Pair,Side,Price,Executed,Amount,Fee“, Zeiten in UTC (Binance FAQ 2026, R2 Abschnitt 4).
/// Mengen tragen das Kürzel ohne Trenner („0.0100000000BTC“), das Paar hat keinen Trenner („BTCEUR“),
/// der Preis kann ein Tausenderkomma haben (Aufbau laut R2: Sekundärquelle 2021, Einschätzung).
/// Die Gegenwährung kommt aus dem Kürzel von `Amount`, die Basis ist der Rest des Paars.
/// Gebühr in der Basis wird zum Ausführungspreis in die Gegenwährung umgerechnet und die Menge
/// entsprechend korrigiert; Gebühr in einer Drittwährung (BNB) wird nicht verbucht und als Hinweis gemeldet.
/// Der Transaktionsverlauf (User ID, Operation, Coin, Change; CoinTaxman book.py 2026) wird nur erkannt.
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum BinanceCSV {
    static let pflichtspalten = ["Date(UTC)", "Pair", "Side", "Price", "Executed", "Amount", "Fee"]
    /// Spalten des Transaktionsverlaufs in allen drei bekannten Fassungen (UTC_Time oder Time).
    static let transaktionsspalten = ["Account", "Operation", "Coin", "Change"]

    public static func erkennt(_ text: String) -> Bool {
        (try? CSVTabelle(text: text).spalten(pflichtspalten)) != nil
    }

    /// Binance-Transaktionsverlauf (Assets → Transaction History); wird nicht gelesen.
    public static func istTransaktionsverlauf(_ text: String) -> Bool {
        (try? CSVTabelle(text: text).spalten(transaktionsspalten)) != nil
    }

    public static func lies(_ text: String) throws -> Kontobewegungen {
        let tabelle = CSVTabelle(text: text)
        if istTransaktionsverlauf(text) { throw CSVImportFehler.unbekanntesFormat(kopf: tabelle.kopf) }
        let spalten = try tabelle.spalten(pflichtspalten)
        var ergebnis = Kontobewegungen()
        var vergeben: [String: Int] = [:]
        for (n, z) in tabelle.zeilen.enumerated() {
            let zeile = n + 2
            func feld(_ name: String) -> String {
                let i = spalten[name]!
                return i < z.count ? z[i].trimmingCharacters(in: .whitespaces) : ""
            }
            let paarText = feld("Pair").uppercased()
            let seite = feld("Side").uppercased()
            let vorgang = "\(paarText) \(seite)"
            let (betragRoh, gegen) = try KryptoWerte.zahlMitKuerzel(feld("Amount"), zeile: zeile)
            guard seite == "BUY" || seite == "SELL", paarText.hasSuffix(gegen), paarText.count > gegen.count,
                  KryptoWerte.geldwaehrungen.contains(gegen)
            else {
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: vorgang, folge: .nichtVerbucht))
                continue
            }
            let basis = String(paarText.dropLast(gegen.count))
            guard let ausgefuehrt = try wert(feld("Executed"), kuerzel: basis, zeile: zeile) else {
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: vorgang, folge: .nichtVerbucht))
                continue
            }
            let preis = try KryptoWerte.zahl(feld("Price"), zeile: zeile)
            let kauf = seite == "BUY"
            let betrag = abs(betragRoh)
            var menge = abs(ausgefuehrt)
            var kasse = kauf ? -betrag : betrag
            var gebuehr: Decimal = 0
            switch try gebuehrLesen(feld("Fee"), basis: basis, gegen: gegen, zeile: zeile) {
            case .keine:
                break
            case .gegen(let fee):
                gebuehr = -abs(fee)
            case .basis(let fee):
                // Die Gebühr kommt aus der Basis: beim Kauf weniger Stücke, beim Verkauf mehr abgegeben.
                // Kassenwirkung bleibt ∓Amount, aufgeteilt in Betrag und Gebühr.
                let wertGebuehr = abs(fee) * preis
                menge = kauf ? menge - abs(fee) : menge + abs(fee)
                kasse = kauf ? -(betrag - wertGebuehr) : betrag + wertGebuehr
                gebuehr = -wertGebuehr
            case .fremd(let kuerzel):
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: "\(vorgang) Gebühr \(kuerzel)",
                                                       folge: .nichtVerbucht))
            }
            let roh = "\(feld("Date(UTC)"))|\(paarText)|\(seite)|\(feld("Executed"))|\(feld("Amount"))"
            vergeben[roh, default: 0] += 1
            let id = vergeben[roh]! == 1 ? roh : "\(roh)#\(vergeben[roh]!)"
            ergebnis.ausfuehrungen.append(Ausfuehrung(
                id: id, zeit: try KryptoWerte.utc(feld("Date(UTC)"), zeile: zeile),
                kennung: KryptoWerte.kennung(basis, gegen), name: basis, seite: kauf ? .buy : .sell,
                menge: menge, preis: preis, betrag: kasse, gebuehr: gebuehr, waehrung: gegen,
                produktart: .krypto, rohzeile: z))
        }
        return ergebnis
    }

    enum Gebuehr: Equatable {
        case keine
        case basis(Decimal)
        case gegen(Decimal)
        case fremd(String)
    }

    /// Gebühr mit Kürzel; das längere passende Kürzel gewinnt, damit „1INCH“ oder „USDT“ nicht falsch zerfallen.
    static func gebuehrLesen(_ text: String, basis: String, gegen: String, zeile: Int) throws -> Gebuehr {
        let roh = text.trimmingCharacters(in: .whitespaces).uppercased()
        if roh.allSatisfy({ !$0.isLetter }) {
            // Ohne Kürzel ist nur „0“, „-“ oder leer eindeutig.
            guard try KryptoWerte.zahl(roh, zeile: zeile) == 0
            else { throw CSVImportFehler.ungueltigeZahl(zeile: zeile, text: text) }
            return .keine
        }
        for kuerzel in [basis, gegen].sorted(by: { $0.count > $1.count }) {
            if let fee = try wert(roh, kuerzel: kuerzel, zeile: zeile) {
                if fee == 0 { return .keine }
                return kuerzel == basis ? .basis(fee) : .gegen(fee)
            }
        }
        let (fee, kuerzel) = try KryptoWerte.zahlMitKuerzel(roh, zeile: zeile)
        return fee == 0 ? .keine : .fremd(kuerzel)
    }

    /// Zahl mit bekanntem Kürzel am Ende; `nil`, wenn das Kürzel nicht passt.
    static func wert(_ text: String, kuerzel: String, zeile: Int) throws -> Decimal? {
        let roh = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard roh.hasSuffix(kuerzel), roh.count > kuerzel.count else { return nil }
        let zahlText = String(roh.dropLast(kuerzel.count))
        guard let letztes = zahlText.last, letztes.isNumber || letztes == "." else { return nil }
        return try KryptoWerte.zahl(zahlText, zeile: zeile)
    }
}
