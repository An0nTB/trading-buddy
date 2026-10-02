import Foundation
@testable import TradingNews

/// Feste Zeit für alle Tests; kein Netz.
let jetzt = Date(timeIntervalSince1970: 1_790_000_000)

func zeit(_ iso: String) -> Date { Zeitleser.lies(iso)! }

func meldung(_ titel: String, anriss: String? = nil, link: String = "https://example.org/a",
             zeit: Date = jetzt, symbole: [String] = [], quelle: String = "Test") -> Meldung {
    Meldung(titel: titel, anriss: anriss, quelle: quelle, link: URL(string: link)!, zeit: zeit,
            symbole: symbole, herkunft: .rss)
}

func parameter(_ anfrage: Anfrage) -> [String: String] {
    let teile = URLComponents(url: anfrage.url, resolvingAgainstBaseURL: false)!
    var ergebnis: [String: String] = [:]
    for eintrag in teile.queryItems ?? [] { ergebnis[eintrag.name] = eintrag.value }
    return ergebnis
}

/// Liefert aufgezeichnete Antworten je Host und Pfad; mehrere Antworten nacheinander, die letzte bleibt.
actor AufgezeichnetesLaden: Laden {
    private var antworten: [String: [Antwort]]
    private(set) var anfragen: [Anfrage] = []

    init(_ antworten: [String: [Antwort]]) {
        self.antworten = antworten
    }

    func lade(_ anfrage: Anfrage) async throws -> Antwort {
        anfragen.append(anfrage)
        let schluessel = (anfrage.url.host ?? "") + anfrage.url.path
        guard var liste = antworten[schluessel], !liste.isEmpty else { return Antwort(status: 404) }
        let antwort = liste.count > 1 ? liste.removeFirst() : liste[0]
        antworten[schluessel] = liste
        return antwort
    }
}

enum Beispiel {
    /// Aufbau wie finanzen.net/rss/news am 02.10.2026 (RSS 2.0, Anriss als HTML in CDATA, Zeit mit +0200).
    static let finanzenNet = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
    <title>Nachrichten Ticker - www.finanzen.net</title><link>https://www.finanzen.net</link>
    <atom:link href="https://www.finanzen.net/rss/news" rel="self" type="application/rss+xml"/>
    <language>de-de</language><lastBuildDate>Tue, 29 Sep 2026 19:27:04 +0200</lastBuildDate>
    <item><title>DAX steigt etwas</title><pubDate>Tue, 29 Sep 2026 19:25:00 +0200</pubDate>
    <link>https://www.finanzen.net/nachricht/aktien/dax-aktuell-1</link>
    <description><![CDATA[<p>Der <b>DAX</b> legte zu &amp; SAP gewann.</p><a href="https://www.finanzen.net/x">mehr</a>]]></description>
    <guid isPermaLink="true">https://www.finanzen.net/nachricht/aktien/dax-aktuell-1</guid></item>
    <item><title>Ohne Link</title><pubDate>Tue, 29 Sep 2026 19:20:00 +0200</pubDate></item>
    <item><title></title><link>https://www.finanzen.net/leer</link></item>
    </channel></rss>
    """

    /// Aufbau wie api.boerse-frankfurt.de/v1/feeds/news.rss am 02.10.2026 (media-Namensraum, Zeit in GMT).
    static let boerseFrankfurt = """
    <rss xmlns:media="http://search.yahoo.com/mrss/" version="2.0"><channel><title>Börse Frankfurt</title>
    <item><title>Rohstoffe: Alles auf Gold</title>
    <link>https://www.boerse-frankfurt.de/nachrichten/rohstoffe-alles-auf-gold</link>
    <description>Die starken Bewegungen an den Rohstoffmärkten setzen sich fort.</description>
    <pubDate>Thu, 01 Oct 2026 07:35:04 GMT</pubDate>
    <guid>https://www.boerse-frankfurt.de/nachrichten/rohstoffe-alles-auf-gold</guid>
    <enclosure url="https://www.boerse-frankfurt.de/bild.jpg" length="1" type="image/jpeg"/>
    <media:thumbnail url="https://www.boerse-frankfurt.de/t.jpg"/>
    <media:content url="https://www.boerse-frankfurt.de/c.jpg"><media:title>Bildtitel</media:title></media:content>
    </item></channel></rss>
    """

    /// Atom, synthetisch nach RFC 4287.
    static let atom = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom"><title>Beispiel</title>
    <entry><title type="html">Zinsen &amp;amp; Anleihen</title>
    <link rel="enclosure" href="https://example.org/ton.mp3"/>
    <link rel="alternate" href="https://example.org/zinsen"/>
    <id>tag:example.org,2026:1</id><updated>2026-10-02T06:00:00Z</updated>
    <summary>Kurz eingeordnet.</summary><content>Volltext gehört nicht in die App.</content></entry>
    </feed>
    """

    /// Synthetisch nach dem Schema der Alpaca-Doku (News articles, 02.10.2026).
    static let alpaca = """
    {"news":[{"id":24843171,"headline":"Apple &amp; Tesla rally","author":"Benzinga Newsdesk",
    "created_at":"2026-10-01T16:19:16Z","updated_at":"2026-10-01T16:19:17Z","summary":"<p>Shares rose.</p>",
    "content":"","url":"https://www.benzinga.com/news/26/10/24843171/apple-tesla","images":[],
    "symbols":["AAPL","tsla"],"source":"benzinga"}],"next_page_token":"MTY0MjAwNDM1Njc1NjAwMDAwMHwyNDg0MzE3MQ=="}
    """

    /// Beispielantwort aus der Marketaux-Doku (gelesen 02.10.2026), gekürzt.
    static let marketaux = """
    {"meta":{"found":140037,"returned":1,"limit":3,"page":1},"data":[{"uuid":"70cb577e-c2dd-4dde-b501-f713823a4939",
    "title":"Trump wins 2024, markets surge globally",
    "description":"Global markets experience a significant surge following Trump's victory",
    "keywords":"","snippet":"Donald Trump has won the 2024 presidential election...",
    "url":"https://www.killerstartups.com/trump-wins-2024/","image_url":"https://images.killerstartups.com/Trump-Wins.jpg",
    "language":"en","published_at":"2024-11-08T01:24:00.000000Z","source":"killerstartups.com","relevance_score":null,
    "entities":[{"symbol":"TSLA","name":"Tesla, Inc.","exchange":null,"exchange_long":null,"country":"us","type":"equity",
    "industry":"Consumer Cyclical","match_score":12.133104,"sentiment_score":0.7783,
    "highlights":[{"highlight":"Text snippet containing entity","sentiment":0.7783,"highlighted_in":"main_text"}]},
    {"symbol":"tsla","name":"Tesla, Inc."}],"similar":[]}]}
    """

    static let marketauxFehler = """
    {"error":{"code":"usage_limit_reached","message":"The usage limit for this account has been reached."}}
    """
}
