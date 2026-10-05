import Foundation
import GRDB
import TradingCore

// Von Hand eingetragene Trades (Formular „Trade eintragen“, Doc 02 Nr. 63). Sie stehen wie importierte in
// `geschlossenePosition` und hängen an einem Importlauf „Von Hand“ je Konto (ohne Datei).

extension Journal {
    /// Name in `Importlauf.importer` für von Hand eingetragene Trades.
    public static let vonHandImporter = "Von Hand"

    /// Fingerabdruck des Importlaufs „Von Hand“ eines Kontos. Kein SHA-256, kann also mit keiner Datei
    /// zusammenfallen.
    static func vonHandKennung(_ kontoId: Int64) -> String { "von-hand-\(kontoId)" }

    /// Legt ein Konto an, etwa für Trades von Hand ohne Import. Gibt es Broker und Nummer schon, kommt das
    /// vorhandene zurück; mit anderer Währung bricht es ab (`andereKontowaehrung`).
    @discardableResult
    public func legeKontoAn(broker: String, kontonummer: String, kontoname: String = "",
                            waehrung: String) throws -> Konto {
        let broker = broker.trimmingCharacters(in: .whitespacesAndNewlines)
        let nummer = kontonummer.trimmingCharacters(in: .whitespacesAndNewlines)
        let waehrung = waehrung.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !broker.isEmpty, !nummer.isEmpty else {
            throw SpeicherFehler.ungueltigerWert("Konto ohne Broker oder Nummer")
        }
        guard waehrung.count == 3, waehrung.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw SpeicherFehler.ungueltigerWert("Währung „\(waehrung)“ ist kein ISO-Code")
        }
        return try schreibe { db in
            try Self.konto(db, broker: broker, nummer: nummer, name: kontoname.isEmpty ? nummer : kontoname,
                           waehrung: waehrung)
        }
    }

    /// Speichert einen von Hand eingetragenen Trade als geschlossene Position.
    ///
    /// Ohne `ticket` entsteht ein neuer Trade mit Ticket `hand-<UUID>`. Mit `ticket` wird der von Hand
    /// eingetragene Trade dieses Tickets ersetzt (oder unter diesem Ticket angelegt); ein importierter Trade
    /// lässt sich so nicht ändern. `eintrag` (Setup, Regeltreue, Notiz, Risiko …) wird in derselben Transaktion
    /// gespeichert, Konto und Ticket setzt die Speicherung; ohne `eintrag` bleibt ein vorhandener Eintrag.
    /// Abgelehnt wird ein Trade, dessen `pruefe()` nicht leer ist.
    /// - Returns: die gespeicherte Position mit ihrem Ticket.
    @discardableResult
    public func speichereManuellenTrade(_ trade: ManuellerTrade, konto: Konto, ticket: String? = nil,
                                        eintrag: Journaleintrag? = nil, jetzt: Date = Date()) throws -> ClosedPosition {
        let probleme = trade.pruefe()
        guard probleme.isEmpty else {
            let liste = probleme.map { "\($0)" }.joined(separator: ", ")
            throw SpeicherFehler.ungueltigerWert("Trade unvollständig: \(liste)")
        }
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        let ticket = ticket?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "hand-\(UUID().uuidString.lowercased())"
        guard !ticket.isEmpty else { throw SpeicherFehler.ungueltigerWert("Ticket leer") }
        var eintrag = eintrag
        eintrag?.kontoId = kontoId
        eintrag?.ticket = ticket
        if let eintrag { try Self.pruefeEintrag(eintrag) }
        let position = trade.position(ticket: ticket)

        return try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            let laufId = try Self.vonHandLauf(db, kontoId: kontoId, jetzt: jetzt)
            let alt = try GeschlossenZeile
                .filter(Column("kontoId") == kontoId && Column("ticket") == ticket).fetchOne(db)
            if let alt, alt.importlaufId != laufId {
                throw SpeicherFehler.ungueltigerWert("Trade \(ticket) stammt aus einem Import")
            }
            try GeschlossenZeile.filter(Column("kontoId") == kontoId && Column("ticket") == ticket).deleteAll(db)
            try GeschlossenZeile(kontoId: kontoId, importlaufId: laufId, position,
                                 markterwartung: trade.markterwartung, schein: trade.schein).insert(db)
            if let eintrag { try eintrag.save(db) }
            guard let gespeichert = try GeschlossenZeile
                .filter(Column("kontoId") == kontoId && Column("ticket") == ticket).fetchOne(db)
            else { throw SpeicherFehler.ungueltigerWert("Trade \(ticket) wurde nicht gespeichert") }
            return try gespeichert.modell()
        }
    }

    /// Importlauf „Von Hand“ des Kontos, bei Bedarf angelegt; der Stichtag rückt auf `jetzt`.
    static func vonHandLauf(_ db: Database, kontoId: Int64, jetzt: Date) throws -> Int64 {
        let kennung = vonHandKennung(kontoId)
        if var lauf = try Importlauf.filter(Column("dateiHash") == kennung).fetchOne(db) {
            lauf.stichtag = jetzt
            try lauf.update(db)
            return lauf.id!
        }
        var lauf = Importlauf(id: nil, kontoId: kontoId, importer: vonHandImporter,
                              importerVersion: TradingCore.version, dateiname: "", dateiHash: kennung, datei: Data(),
                              art: "von-hand", stichtag: jetzt, serverZeitzone: "UTC", importiertAm: jetzt)
        try lauf.insert(db)
        return lauf.id!
    }

    /// Der von Hand eingetragene Trade zum Ticket, so wie das Formular ihn wieder anzeigt; `nil`, wenn es ihn
    /// nicht gibt oder er aus einem Import stammt. Der Stop kommt als `stopKurs` zurück, das Risiko steht im
    /// Journaleintrag (`risikoEinstieg`).
    public func manuellerTrade(konto: Konto, ticket: String) throws -> ManuellerTrade? {
        try lies { db in
            guard let kontoId = konto.id,
                  let lauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(kontoId)).fetchOne(db),
                  let zeile = try GeschlossenZeile
                    .filter(Column("kontoId") == kontoId && Column("ticket") == ticket
                            && Column("importlaufId") == lauf.id!).fetchOne(db)
            else { return nil }
            let p = try zeile.modell()
            return ManuellerTrade(symbol: p.symbol, einstieg: p.openTime,
                                  ausstieg: p.ausstiegszeitBekannt ? p.closeTime : nil,
                                  markterwartung: try zeile.erwartung(), schein: zeile.schein, groesse: p.lots,
                                  einstiegskurs: p.openPrice, ausstiegskurs: p.closePrice, stopKurs: p.stopLoss,
                                  ziel: p.takeProfit, gebuehren: -p.commission, produktart: p.produktart)
        }
    }

    /// Tickets der von Hand eingetragenen Trades eines Kontos.
    public func manuelleTickets(konto: Konto) throws -> Set<String> {
        try lies { db in
            guard let kontoId = konto.id,
                  let lauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(kontoId)).fetchOne(db)
            else { return [] }
            return Set(try String.fetchAll(db, sql: """
                SELECT ticket FROM geschlossenePosition WHERE kontoId = ? AND importlaufId = ?
                """, arguments: [kontoId, lauf.id!]))
        }
    }

    /// Löscht einen von Hand eingetragenen Trade samt Journaleintrag, Häkchen und Tags. Importierte Trades
    /// bleiben (Fehler). Gibt die Dateinamen der Bildverweise des Trades zurück, die mit gelöscht wurden;
    /// die Dateien selbst bleiben, wie bei `loescheKonto`.
    @discardableResult
    public func loescheManuellenTrade(konto: Konto, ticket: String) throws -> [String] {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        return try schreibe { db in
            guard let zeile = try GeschlossenZeile
                .filter(Column("kontoId") == kontoId && Column("ticket") == ticket).fetchOne(db)
            else { throw SpeicherFehler.ungueltigerWert("Trade \(ticket) gibt es nicht") }
            let lauf = try Importlauf.fetchOne(db, key: zeile.importlaufId)
            guard lauf?.dateiHash == Self.vonHandKennung(kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Trade \(ticket) stammt aus einem Import")
            }
            let bilder = try String.fetchAll(db, sql: """
                SELECT datei FROM bild WHERE kontoId = ? AND ticket = ? ORDER BY datei
                """, arguments: [kontoId, ticket])
            for tabelle in ["geschlossenePosition", "journal", "tradetag", "bild"] {
                try db.execute(sql: "DELETE FROM \(tabelle) WHERE kontoId = ? AND ticket = ?",
                               arguments: [kontoId, ticket])
            }
            return bilder
        }
    }

    /// Erwartete Marktrichtung je Ticket, nur wo sie gespeichert ist (Journal-Sicherung, von Hand). Bei einem
    /// Short-Schein ist sie `sell`, obwohl die Position gekauft ist; für `Trade.markterwartung`.
    public func markterwartungen(konto: Konto) throws -> [String: Side] {
        try lies { db in
            var ergebnis: [String: Side] = [:]
            let zeilen = try GeschlossenZeile
                .filter(Column("kontoId") == konto.id! && Column("markterwartung") != nil).fetchAll(db)
            for zeile in zeilen { ergebnis[zeile.ticket] = try zeile.erwartung() }
            return ergebnis
        }
    }
}
