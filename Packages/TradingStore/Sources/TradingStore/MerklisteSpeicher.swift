import Foundation
import GRDB
import TradingCore

// Speicherung der Merkliste für Nachrichten (Migration v9, Doc 26). Für alle Konten.

struct MerkZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "merkliste"
    var id: String
    var begriff: String
    var schluessel: String
    var art: String
    var anzeigename: String
    var herkunft: String
    var status: String
    var notiz: String
    var erstellt: Date

    init(_ e: Merklisteneintrag) {
        id = e.id
        begriff = e.begriff
        schluessel = e.schluessel
        art = e.art.rawValue
        anzeigename = e.anzeigename
        herkunft = e.herkunft.rawValue
        status = e.status.rawValue
        notiz = e.notiz
        erstellt = e.erstellt
    }

    func modell() throws -> Merklisteneintrag {
        guard let a = Merklisteneintrag.Art(rawValue: art) else { throw SpeicherFehler.unbekannterWert(art) }
        guard let h = Merklisteneintrag.Herkunft(rawValue: herkunft) else {
            throw SpeicherFehler.unbekannterWert(herkunft)
        }
        guard let s = Merklisteneintrag.Status(rawValue: status) else { throw SpeicherFehler.unbekannterWert(status) }
        return Merklisteneintrag(id: id, begriff: begriff, art: a, anzeigename: anzeigename, herkunft: h, status: s,
                                 notiz: notiz, erstellt: erstellt)
    }
}

extension Journal {
    /// Alle Einträge der Merkliste, auch vorgeschlagene und abgelehnte, nach Begriff sortiert. Passt als
    /// `bestehend` in `Merkliste.vorschlag`.
    public func merkliste() throws -> [Merklisteneintrag] {
        try lies { db in try MerkZeile.order(Column("schluessel")).fetchAll(db).map { try $0.modell() } }
    }

    /// Legt den Eintrag an oder ersetzt den mit derselben `id`; gibt ihn so zurück, wie er gespeichert ist.
    ///
    /// Der Begriff wird wie in `Merkliste.bereinigt` gesäubert, ein leerer Anzeigename wird der Begriff.
    /// Abgelehnt werden: leere `id`, leerer Begriff, ein Begriff, der unter anderer `id` schon auf der
    /// Liste steht (ohne Groß- und Kleinschreibung, auch abgelehnte).
    @discardableResult
    public func speichereMerklisteneintrag(_ eintrag: Merklisteneintrag) throws -> Merklisteneintrag {
        var e = eintrag
        e.begriff = Merkliste.bereinigt(e.begriff)
        guard !e.id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SpeicherFehler.ungueltigerWert("Merklisteneintrag ohne ID")
        }
        guard !e.begriff.isEmpty else { throw SpeicherFehler.ungueltigerWert("Merklisteneintrag ohne Begriff") }
        if e.anzeigename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { e.anzeigename = e.begriff }
        let zeile = MerkZeile(e)
        return try schreibe { db in
            if let andere = try MerkZeile.filter(Column("schluessel") == zeile.schluessel).fetchOne(db),
               andere.id != zeile.id {
                throw SpeicherFehler.ungueltigerWert("„\(andere.begriff)“ steht schon auf der Merkliste")
            }
            try zeile.save(db)
            // Neu gelesen, damit Zeiten genau so zurückkommen wie gespeichert (auf die Millisekunde).
            guard let gespeichert = try MerkZeile.fetchOne(db, key: zeile.id) else {
                throw SpeicherFehler.ungueltigerWert("Merklisteneintrag wurde nicht gespeichert")
            }
            return try gespeichert.modell()
        }
    }

    /// Entfernt den Eintrag. Wer einen Vorschlag nur nicht will, setzt besser Status `abgelehnt`, sonst
    /// kommt er beim nächsten Vorschlag wieder.
    public func loescheMerklisteneintrag(id: String) throws {
        try schreibe { db in _ = try MerkZeile.deleteOne(db, key: id) }
    }
}
