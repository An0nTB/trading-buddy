import Foundation
import TradingCalendar
import TradingClock
import TradingCore

/// Wirtschaftstermine aus dem Paket TradingCalendar (Stand-Doc 25) für die App: nächste Termine, Termine in der
/// Haltezeit eines Trades (Doc 18 F9 „über Termin gehalten“) und der Währungsfilter der Kalender-Seite.
/// Lädt die Jahresdateien einmal beim Start, dazu die Börsenfeiertage aus der Börsenuhr (TradingClock), damit sie nur
/// dort gepflegt werden (Stand-Doc 63); scheitert das, bleibt der Kalender leer und `fehler` nennt den Grund.
/// Keine Prognose- und Ist-Werte, nur Zeitpunkte (R1 Abschnitt 5).
@Observable @MainActor
final class Termindienst {
    static let schluesselFilter = "kalenderNurMeineWaehrungen"
    static let schluesselWichtige = "kalenderNurWichtige"
    static let schluesselRegion = "kalenderRegion"

    private(set) var kalender: Terminkalender?
    private(set) var fehler: String?
    /// Kalender-Seite: nur Termine der Währungen aus den Symbolen des Kontos (Standard) oder alle Währungen.
    var nurMeineWaehrungen: Bool {
        didSet { UserDefaults.standard.set(nurMeineWaehrungen, forKey: Termindienst.schluesselFilter) }
    }
    /// Kalender-Seite: nur Termine mit Wichtigkeit „hoch“ (Zinsentscheide, Arbeitsmarkt, Inflation, BIP, ...).
    var nurWichtige: Bool {
        didSet { UserDefaults.standard.set(nurWichtige, forKey: Termindienst.schluesselWichtige) }
    }
    /// Kalender-Seite: Kürzel einer Region aus `Terminkalender.regionen`, leer heißt alle Regionen.
    var region: String {
        didSet { UserDefaults.standard.set(region, forKey: Termindienst.schluesselRegion) }
    }

    init() {
        nurMeineWaehrungen = UserDefaults.standard.object(forKey: Termindienst.schluesselFilter) as? Bool ?? true
        nurWichtige = UserDefaults.standard.object(forKey: Termindienst.schluesselWichtige) as? Bool ?? false
        region = UserDefaults.standard.string(forKey: Termindienst.schluesselRegion) ?? ""
        do {
            kalender = try Terminkalender.mitgeliefert(zusaetzlich: Termindienst.boersenfeiertage())
        } catch {
            fehler = Termindienst.text(error)
        }
    }

    var termine: [Termin] { kalender?.termine ?? [] }

    /// Feiertage aller mitgelieferten Börsen der Börsenuhr als ganztägige Termine; Nasdaq-Tage, die die NYSE
    /// auch hat, entfallen. Ohne lesbare Börsendaten bleibt die Liste leer (die Börsenuhr meldet den Fehler selbst).
    nonisolated static func boersenfeiertage() -> [Termin] {
        let boersen = (try? Boersenuhr.mitgelieferteBoersen()) ?? []
        let nyse = Set(boersen.first { $0.id == "nyse" }?.feiertage.map(\.datum) ?? [])
        var ergebnis: [Termin] = []
        for boerse in boersen {
            for feiertag in boerse.feiertage where !(boerse.id == "nasdaq" && nyse.contains(feiertag.datum)) {
                let titel = String(localized: "\(boerse.name) geschlossen: \(feiertag.name.uebersetzt)")
                if let termin = Terminkalender.boersenfeiertag(boerse: boerse.id, titel: titel, jahr: feiertag.datum.jahr,
                                                               monat: feiertag.datum.monat, tag: feiertag.datum.tag,
                                                               zeitzone: boerse.timeZone) {
                    ergebnis.append(termin)
                }
            }
        }
        return ergebnis
    }

    /// Region der Kalender-Seite als Filter, `nil` für alle.
    var regionFilter: Set<String>? { region.isEmpty ? nil : [region] }

    /// Wichtigkeit der Kalender-Seite als Filter, `nil` für alle.
    var wichtigkeitFilter: Wichtigkeit? { nurWichtige ? .hoch : nil }

    /// Klartext zu einem Lesefehler der Jahresdateien, ohne interne Fallnamen.
    nonisolated static func text(_ fehler: Error) -> String {
        guard let fehler = fehler as? TerminkalenderFehler else { return fehler.localizedDescription }
        switch fehler {
        case .mitgelieferteDatenFehlen:
            return String(localized: "Der Ordner mit den Terminen fehlt im Paket.")
        case .unbekanntesFormat(let format):
            return String(localized: "Dateiformat \(format) kennt diese Version nicht.")
        case .ungueltigesDatum(let id, let text):
            return String(localized: "Termin „\(id)“: Datum „\(text)“ ist nicht JJJJ-MM-TT.")
        case .ungueltigeUhrzeit(let id, let text):
            return String(localized: "Termin „\(id)“: Uhrzeit „\(text)“ ist nicht HH:MM.")
        case .unbekannteZeitzone(let id, let text):
            return String(localized: "Termin „\(id)“: Zeitzone „\(text)“ ist unbekannt.")
        case .falschesJahr(let id, let jahr):
            return String(localized: "Termin „\(id)“ liegt nicht im Jahr \(jahr) seiner Datei.")
        case .doppelteID(let id):
            return String(localized: "Termin „\(id)“ steht doppelt in den Dateien.")
        }
    }

    /// Jüngster Pflegestand der Jahresdateien („2026-10-02“), `nil` ohne Daten.
    var stand: String? { kalender?.dateien.map(\.stand).max() }

    /// Jahre, in denen eine Terminart vollständig erfasst ist, aufsteigend.
    func jahre(mit art: Terminart) -> [Int] {
        (kalender?.dateien ?? []).filter { $0.vollstaendig.contains(art) }.map(\.jahr).sorted()
    }

    /// Währungen aus Symbolen (EURUSD → EUR und USD, GER40 → EUR, BTCUSDT → USD); leer, wenn kein Symbol passt.
    static func waehrungen(symbole: [String]) -> Set<String> {
        symbole.reduce(into: Set<String>()) { $0.formUnion(Terminkalender.waehrungen(symbol: $1)) }
    }

    /// Termine ab `jetzt`, laufende ganztägige eingeschlossen, aufsteigend; `nil` heißt jeweils ohne Filter.
    func naechste(ab jetzt: Date, waehrungen: Set<String>?, regionen: Set<String>? = nil,
                  mindestens: Wichtigkeit? = nil) -> [Termin] {
        termine.filter { termin in
            termin.ende >= jetzt && termin.passt(waehrungen: waehrungen, regionen: regionen, mindestens: mindestens)
        }
    }

    /// Arten, die als „über Termin gehalten“ zählen. Bankfeiertage (rund 40 im Jahr) bleiben außen vor
    /// (Gesamt-Review C1, Standardwert 02.10.2026); wer sie mitzählen will, ergänzt hier `.feiertag`.
    static let ueberTerminArten: Set<Terminart> = [.zinsentscheid, .arbeitsmarkt, .inflation]

    /// Nur Termine mit Wichtigkeit „hoch“ zählen als „über Termin gehalten“, sonst träfen wöchentliche
    /// Erstanträge jeden über Donnerstag gehaltenen USD-Trade (Stand-Doc 63, Standardwert 05.10.2026).
    static let ueberTerminMindestens: Wichtigkeit = .hoch

    /// Termine in der Haltezeit eines Trades, die die Währungen seines Symbols betreffen; leer ohne Währung.
    func termine(fuer trade: Trade) -> [Termin] {
        guard let kalender else { return [] }
        let waehrungen = Terminkalender.waehrungen(symbol: trade.symbol)
        guard !waehrungen.isEmpty else { return [] }
        return kalender.termine(von: trade.openTime, bis: trade.closeTime, waehrungen: waehrungen,
                                arten: Termindienst.ueberTerminArten, mindestens: Termindienst.ueberTerminMindestens)
    }

    /// Ist die Haltezeit für die gezählten Terminarten erfasst? Sonst sagt „kein Termin“ nichts.
    func abgedeckt(_ trade: Trade) -> Bool {
        kalender?.abgedeckt(von: trade.openTime, bis: trade.closeTime, arten: Termindienst.ueberTerminArten) ?? false
    }
}
