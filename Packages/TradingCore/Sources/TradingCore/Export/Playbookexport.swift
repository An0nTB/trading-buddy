import Foundation

extension JournalExport {
    /// Karte des Playbooks für den Connector: Kriterien der Checkliste, Stop- und Zielregel, Marktumfeld und Status.
    /// Gilt für alle Konten; verbunden mit dem Trade über `Journalangaben.setup`, die abgehakten Kriterien stehen in
    /// `Kontodaten.checklisten`. Damit kann Claude im Review prüfen, ob ein Trade nach Plan lief. Ohne Notiz.
    public struct Playbookkarte: Sendable, Equatable, Codable {
        public var name: String
        public var kriterien: [Kriterium]
        public var stopRegel: String?
        public var zielRegel: String?
        public var marktumfeld: String?
        /// `Setup.Status` als Text („test“, „aktiv“, „pausiert“), damit ein neuer Status ältere Connectoren nicht stört.
        public var status: String
        // Ab Rechenkern 0.29.0 (E4, E5, E7, E8); alle optional, Format bleibt 2.
        /// Standard-Risiko der Karte in Kontowährung (E8); fehlt ohne Angabe.
        public var standardRisiko: Decimal?
        /// Höchstens so viele Trades je Tag mit diesem Setup (E4).
        public var maxTradesJeTag: Int?
        /// `Setup.Haltedauer` als Text („gleicherTag“, „keinWochenende“; E5).
        public var haltedauer: String?
        /// N der Prüfung des Erwartungswerts (E7).
        public var pruefungNachTrades: Int?
        /// Stand der Prüfung je Kontoart (E7); fehlt ohne N oder ohne Trades.
        public var pruefung: [Setuppruefung]?

        public init(name: String, kriterien: [Kriterium] = [], stopRegel: String? = nil, zielRegel: String? = nil,
                    marktumfeld: String? = nil, status: String = Setup.Status.aktiv.rawValue,
                    standardRisiko: Decimal? = nil, maxTradesJeTag: Int? = nil, haltedauer: String? = nil,
                    pruefungNachTrades: Int? = nil, pruefung: [Setuppruefung] = []) {
            self.name = name
            self.kriterien = kriterien
            self.stopRegel = stopRegel.flatMap { $0.isEmpty ? nil : $0 }
            self.zielRegel = zielRegel.flatMap { $0.isEmpty ? nil : $0 }
            self.marktumfeld = marktumfeld.flatMap { $0.isEmpty ? nil : $0 }
            self.status = status
            self.standardRisiko = standardRisiko
            self.maxTradesJeTag = maxTradesJeTag
            self.haltedauer = haltedauer
            self.pruefungNachTrades = pruefungNachTrades
            self.pruefung = pruefung.isEmpty ? nil : pruefung.sorted { $0.kontoart < $1.kontoart }
        }

        /// Karte aus dem Playbook; `pruefung` aus `Setuppruefung.berechne`, hier auf diese Karte gefiltert.
        public init(_ s: Setup, standardRisiko: Decimal? = nil, pruefung: [Setuppruefung] = []) {
            self.init(name: s.name, kriterien: s.kriterien, stopRegel: s.stopRegel, zielRegel: s.zielRegel,
                      marktumfeld: s.marktumfeld, status: s.status.rawValue, standardRisiko: standardRisiko,
                      maxTradesJeTag: s.maxTradesJeTag, haltedauer: s.haltedauer?.rawValue,
                      pruefungNachTrades: s.pruefungNachTrades,
                      pruefung: pruefung.filter { Setup.schluessel($0.setup) == Setup.schluessel(s.name) })
        }

        /// Die Regeln der Karte als `Setup` für `Regelpruefung` im Connector; Status und Kriterien zählen dort nicht.
        public var setupRegeln: Setup {
            Setup(name: name, kriterien: kriterien, maxTradesJeTag: maxTradesJeTag,
                  haltedauer: haltedauer.flatMap(Setup.Haltedauer.init(rawValue:)), pruefungNachTrades: pruefungNachTrades)
        }
    }

    /// Karte zum Setup-Namen aus dem Journal, ohne Rücksicht auf Groß- und Kleinschreibung und Leerzeichen am Rand.
    public func playbookkarte(_ setup: String?) -> Playbookkarte? {
        guard let name = setup?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
        return playbook?.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == name }
    }
}
