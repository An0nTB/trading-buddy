#if os(macOS)
import Foundation
import Observation

/// Update-Hinweis für Beta-Tester (Doc 51, Update-Weg 03.10.2026): Henry fragt höchstens einmal am Tag bei der
/// GitHub-API nach der neuesten veröffentlichten Version und meldet eine neuere einmal je Version. Henry lädt und
/// installiert nichts selbst (kein Sparkle, das bräuchte Signatur und eigenen Schlüssel). Hinaus geht nur die
/// Anfrage selbst, ohne Daten aus dem Journal. Entwürfe und Vorabversionen liefert die API hier nicht aus.
enum Aktualisierung {
    /// Schalter „Nach Updates suchen“ (Einstellungen › Allgemein), Standard an.
    static let schalterSchluessel = "aktualisierung.pruefen"
    static let letztePruefungSchluessel = "aktualisierung.letztePruefung"
    /// Version, zu der der Hinweis schon kam; dieselbe Version meldet Henry nicht noch einmal.
    static let gemeldetSchluessel = "aktualisierung.gemeldet"

    /// Neueste Version ohne Entwürfe und Vorabversionen (GitHub REST, „Get the latest release“, 2026);
    /// ohne Anmeldung für öffentliche Repos, 60 Anfragen je Stunde und Adresse.
    static let adresse = URL(string: "https://api.github.com/repos/An0nTB/trading-buddy/releases/latest")!
    /// Seite mit allen Versionen, falls die Antwort keinen eigenen Link trägt.
    static let seite = URL(string: "https://github.com/An0nTB/trading-buddy/releases")!
    static let abstand: TimeInterval = 24 * 60 * 60

    struct Veroeffentlichung: Decodable, Equatable, Sendable {
        var tag: String
        var seite: URL

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case seite = "html_url"
        }

        /// Versionsnummer ohne führendes „v“, wie sie der Hinweis zeigt.
        var version: String { tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag }
    }

    /// „v0.9.1“ oder „0.9.1“ → [0, 9, 1]; `nil`, wenn ein Teil keine Zahl ist (etwa „0.9.1-beta“).
    static func versionsteile(_ text: String) -> [Int]? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        let teile = rest.split(separator: ".", omittingEmptySubsequences: false)
        let zahlen = teile.compactMap { Int($0) }.filter { $0 >= 0 }
        guard !teile.isEmpty, zahlen.count == teile.count else { return nil }
        return zahlen
    }

    /// Ob `kandidat` neuer ist als `aktuell`; fehlende Stellen zählen als 0 („1.0“ = „1.0.0“).
    /// Unlesbare Nummern gelten nie als neuer, damit ein seltsamer Tag keinen Hinweis auslöst.
    static func istNeuer(_ kandidat: String, als aktuell: String) -> Bool {
        guard let neu = versionsteile(kandidat), let alt = versionsteile(aktuell) else { return false }
        for i in 0..<max(neu.count, alt.count) {
            let a = i < neu.count ? neu[i] : 0
            let b = i < alt.count ? alt[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Fällig, wenn noch nie geprüft oder die letzte Prüfung einen Tag zurückliegt. Liegt sie in der Zukunft
    /// (Uhr verstellt), gilt sie als fällig, damit die Prüfung nicht für immer ausbleibt.
    static func faellig(letzte: Date?, jetzt: Date) -> Bool {
        guard let letzte else { return true }
        let vergangen = jetzt.timeIntervalSince(letzte)
        return vergangen >= abstand || vergangen < 0
    }

    static func lies(_ daten: Data) throws -> Veroeffentlichung {
        try JSONDecoder().decode(Veroeffentlichung.self, from: daten)
    }

    /// Fragt GitHub; `nil`, solange es keine veröffentlichte Version gibt (404).
    static func hole(session: URLSession = .shared) async throws -> Veroeffentlichung? {
        var anfrage = URLRequest(url: adresse, timeoutInterval: 15)
        anfrage.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        anfrage.setValue("Henry", forHTTPHeaderField: "User-Agent")
        let (daten, antwort) = try await session.data(for: anfrage)
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try lies(daten)
    }

    /// Version dieser App aus dem Bundle.
    static var eigeneVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

/// Zustand der Prüfung für Hinweis und Einstellungen. Einstellungen und Abruf kommen von außen, damit Tests
/// weder `UserDefaults.standard` noch das Netz anfassen.
@Observable @MainActor
final class Aktualisierungsdienst {
    static let geteilt = Aktualisierungsdienst()

    typealias Abruf = @Sendable () async throws -> Aktualisierung.Veroeffentlichung?

    /// Neuere Version, zu der der Hinweis noch aussteht; `gemeldet()` räumt ihn ab.
    private(set) var hinweis: Aktualisierung.Veroeffentlichung?
    /// Neueste bekannte Version aus der letzten Antwort.
    private(set) var neueste: Aktualisierung.Veroeffentlichung?
    private(set) var letztePruefung: Date?
    private(set) var fehler: String?
    private(set) var laeuft = false

    private let einstellungen: UserDefaults
    private let abruf: Abruf
    private let eigeneVersion: String

    init(einstellungen: UserDefaults = .standard, eigeneVersion: String = Aktualisierung.eigeneVersion,
         abruf: @escaping Abruf = { try await Aktualisierung.hole() }) {
        self.einstellungen = einstellungen
        self.eigeneVersion = eigeneVersion
        self.abruf = abruf
        letztePruefung = einstellungen.object(forKey: Aktualisierung.letztePruefungSchluessel) as? Date
    }

    var eingeschaltet: Bool {
        einstellungen.object(forKey: Aktualisierung.schalterSchluessel) as? Bool ?? true
    }

    /// Ob `neueste` neuer ist als diese App.
    var gibtNeuere: Bool {
        neueste.map { Aktualisierung.istNeuer($0.version, als: eigeneVersion) } ?? false
    }

    /// Beim Start: nur wenn eingeschaltet und fällig. `erzwungen` (Knopf „Jetzt prüfen“) übergeht beides
    /// und zeigt das Ergebnis in den Einstellungen statt als Hinweis.
    func pruefe(erzwungen: Bool = false, jetzt: Date = Date()) async {
        guard !laeuft else { return }
        if !erzwungen {
            guard eingeschaltet, Aktualisierung.faellig(letzte: letztePruefung, jetzt: jetzt) else { return }
        }
        laeuft = true
        defer { laeuft = false }
        do {
            neueste = try await abruf()
            fehler = nil
        } catch {
            fehler = error.localizedDescription
            return
        }
        letztePruefung = jetzt
        einstellungen.set(jetzt, forKey: Aktualisierung.letztePruefungSchluessel)
        guard !erzwungen, let neu = neueste, gibtNeuere,
              einstellungen.string(forKey: Aktualisierung.gemeldetSchluessel) != neu.tag else { return }
        hinweis = neu
    }

    /// Der Hinweis wurde gezeigt; dieselbe Version meldet Henry nicht noch einmal.
    func gemeldet() {
        if let hinweis { einstellungen.set(hinweis.tag, forKey: Aktualisierung.gemeldetSchluessel) }
        hinweis = nil
    }
}
#endif
