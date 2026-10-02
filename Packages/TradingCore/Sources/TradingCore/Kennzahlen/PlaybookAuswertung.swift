import Foundation

/// Kennzahlen je Setup und je Kriterium (Doc 18, F3): Welche Bedingungen hängen mit Gewinn zusammen?
/// „Prozess vor Ergebnis“: vollständig abgehakte Trades werden getrennt von unvollständigen ausgewiesen.
/// Unter 30 Trades je Gruppe nur beschreiben (`Kennzahlen.genugDaten`).
public struct PlaybookAuswertung: Sendable, Equatable {
    public struct JeSetup: Sendable, Equatable {
        public var setup: String
        public var kennzahlen: Kennzahlen
        /// Trades, bei denen alle Kriterien der Karte abgehakt sind.
        public var vollstaendig: Kennzahlen
        public var unvollstaendig: Kennzahlen
        /// Anteil vollständiger Trades; `nil` ohne Trades oder ohne Kriterien auf der Karte.
        public var regeltreue: Decimal?
    }

    public struct JeKriterium: Sendable, Equatable {
        public var setup: String
        public var kriterium: Kriterium
        public var erfuellt: Kennzahlen
        public var nichtErfuellt: Kennzahlen
        /// Erwartungswert erfüllt minus nicht erfüllt, in Kontowährung; `nil`, wenn eine Seite leer ist.
        public var effekt: Decimal?
        /// Beide Seiten mit mindestens 30 Trades.
        public var genugDaten: Bool { erfuellt.genugDaten && nichtErfuellt.genugDaten }
    }

    /// Je Setup aus dem Playbook, in der Reihenfolge des Playbooks. Setups ohne Trades erscheinen mit 0.
    public var setups: [JeSetup]
    /// Je Kriterium, nach Betrag des Effekts absteigend; ohne Effekt am Ende.
    public var kriterien: [JeKriterium]
    /// Trades mit einem Setup-Namen, der im Playbook fehlt (Tippfehler, gelöschte Karte).
    public var unbekannteSetups: [String: Kennzahlen]
    public var ohneSetup: Kennzahlen

    public init(trades: [Trade], playbook: [Setup], checklisten: [String: Checkliste]) {
        let karten = Dictionary(playbook.map { ($0.name, $0) }, uniquingKeysWith: { erste, _ in erste })
        let mitSetup = trades.filter { checklisten[$0.id] != nil }
        ohneSetup = Kennzahlen(trades: trades.filter { checklisten[$0.id] == nil })
        let unbekannt = Dictionary(grouping: mitSetup.filter { karten[checklisten[$0.id]!.setup] == nil }) {
            checklisten[$0.id]!.setup
        }
        unbekannteSetups = unbekannt.mapValues { Kennzahlen(trades: $0) }

        var jeSetup: [JeSetup] = []
        var jeKriterium: [JeKriterium] = []
        for karte in playbook {
            let eigene = mitSetup.filter { checklisten[$0.id]!.setup == karte.name }
            let ids = Set(karte.kriterien.map(\.id))
            let voll = eigene.filter { ids.isSubset(of: checklisten[$0.id]!.erfuellt) }
            let rest = eigene.filter { !ids.isSubset(of: checklisten[$0.id]!.erfuellt) }
            jeSetup.append(JeSetup(
                setup: karte.name, kennzahlen: Kennzahlen(trades: eigene), vollstaendig: Kennzahlen(trades: voll),
                unvollstaendig: Kennzahlen(trades: rest),
                regeltreue: eigene.isEmpty || ids.isEmpty ? nil : Decimal(voll.count) / Decimal(eigene.count)))
            for k in karte.kriterien {
                let ja = Kennzahlen(trades: eigene.filter { checklisten[$0.id]!.erfuellt.contains(k.id) })
                let nein = Kennzahlen(trades: eigene.filter { !checklisten[$0.id]!.erfuellt.contains(k.id) })
                var effekt: Decimal?
                if let a = ja.erwartungswert, let b = nein.erwartungswert { effekt = a - b }
                jeKriterium.append(JeKriterium(setup: karte.name, kriterium: k, erfuellt: ja, nichtErfuellt: nein,
                                               effekt: effekt))
            }
        }
        setups = jeSetup
        kriterien = jeKriterium.enumerated().sorted { a, b in
            switch (a.element.effekt, b.element.effekt) {
            case let (x?, y?) where abs(x) != abs(y): return abs(x) > abs(y)
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
}
