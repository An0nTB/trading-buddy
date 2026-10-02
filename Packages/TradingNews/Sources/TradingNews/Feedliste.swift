import Foundation

/// Ein RSS-Feed mit Anzeigename der Quelle.
public struct Feed: Codable, Hashable, Sendable {
    public enum Bereich: String, Codable, Sendable, CaseIterable {
        /// Allgemeine Börsen- und Marktnachrichten.
        case markt
        /// Ad-hoc-Mitteilungen börsennotierter Unternehmen.
        case adhoc
        /// Zentralbanken und Aufsicht.
        case amtlich
    }

    public var quelle: String
    public var titel: String
    public var adresse: URL
    public var bereich: Bereich

    public init(quelle: String, titel: String, adresse: URL, bereich: Bereich) {
        self.quelle = quelle
        self.titel = titel
        self.adresse = adresse
        self.bereich = bereich
    }
}

/// Vorbelegte Feeds (Entscheidung N-E1, Tim 02.10.2026; Bedingungen in R6 Abschnitt 2 und 6).
/// Alle erlauben Überschrift, Anriss und Link; der Link öffnet im Browser.
/// Adressen von den Feed-Übersichten der Anbieter, gelesen 02.10.2026. Bundesbank und BaFin fehlen noch,
/// weil ihre Feed-Adressen nicht geprüft sind.
public enum Feedliste {
    public static let standard: [Feed] = [
        feed("finanzen.net", "News", "https://www.finanzen.net/rss/news", .markt),
        feed("finanzen.net", "Analysen", "https://www.finanzen.net/rss/analysen", .markt),
        feed("Börse Frankfurt", "Nachrichten", "https://api.boerse-frankfurt.de/v1/feeds/news.rss", .markt),
        feed("wallstreet-online", "Marktberichte", "https://www.wallstreet-online.de/rss/nachrichten-marktberichte.xml", .markt),
        feed("wallstreet-online", "Ad-hoc", "https://www.wallstreet-online.de/rss/nachrichten-ad-hocs.xml", .adhoc),
        feed("finanznachrichten.de", "Aktien Deutschland", "https://www.finanznachrichten.de/rss-nachrichten-aktien-deutschland", .markt),
        feed("finanznachrichten.de", "Aktien USA", "https://www.finanznachrichten.de/rss-nachrichten-aktien-usa", .markt),
        feed("finanznachrichten.de", "Ad-hoc", "https://www.finanznachrichten.de/rss-aktien-adhoc", .adhoc),
        feed("EZB", "Pressemitteilungen", "https://www.ecb.europa.eu/rss/press.html", .amtlich),
        feed("Fed", "Pressemitteilungen", "https://www.federalreserve.gov/feeds/press_all.xml", .amtlich)
    ]

    private static func feed(_ quelle: String, _ titel: String, _ adresse: String, _ bereich: Feed.Bereich) -> Feed {
        Feed(quelle: quelle, titel: titel, adresse: URL(string: adresse)!, bereich: bereich)
    }
}
