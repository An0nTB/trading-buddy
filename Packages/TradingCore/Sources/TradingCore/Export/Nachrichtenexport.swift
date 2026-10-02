import Foundation

extension JournalExport {
    /// Nachrichtenmeldung im Export für die Zusammenfassung über den Connector (Doc 26).
    /// Nur Überschrift, Anriss, Quelle, Zeit und Link wie in der App, nie der Volltext (R6 Abschnitt 2).
    public struct Meldung: Sendable, Equatable, Codable {
        public var titel: String
        public var anriss: String?
        /// Anzeigename der Quelle; muss in jeder Zusammenfassung sichtbar bleiben.
        public var quelle: String
        public var link: String
        public var zeit: Date
        /// Aktiensymbole laut Anbieter; leer bei RSS.
        public var symbole: [String]
        /// Begriffe der Merkliste, zu denen die Meldung passt; leer heißt „Markt“.
        public var merkliste: [String]

        public init(titel: String, anriss: String? = nil, quelle: String, link: String, zeit: Date,
                    symbole: [String] = [], merkliste: [String] = []) {
            self.titel = titel
            self.anriss = anriss.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            self.quelle = quelle
            self.link = link
            self.zeit = zeit
            self.symbole = symbole
            self.merkliste = merkliste
        }
    }

    /// So viele Tage Nachrichten trägt die Datei höchstens.
    public static let nachrichtenTage = 7
    /// So viele Meldungen trägt die Datei höchstens, die neuesten zuerst.
    public static let nachrichtenHoechstens = 300
}
