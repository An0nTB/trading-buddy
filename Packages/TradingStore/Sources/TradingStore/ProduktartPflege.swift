import Foundation
import GRDB
import TradingCore

/// Wertpapier eines Kontos, für das noch Zeilen ohne Produktart gespeichert sind.
public struct ProduktartLuecke: Sendable, Equatable {
    /// Schlüssel für `setzeProduktart`: ISIN oder Symbol aus der Datei, ohne Kennung der Name.
    public var symbol: String
    /// Anzeigename aus der Datei (bei Ausführungen der Wertpapiername), sonst das Symbol.
    public var name: String
    /// Gespeicherte Zeilen ohne Art (Ausführungen, geschlossene und offene Positionen).
    public var anzahl: Int

    public init(symbol: String, name: String, anzahl: Int) {
        self.symbol = symbol
        self.name = name
        self.anzahl = anzahl
    }
}

// Nachpflege der Produktart je Symbol (ohne Migration): für Scalable, XTB und andere Dateien ohne Art.
extension Journal {
    /// Wertpapiere des Kontos mit Zeilen ohne Produktart, nach Name sortiert. Ausführungen ohne Kennung
    /// (Scalable ohne ISIN) stehen unter ihrem Namen; ohne Kennung und Name lassen sie sich nicht zuordnen
    /// und fehlen.
    public func symboleOhneProduktart(konto: Konto) throws -> [ProduktartLuecke] {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        let unbekannt = Produktart.unbekannt.rawValue
        return try lies { db in
            let zeilen = try Row.fetchAll(db, sql: """
                SELECT CASE WHEN kennung = '' THEN name ELSE kennung END AS symbol, MAX(name) AS name,
                    COUNT(*) AS anzahl FROM ausfuehrung
                    WHERE kontoId = ? AND produktart = ? AND (kennung != '' OR name != '')
                    GROUP BY CASE WHEN kennung = '' THEN name ELSE kennung END
                UNION ALL
                SELECT symbol, symbol, COUNT(*) FROM geschlossenePosition
                    WHERE kontoId = ? AND produktart = ? GROUP BY symbol
                UNION ALL
                SELECT symbol, symbol, COUNT(*) FROM offenePosition
                    WHERE produktart = ? AND importlaufId IN (SELECT id FROM importlauf WHERE kontoId = ?)
                    GROUP BY symbol
                """, arguments: [kontoId, unbekannt, kontoId, unbekannt, unbekannt, kontoId])
            var jeSymbol: [String: ProduktartLuecke] = [:]
            for z in zeilen {
                let symbol: String = z["symbol"]
                let name: String = z["name"]
                let anzahl: Int = z["anzahl"]
                var l = jeSymbol[symbol] ?? ProduktartLuecke(symbol: symbol, name: symbol, anzahl: 0)
                if l.name == symbol, !name.isEmpty { l.name = name }
                l.anzahl += anzahl
                jeSymbol[symbol] = l
            }
            return jeSymbol.values.sorted { ($0.name.lowercased(), $0.symbol) < ($1.name.lowercased(), $1.symbol) }
        }
    }

    /// Setzt die Produktart aller gespeicherten Zeilen des Kontos zu diesem Symbol: Ausführungen (Kennung oder
    /// Name gleich `symbol`), geschlossene und offene Positionen. Überschreibt auch eine bekannte Art, das ist
    /// die Korrektur von Hand. Gibt die Zahl der geänderten Zeilen zurück. Den Export schreibt die App neu.
    ///
    /// Abgelehnt werden ein leeres Symbol und ein Konto, das es nicht gibt.
    @discardableResult
    public func setzeProduktart(konto: Konto, symbol: String, _ art: Produktart) throws -> Int {
        guard !symbol.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SpeicherFehler.ungueltigerWert("Produktart ohne Symbol")
        }
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        return try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            var geaendert = 0
            try db.execute(sql: """
                UPDATE ausfuehrung SET produktart = ?
                WHERE kontoId = ? AND (kennung = ? OR name = ?) AND produktart != ?
                """, arguments: [art.rawValue, kontoId, symbol, symbol, art.rawValue])
            geaendert += db.changesCount
            try db.execute(sql: """
                UPDATE geschlossenePosition SET produktart = ?
                WHERE kontoId = ? AND symbol = ? AND produktart != ?
                """, arguments: [art.rawValue, kontoId, symbol, art.rawValue])
            geaendert += db.changesCount
            try db.execute(sql: """
                UPDATE offenePosition SET produktart = ?
                WHERE symbol = ? AND produktart != ? AND importlaufId IN (SELECT id FROM importlauf WHERE kontoId = ?)
                """, arguments: [art.rawValue, symbol, art.rawValue, kontoId])
            geaendert += db.changesCount
            return geaendert
        }
    }
}
