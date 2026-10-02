import Foundation

/// Schlüssel für Alpaca. Derselbe Schlüsselbund-Eintrag wie für die Kurse (TradingQuotes);
/// die App reicht ihn an beide Pakete. Nie in Dateien oder Protokolle.
public struct AlpacaNewsSchluessel: Sendable, Equatable, CustomStringConvertible {
    public var schluesselID: String
    public var geheimnis: String

    public init(schluesselID: String, geheimnis: String) {
        self.schluesselID = schluesselID
        self.geheimnis = geheimnis
    }

    public var description: String { "AlpacaNewsSchluessel(***)" }
}

/// Alpaca News, Inhalte von Benzinga, US-Aktien und Krypto mit Symbolen je Meldung.
/// Format laut docs.alpaca.markets (News, Historical News Data), gelesen 02.10.2026:
/// GET https://data.alpaca.markets/v1beta1/news mit `symbols`, `start`, `sort`, `limit` (1 bis 50),
/// `include_content`; Antwort `{"news":[{id, headline, author, created_at, updated_at, summary, content,
/// url, images, symbols, source}], "next_page_token"}`. Anmeldung über die Kopfzeilen
/// `APCA-API-KEY-ID` und `APCA-API-SECRET-KEY`.
/// Offen (R6): ob der Gratisplan Meldungen sofort oder 15 Minuten verzögert liefert.
public enum AlpacaNews {
    static let adresse = URL(string: "https://data.alpaca.markets/v1beta1/news")!

    /// Ohne Symbole liefert Alpaca allgemeine US-Marktnachrichten.
    public static func anfrage(symbole: [String], seit: Date?, limit: Int = 50,
                               schluessel: AlpacaNewsSchluessel) -> Anfrage {
        var teile = URLComponents(url: adresse, resolvingAgainstBaseURL: false)!
        var parameter = [
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            // Kein Volltext (Lizenz, R6); die Zusammenfassung von Benzinga reicht als Anriss.
            URLQueryItem(name: "include_content", value: "false")
        ]
        let liste = symbole.map { $0.uppercased() }.filter { !$0.isEmpty }
        if !liste.isEmpty { parameter.append(URLQueryItem(name: "symbols", value: liste.joined(separator: ","))) }
        if let seit { parameter.append(URLQueryItem(name: "start", value: Zeitleser.iso(seit))) }
        teile.queryItems = parameter
        return Anfrage(url: teile.url!, kopf: [
            "APCA-API-KEY-ID": schluessel.schluesselID,
            "APCA-API-SECRET-KEY": schluessel.geheimnis,
            "Accept": "application/json"
        ])
    }

    struct Antwort: Decodable {
        struct Eintrag: Decodable {
            let headline: String
            let summary: String?
            let url: String?
            let symbols: [String]?
            let source: String?
            let created_at: String?
            let updated_at: String?
        }
        let news: [Eintrag]
        let next_page_token: String?
    }

    public struct Seite: Sendable, Equatable {
        public var meldungen: [Meldung]
        public var naechsteSeite: String?
    }

    public static func lies(_ daten: Data, jetzt: Date) throws -> Seite {
        let antwort = try JSONDecoder().decode(Antwort.self, from: daten)
        let meldungen = antwort.news.compactMap { e -> Meldung? in
            guard let text = e.url, let url = URL(string: text), !e.headline.isEmpty else { return nil }
            let zeit = (e.created_at ?? e.updated_at).flatMap(Zeitleser.lies) ?? jetzt
            return Meldung(titel: Text.bereinigt(e.headline), anriss: Text.anriss(e.summary),
                           quelle: anzeigename(e.source), link: url, zeit: zeit,
                           symbole: (e.symbols ?? []).map { $0.uppercased() }, herkunft: .alpaca)
        }
        return Seite(meldungen: meldungen, naechsteSeite: antwort.next_page_token)
    }

    /// `benzinga` → `Benzinga`.
    static func anzeigename(_ quelle: String?) -> String {
        guard let quelle, let erstes = quelle.first else { return "Alpaca" }
        return erstes.uppercased() + quelle.dropFirst()
    }
}
