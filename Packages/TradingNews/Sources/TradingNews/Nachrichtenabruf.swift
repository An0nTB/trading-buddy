import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Eine Abfrage: Adresse und Kopfzeilen. Eigener Typ statt `URLRequest`, damit er auf Linux und
/// Apple-Systemen gleich `Sendable` ist und Tests ihn vergleichen können.
public struct Anfrage: Sendable, Equatable, CustomStringConvertible {
    public var url: URL
    public var kopf: [String: String]

    public init(url: URL, kopf: [String: String] = [:]) {
        self.url = url
        self.kopf = kopf
    }

    /// Ohne Abfrageteil und Kopfzeilen: dort stehen bei Alpaca und Marketaux die Schlüssel.
    public var description: String { "Anfrage(\(url.host ?? "")\(url.path))" }
}

/// Antwort mit Status, Kopfzeilen (Namen klein geschrieben) und Inhalt.
public struct Antwort: Sendable, Equatable {
    public var status: Int
    public var kopf: [String: String]
    public var daten: Data

    public init(status: Int, kopf: [String: String] = [:], daten: Data = Data()) {
        self.status = status
        self.kopf = Dictionary(kopf.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.daten = daten
    }
}

/// Lädt eine Adresse. Tests setzen aufgezeichnete Antworten ein.
public protocol Laden: Sendable {
    func lade(_ anfrage: Anfrage) async throws -> Antwort
}

public enum LadeFehler: Error, Sendable, Equatable {
    case keineHTTPAntwort
}

/// Laden über `URLSession`. Die App braucht in der Sandbox ausgehende Verbindungen
/// (com.apple.security.network.client).
public struct URLSessionLaden: Laden {
    public init() {}

    public func lade(_ anfrage: Anfrage) async throws -> Antwort {
        var request = URLRequest(url: anfrage.url)
        request.timeoutInterval = 20
        for (name, wert) in anfrage.kopf { request.setValue(wert, forHTTPHeaderField: name) }
        return try await withCheckedThrowingContinuation { fortsetzung in
            URLSession.shared.dataTask(with: request) { daten, antwort, fehler in
                if let fehler { fortsetzung.resume(throwing: fehler); return }
                guard let http = antwort as? HTTPURLResponse else {
                    fortsetzung.resume(throwing: LadeFehler.keineHTTPAntwort); return
                }
                var kopf: [String: String] = [:]
                for (name, wert) in http.allHeaderFields {
                    if let name = name as? String, let wert = wert as? String { kopf[name] = wert }
                }
                fortsetzung.resume(returning: Antwort(status: http.statusCode, kopf: kopf, daten: daten ?? Data()))
            }.resume()
        }
    }
}

/// Liefert einen Schlüssel aus dem Schlüsselbund der App; `nil`, wenn keiner eingetragen ist.
public typealias Schluesselquelle<T: Sendable> = @Sendable () async throws -> T?

public struct Abrufergebnis: Sendable, Equatable {
    /// Ohne Doppelte, neueste zuerst.
    public var meldungen: [Meldung]
    /// Fehler je Quelle, als Text für die App. Andere Quellen laufen weiter.
    public var fehler: [String: String]
    /// Freie Marketaux-Abrufe für heute.
    public var marketauxRest: Int
}

/// Holt Nachrichten aus allen Quellen und merkt sich den Stand je Quelle.
/// Regeln: je Quelle höchstens alle `mindestabstand` Sekunden (Standard 15 Minuten; finanznachrichten.de
/// aktualisiert alle 10 Minuten, R6); RSS mit `If-None-Match`/`If-Modified-Since`, bei 304 bleibt der alte Stand;
/// Marketaux nur, solange das Tagesbudget reicht; Alpaca nur mit Schlüssel. Fällt eine Quelle aus, bleibt
/// ihr letzter Stand und der Fehler steht im Ergebnis.
public actor Nachrichtenabruf {
    private let laden: any Laden
    private let feeds: [Feed]
    private let alpacaSchluessel: Schluesselquelle<AlpacaNewsSchluessel>?
    private let marketauxToken: Schluesselquelle<String>?
    private let mindestabstand: TimeInterval
    public private(set) var budget: Abrufbudget

    private struct Stand {
        var meldungen: [Meldung] = []
        var abgerufen: Date?
        var etag: String?
        var geaendert: String?
    }

    private var staende: [String: Stand] = [:]

    static let kennung = "TradingBuddy/1 (privat; RSS-Leser)"

    public init(laden: any Laden = URLSessionLaden(),
                feeds: [Feed] = Feedliste.standard,
                alpacaSchluessel: Schluesselquelle<AlpacaNewsSchluessel>? = nil,
                marketauxToken: Schluesselquelle<String>? = nil,
                mindestabstand: TimeInterval = 15 * 60,
                budget: Abrufbudget) {
        self.laden = laden
        self.feeds = feeds
        self.alpacaSchluessel = alpacaSchluessel
        self.marketauxToken = marketauxToken
        self.mindestabstand = mindestabstand
        self.budget = budget
    }

    public func aktualisiere(begriffe: [Merkbegriff], jetzt: Date) async -> Abrufergebnis {
        var fehler: [String: String] = [:]

        for feed in feeds {
            let schluessel = "rss:" + feed.adresse.absoluteString
            guard faellig(schluessel, jetzt: jetzt) else { continue }
            do { try await holeFeed(feed, schluessel: schluessel, jetzt: jetzt) } catch {
                fehler["\(feed.quelle) \(feed.titel)"] = beschreibung(error)
            }
        }

        let symbole = begriffe.filter { $0.art == .symbol }.map(\.text)
        if let alpacaSchluessel, faellig("alpaca", jetzt: jetzt) {
            do {
                if let schluessel = try await alpacaSchluessel() {
                    let seit = jetzt.addingTimeInterval(-3 * 24 * 3600)
                    let antwort = try await laden.lade(
                        AlpacaNews.anfrage(symbole: symbole, seit: seit, schluessel: schluessel))
                    try pruefe(antwort, anbieter: "Alpaca")
                    staende["alpaca", default: Stand()].meldungen = try AlpacaNews.lies(antwort.daten, jetzt: jetzt).meldungen
                    staende["alpaca", default: Stand()].abgerufen = jetzt
                }
            } catch {
                fehler["Alpaca"] = beschreibung(error)
            }
        }

        if let marketauxToken {
            do {
                if let token = try await marketauxToken() {
                    for begriff in begriffe {
                        let schluessel = "marketaux:\(begriff.art.rawValue):\(begriff.text)"
                        guard faellig(schluessel, jetzt: jetzt) else { continue }
                        let seit = jetzt.addingTimeInterval(-7 * 24 * 3600)
                        guard let anfrage = Marketaux.anfrage(fuer: begriff, token: token, seit: seit) else { continue }
                        guard budget.buche(jetzt: jetzt) else {
                            fehler["Marketaux"] = "Tagesgrenze von \(budget.grenzeJeTag) Abrufen erreicht"
                            break
                        }
                        let antwort = try await laden.lade(anfrage)
                        // Marketaux schickt Fehler als JSON, auch bei Status 4xx; erst lesen, dann Status prüfen.
                        let meldungen: [Meldung]
                        do {
                            meldungen = try Marketaux.lies(antwort.daten, jetzt: jetzt)
                        } catch let fehler as Marketaux.Fehler {
                            throw fehler
                        } catch {
                            try pruefe(antwort, anbieter: "Marketaux")
                            throw error
                        }
                        try pruefe(antwort, anbieter: "Marketaux")
                        staende[schluessel, default: Stand()].meldungen = meldungen
                        staende[schluessel, default: Stand()].abgerufen = jetzt
                    }
                }
            } catch {
                fehler["Marketaux"] = beschreibung(error)
            }
        }

        let alle = staende.values.flatMap(\.meldungen)
        return Abrufergebnis(meldungen: Doppelte.entferne(alle), fehler: fehler,
                             marketauxRest: budget.rest(jetzt: jetzt))
    }

    private func faellig(_ schluessel: String, jetzt: Date) -> Bool {
        guard let zuletzt = staende[schluessel]?.abgerufen else { return true }
        return jetzt.timeIntervalSince(zuletzt) >= mindestabstand
    }

    private func holeFeed(_ feed: Feed, schluessel: String, jetzt: Date) async throws {
        var anfrage = Anfrage(url: feed.adresse, kopf: ["User-Agent": Self.kennung])
        if let etag = staende[schluessel]?.etag { anfrage.kopf["If-None-Match"] = etag }
        if let geaendert = staende[schluessel]?.geaendert { anfrage.kopf["If-Modified-Since"] = geaendert }
        let antwort = try await laden.lade(anfrage)
        var stand = staende[schluessel] ?? Stand()
        stand.abgerufen = jetzt
        if antwort.status == 304 {
            staende[schluessel] = stand
            return
        }
        // Auch bei einem Fehler zählt der Versuch, damit ein ausgefallener Feed nicht jede Minute neu geladen wird.
        staende[schluessel] = stand
        try pruefe(antwort, anbieter: feed.quelle)
        stand.meldungen = RSSLeser.lies(antwort.daten, quelle: feed.quelle, jetzt: jetzt)
        stand.etag = antwort.kopf["etag"]
        stand.geaendert = antwort.kopf["last-modified"]
        staende[schluessel] = stand
    }

    private func pruefe(_ antwort: Antwort, anbieter: String) throws {
        guard (200..<300).contains(antwort.status) else {
            throw HTTPFehler(anbieter: anbieter, status: antwort.status)
        }
    }

    /// Nur eigene Fehlertexte wörtlich; bei Netzfehlern die allgemeine Beschreibung, weil deren Text die
    /// Adresse enthalten kann und bei Marketaux steht dort der Schlüssel.
    private func beschreibung(_ fehler: Error) -> String {
        switch fehler {
        case let f as HTTPFehler: return f.description
        case let f as Marketaux.Fehler: return f.description
        case is DecodingError: return "Antwort nicht lesbar"
        default: return "Netzfehler: " + (fehler as NSError).localizedDescription
        }
    }
}

public struct HTTPFehler: Error, Sendable, Equatable, CustomStringConvertible {
    public var anbieter: String
    public var status: Int
    public var description: String {
        switch status {
        case 401, 403: return "\(anbieter): Zugang abgelehnt (\(status)), Schlüssel prüfen"
        case 429: return "\(anbieter): zu viele Abrufe (429)"
        default: return "\(anbieter): Antwort \(status)"
        }
    }
}
