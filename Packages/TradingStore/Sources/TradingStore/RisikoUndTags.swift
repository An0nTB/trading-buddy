import Foundation
import GRDB

// Geplantes Risiko und freie Tags je Trade (Migration v10, Doc 02 Nr. 64 und 65, Doc 11 Entscheidung 52).

/// Woher das wirksame Risiko eines Trades stammt.
public enum Risikoherkunft: String, Sendable, Equatable {
    /// Angabe am Trade (`Journaleintrag.risikoEinstieg`).
    case trade
    /// Standard der Setup-Karte, deren Name im Journal steht.
    case setup
    /// Standard des Kontos.
    case konto
}

/// Geplantes Risiko eines Trades als Betrag in Kontowährung, mit Herkunft.
public struct WirksamesRisiko: Sendable, Equatable {
    public var betrag: Decimal
    public var herkunft: Risikoherkunft

    public init(betrag: Decimal, herkunft: Risikoherkunft) {
        self.betrag = betrag
        self.herkunft = herkunft
    }
}

/// Alle Risiko-Angaben eines Kontos auf einmal gelesen. `wirksam(ticket:)` wählt Trade vor Setup vor Konto.
public struct Risikoquellen: Sendable, Equatable {
    /// Standard-Risiko des Kontos.
    public var konto: Decimal?
    /// Standard-Risiko je Setup-Karte, Schlüssel ist der Name der Karte.
    public var setups: [String: Decimal]
    /// Setup-Name je Ticket aus dem Journal.
    public var setupJeTicket: [String: String]
    /// Risiko-Angabe je Ticket aus dem Journal.
    public var tradeJeTicket: [String: Decimal]

    public init(konto: Decimal? = nil, setups: [String: Decimal] = [:], setupJeTicket: [String: String] = [:],
                tradeJeTicket: [String: Decimal] = [:]) {
        self.konto = konto
        self.setups = setups
        self.setupJeTicket = setupJeTicket
        self.tradeJeTicket = tradeJeTicket
    }

    /// Wirksames Risiko des Trades: Angabe am Trade, sonst Standard seines Setups, sonst des Kontos.
    /// `nil`, wenn nichts davon gesetzt ist.
    public func wirksam(ticket: String) -> WirksamesRisiko? {
        if let betrag = tradeJeTicket[ticket] { return WirksamesRisiko(betrag: betrag, herkunft: .trade) }
        if let setup = setupJeTicket[ticket], let betrag = setups[setup] {
            return WirksamesRisiko(betrag: betrag, herkunft: .setup)
        }
        return konto.map { WirksamesRisiko(betrag: $0, herkunft: .konto) }
    }
}

struct TradetagZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tradetag"
    var kontoId: Int64
    var ticket: String
    var tag: String
    var schluessel: String
    var erstellt: Date
}

extension Journal {
    static func pruefeRisiko(_ betrag: Decimal?) throws {
        if let betrag, betrag <= 0 {
            throw SpeicherFehler.ungueltigerWert("Risiko \(betrag) muss größer als 0 sein")
        }
    }

    // MARK: Standard-Risiko

    /// Setzt das Standard-Risiko des Kontos (Betrag in Kontowährung); `nil` entfernt es.
    public func setzeStandardRisiko(_ betrag: Decimal?, konto: Konto) throws {
        try Self.pruefeRisiko(betrag)
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            try db.execute(sql: "UPDATE konto SET standardRisiko = ? WHERE id = ?", arguments: [betrag, kontoId])
        }
    }

    /// Standard-Risiko des Kontos, `nil` ohne Angabe.
    public func standardRisiko(konto: Konto) throws -> Decimal? {
        try lies { db in
            try Decimal.fetchOne(db, sql: "SELECT standardRisiko FROM konto WHERE id = ?", arguments: [konto.id])
        }
    }

    /// Setzt das Standard-Risiko einer Setup-Karte; `nil` entfernt es. Es gilt für Trades mit diesem Setup in
    /// jedem Konto, jeweils als Betrag in dessen Kontowährung.
    public func setzeStandardRisiko(_ betrag: Decimal?, setupId: Int64) throws {
        try Self.pruefeRisiko(betrag)
        try schreibe { db in
            guard try SetupZeile.exists(db, key: setupId) else {
                throw SpeicherFehler.ungueltigerWert("Setup \(setupId) gibt es nicht")
            }
            try db.execute(sql: "UPDATE setup SET standardRisiko = ? WHERE id = ?", arguments: [betrag, setupId])
        }
    }

    /// Standard-Risiko je Setup-Karte, Schlüssel ist der Name; Karten ohne Angabe fehlen.
    public func standardRisikoJeSetup() throws -> [String: Decimal] {
        try lies { db in
            var ergebnis: [String: Decimal] = [:]
            let zeilen = try Row.fetchAll(db, sql: """
                SELECT name, standardRisiko FROM setup WHERE standardRisiko IS NOT NULL
                """)
            for zeile in zeilen {
                if let betrag = zeile["standardRisiko"] as Decimal? { ergebnis[zeile["name"]] = betrag }
            }
            return ergebnis
        }
    }

    /// Alles, was für das wirksame Risiko der Trades eines Kontos nötig ist, in einem Lesevorgang.
    public func risikoquellen(konto: Konto) throws -> Risikoquellen {
        let kontoRisiko = try standardRisiko(konto: konto)
        let setups = try standardRisikoJeSetup()
        let eintraege = try journaleintraege(konto: konto)
        return Risikoquellen(konto: kontoRisiko, setups: setups,
                             setupJeTicket: eintraege.compactMapValues(\.setup),
                             tradeJeTicket: eintraege.compactMapValues(\.risikoEinstieg))
    }

    // MARK: Tags

    /// Ersetzt die Tags eines Trades. Leerraum am Rand fällt weg, leere Tags fallen weg, derselbe Tag in anderer
    /// Schreibweise zählt einmal (die erste gewinnt). Die Schreibweise bleibt erhalten. Eine leere Liste
    /// entfernt alle Tags. Eine Position zum Ticket muss es nicht geben, das Konto schon.
    public func setzeTags(_ tags: [String], konto: Konto, ticket: String, jetzt: Date = Date()) throws {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        var gesehen = Set<String>()
        let sauber = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && gesehen.insert($0.lowercased()).inserted }
        try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            let alt = try TradetagZeile.filter(Column("kontoId") == kontoId && Column("ticket") == ticket)
                .fetchAll(db)
            let erstellt = Dictionary(alt.map { ($0.tag, $0.erstellt) }, uniquingKeysWith: { a, _ in a })
            try TradetagZeile.filter(Column("kontoId") == kontoId && Column("ticket") == ticket).deleteAll(db)
            for tag in sauber {
                try TradetagZeile(kontoId: kontoId, ticket: ticket, tag: tag, schluessel: tag.lowercased(),
                                  erstellt: erstellt[tag] ?? jetzt).insert(db)
            }
        }
    }

    /// Tags je Ticket eines Kontos, je Trade in der Reihenfolge, in der sie gesetzt wurden.
    public func tags(konto: Konto) throws -> [String: [String]] {
        try lies { db in
            let zeilen = try TradetagZeile.filter(Column("kontoId") == konto.id!)
                .order(Column("rowid")).fetchAll(db)
            return Dictionary(grouping: zeilen, by: \.ticket).mapValues { $0.map(\.tag) }
        }
    }

    /// Alle Tags eines Kontos für Vorschläge: jeder Tag einmal (ohne Groß- und Kleinschreibung), in der zuletzt
    /// gesetzten Schreibweise, häufigste zuerst, bei Gleichstand alphabetisch.
    public func alleTags(konto: Konto) throws -> [String] {
        try lies { db in
            let zeilen = try TradetagZeile.filter(Column("kontoId") == konto.id!)
                .order(Column("rowid")).fetchAll(db)
            var anzahl: [String: Int] = [:]
            var schreibweise: [String: String] = [:]
            for zeile in zeilen {
                anzahl[zeile.schluessel, default: 0] += 1
                schreibweise[zeile.schluessel] = zeile.tag
            }
            return anzahl.keys
                .sorted { anzahl[$0]! != anzahl[$1]! ? anzahl[$0]! > anzahl[$1]! : $0 < $1 }
                .map { schreibweise[$0]! }
        }
    }
}
