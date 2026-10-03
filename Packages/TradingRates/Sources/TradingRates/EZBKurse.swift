import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TradingCore

/// Lädt die EZB-Referenzkurse, legt sie im `Kursspeicher` ab und liefert `Referenzkurse` für
/// `Steuerorientierung.toepfe(…, kurse:)` und `KryptoHaltefrist.jahr(…, kurse:)`.
/// Ohne Netz gilt der Zwischenspeicher. Kein Schlüssel nötig.
public struct EZBKurse: Sendable {
    /// Lädt eine Adresse; Tests setzen eine aufgezeichnete Datei ein.
    public typealias Abruf = @Sendable (URL) async throws -> Data

    /// Welche EZB-Datei ein Abruf braucht.
    public enum Datei: String, Sendable, CaseIterable {
        /// Nur der letzte Arbeitstag, rund 2 KB.
        case heute = "eurofxref-daily.xml"
        /// Die letzten 90 Kalendertage.
        case neunzigTage = "eurofxref-hist-90d.xml"
        /// Alles seit 04.01.1999, mehrere MB; nur beim ersten Abruf oder nach langer Pause.
        case verlauf = "eurofxref-hist.xml"

        public var url: URL { URL(string: "https://www.ecb.europa.eu/stats/eurofxref/\(rawValue)")! }
    }

    public enum Quelle: Sendable, Equatable {
        /// Gerade von der EZB geladen.
        case netz
        /// Aus der Datei, weil kein Abruf nötig war oder der Abruf scheiterte (dann steht `fehler`).
        case zwischenspeicher
        /// Weder Netz noch Datei: alle Fremdwährungsbeträge bleiben Lücke.
        case keine
    }

    public struct Stand: Sendable, Equatable {
        /// Noch nichts geladen; für den Start der App, bevor `zwischenspeicher()` oder `laden()` fertig ist.
        public static let leer = Stand(kurse: Referenzkurse(kurse: [:]), quelle: .keine, letzterTag: nil,
                                       abgerufen: nil, fehler: nil)

        public var kurse: Referenzkurse
        public var quelle: Quelle
        /// Jüngster Tag mit Kursen, für die Anzeige „EZB-Kurse bis …“.
        public var letzterTag: Journaltag?
        public var abgerufen: Date?
        /// Fehlertext des letzten Abrufs; Kurse aus dem Zwischenspeicher gelten trotzdem.
        public var fehler: String?
    }

    /// So lange nach einem erfolgreichen Abruf fragt `laden()` nicht erneut.
    public static let ruhezeit: TimeInterval = 6 * 60 * 60
    /// Bis zu dieser Lücke reicht die 90-Tage-Datei (Puffer zu den 90 Kalendertagen der EZB).
    public static let neunzigTageReichtBis = 85
    /// So viele Kalenderjahre vor dem laufenden behält der Zwischenspeicher (rund 2 MB statt über 5 MB für 1999 bis heute).
    public static let aufbewahrenJahre = 10
    /// Kalendertage der EZB (Frankfurt); daran hängt, welcher Tag „heute“ ist.
    public static let zeitzone = TimeZone(identifier: "Europe/Berlin")!

    /// Währungen, die die EZB nicht notiert und die `Referenzkurse` gleichsetzt (USDT wie USD).
    /// Die App kennzeichnet Beträge darin als Näherung.
    public static func istNaeherung(_ waehrung: String) -> Bool {
        Referenzkurse.gleichgesetzt[waehrung.uppercased()] != nil
    }

    public let speicher: Kursspeicher
    private let abruf: Abruf
    private let jetzt: @Sendable () -> Date

    public init(speicher: Kursspeicher = Kursspeicher(datei: Kursspeicher.standardDatei()),
                abruf: @escaping Abruf = EZBKurse.urlSession,
                jetzt: @escaping @Sendable () -> Date = { Date() }) {
        self.speicher = speicher
        self.abruf = abruf
        self.jetzt = jetzt
    }

    /// Nur der Zwischenspeicher, ohne Netz; für den ersten Bildaufbau.
    public func zwischenspeicher() -> Stand {
        Self.stand(speicher.lies(), quelle: .zwischenspeicher, fehler: nil)
    }

    /// Lädt, wenn nötig, die passende EZB-Datei, ergänzt den Zwischenspeicher und liefert alle Kurse.
    public func laden() async -> Stand {
        let alt = speicher.lies()
        guard let datei = Self.welcheDatei(letzterTag: alt?.letzterTag, abgerufen: alt?.abgerufen, jetzt: jetzt()) else {
            return Self.stand(alt, quelle: .zwischenspeicher, fehler: nil)
        }
        do {
            let neu = try EZBKursdatei.lies(try await abruf(datei.url))
            var kurse = alt?.kurse ?? [:]
            kurse.merge(neu) { _, frisch in frisch }
            let abJahr = Journaltag(jetzt(), zeitzone: Self.zeitzone).jahr - Self.aufbewahrenJahre
            kurse = kurse.filter { $0.key.jahr >= abJahr }
            let inhalt = Kursspeicher.Inhalt(kurse: kurse, abgerufen: jetzt())
            do {
                try speicher.schreibe(inhalt)
            } catch {
                return Self.stand(inhalt, quelle: .netz, fehler: "Zwischenspeicher nicht geschrieben: \(error.localizedDescription)")
            }
            return Self.stand(inhalt, quelle: .netz, fehler: nil)
        } catch {
            return Self.stand(alt, quelle: .zwischenspeicher, fehler: "EZB-Kurse nicht geladen: \(error.localizedDescription)")
        }
    }

    /// Welche Datei geladen werden muss; `nil`, wenn der Zwischenspeicher aktuell ist.
    /// - Leer: ganzer Verlauf.
    /// - Abruf jünger als `ruhezeit` oder Kurs von heute vorhanden: nichts.
    /// - Dazwischen nur Wochenende: Tagesdatei. Lücke bis `neunzigTageReichtBis` Tage: 90-Tage-Datei. Sonst Verlauf.
    public static func welcheDatei(letzterTag: Journaltag?, abgerufen: Date?, jetzt: Date) -> Datei? {
        guard let letzterTag else { return .verlauf }
        if let abgerufen, jetzt.timeIntervalSince(abgerufen) < ruhezeit, abgerufen <= jetzt { return nil }
        let heute = Journaltag(jetzt, zeitzone: zeitzone)
        if letzterTag >= heute { return nil }
        let utc = TimeZone(secondsFromGMT: 0)!
        var k = Calendar(identifier: .gregorian)
        k.timeZone = utc
        let von = letzterTag.beginn(in: utc), bis = heute.beginn(in: utc)
        let luecke = k.dateComponents([.day], from: von, to: bis).day ?? .max
        if luecke > neunzigTageReichtBis { return .verlauf }
        // Fehlende Tage zwischen letztem Kurs und heute (beide ausgenommen): nur Samstag und Sonntag?
        let nurWochenende = (1..<max(1, luecke)).allSatisfy { versatz in
            let wochentag = k.component(.weekday, from: k.date(byAdding: .day, value: versatz, to: von)!)
            return wochentag == 1 || wochentag == 7 // Sonntag, Samstag
        }
        return nurWochenende ? .heute : .neunzigTage
    }

    static func stand(_ inhalt: Kursspeicher.Inhalt?, quelle: Quelle, fehler: String?) -> Stand {
        guard let inhalt, !inhalt.kurse.isEmpty else {
            return Stand(kurse: Referenzkurse(kurse: [:]), quelle: .keine, letzterTag: nil, abgerufen: nil, fehler: fehler)
        }
        return Stand(kurse: Referenzkurse(kurse: inhalt.kurse), quelle: quelle, letzterTag: inhalt.letzterTag,
                     abgerufen: inhalt.abgerufen, fehler: fehler)
    }

    public enum AbrufFehler: LocalizedError, Sendable, Equatable {
        case keineHTTPAntwort
        case status(Int)

        public var errorDescription: String? {
            switch self {
            case .keineHTTPAntwort: "Keine Antwort vom EZB-Server."
            case .status(let code): "Der EZB-Server antwortet mit Status \(code)."
            }
        }
    }

    /// Abruf über `URLSession`. Die App braucht in der Sandbox ausgehende Verbindungen
    /// (com.apple.security.network.client, auf macOS vorhanden).
    public static let urlSession: Abruf = { url in
        var anfrage = URLRequest(url: url)
        anfrage.timeoutInterval = 30
        return try await withCheckedThrowingContinuation { fortsetzung in
            URLSession.shared.dataTask(with: anfrage) { daten, antwort, fehler in
                if let fehler { fortsetzung.resume(throwing: fehler); return }
                guard let http = antwort as? HTTPURLResponse else {
                    fortsetzung.resume(throwing: AbrufFehler.keineHTTPAntwort); return
                }
                guard (200..<300).contains(http.statusCode) else {
                    fortsetzung.resume(throwing: AbrufFehler.status(http.statusCode)); return
                }
                fortsetzung.resume(returning: daten ?? Data())
            }.resume()
        }
    }
}
