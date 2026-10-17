import Foundation

/// Karte eines Setups im Playbook (Doc 18, F3; R5 Kapitel 10 Abschnitt 3).
/// Der Name verbindet die Karte mit dem Feld „Setup“ im Journal. Gespeichert in TradingStore (Migration v7).
public struct Setup: Codable, Sendable, Equatable {
    /// R5: neue Setups erst nach einer Testphase übernehmen, schwache pausieren; Wechsel mit Datum.
    public enum Status: String, Codable, Sendable, CaseIterable {
        case test, aktiv, pausiert
    }

    /// Von der Datenbank vergeben; `nil`, solange die Karte nicht gespeichert ist.
    public var id: Int64?
    public var name: String
    /// Bedingungen für den Einstieg; je Trade abhakbar.
    public var kriterien: [Kriterium]
    public var stopRegel: String?
    public var zielRegel: String?
    public var marktumfeld: String?
    public var notiz: String?
    public var status: Status
    public var statusSeit: Date
    /// Höchstens so viele Trades je Kalendertag mit diesem Setup, zusätzlich zur Grenze des Kontos (E4).
    public var maxTradesJeTag: Int?
    /// Wie lange ein Trade dieses Setups offen bleiben darf (E5); `nil` heißt ohne Grenze.
    public var haltedauer: Haltedauer?
    /// Nach so vielen Trades ist die Prüfung des Erwartungswerts in R fällig (E7, Kill-Kriterium).
    public var pruefungNachTrades: Int?

    /// Haltedauer-Regel eines Setups (E5, Daytrading-Regel D1).
    public enum Haltedauer: String, Codable, Sendable, CaseIterable {
        /// Am Eröffnungstag schließen; schließt „übers Wochenende“ ein.
        case gleicherTag
        /// Über Nacht erlaubt, aber nicht über Samstag oder Sonntag.
        case keinWochenende
    }

    public init(id: Int64? = nil, name: String, kriterien: [Kriterium] = [], stopRegel: String? = nil,
                zielRegel: String? = nil, marktumfeld: String? = nil, notiz: String? = nil,
                status: Status = .test, statusSeit: Date = Date(), maxTradesJeTag: Int? = nil,
                haltedauer: Haltedauer? = nil, pruefungNachTrades: Int? = nil) {
        self.id = id
        self.name = name
        self.kriterien = kriterien
        self.stopRegel = stopRegel
        self.zielRegel = zielRegel
        self.marktumfeld = marktumfeld
        self.notiz = notiz
        self.status = status
        self.statusSeit = statusSeit
        self.maxTradesJeTag = maxTradesJeTag
        self.haltedauer = haltedauer
        self.pruefungNachTrades = pruefungNachTrades
    }

    /// Schlüssel für den Vergleich mit dem Setup-Feld im Journal: ohne Leerraum am Rand, Kleinbuchstaben.
    public static func schluessel(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Eine Bedingung der Checkliste. Die Kennung bleibt gleich, wenn der Text umformuliert wird,
/// damit alte Häkchen gültig bleiben.
public struct Kriterium: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var text: String

    public init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }
}

/// Was beim Trade tatsächlich vorlag: Setup laut Journal und die abgehakten Kriterien.
public struct Checkliste: Codable, Sendable, Equatable {
    public var setup: String
    public var erfuellt: Set<String>

    public init(setup: String, erfuellt: Set<String> = []) {
        self.setup = setup
        self.erfuellt = erfuellt
    }
}
