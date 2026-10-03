import Foundation
import GRDB

// Konto mit allem löschen, was daran hängt (Beispieldaten für Beta-Tester, AP11; Doc 11, Entscheidung 49).
extension Journal {
    /// Tabellen, die ohne Kaskade auf Konto und Importlauf verweisen. Sie müssen vor dem Importlauf weg.
    static let kontotabellenOhneKaskade = ["geschlossenePosition", "geloeschteOrder", "ausfuehrung",
                                           "geldbewegung", "kapitalmassnahme", "verworfenerVorgang"]

    /// Löscht das Konto mit allem, was daran hängt, in einer Transaktion: Importläufe samt Originaldateien,
    /// Positionen, Orders, Ausführungen, Geldbewegungen, Kapitalmaßnahmen, verworfene Vorgänge, Hinweise und
    /// Kontostände, dazu Journal, Haken, Handelsregeln, Review-Ziele und Bildverweise des Kontos. Andere
    /// Konten und kontoübergreifende Daten (Playbook, Tagesnotizen, verpasste Trades, Merkliste) bleiben.
    /// Dieselbe Datei lässt sich danach wieder importieren.
    ///
    /// Gibt die Dateinamen der gelöschten Bildverweise zurück. Die Bilddateien liegen im Bilderordner der
    /// App und bleiben stehen; ob sie weg sollen, entscheidet die App.
    @discardableResult
    public func loescheKonto(_ konto: Konto) throws -> [String] {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        return try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            let bilder = try String.fetchAll(db, sql: "SELECT datei FROM bild WHERE kontoId = ? ORDER BY datei",
                                             arguments: [kontoId])
            for tabelle in Self.kontotabellenOhneKaskade {
                try db.execute(sql: "DELETE FROM \(tabelle) WHERE kontoId = ?", arguments: [kontoId])
            }
            // Kaskade: Kontostand, offene Positionen, wartende Orders, Importhinweise.
            try db.execute(sql: "DELETE FROM importlauf WHERE kontoId = ?", arguments: [kontoId])
            // Kaskade: Journal (und damit Haken), Review-Ziele, Handelsregeln, Bildverweise.
            _ = try Konto.deleteOne(db, key: kontoId)
            return bilder
        }
    }
}
