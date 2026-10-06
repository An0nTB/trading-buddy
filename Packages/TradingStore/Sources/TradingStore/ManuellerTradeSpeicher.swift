import Foundation
import GRDB
import TradingCore

// Von Hand eingetragene Trades (Formular „Trade eintragen“, Doc 02 Nr. 63). Sie stehen wie importierte in
// `geschlossenePosition` und hängen an einem Importlauf „Von Hand“ je Konto (ohne Datei). Offene Trades von Hand
// stehen am selben Lauf in `offenePosition` (v12); Schließen ersetzt die offene Zeile durch eine geschlossene unter
// demselben Ticket, Journaleintrag, Tags und Bilder bleiben.

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

    /// Speichert einen geschlossenen, von Hand eingetragenen Trade als geschlossene Position (Regeln wie
    /// `speichereHandtrade`); ein offener Trade bricht ab.
    /// - Returns: die gespeicherte Position mit ihrem Ticket.
    @discardableResult
    public func speichereManuellenTrade(_ trade: ManuellerTrade, konto: Konto, ticket: String? = nil,
                                        eintrag: Journaleintrag? = nil, jetzt: Date = Date()) throws -> ClosedPosition {
        guard !trade.offen else { throw SpeicherFehler.ungueltigerWert("Trade ist offen") }
        let ticket = try speichereHandtrade(trade, konto: konto, ticket: ticket, eintrag: eintrag, jetzt: jetzt)
        return try lies { db in
            guard let zeile = try GeschlossenZeile
                .filter(Column("kontoId") == konto.id! && Column("ticket") == ticket).fetchOne(db)
            else { throw SpeicherFehler.ungueltigerWert("Trade \(ticket) wurde nicht gespeichert") }
            return try zeile.modell()
        }
    }

    /// Speichert einen von Hand eingetragenen Trade: geschlossen als geschlossene Position, offen
    /// (`trade.offen`) als offene Position am Lauf „Von Hand“.
    ///
    /// Ohne `ticket` entsteht ein neuer Trade mit Ticket `hand-<UUID>`. Mit `ticket` wird der von Hand
    /// eingetragene Trade dieses Tickets ersetzt (oder unter diesem Ticket angelegt); ein importierter Trade
    /// lässt sich so nicht ändern. `eintrag` (Setup, Regeltreue, Notiz, Risiko …) wird in derselben Transaktion
    /// gespeichert, Konto und Ticket setzt die Speicherung; ohne `eintrag` bleibt ein vorhandener Eintrag.
    /// Abgelehnt wird ein Trade, dessen `pruefe()` nicht leer ist. Ein offener und ein geschlossener Trade von
    /// Hand mit demselben Ticket gibt es nie zugleich: Speichern geschlossen schließt den offenen, Speichern offen
    /// öffnet den geschlossenen wieder.
    /// - Returns: das Ticket des gespeicherten Trades.
    @discardableResult
    public func speichereHandtrade(_ trade: ManuellerTrade, konto: Konto, ticket: String? = nil,
                                   eintrag: Journaleintrag? = nil, jetzt: Date = Date()) throws -> String {
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
            try OffenZeile.filter(Column("importlaufId") == laufId && Column("ticket") == ticket).deleteAll(db)
            if trade.offen {
                try OffenZeile(importlaufId: laufId, trade.offenePosition(ticket: ticket),
                               markterwartung: trade.markterwartung, schein: trade.schein).insert(db)
            } else {
                try GeschlossenZeile(kontoId: kontoId, importlaufId: laufId, trade.position(ticket: ticket),
                                     markterwartung: trade.markterwartung, schein: trade.schein).insert(db)
            }
            if let eintrag { try eintrag.save(db) }
            return ticket
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
    /// Journaleintrag (`risikoEinstieg`). Ein offener kommt ohne Ausstieg zurück (`offen`).
    public func manuellerTrade(konto: Konto, ticket: String) throws -> ManuellerTrade? {
        try lies { db in
            guard let kontoId = konto.id,
                  let lauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(kontoId)).fetchOne(db)
            else { return nil }
            if let offen = try OffenZeile
                .filter(Column("importlaufId") == lauf.id! && Column("ticket") == ticket).fetchOne(db) {
                return try Self.manuellerTrade(offen)
            }
            guard let zeile = try GeschlossenZeile
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

    /// Offener Trade von Hand aus seiner Zeile, ohne Ausstieg.
    static func manuellerTrade(_ zeile: OffenZeile) throws -> ManuellerTrade {
        let p = try zeile.modell()
        return ManuellerTrade(symbol: p.symbol, einstieg: p.openTime, markterwartung: try zeile.erwartung(),
                              schein: zeile.schein, groesse: p.lots, einstiegskurs: p.openPrice, ausstiegskurs: nil,
                              stopKurs: p.stopLoss, ziel: p.takeProfit, gebuehren: -p.commission,
                              produktart: p.produktart)
    }

    /// Offene Trades von Hand eines Kontos mit Ticket, nach Einstieg sortiert. Getrennt von den offenen Positionen
    /// aus Auszügen (`offenePositionenLetzterAuszug`), die nur den MT4-Lauf lesen.
    public func offeneManuelleTrades(konto: Konto) throws -> [OffenerHandtrade] {
        try lies { db in
            guard let kontoId = konto.id,
                  let lauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(kontoId)).fetchOne(db)
            else { return [] }
            return try OffenZeile.filter(Column("importlaufId") == lauf.id!)
                .order(Column("openTime"), Column("ticket")).fetchAll(db)
                .map { OffenerHandtrade(ticket: $0.ticket, trade: try Self.manuellerTrade($0)) }
        }
    }

    /// Tickets der geschlossenen, von Hand eingetragenen Trades eines Kontos.
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

    /// Löscht einen von Hand eingetragenen Trade (offen oder geschlossen) samt Journaleintrag, Häkchen und Tags.
    /// Importierte Trades bleiben (Fehler). Gibt die Dateinamen der Bildverweise des Trades zurück, die mit
    /// gelöscht wurden; die Dateien selbst bleiben, wie bei `loescheKonto`.
    @discardableResult
    public func loescheManuellenTrade(konto: Konto, ticket: String) throws -> [String] {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        return try schreibe { db in
            let handLauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(kontoId)).fetchOne(db)
            let offen = try handLauf.flatMap { lauf in
                try OffenZeile.filter(Column("importlaufId") == lauf.id! && Column("ticket") == ticket).fetchOne(db)
            }
            let zeile = try GeschlossenZeile
                .filter(Column("kontoId") == kontoId && Column("ticket") == ticket).fetchOne(db)
            guard offen != nil || zeile != nil else {
                throw SpeicherFehler.ungueltigerWert("Trade \(ticket) gibt es nicht")
            }
            if let zeile, zeile.importlaufId != handLauf?.id {
                throw SpeicherFehler.ungueltigerWert("Trade \(ticket) stammt aus einem Import")
            }
            if let lauf = handLauf {
                try OffenZeile.filter(Column("importlaufId") == lauf.id! && Column("ticket") == ticket).deleteAll(db)
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
            if let lauf = try Importlauf.filter(Column("dateiHash") == Self.vonHandKennung(konto.id!)).fetchOne(db) {
                let offene = try OffenZeile
                    .filter(Column("importlaufId") == lauf.id! && Column("markterwartung") != nil).fetchAll(db)
                for zeile in offene { ergebnis[zeile.ticket] = try zeile.erwartung() }
            }
            return ergebnis
        }
    }
}

/// Offener Trade von Hand mit seinem Ticket (`Journal.offeneManuelleTrades`).
public struct OffenerHandtrade: Sendable, Equatable {
    public var ticket: String
    public var trade: ManuellerTrade

    public init(ticket: String, trade: ManuellerTrade) {
        self.ticket = ticket
        self.trade = trade
    }
}
