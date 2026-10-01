import Foundation
import GRDB

/// Ein Ziel aus einer Wochen- oder Monatsauswertung, z. B. „Höchstens zwei Trades nach einem Verlust“.
/// Das nächste Review greift es auf und hakt es ab (Rezept Punkt 6 und 7 im Connector).
public struct ReviewZiel: Sendable, Equatable {
    public enum Status: String, Sendable, CaseIterable {
        case offen
        case erreicht
        case verfehlt
        /// Nicht mehr verfolgt, ohne Urteil über erreicht oder verfehlt.
        case verworfen
    }

    /// Von der Datenbank vergeben; `nil`, solange das Ziel nicht gespeichert ist.
    public var id: Int64?
    /// Konto, für das das Ziel gilt; `nil` heißt für alle Konten.
    public var kontoId: Int64?
    /// Zeitraum, in dem das Ziel gilt: `von` einschließlich, `bis` ausschließlich.
    public var von: Date
    public var bis: Date
    public var text: String
    public var status: Status
    /// Was beim Abhaken festgestellt wurde, z. B. „1 Trade nach Verlust statt höchstens 2“.
    public var ergebnis: String?
    public var angelegtAm: Date
    public var geaendertAm: Date

    public init(id: Int64? = nil, kontoId: Int64? = nil, von: Date, bis: Date, text: String,
                status: Status = .offen, ergebnis: String? = nil, angelegtAm: Date = Date(),
                geaendertAm: Date? = nil) {
        self.id = id
        self.kontoId = kontoId
        self.von = von
        self.bis = bis
        self.text = text
        self.status = status
        self.ergebnis = ergebnis
        self.angelegtAm = angelegtAm
        self.geaendertAm = geaendertAm ?? angelegtAm
    }
}

/// Zeile der Tabelle `reviewZiel`; Status als Text, damit ein unbekannter Wert als Fehler ankommt.
struct ZielZeile: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "reviewZiel"
    var id: Int64?
    var kontoId: Int64?
    var von: Date
    var bis: Date
    var text: String
    var status: String
    var ergebnis: String?
    var angelegtAm: Date
    var geaendertAm: Date

    init(_ z: ReviewZiel) {
        id = z.id
        kontoId = z.kontoId
        von = z.von
        bis = z.bis
        text = z.text
        status = z.status.rawValue
        ergebnis = z.ergebnis
        angelegtAm = z.angelegtAm
        geaendertAm = z.geaendertAm
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func modell() throws -> ReviewZiel {
        guard let s = ReviewZiel.Status(rawValue: status) else { throw SpeicherFehler.unbekannterWert(status) }
        return ReviewZiel(id: id, kontoId: kontoId, von: von, bis: bis, text: text, status: s,
                          ergebnis: ergebnis, angelegtAm: angelegtAm, geaendertAm: geaendertAm)
    }
}

extension Journal {
    /// Speichert ein neues Ziel und gibt es mit vergebener `id` zurück.
    /// Abgelehnt werden: leerer Text, `von` nicht vor `bis`, ein Konto, das es nicht gibt, eine schon gesetzte `id`.
    @discardableResult
    public func legeZielAn(_ ziel: ReviewZiel) throws -> ReviewZiel {
        guard ziel.id == nil else { throw SpeicherFehler.ungueltigerWert("Neues Ziel hat schon die ID \(ziel.id!)") }
        guard !ziel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeicherFehler.ungueltigerWert("Ziel ohne Text")
        }
        guard ziel.von < ziel.bis else { throw SpeicherFehler.ungueltigerWert("Zeitraum endet nicht nach seinem Beginn") }
        return try schreibe { db in
            if let kontoId = ziel.kontoId, try !Konto.exists(db, key: kontoId) {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            var zeile = ZielZeile(ziel)
            try zeile.insert(db)
            // Neu gelesen, damit Zeiten genau so zurückkommen wie gespeichert (auf die Millisekunde).
            guard let gespeichert = try ZielZeile.fetchOne(db, key: zeile.id!) else {
                throw SpeicherFehler.ungueltigerWert("Ziel wurde nicht gespeichert")
            }
            return try gespeichert.modell()
        }
    }

    /// Hakt ein Ziel ab oder öffnet es wieder. `ergebnis` ersetzt das bisherige Ergebnis, auch durch `nil`.
    public func setzeZielstatus(id: Int64, _ status: ReviewZiel.Status, ergebnis: String? = nil,
                                jetzt: Date = Date()) throws {
        try schreibe { db in
            guard var zeile = try ZielZeile.fetchOne(db, key: id) else {
                throw SpeicherFehler.ungueltigerWert("Ziel \(id) gibt es nicht")
            }
            zeile.status = status.rawValue
            zeile.ergebnis = ergebnis
            zeile.geaendertAm = jetzt
            try zeile.update(db)
        }
    }

    /// Entfernt ein Ziel, falls vorhanden.
    public func loescheZiel(id: Int64) throws {
        try schreibe { db in _ = try ZielZeile.deleteOne(db, key: id) }
    }

    /// Ziele, deren Zeitraum sich mit `von` bis `bis` überschneidet (ohne Angabe: alle), nach Beginn sortiert.
    /// Ziele aller Konten und kontoübergreifende; filtern nach Konto über `kontoId`.
    public func reviewZiele(von: Date? = nil, bis: Date? = nil,
                            status: ReviewZiel.Status? = nil) throws -> [ReviewZiel] {
        try lies { db in
            var anfrage = ZielZeile.all()
            if let von { anfrage = anfrage.filter(Column("bis") > von) }
            if let bis { anfrage = anfrage.filter(Column("von") < bis) }
            if let status { anfrage = anfrage.filter(Column("status") == status.rawValue) }
            return try anfrage.order(Column("von"), Column("id")).fetchAll(db).map { try $0.modell() }
        }
    }
}
