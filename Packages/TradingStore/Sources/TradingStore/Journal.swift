import Crypto
import Foundation
import GRDB
import TradingCore

/// Fehler beim Speichern. Bei jedem dieser Fehler bleibt die Datenbank unverändert.
public enum SpeicherFehler: Error, Equatable, Sendable {
    /// Die Datei ist kein UTF-8-Text.
    case keinText
    /// Der Auszug passt nicht zu seinen eigenen Summen (`MT4Statement.pruefe()`).
    case auszugWidersprichtSeinenSummen([String])
    /// Das Konto ist schon mit einer anderen Währung angelegt.
    case andereKontowaehrung(gespeichert: String, angegeben: String)
    /// Gleiches Ticket, aber andere Werte als beim früheren Import.
    case abweichenderDatensatz(tickets: [String])
    /// In der Datenbank steht ein Wert, den das Datenmodell nicht kennt.
    case unbekannterWert(String)
    /// Eine Eingabe liegt außerhalb des erlaubten Bereichs.
    case ungueltigerWert(String)
}

/// Was ein Import bewirkt hat.
public struct ImportErgebnis: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Datei war neu und ist gespeichert.
        case gespeichert
        /// Genau diese Datei wurde schon importiert; nichts wurde geändert.
        case dateiBereitsImportiert
    }

    public var status: Status
    public var importlaufId: Int64
    public var geschlosseneNeu: Int = 0
    /// Geschlossene Positionen, die schon aus einem anderen Auszug bekannt waren.
    public var geschlosseneBekannt: Int = 0
    public var geloeschteNeu: Int = 0
    public var geloeschteBekannt: Int = 0
    public var offene: Int = 0
    public var wartende: Int = 0
    /// Zähler eines CSV-Imports (Trade Republic, Scalable); bei XTB Kassenoperationen und Hinweise;
    /// beim MT4-Import leer.
    public var csv = CSVZaehler()
}

/// Das Trading-Journal auf der Festplatte: eine SQLite-Datei.
public final class Journal: Sendable {
    /// Name, unter dem der MT4-Importer in `Importlauf.importer` steht.
    public static let mt4Importer = "MT4-Auszug"

    private let db: any DatabaseWriter

    /// Öffnet die Datenbank an diesem Pfad oder legt sie an und bringt sie auf den neuesten Aufbau.
    public convenience init(pfad: String) throws {
        try self.init(writer: DatabaseQueue(path: pfad))
    }

    /// Datenbank nur im Arbeitsspeicher, für Tests.
    public static func imSpeicher() throws -> Journal {
        try Journal(writer: DatabaseQueue())
    }

    private init(writer: any DatabaseWriter) throws {
        db = writer
        try Schema.migrator.migrate(db)
    }

    func lies<T>(_ arbeit: (Database) throws -> T) throws -> T { try db.read(arbeit) }
    func schreibe<T>(_ arbeit: (Database) throws -> T) throws -> T { try db.write(arbeit) }

    /// Namen der Migrationen, die in dieser Datenbank gelaufen sind.
    public func angewandteMigrationen() throws -> [String] {
        try db.read { try Schema.migrator.appliedMigrations($0) }
    }

    // MARK: Import

    /// Liest einen MT4-Auszug und speichert ihn.
    ///
    /// Doppelte werden auf zwei Ebenen erkannt:
    /// 1. Dieselbe Datei (gleicher SHA-256) wird nicht ein zweites Mal gespeichert.
    /// 2. Ein Ticket, das schon aus einem anderen Auszug desselben Kontos bekannt ist
    ///    (Tages- und Monatsauszug überschneiden sich), wird nicht doppelt angelegt.
    ///    Weicht ein Wert ab, bricht der Import ab, statt still eine Fassung zu wählen.
    ///
    /// Alles läuft in einer Transaktion: Entweder ist der ganze Auszug gespeichert oder nichts.
    /// - Parameters:
    ///   - kontowaehrung: steht nicht im Auszug; die App fragt sie ab, Vorgabe EUR.
    ///   - serverZeitzone: steht nicht im Auszug; die App fragt sie ab.
    @discardableResult
    public func importiereMT4(datei: Data, dateiname: String, serverZeitzone: TimeZone,
                              kontowaehrung: String = "EUR",
                              jetzt: Date = Date()) throws -> ImportErgebnis {
        let hash = Self.fingerabdruck(datei)
        if let bekannt = try db.read({ try Importlauf.filter(Column("dateiHash") == hash).fetchOne($0) }) {
            return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
        }

        guard let html = String(data: datei, encoding: .utf8) else { throw SpeicherFehler.keinText }
        let auszug = try MT4Statement.parse(html: html, serverZeitzone: serverZeitzone)
        let abweichungen = auszug.pruefe()
        guard abweichungen.isEmpty else {
            throw SpeicherFehler.auszugWidersprichtSeinenSummen(abweichungen.map(\.description))
        }

        return try db.write { db in
            // Erneut prüfen, falls dieselbe Datei inzwischen parallel importiert wurde.
            if let bekannt = try Importlauf.filter(Column("dateiHash") == hash).fetchOne(db) {
                return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
            }
            let konto = try Self.konto(db, broker: auszug.broker, nummer: auszug.accountNumber,
                                       name: auszug.accountName, waehrung: kontowaehrung)
            var lauf = Importlauf(id: nil, kontoId: konto.id!, importer: Self.mt4Importer,
                                  importerVersion: TradingCore.version, dateiname: dateiname,
                                  dateiHash: hash, datei: datei, art: auszug.kind.rawValue,
                                  stichtag: auszug.reportTime,
                                  serverZeitzone: auszug.serverZeitzone.identifier,
                                  importiertAm: jetzt)
            try lauf.insert(db)
            let laufId = lauf.id!
            var ergebnis = ImportErgebnis(status: .gespeichert, importlaufId: laufId)
            var abweichend: [String] = []

            try KontostandZeile(importlaufId: laufId, auszug.summary).insert(db)

            for p in auszug.closedPositions {
                let neu = GeschlossenZeile(kontoId: konto.id!, importlaufId: laufId, p)
                if let alt = try GeschlossenZeile
                    .filter(Column("kontoId") == konto.id! && Column("ticket") == p.ticket)
                    .fetchOne(db) {
                    if try alt.modell() == p { ergebnis.geschlosseneBekannt += 1 }
                    else { abweichend.append(p.ticket) }
                } else {
                    try neu.insert(db)
                    ergebnis.geschlosseneNeu += 1
                }
            }

            for o in auszug.cancelledOrders {
                let neu = GeloeschtZeile(kontoId: konto.id!, importlaufId: laufId, o)
                if let alt = try GeloeschtZeile
                    .filter(Column("kontoId") == konto.id! && Column("ticket") == o.ticket)
                    .fetchOne(db) {
                    if try alt.modell() == o { ergebnis.geloeschteBekannt += 1 }
                    else { abweichend.append(o.ticket) }
                } else {
                    try neu.insert(db)
                    ergebnis.geloeschteNeu += 1
                }
            }

            for p in auszug.openPositions {
                try OffenZeile(importlaufId: laufId, p).insert(db)
                ergebnis.offene += 1
            }
            for o in auszug.workingOrders {
                try WartendZeile(importlaufId: laufId, o).insert(db)
                ergebnis.wartende += 1
            }

            // Ein Fehler in der Transaktion macht alle Schreibvorgänge oben rückgängig.
            guard abweichend.isEmpty else { throw SpeicherFehler.abweichenderDatensatz(tickets: abweichend) }
            return ergebnis
        }
    }

    /// SHA-256 des Dateiinhalts als Hex-Text: der Fingerabdruck einer Datei.
    public static func fingerabdruck(_ datei: Data) -> String {
        SHA256.hash(data: datei).map { String(format: "%02x", $0) }.joined()
    }

    static func konto(_ db: Database, broker: String, nummer: String,
                              name: String, waehrung: String) throws -> Konto {
        if let konto = try Konto
            .filter(Column("broker") == broker && Column("kontonummer") == nummer)
            .fetchOne(db) {
            guard konto.waehrung == waehrung else {
                throw SpeicherFehler.andereKontowaehrung(gespeichert: konto.waehrung, angegeben: waehrung)
            }
            return konto
        }
        var konto = Konto(id: nil, broker: broker, kontonummer: nummer, kontoname: name, waehrung: waehrung)
        try konto.insert(db)
        return konto
    }

    // MARK: Abfragen

    public func konten() throws -> [Konto] {
        try db.read { try Konto.order(Column("id")).fetchAll($0) }
    }

    /// Alle Importe eines Kontos, ältester Stichtag zuerst.
    public func importe(konto: Konto) throws -> [Importlauf] {
        try db.read {
            try Importlauf.filter(Column("kontoId") == konto.id!)
                .order(Column("stichtag"), Column("id")).fetchAll($0)
        }
    }

    /// Geschlossene Positionen eines Kontos, je Ticket einmal, nach Schließzeit sortiert.
    /// `von` und `bis` begrenzen die Schließzeit (von einschließlich, bis ausschließlich).
    public func geschlossenePositionen(konto: Konto, von: Date? = nil, bis: Date? = nil) throws -> [ClosedPosition] {
        try db.read { db in
            var anfrage = GeschlossenZeile.filter(Column("kontoId") == konto.id!)
            if let von { anfrage = anfrage.filter(Column("closeTime") >= von) }
            if let bis { anfrage = anfrage.filter(Column("closeTime") < bis) }
            return try anfrage.order(Column("closeTime"), Column("ticket")).fetchAll(db).map { try $0.modell() }
        }
    }

    /// Gelöschte Pending Orders eines Kontos, je Ticket einmal.
    public func geloeschteOrders(konto: Konto) throws -> [CancelledOrder] {
        try db.read { db in
            try GeloeschtZeile.filter(Column("kontoId") == konto.id!)
                .order(Column("cancelledAt"), Column("ticket")).fetchAll(db).map { try $0.modell() }
        }
    }

    /// Kontoübersicht aus einem Import.
    public func kontostand(importlauf: Importlauf) throws -> AccountSummary? {
        try db.read { try KontostandZeile.fetchOne($0, key: importlauf.id!)?.modell }
    }

    /// Offene Positionen laut einem Import (Momentaufnahme zum Stichtag dieses Auszugs).
    public func offenePositionen(importlauf: Importlauf) throws -> [OpenPosition] {
        try db.read { db in
            try OffenZeile.filter(Column("importlaufId") == importlauf.id!)
                .order(Column("ticket")).fetchAll(db).map { try $0.modell() }
        }
    }

    /// Offene Positionen laut dem jüngsten MT4-Auszug eines Kontos (größter Stichtag), mit diesem Auszug.
    /// Nur eine Momentaufnahme, nie über Auszüge summiert. Leere Liste: Der Auszug zeigt keine offene Position.
    /// `nil`: Für das Konto gibt es keinen MT4-Auszug (andere Importer liefern keine offenen Positionen).
    public func offenePositionenLetzterAuszug(konto: Konto) throws
        -> (importlauf: Importlauf, positionen: [OpenPosition])? {
        try db.read { db in
            guard let lauf = try Importlauf
                .filter(Column("kontoId") == konto.id! && Column("importer") == Self.mt4Importer)
                .order(Column("stichtag").desc, Column("id").desc).fetchOne(db)
            else { return nil }
            let positionen = try OffenZeile.filter(Column("importlaufId") == lauf.id!)
                .order(Column("ticket")).fetchAll(db).map { try $0.modell() }
            return (lauf, positionen)
        }
    }

    /// Wartende Orders laut einem Import.
    public func wartendeOrders(importlauf: Importlauf) throws -> [WorkingOrder] {
        try db.read { db in
            try WartendZeile.filter(Column("importlaufId") == importlauf.id!)
                .order(Column("ticket")).fetchAll(db).map { try $0.modell() }
        }
    }
}
