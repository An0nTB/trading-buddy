import Foundation
import TradingCalendar
import TradingCore

/// Wirtschaftstermine aus dem Paket TradingCalendar (Stand-Doc 25) für die App: nächste Termine, Termine in der
/// Haltezeit eines Trades (Doc 18 F9 „über Termin gehalten“) und der Währungsfilter der Kalender-Seite.
/// Lädt die Jahresdateien einmal beim Start; scheitert das, bleibt der Kalender leer und `fehler` nennt den Grund.
/// Keine Prognose- und Ist-Werte, nur Zeitpunkte (R1 Abschnitt 5).
@Observable @MainActor
final class Termindienst {
    static let schluesselFilter = "kalenderNurMeineWaehrungen"

    private(set) var kalender: Terminkalender?
    private(set) var fehler: String?
    /// Kalender-Seite: nur Termine der Währungen aus den Symbolen des Kontos (Standard) oder alle Währungen.
    var nurMeineWaehrungen: Bool {
        didSet { UserDefaults.standard.set(nurMeineWaehrungen, forKey: Termindienst.schluesselFilter) }
    }

    init() {
        nurMeineWaehrungen = UserDefaults.standard.object(forKey: Termindienst.schluesselFilter) as? Bool ?? true
        do {
            kalender = try Terminkalender.mitgeliefert()
        } catch {
            fehler = Termindienst.text(error)
        }
    }

    var termine: [Termin] { kalender?.termine ?? [] }

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

    /// Termine ab `jetzt`, laufende ganztägige eingeschlossen, aufsteigend; `waehrungen` nil heißt alle.
    func naechste(ab jetzt: Date, waehrungen: Set<String>?) -> [Termin] {
        termine.filter { termin in
            termin.ende >= jetzt && (waehrungen.map { !termin.waehrungen.isDisjoint(with: $0) } ?? true)
        }
    }

    /// Arten, die als „über Termin gehalten“ zählen. Bankfeiertage (rund 40 im Jahr) bleiben außen vor
    /// (Gesamt-Review C1, Standardwert 02.10.2026); wer sie mitzählen will, ergänzt hier `.feiertag`.
    static let ueberTerminArten: Set<Terminart> = [.zinsentscheid, .arbeitsmarkt, .inflation]

    /// Termine in der Haltezeit eines Trades, die die Währungen seines Symbols betreffen; leer ohne Währung.
    func termine(fuer trade: Trade) -> [Termin] {
        guard let kalender else { return [] }
        let waehrungen = Terminkalender.waehrungen(symbol: trade.symbol)
        guard !waehrungen.isEmpty else { return [] }
        return kalender.termine(von: trade.openTime, bis: trade.closeTime, waehrungen: waehrungen,
                                arten: Termindienst.ueberTerminArten)
    }

    /// Ist die Haltezeit für die gezählten Terminarten erfasst? Sonst sagt „kein Termin“ nichts.
    func abgedeckt(_ trade: Trade) -> Bool {
        kalender?.abgedeckt(von: trade.openTime, bis: trade.closeTime, arten: Termindienst.ueberTerminArten) ?? false
    }
}
