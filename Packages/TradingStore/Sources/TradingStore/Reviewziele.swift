import Foundation
import GRDB
import TradingCore

/// Zeile der Tabelle `reviewziel` (Migration v4). Der Status steht als Text, damit ein unbekanntes
/// Wort als `SpeicherFehler.unbekannterWert` ankommt statt als Absturz beim Lesen.
struct ZielZeile: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "reviewziel"
    var id: Int64?
    var kontoId: Int64
    var text: String
    var von: Date
    var bis: Date
    var messgroesse: String?
    var zielwert: Decimal?
    var status: String
    var ergebnis: String?
    var erstellt: Date
    var geaendert: Date

    init(kontoId: Int64, _ z: Reviewziel) {
        id = z.id
        self.kontoId = kontoId
        text = z.text
        von = z.von
        bis = z.bis
        messgroesse = z.messgroesse
        zielwert = z.zielwert
        status = z.status.rawValue
        ergebnis = z.ergebnis
        erstellt = z.erstellt
        geaendert = z.geaendert
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func modell() throws -> Reviewziel {
        guard let s = Reviewziel.Status(rawValue: status) else { throw SpeicherFehler.unbekannterWert(status) }
        return Reviewziel(id: id, text: text, von: von, bis: bis, messgroesse: messgroesse, zielwert: zielwert,
                          status: s, ergebnis: ergebnis, erstellt: erstellt, geaendert: geaendert)
    }
}

extension Journal {
    /// Speichert ein neues Ziel für dieses Konto und gibt es so zurück, wie es gespeichert ist (mit `id`).
    /// Abgelehnt werden: leerer Text, `von` nicht vor `bis`, ein Konto, das es nicht gibt, eine schon gesetzte `id`.
    @discardableResult
    public func legeZielAn(_ ziel: Reviewziel, konto: Konto) throws -> Reviewziel {
        if let id = ziel.id { throw SpeicherFehler.ungueltigerWert("Neues Ziel hat schon die ID \(id)") }
        guard !ziel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeicherFehler.ungueltigerWert("Ziel ohne Text")
        }
        guard ziel.von < ziel.bis else {
            throw SpeicherFehler.ungueltigerWert("Zeitraum endet nicht nach seinem Beginn")
        }
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        return try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            var zeile = ZielZeile(kontoId: kontoId, ziel)
            try zeile.insert(db)
            // Neu gelesen, damit Zeiten genau so zurückkommen wie gespeichert (auf die Millisekunde).
            guard let gespeichert = try ZielZeile.fetchOne(db, key: zeile.id!) else {
                throw SpeicherFehler.ungueltigerWert("Ziel wurde nicht gespeichert")
            }
            return try gespeichert.modell()
        }
    }

    /// Hakt ein Ziel ab oder öffnet es wieder. `ergebnis` ersetzt das bisherige Ergebnis, auch durch `nil`.
    public func setzeZielstatus(id: Int64, _ status: Reviewziel.Status, ergebnis: String? = nil,
                                jetzt: Date = Date()) throws {
        try schreibe { db in
            guard var zeile = try ZielZeile.fetchOne(db, key: id) else {
                throw SpeicherFehler.ungueltigerWert("Ziel \(id) gibt es nicht")
            }
            zeile.status = status.rawValue
            zeile.ergebnis = ergebnis
            zeile.geaendert = jetzt
            try zeile.update(db)
        }
    }

    /// Entfernt ein Ziel, falls vorhanden.
    public func loescheZiel(id: Int64) throws {
        try schreibe { db in _ = try ZielZeile.deleteOne(db, key: id) }
    }

    /// Ziele eines Kontos, nach Beginn sortiert. `von` und `bis` begrenzen auf Ziele, deren Zeitraum sich
    /// damit überschneidet; `status` auf einen Status. Ohne Angaben: alle Ziele des Kontos.
    public func ziele(konto: Konto, von: Date? = nil, bis: Date? = nil,
                      status: Reviewziel.Status? = nil) throws -> [Reviewziel] {
        try lies { db in
            var anfrage = ZielZeile.filter(Column("kontoId") == konto.id!)
            if let von { anfrage = anfrage.filter(Column("bis") > von) }
            if let bis { anfrage = anfrage.filter(Column("von") < bis) }
            if let status { anfrage = anfrage.filter(Column("status") == status.rawValue) }
            return try anfrage.order(Column("von"), Column("id")).fetchAll(db).map { try $0.modell() }
        }
    }
}
