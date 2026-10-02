import Foundation
import GRDB
import TradingCore

// Speicherung des Playbooks (Migration v7): Setup-Karten mit Kriterien für alle Konten, abgehakte
// Kriterien je Trade. Das Setup eines Trades steht in `journal.setup`.

struct SetupZeile: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "setup"
    var id: Int64?
    var name: String
    var stopRegel: String?
    var zielRegel: String?
    var marktumfeld: String?
    var notiz: String?
    var status: String
    var statusSeit: Date

    init(_ s: Setup) {
        id = s.id
        name = s.name
        stopRegel = s.stopRegel
        zielRegel = s.zielRegel
        marktumfeld = s.marktumfeld
        notiz = s.notiz
        status = s.status.rawValue
        statusSeit = s.statusSeit
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func modell(_ kriterien: [Kriterium]) throws -> Setup {
        guard let s = Setup.Status(rawValue: status) else { throw SpeicherFehler.unbekannterWert(status) }
        return Setup(id: id, name: name, kriterien: kriterien, stopRegel: stopRegel, zielRegel: zielRegel,
                     marktumfeld: marktumfeld, notiz: notiz, status: s, statusSeit: statusSeit)
    }
}

struct KriteriumZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kriterium"
    var setupId: Int64
    var kennung: String
    var text: String
    var position: Int
}

struct HakenZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "haken"
    var kontoId: Int64
    var ticket: String
    var kennung: String
}

extension Journal {
    /// Alle Setup-Karten, nach Name sortiert, Kriterien in ihrer Reihenfolge.
    public func playbook() throws -> [Setup] {
        try lies { db in
            let kriterien = Dictionary(grouping: try KriteriumZeile.order(Column("position")).fetchAll(db),
                                       by: \.setupId)
            return try SetupZeile.order(Column("name")).fetchAll(db).map { z in
                try z.modell((kriterien[z.id!] ?? []).map { Kriterium(id: $0.kennung, text: $0.text) })
            }
        }
    }

    /// Legt eine Karte an (`id` ist `nil`) oder ersetzt die gespeicherte mit dieser `id` samt Kriterien.
    /// Gibt die Karte so zurück, wie sie gespeichert ist.
    ///
    /// Ein neuer Name wird auch in die Journaleinträge mit dem alten Namen übernommen, damit Trades
    /// beim Umbenennen nicht ihre Karte verlieren. Abgelehnt werden: leerer oder schon vergebener Name,
    /// leere oder doppelte Kriterien-Kennung, leerer Kriterientext, eine `id`, die es nicht gibt.
    @discardableResult
    public func speichereSetup(_ setup: Setup) throws -> Setup {
        let name = setup.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SpeicherFehler.ungueltigerWert("Setup ohne Namen") }
        guard name == setup.name else {
            throw SpeicherFehler.ungueltigerWert("Setup-Name „\(setup.name)“ beginnt oder endet mit Leerraum")
        }
        let kennungen = setup.kriterien.map(\.id)
        if kennungen.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw SpeicherFehler.ungueltigerWert("Kriterium ohne Kennung in „\(name)“")
        }
        if Set(kennungen).count != kennungen.count {
            throw SpeicherFehler.ungueltigerWert("Kriterium doppelt in „\(name)“")
        }
        if setup.kriterien.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw SpeicherFehler.ungueltigerWert("Kriterium ohne Text in „\(name)“")
        }
        return try schreibe { db in
            if let andere = try SetupZeile.filter(Column("name") == name).fetchOne(db), andere.id != setup.id {
                throw SpeicherFehler.ungueltigerWert("Setup „\(name)“ gibt es schon")
            }
            var zeile = SetupZeile(setup)
            if let id = setup.id {
                guard let alt = try SetupZeile.fetchOne(db, key: id) else {
                    throw SpeicherFehler.ungueltigerWert("Setup \(id) gibt es nicht")
                }
                try zeile.update(db)
                if alt.name != name {
                    try Journaleintrag.filter(Column("setup") == alt.name)
                        .updateAll(db, Column("setup").set(to: name))
                }
                try KriteriumZeile.filter(Column("setupId") == id).deleteAll(db)
            } else {
                try zeile.insert(db)
            }
            let id = zeile.id!
            for (n, k) in setup.kriterien.enumerated() {
                try KriteriumZeile(setupId: id, kennung: k.id, text: k.text, position: n).insert(db)
            }
            // Neu gelesen, damit Zeiten genau so zurückkommen wie gespeichert (auf die Millisekunde).
            guard let gespeichert = try SetupZeile.fetchOne(db, key: id) else {
                throw SpeicherFehler.ungueltigerWert("Setup wurde nicht gespeichert")
            }
            return try gespeichert.modell(setup.kriterien)
        }
    }

    /// Entfernt eine Karte samt Kriterien. Journaleinträge behalten den Setup-Namen und ihre Häkchen;
    /// in der Auswertung erscheinen sie dann unter „Setup ohne Karte“.
    public func loescheSetup(id: Int64) throws {
        try schreibe { db in _ = try SetupZeile.deleteOne(db, key: id) }
    }

    /// Checklisten eines Kontos, Schlüssel ist das Ticket. Nur Trades mit Setup im Journal; passt direkt
    /// als `checklisten` in `PlaybookAuswertung`.
    public func checklisten(konto: Konto) throws -> [String: Checkliste] {
        try lies { db in
            let haken = Dictionary(grouping: try HakenZeile.filter(Column("kontoId") == konto.id!).fetchAll(db),
                                   by: \.ticket)
            let eintraege = try Journaleintrag.filter(Column("kontoId") == konto.id! && Column("setup") != nil)
                .fetchAll(db)
            var ergebnis: [String: Checkliste] = [:]
            for e in eintraege {
                ergebnis[e.ticket] = Checkliste(setup: e.setup!, erfuellt: Set((haken[e.ticket] ?? []).map(\.kennung)))
            }
            return ergebnis
        }
    }

    /// Setzt Setup und abgehakte Kriterien eines Trades. Schreibt das Setup in den Journaleintrag (legt ihn
    /// bei Bedarf an, andere Felder bleiben) und ersetzt die bisherigen Häkchen. Eine Karte zum Namen und
    /// eine Position zum Ticket muss es nicht geben, das Konto schon.
    public func setzeCheckliste(_ checkliste: Checkliste, konto: Konto, ticket: String,
                                jetzt: Date = Date()) throws {
        let setup = checkliste.setup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !setup.isEmpty else { throw SpeicherFehler.ungueltigerWert("Checkliste ohne Setup") }
        if checkliste.erfuellt.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw SpeicherFehler.ungueltigerWert("Häkchen ohne Kennung")
        }
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            var eintrag = try Journaleintrag.fetchOne(db, key: ["kontoId": kontoId, "ticket": ticket])
                ?? Journaleintrag(kontoId: kontoId, ticket: ticket)
            eintrag.setup = setup
            eintrag.geaendertAm = jetzt
            try eintrag.save(db)
            try HakenZeile.filter(Column("kontoId") == kontoId && Column("ticket") == ticket).deleteAll(db)
            for kennung in checkliste.erfuellt.sorted() {
                try HakenZeile(kontoId: kontoId, ticket: ticket, kennung: kennung).insert(db)
            }
        }
    }
}
