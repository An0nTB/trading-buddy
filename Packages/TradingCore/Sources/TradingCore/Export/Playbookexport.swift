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

        public init(name: String, kriterien: [Kriterium] = [], stopRegel: String? = nil, zielRegel: String? = nil,
                    marktumfeld: String? = nil, status: String = Setup.Status.aktiv.rawValue) {
            self.name = name
            self.kriterien = kriterien
            self.stopRegel = stopRegel.flatMap { $0.isEmpty ? nil : $0 }
            self.zielRegel = zielRegel.flatMap { $0.isEmpty ? nil : $0 }
            self.marktumfeld = marktumfeld.flatMap { $0.isEmpty ? nil : $0 }
            self.status = status
        }

        public init(_ s: Setup) {
            self.init(name: s.name, kriterien: s.kriterien, stopRegel: s.stopRegel, zielRegel: s.zielRegel,
                      marktumfeld: s.marktumfeld, status: s.status.rawValue)
        }
    }

    /// Karte zum Setup-Namen aus dem Journal, ohne Rücksicht auf Groß- und Kleinschreibung und Leerzeichen am Rand.
    public func playbookkarte(_ setup: String?) -> Playbookkarte? {
        guard let name = setup?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
        return playbook?.first { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == name }
    }
}
