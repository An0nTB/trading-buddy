import Foundation
import GRDB

/// Eigene Angaben zu einem Trade im Journal. Alle Felder außer Schlüssel und Zeitstempel
/// sind freiwillig; `nil` heißt „nicht ausgefüllt“.
public struct Journaleintrag: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "journal"
    public var kontoId: Int64
    public var ticket: String
    /// Name des Setups, z. B. „Ausbruch“.
    public var setup: String?
    /// Nach den eigenen Regeln gehandelt?
    public var regeltreue: Bool?
    /// Eigener Zustand von 1 (schlecht) bis 5 (sehr gut).
    public var zustand: Int?
    public var marktumfeld: String?
    /// Grund für den Einstieg, freier Text.
    public var grund: String?
    /// Nachgetragener Stop beim Einstieg, wenn der Export keinen oder einen später
    /// verschobenen Stop zeigt. Ersetzt für die Kennzahlen den Stop aus dem Export.
    public var stopEinstieg: Decimal?
    /// Geplantes Risiko dieses Trades als Betrag in Kontowährung (v10). Geht vor dem Standard des Setups
    /// und des Kontos (`Risikoquellen`).
    public var risikoEinstieg: Decimal?
    public var geaendertAm: Date

    public init(kontoId: Int64, ticket: String, setup: String? = nil, regeltreue: Bool? = nil,
                zustand: Int? = nil, marktumfeld: String? = nil, grund: String? = nil,
                stopEinstieg: Decimal? = nil, risikoEinstieg: Decimal? = nil, geaendertAm: Date = Date()) {
        self.kontoId = kontoId
        self.ticket = ticket
        self.setup = setup
        self.regeltreue = regeltreue
        self.zustand = zustand
        self.marktumfeld = marktumfeld
        self.grund = grund
        self.stopEinstieg = stopEinstieg
        self.risikoEinstieg = risikoEinstieg
        self.geaendertAm = geaendertAm
    }
}

extension Journal {
    /// Alle Journaleinträge eines Kontos, Schlüssel ist das Ticket.
    public func journaleintraege(konto: Konto) throws -> [String: Journaleintrag] {
        let eintraege = try lies { db in
            try Journaleintrag.filter(Column("kontoId") == konto.id!).fetchAll(db)
        }
        return Dictionary(uniqueKeysWithValues: eintraege.map { ($0.ticket, $0) })
    }

    /// Legt den Eintrag an oder ersetzt den vorhandenen mit gleichem Konto und Ticket.
    /// Eine Position zum Ticket muss es nicht geben, das Konto schon.
    public func speichereJournal(_ eintrag: Journaleintrag) throws {
        try Self.pruefeEintrag(eintrag)
        try schreibe { db in
            guard try Konto.exists(db, key: eintrag.kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(eintrag.kontoId) gibt es nicht")
            }
            try eintrag.save(db)
        }
    }

    /// Wertebereiche eines Eintrags; auch für das Formular „Trade eintragen“.
    static func pruefeEintrag(_ eintrag: Journaleintrag) throws {
        if let zustand = eintrag.zustand, !(1...5).contains(zustand) {
            throw SpeicherFehler.ungueltigerWert("Zustand \(zustand), erlaubt 1 bis 5")
        }
        try pruefeRisiko(eintrag.risikoEinstieg)
    }

    /// Entfernt den Eintrag zu diesem Ticket, falls vorhanden.
    public func loescheJournal(konto: Konto, ticket: String) throws {
        try schreibe { db in
            _ = try Journaleintrag.deleteOne(db, key: ["kontoId": konto.id!, "ticket": ticket])
        }
    }
}
