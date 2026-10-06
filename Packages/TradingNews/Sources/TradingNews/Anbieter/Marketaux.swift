import Foundation

/// Marketaux, Nachrichten weltweit mit Symbolen, filterbar nach Land und Sprache.
/// Gratis 100 Abrufe am Tag, 3 Artikel je Abruf (marketaux.com/pricing, 02.10.2026); laut R1 keine
/// kommerzielle Nutzung im Gratisplan.
/// Format laut marketaux.com/documentation, gelesen 02.10.2026: GET https://api.marketaux.com/v1/news/all
/// mit `api_token`, `symbols`, `search`, `language`, `filter_entities`, `published_after`, `limit`;
/// Antwort `{"meta":{…},"data":[{uuid, title, description, snippet, url, published_at, source, entities:[{symbol,…}]}]}`;
/// Fehler `{"error":{"code","message"}}`.
/// Achtung: Der Schlüssel steht in der Adresse. Anfrage-Adressen nie protokollieren.
public enum Marketaux {
    static let adresse = URL(string: "https://api.marketaux.com/v1/news/all")!
    /// Artikel je Abruf im Gratisplan.
    public static let artikelJeAbruf = 3
    public static let abrufeJeTagGratis = 100

    /// Eine Anfrage je Merkbegriff. ISIN geht nicht über Marketaux (kein belegter Filter), dort reicht die
    /// Textsuche in den RSS-Feeds; dann `nil`.
    public static func anfrage(fuer begriff: Merkbegriff, token: String, seit: Date?,
                               sprachen: [String] = ["de", "en"]) -> Anfrage? {
        guard !begriff.text.isEmpty else { return nil }
        var parameter = [
            URLQueryItem(name: "api_token", value: token),
            URLQueryItem(name: "language", value: sprachen.joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(artikelJeAbruf))
        ]
        switch begriff.art {
        case .symbol:
            // Index-CFDs kennt Marketaux nicht als Symbol; Suche nach dem Indexnamen als Wortfolge.
            if let name = Indizes.namen(fuer: begriff.text)?.first {
                parameter.append(URLQueryItem(name: "search", value: "\"\(name)\""))
                break
            }
            parameter.append(URLQueryItem(name: "symbols", value: begriff.text.uppercased()))
            parameter.append(URLQueryItem(name: "filter_entities", value: "true"))
        case .name:
            parameter.append(URLQueryItem(name: "search", value: "\"\(begriff.text)\""))
        case .stichwort:
            let woerter = begriff.text.split(separator: " ").map(String.init)
            parameter.append(URLQueryItem(name: "search", value: woerter.joined(separator: " + ")))
        case .isin:
            return nil
        }
        if let seit { parameter.append(URLQueryItem(name: "published_after", value: Zeitleser.utcOhneZone(seit))) }
        var teile = URLComponents(url: adresse, resolvingAgainstBaseURL: false)!
        teile.queryItems = parameter
        // „+“ ist bei Marketaux das UND der Suche; unkodiert würde der Server ein Leerzeichen lesen.
        teile.percentEncodedQuery = teile.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return Anfrage(url: teile.url!, kopf: ["Accept": "application/json"])
    }

    public struct Fehler: Error, Sendable, Equatable, CustomStringConvertible {
        public var code: String
        public var nachricht: String
        public var description: String { "Marketaux \(code): \(nachricht)" }
    }

    struct Antwort: Decodable {
        struct Eintrag: Decodable {
            struct Entitaet: Decodable { let symbol: String? }
            let title: String
            let description: String?
            let snippet: String?
            let url: String?
            let published_at: String?
            let source: String?
            let entities: [Entitaet]?
        }
        let data: [Eintrag]
    }

    struct FehlerAntwort: Decodable {
        struct Inhalt: Decodable { let code: String; let message: String }
        let error: Inhalt
    }

    public static func lies(_ daten: Data, jetzt: Date) throws -> [Meldung] {
        if let fehler = try? JSONDecoder().decode(FehlerAntwort.self, from: daten) {
            throw Fehler(code: fehler.error.code, nachricht: fehler.error.message)
        }
        let antwort = try JSONDecoder().decode(Antwort.self, from: daten)
        return antwort.data.compactMap { e -> Meldung? in
            guard let text = e.url, let url = URL(string: text), !e.title.isEmpty else { return nil }
            let anriss = [e.description, e.snippet].compactMap { $0 }.first { !$0.isEmpty }
            let symbole = (e.entities ?? []).compactMap { $0.symbol?.uppercased() }
            return Meldung(titel: Text.bereinigt(e.title), anriss: Text.anriss(anriss),
                           quelle: e.source ?? "Marketaux", link: url,
                           zeit: e.published_at.flatMap(Zeitleser.lies) ?? jetzt,
                           symbole: symbole.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } },
                           herkunft: .marketaux)
        }
    }
}
