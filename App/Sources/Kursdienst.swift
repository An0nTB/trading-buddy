import Foundation
import Observation
import TradingQuotes

/// Kurse offener Trades (P10, Stand-Doc 20): hält die Zuordnungen des Nutzers, startet den Kursbeobachter für
/// die offenen Symbole und sammelt den letzten Stand je Symbol. Netz nur, wenn der Nutzer Kurse eingeschaltet hat;
/// Zuordnungen und Schalter liegen in den Einstellungen der App, der Alpaca-Schlüssel im Schlüsselbund.
@Observable @MainActor
final class Kursdienst {
    static let schluesselAktiv = "kurseAktiv"
    static let schluesselZuordnungen = "kurszuordnungen"

    /// Eigene Zuordnungen des Nutzers; sie überstimmen die Vorschläge des Pakets.
    private(set) var eigene: [Kurszuordnung]
    private(set) var stand = Kursstand()
    /// Symbole in Journal-Schreibweise, die gerade beobachtet werden.
    private(set) var symbole: [String] = []
    private(set) var aktiv: Bool
    private var aufgabe: Task<Void, Never>?
    private let speicher: UserDefaults
    /// Alle Quellen, die die App kennt; verbunden wird nur, was eine Zuordnung braucht.
    let quellen: [any Kursquelle] = [Kursquellen.kraken(), Kursquellen.coinbase(), Kursquellen.binance(),
                                     Kursquellen.alpaca(schluessel: Schluesselbund())]
    /// Tageskerzen für die Analyse in Frag Henry (Paket A1, Doc 38), je Journal-Symbol; nur beschreibend.
    private(set) var verlaeufe = Verlaufsstand.leer
    private var verlaufLaeuft = false
    private let verlaufsspeicher = Verlaufsspeicher(datei: Verlaufsspeicher.standardDatei())
    /// Krypto über Kraken ohne Schlüssel, US-Aktien über Alpaca mit dem Schlüssel der Echtzeitkurse.
    let verlaufsquellen: [any Verlaufsquelle] = [Kursverlaeufe.kraken(),
                                                 Kursverlaeufe.alpaca(schluessel: Schluesselbund())]

    init(speicher: UserDefaults = .standard) {
        self.speicher = speicher
        aktiv = speicher.bool(forKey: Self.schluesselAktiv)
        if let daten = speicher.data(forKey: Self.schluesselZuordnungen),
           let gespeichert = try? JSONDecoder().decode([Kurszuordnung].self, from: daten) {
            eigene = gespeichert
        } else {
            eigene = []
        }
    }

    /// Anzeigename einer Quelle, sonst ihre Kennung.
    func quellenname(_ id: String) -> String {
        quellen.first { $0.id == id }?.name ?? id
    }

    /// Zuordnung für ein Symbol: die eigene, sonst der Vorschlag des Pakets, sonst der Grund dagegen.
    func zuordnung(fuer symbol: String) -> Zuordnungswahl {
        if let eigen = eigene.first(where: { $0.journalSymbol == symbol }) { return .eigene(eigen) }
        switch Kurszuordner.vorschlag(fuer: symbol) {
        case .zuordnung(let z): return .vorschlag(z)
        case .ohneQuelle(let grund): return .ohneQuelle(grund)
        }
    }

    func setzeAktiv(_ neu: Bool) {
        guard neu != aktiv else { return }
        aktiv = neu
        speicher.set(neu, forKey: Self.schluesselAktiv)
        neustart()
    }

    func setzeZuordnung(_ zuordnung: Kurszuordnung) {
        eigene.removeAll { $0.journalSymbol == zuordnung.journalSymbol }
        eigene.append(zuordnung)
        speichere()
        neustart()
    }

    func entferneZuordnung(symbol: String) {
        eigene.removeAll { $0.journalSymbol == symbol }
        speichere()
        neustart()
    }

    /// Beobachtet diese Symbole; startet nur neu, wenn sich die Liste ändert.
    func beobachte(_ neu: [String]) {
        let sortiert = Array(Set(neu)).sorted()
        guard sortiert != symbole else { return }
        symbole = sortiert
        neustart()
    }

    /// Startet den Beobachter neu, auch nach dem Schlüsselwechsel in den Einstellungen.
    func neustart() {
        aufgabe?.cancel()
        aufgabe = nil
        stand = Kursstand()
        guard aktiv, !symbole.isEmpty else { return }
        var zuordnungen: [Kurszuordnung] = []
        for symbol in symbole {
            switch zuordnung(fuer: symbol) {
            case .eigene(let z), .vorschlag(let z): zuordnungen.append(z)
            case .ohneQuelle: break
            }
        }
        guard !zuordnungen.isEmpty else { return }
        let strom = Kursbeobachter(quellen: quellen).beobachte(zuordnungen)
        aufgabe = Task { [weak self] in
            for await ereignis in strom {
                guard let self, !Task.isCancelled else { return }
                self.stand.uebernimm(ereignis)
            }
        }
    }

    /// Lädt Tageskerzen der letzten 12 Monate für diese Journal-Symbole (eigene Trades und Merkliste), höchstens
    /// einmal in 20 Stunden; sonst gilt der Zwischenspeicher. Netz nur bei eingeschalteten Kursen, wie beim Beobachter.
    func ladeVerlaeufe(fuer journalSymbole: [String], jetzt: Date = Date()) async {
        if verlaeufe.geladen == nil, let gespeichert = verlaufsspeicher.lies() { verlaeufe = gespeichert }
        guard aktiv, !verlaufLaeuft else { return }
        let zuordnungen = Array(Set(journalSymbole)).sorted().compactMap { zuordnung(fuer: $0).zuordnung }
        guard !zuordnungen.isEmpty,
              !verlaeufe.istAktuell(fuer: zuordnungen.map(\.journalSymbol), jetzt: jetzt) else { return }
        verlaufLaeuft = true
        defer { verlaufLaeuft = false }
        let neu = await Verlaufslader(quellen: verlaufsquellen).lade(zuordnungen, bisher: verlaeufe, jetzt: jetzt)
        verlaeufe = neu
        try? verlaufsspeicher.schreibe(neu)
    }

    private func speichere() {
        if let daten = try? JSONEncoder().encode(eigene) {
            speicher.set(daten, forKey: Self.schluesselZuordnungen)
        }
    }
}

/// Woher die Zuordnung eines Symbols stammt, für Kapsel und Blatt.
enum Zuordnungswahl {
    case eigene(Kurszuordnung)
    case vorschlag(Kurszuordnung)
    case ohneQuelle(String)

    var zuordnung: Kurszuordnung? {
        switch self {
        case .eigene(let z), .vorschlag(let z): z
        case .ohneQuelle: nil
        }
    }

    var grund: String? {
        if case .ohneQuelle(let grund) = self { return grund }
        return nil
    }
}
