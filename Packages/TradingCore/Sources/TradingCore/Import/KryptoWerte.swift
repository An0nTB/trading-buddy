import Foundation

/// Gemeinsame Regeln der Krypto-Importer (R2 Abschnitt 4).
/// Kennung einer Krypto-Ausführung ist das Paar „BTC/EUR“: Die Positionsbildung führt dann nur
/// Käufe und Verkäufe in derselben Gegenwährung zusammen und mischt nie Euro mit US-Dollar.
enum KryptoWerte {
    /// Gegenwährungen mit festem Geldwert. Alles andere (BTC, ETH, BNB) hat ohne Tageskurs keinen
    /// Euro-Wert; solche Zeilen werden Hinweise statt Trades.
    static let geldwaehrungen: Set<String> = ["EUR", "USD", "CHF", "GBP", "USDT", "USDC", "EURC"]

    static func kennung(_ basis: String, _ gegen: String) -> String { "\(basis)/\(gegen)" }

    /// Zahl mit Punkt als Dezimalzeichen. Währungszeichen und Tausenderkommas fallen weg
    /// („€1,234.56“, „-€496.00“); „-“ oder leer zählt als 0.
    static func zahl(_ text: String, zeile: Int) throws -> Decimal {
        let roh = text.trimmingCharacters(in: .whitespaces)
        if roh.isEmpty || roh == "-" { return 0 }
        let bereinigt = roh.filter { !"€$£,".contains($0) }
        return try CSVWerte.zahl(bereinigt, .punkt, zeile: zeile)
    }

    /// Zahl mit angehängtem Kürzel, wie Binance sie schreibt: „0.0100000000BTC“ → (0.01, "BTC").
    static func zahlMitKuerzel(_ text: String, zeile: Int) throws -> (Decimal, String) {
        let roh = text.trimmingCharacters(in: .whitespaces)
        let kuerzel = String(roh.reversed().prefix { $0.isLetter }.reversed())
        let wert = try zahl(String(roh.dropLast(kuerzel.count)), zeile: zeile)
        guard !kuerzel.isEmpty else { throw CSVImportFehler.ungueltigeZahl(zeile: zeile, text: text) }
        return (wert, kuerzel.uppercased())
    }

    /// UTC-Zeit „2026-03-02 09:05:00.1234“ oder „2026-03-02 09:00:00 UTC“.
    static func utc(_ text: String, zeile: Int) throws -> Date {
        let teile = text.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard teile.count >= 2 else { throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: text) }
        return try CSVWerte.zeit(datum: String(teile[0]), uhrzeit: String(teile[1]),
                                 zeitzone: TimeZone(secondsFromGMT: 0)!, zeile: zeile)
    }

    /// ISO 8601 mit Offset („2026-03-30T10:00:00+02:00“) oder „Z“; Sekundenbruchteile fallen weg.
    static func iso(_ text: String, zeile: Int) throws -> Date {
        let roh = text.trimmingCharacters(in: .whitespaces)
        let datumZeit = roh.prefix(19)
        var rest = roh.dropFirst(19)
        if rest.first == "." { rest = rest.drop(while: { $0 == "." || $0.isNumber }) }
        var versatz = 0
        if rest.first == "+" || rest.first == "-" {
            let hm = rest.dropFirst().split(separator: ":").compactMap { Int($0) }
            guard hm.count == 2 else { throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: text) }
            versatz = (hm[0] * 3600 + hm[1] * 60) * (rest.first == "-" ? -1 : 1)
        } else if !(rest.isEmpty || rest == "Z") {
            throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: text)
        }
        let teile = datumZeit.split(separator: "T")
        guard teile.count == 2, let zone = TimeZone(secondsFromGMT: versatz)
        else { throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: text) }
        return try CSVWerte.zeit(datum: String(teile[0]), uhrzeit: String(teile[1]), zeitzone: zone, zeile: zeile)
    }

    /// Text ab der Kopfzeile, deren erstes Feld `erstesFeld` ist (Vorspann bei Coinbase und Bitpanda),
    /// dazu die Zahl der übersprungenen Zeilen für richtige Zeilennummern in Hinweisen.
    static func abKopf(_ text: String, erstesFeld: String) -> (text: String, versatz: Int)? {
        // „\r\n“ ist in Swift ein einziges Zeichen, deshalb nach Zeilenumbruch trennen, nicht nach "\n".
        let zeilen = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (i, zeile) in zeilen.prefix(15).enumerated() {
            let ohneBOM = zeile.hasPrefix("\u{FEFF}") ? zeile.dropFirst() : zeile
            if ohneBOM.hasPrefix(erstesFeld + ",") || ohneBOM.hasPrefix("\"\(erstesFeld)\",") {
                return (zeilen[i...].joined(separator: "\n"), i)
            }
        }
        return nil
    }
}
