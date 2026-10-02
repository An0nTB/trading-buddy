import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Eine Tageskerze. Grundlage der beschreibenden Analyse in Frag Henry (Paket A1, Doc 38): nur Kursdaten,
/// keine Signale. In JSON stehen Preise als Text („58123.45“), weil Decimal als JSON-Zahl Stellen verliert.
public struct Tageskerze: Sendable, Equatable, Codable {
    /// Beginn der Kerze laut Quelle (Kraken 00:00 UTC, Alpaca Mitternacht New York).
    public var zeit: Date
    public var eroeffnung: Decimal
    public var hoch: Decimal
    public var tief: Decimal
    public var schluss: Decimal
    public var volumen: Decimal?
    /// `false` für die Kerze des laufenden Tages: Ihr Schlusskurs ist nur der letzte Stand.
    public var abgeschlossen: Bool

    public init(zeit: Date, eroeffnung: Decimal, hoch: Decimal, tief: Decimal, schluss: Decimal,
                volumen: Decimal? = nil, abgeschlossen: Bool = true) {
        self.zeit = zeit
        self.eroeffnung = eroeffnung
        self.hoch = hoch
        self.tief = tief
        self.schluss = schluss
        self.volumen = volumen
        self.abgeschlossen = abgeschlossen
    }

    /// Eine Kerze gilt als abgeschlossen, wenn seit ihrem Beginn ein voller Tag vergangen ist.
    static func istAbgeschlossen(_ zeit: Date, jetzt: Date) -> Bool {
        zeit.addingTimeInterval(86_400) <= jetzt
    }

    private enum CodingKeys: String, CodingKey {
        case zeit, eroeffnung, hoch, tief, schluss, volumen, abgeschlossen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func zahl(_ key: CodingKeys) throws -> Decimal { try c.decode(Zahl.self, forKey: key).wert }
        zeit = try c.decode(Date.self, forKey: .zeit)
        eroeffnung = try zahl(.eroeffnung)
        hoch = try zahl(.hoch)
        tief = try zahl(.tief)
        schluss = try zahl(.schluss)
        volumen = try c.decodeIfPresent(Zahl.self, forKey: .volumen)?.wert
        abgeschlossen = try c.decode(Bool.self, forKey: .abgeschlossen)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(zeit, forKey: .zeit)
        try c.encode("\(eroeffnung)", forKey: .eroeffnung)
        try c.encode("\(hoch)", forKey: .hoch)
        try c.encode("\(tief)", forKey: .tief)
        try c.encode("\(schluss)", forKey: .schluss)
        try c.encodeIfPresent(volumen.map { "\($0)" }, forKey: .volumen)
        try c.encode(abgeschlossen, forKey: .abgeschlossen)
    }
}

/// Tageskerzen eines Symbols aus einer Quelle, älteste zuerst.
public struct Kursverlauf: Sendable, Equatable, Codable {
    /// Symbol so, wie es im Journal steht.
    public var journalSymbol: String
    /// `Verlaufsquelle.id`, etwa "kraken".
    public var quelle: String
    public var quellSymbol: String
    /// Hinweis aus der Zuordnung, etwa „Kurs von Kraken als Näherung“.
    public var naeherung: String?
    public var kerzen: [Tageskerze]
    public var geladen: Date

    public init(journalSymbol: String, quelle: String, quellSymbol: String, naeherung: String? = nil,
                kerzen: [Tageskerze], geladen: Date) {
        self.journalSymbol = journalSymbol
        self.quelle = quelle
        self.quellSymbol = quellSymbol
        self.naeherung = naeherung
        self.kerzen = kerzen
        self.geladen = geladen
    }
}

/// Liefert Tageskerzen per Abruf, ohne dauerhafte Verbindung.
public protocol Verlaufsquelle: Sendable {
    /// Gleich der `Kursquelle.id` derselben Plattform, damit eine Kurszuordnung für beides gilt.
    var id: String { get }
    /// Kerzen ab `seit`, älteste zuerst.
    func tageskerzen(_ quellSymbol: String, seit: Date, jetzt: Date) async throws -> [Tageskerze]
}

public enum Verlaufsfehler: Error, Sendable, Equatable, CustomStringConvertible {
    case schluesselFehlt
    case http(Int)
    case anbieter(String)
    case format

    public var description: String {
        switch self {
        case .schluesselFehlt: "Schlüssel fehlt"
        case .http(let status): "HTTP \(status)"
        case .anbieter(let text): text
        case .format: "Antwort nicht lesbar"
        }
    }
}

/// Eine HTTP-Anfrage ohne Körper; Tests setzen aufgezeichnete Antworten ein.
public struct Abrufanfrage: Sendable, Equatable {
    public var url: URL
    public var kopf: [String: String]

    public init(url: URL, kopf: [String: String] = [:]) {
        self.url = url
        self.kopf = kopf
    }
}

public typealias Abruf = @Sendable (Abrufanfrage) async throws -> (status: Int, daten: Data)

public enum Kursverlaeufe {
    /// Abruf über `URLSession`. Die App braucht in der Sandbox ausgehende Verbindungen (network.client).
    public static let urlSession: Abruf = { anfrage in
        var request = URLRequest(url: anfrage.url)
        request.timeoutInterval = 20
        for (name, wert) in anfrage.kopf { request.setValue(wert, forHTTPHeaderField: name) }
        return try await withCheckedThrowingContinuation { fortsetzung in
            URLSession.shared.dataTask(with: request) { daten, antwort, fehler in
                if let fehler { fortsetzung.resume(throwing: fehler); return }
                let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
                fortsetzung.resume(returning: (status, daten ?? Data()))
            }.resume()
        }
    }
}
