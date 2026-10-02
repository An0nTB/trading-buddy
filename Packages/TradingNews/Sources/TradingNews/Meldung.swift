import Foundation

/// Eine Nachricht, wie die App sie zeigt: Überschrift, kurzer Anriss, Quelle, Zeit, Link.
/// Nie der Volltext: Die Anbieter erlauben nur Überschrift, Anriss und Link (R6 Abschnitt 2).
public struct Meldung: Codable, Hashable, Sendable, Identifiable {
    /// Normalisierte Adresse (`Doppelte.schluessel(fuer:)`), damit dieselbe Meldung aus zwei Feeds gleich heißt.
    public var id: String
    public var titel: String
    public var anriss: String?
    /// Anzeigename der Quelle, z. B. „finanzen.net“ oder „Benzinga“. Muss sichtbar bleiben (Quellenangabe).
    public var quelle: String
    /// Öffnet im Browser, nicht eingebettet (Bedingung finanzen.net und finanznachrichten.de, R6).
    public var link: URL
    public var zeit: Date
    /// Aktiensymbole, soweit der Anbieter sie liefert (Alpaca, Marketaux). RSS liefert keine.
    public var symbole: [String]
    public var herkunft: Herkunft

    public init(titel: String, anriss: String?, quelle: String, link: URL, zeit: Date,
                symbole: [String] = [], herkunft: Herkunft) {
        self.id = Doppelte.schluessel(fuer: link)
        self.titel = titel
        self.anriss = anriss
        self.quelle = quelle
        self.link = link
        self.zeit = zeit
        self.symbole = symbole
        self.herkunft = herkunft
    }
}

public enum Herkunft: String, Codable, Sendable, CaseIterable {
    case rss, alpaca, marketaux
}
