import Foundation
import Observation
import SwiftUI

/// Die drei Stufen des Lernpfads (Recherche R5, 12_Lernpfad.md). Reihenfolge ist die Rangfolge:
/// Fortgeschritten baut auf Grundlagen auf, Profi auf beidem.
enum Lernstufe: String, CaseIterable, Identifiable, Comparable, Codable {
    case grundlagen, fortgeschritten, profi

    var id: String { rawValue }

    var titel: LocalizedStringKey {
        switch self {
        case .grundlagen: "Grundlagen"
        case .fortgeschritten: "Fortgeschritten"
        case .profi: "Profi"
        }
    }

    /// Kürzel in den Markdown-Überschriften: `[G]`, `[F]`, `[P]`, kombiniert `[G/F]`.
    var kuerzel: String {
        switch self {
        case .grundlagen: "G"
        case .fortgeschritten: "F"
        case .profi: "P"
        }
    }

    init?(kuerzel: String) {
        guard let stufe = Lernstufe.allCases.first(where: { $0.kuerzel == kuerzel }) else { return nil }
        self = stufe
    }

    /// Woran die Stufe erreicht ist (12_Lernpfad.md, Abschnitt 1).
    var erkennbar: String {
        switch self {
        case .grundlagen: String(localized: "Jede Position lässt sich in Euro-Risiko ausdrücken, bevor sie eröffnet wird.")
        case .fortgeschritten: String(localized: "Erwartungswert in R je Setup und die drei häufigsten eigenen Fehler sind bekannt.")
        case .profi: String(localized: "Entscheidungen über Strategien folgen vorab festgelegten Kriterien und Stichproben.")
        }
    }

    private var rang: Int {
        switch self {
        case .grundlagen: 0
        case .fortgeschritten: 1
        case .profi: 2
        }
    }

    static func < (lhs: Lernstufe, rhs: Lernstufe) -> Bool { lhs.rang < rhs.rang }
}

/// Ein Kapitel des Lernbereichs: eine Markdown-Datei im Bundle (`App/Resources/Lernen`).
/// Nummern wie in der Recherche R5 (01 bis 11); 0 ist der Lernpfad als Startseite.
struct Lernkapitel: Identifiable, Hashable {
    let nummer: Int
    /// Ressourcenname ohne Endung.
    let datei: String
    let titel: String
    /// Inhaltszeile aus dem Index der Recherche.
    let kurz: String
    let stufen: [Lernstufe]

    var id: Int { nummer }

    static let lernpfad = Lernkapitel(nummer: 0, datei: "00_lernpfad", titel: "Lernpfad",
                                      kurz: "Stufen mit Erfolgskriterien, Reihenfolge, Literatur", stufen: [])

    static let alle: [Lernkapitel] = [
        Lernkapitel(nummer: 1, datei: "01_maerkte", titel: "Märkte und Instrumente",
                    kurz: "Spread, Liquidität, Anlageklassen, Eigentum oder Derivat, Börse oder außerbörslich", stufen: [.grundlagen, .fortgeschritten]),
        Lernkapitel(nummer: 2, datei: "02_hebelprodukte", titel: "Hebelprodukte und Derivate",
                    kurz: "CFDs, Knock-outs, Faktor, Optionsscheine, Futures, Optionen; Aufsichtszahlen", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 3, datei: "03_krypto", titel: "Krypto",
                    kurz: "Spot, Börsen, Verwahrung, Perpetuals mit Funding und Liquidation, MiCA", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 4, datei: "04_orderarten", titel: "Orderarten und Ausführung",
                    kurz: "Orderarten, MetaTrader-Begriffe, Slippage, was ein Stop leistet", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 5, datei: "05_handelsstile", titel: "Handelsstile",
                    kurz: "Scalping bis langfristig, Strategietypen, Studienlage, Stile kontrolliert testen", stufen: [.grundlagen, .fortgeschritten]),
        Lernkapitel(nummer: 6, datei: "06_analysemethoden", titel: "Analysemethoden",
                    kurz: "Chart, Indikatoren, Forschungsstand, Fundamentales, Makro-Termine, Stimmung", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 7, datei: "07_risiko", titel: "Risiko und Positionsgröße",
                    kurz: "Positionsgröße, Verlustserien, Drawdown-Erholung, Grenzen, Korrelation, Kelly, Monte Carlo", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 8, datei: "08_kennzahlen", titel: "Kennzahlen",
                    kurz: "Trefferquote, Erwartungswert, R-Multiple, Profitfaktor, Drawdown, MAE/MFE, Sharpe, SQN, Stichprobe", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 9, datei: "09_psychologie", titel: "Psychologie und Fehlermuster",
                    kurz: "Belegte Verzerrungen, 13 Fehlermuster mit Datensignal, Gegenmittel", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 10, datei: "10_journal", titel: "Journal und Review",
                    kurz: "Journal-Felder, Setup-Katalog, Review-Rhythmus, sieben Fragen, Experimente", stufen: Lernstufe.allCases),
        Lernkapitel(nummer: 11, datei: "11_kosten_steuern", titel: "Kosten und Steuern in Deutschland",
                    kurz: "Kostenarten, Abgeltungsteuer, Verlusttöpfe, Termingeschäfte, Krypto", stufen: [.grundlagen, .fortgeschritten]),
    ]

    static func kapitel(_ nummer: Int) -> Lernkapitel? {
        nummer == 0 ? lernpfad : alle.first { $0.nummer == nummer }
    }

    /// Markdown-Text aus dem App-Bundle; nil, wenn die Datei fehlt. Xcode legt Ressourcen flach ab,
    /// ein Unterordner `Lernen` wird zur Sicherheit auch durchsucht.
    func markdown() -> String? {
        let url = Bundle.main.url(forResource: datei, withExtension: "md")
            ?? Bundle.main.url(forResource: datei, withExtension: "md", subdirectory: "Lernen")
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Ein Baustein des Lernpfads (12_Lernpfad.md, Abschnitte 2 bis 4): Kapitel, wahlweise ab einem Abschnitt,
/// mit dem Erfolgskriterium als Selbsttest.
struct Lernbaustein: Identifiable, Hashable {
    let stufe: Lernstufe
    let kapitel: Int
    let titel: String
    let erfolgskriterium: String
    /// Nummer des ersten Abschnitts, zu dem die Seite springt; nil für das ganze Kapitel.
    var abschnitt: Int?

    var id: String { "\(stufe.rawValue).\(kapitel).\(abschnitt ?? 0)" }

    static let alle: [Lernbaustein] = [
        // Grundlagen
        Lernbaustein(stufe: .grundlagen, kapitel: 1, titel: "Markt, Spread, Long und Short",
                     erfolgskriterium: "Erklären können, warum ein Trade mit dem Spread im Minus startet."),
        Lernbaustein(stufe: .grundlagen, kapitel: 2, titel: "Hebelprodukte und ihre Kosten",
                     erfolgskriterium: "Für CFD, Turbo und Faktor-Zertifikat je eine Kostenquelle nennen."),
        Lernbaustein(stufe: .grundlagen, kapitel: 3, titel: "Krypto-Grundlagen",
                     erfolgskriterium: "Spot, Perpetual und Funding unterscheiden."),
        Lernbaustein(stufe: .grundlagen, kapitel: 4, titel: "Orderarten",
                     erfolgskriterium: "Für jede Orderart einen Fall nennen, in dem sie schlecht ausgeführt wird."),
        Lernbaustein(stufe: .grundlagen, kapitel: 7, titel: "Positionsgröße",
                     erfolgskriterium: "Größe aus Konto, Risiko-% und Stop korrekt rechnen, drei Beispiele.", abschnitt: 2),
        Lernbaustein(stufe: .grundlagen, kapitel: 8, titel: "Basiskennzahlen",
                     erfolgskriterium: "Erwartungswert und R aus eigenen Trades von Hand rechnen.", abschnitt: 2),
        // Fortgeschritten
        Lernbaustein(stufe: .fortgeschritten, kapitel: 5, titel: "Stil wählen und begrenzen",
                     erfolgskriterium: "Ein Stil, schriftliche Regeln, Kill-Kriterium mit Termin."),
        Lernbaustein(stufe: .fortgeschritten, kapitel: 6, titel: "Analyse als Werkzeug",
                     erfolgskriterium: "Drei Setups als Karten beschrieben."),
        Lernbaustein(stufe: .fortgeschritten, kapitel: 7, titel: "Grenzen und Korrelation",
                     erfolgskriterium: "Tagesverlust-Grenze festgelegt und vier Wochen eingehalten.", abschnitt: 4),
        Lernbaustein(stufe: .fortgeschritten, kapitel: 8, titel: "Kennzahlen und Stichprobe",
                     erfolgskriterium: "Für jedes Setup die Stichprobengröße kennen, bevor ein Urteil fällt.", abschnitt: 4),
        Lernbaustein(stufe: .fortgeschritten, kapitel: 9, titel: "Fehlermuster",
                     erfolgskriterium: "Die eigenen drei häufigsten Muster mit Häufigkeit und Kosten in R kennen."),
        Lernbaustein(stufe: .fortgeschritten, kapitel: 10, titel: "Journal und Review",
                     erfolgskriterium: "Zwölf Wochen ohne ausgelassenes Wochen-Review."),
        Lernbaustein(stufe: .fortgeschritten, kapitel: 11, titel: "Kosten und Steuern",
                     erfolgskriterium: "Kostenquote je Broker bekannt."),
        // Profi
        Lernbaustein(stufe: .profi, kapitel: 2, titel: "Futures und Optionen an der Börse",
                     erfolgskriterium: "Futures, Optionen und die Griechen erklären können.", abschnitt: 6),
        Lernbaustein(stufe: .profi, kapitel: 6, titel: "Backtests ohne Data Snooping",
                     erfolgskriterium: "Eine Strategie auf Daten geprüft, die beim Entwurf nicht benutzt wurden.", abschnitt: 3),
        Lernbaustein(stufe: .profi, kapitel: 7, titel: "Monte Carlo und Risikobudget",
                     erfolgskriterium: "Eigene Ergebnisse per Monte Carlo gemischt, Risikobudget je Strategie festgelegt.", abschnitt: 7),
        Lernbaustein(stufe: .profi, kapitel: 8, titel: "Risikoadjustierte Kennzahlen",
                     erfolgskriterium: "Wissen, ab welcher Datenmenge Sharpe, Sortino und SQN tragen.", abschnitt: 6),
        Lernbaustein(stufe: .profi, kapitel: 9, titel: "Hypothesen vorab festlegen",
                     erfolgskriterium: "Eine Vermutung schriftlich festgehalten, bevor die Daten geprüft wurden.", abschnitt: 4),
        Lernbaustein(stufe: .profi, kapitel: 10, titel: "Experimente mit Kill-Kriterium",
                     erfolgskriterium: "Ein Experiment mit Kill-Kriterium und Termin abgeschlossen.", abschnitt: 6),
    ]

    static func fuer(_ stufe: Lernstufe) -> [Lernbaustein] {
        alle.filter { $0.stufe == stufe }
    }

    static func fuer(kapitel: Int) -> [Lernbaustein] {
        alle.filter { $0.kapitel == kapitel }
    }
}

/// Erledigte Selbsttests, gespeichert in den Einstellungen dieses Geräts (kein Abgleich, kein Export).
@Observable @MainActor
final class Lernfortschritt {
    static let schluessel = "lernen.erledigt"

    private(set) var erledigt: Set<String>

    init() {
        erledigt = Set(UserDefaults.standard.stringArray(forKey: Lernfortschritt.schluessel) ?? [])
    }

    func istErledigt(_ baustein: Lernbaustein) -> Bool {
        erledigt.contains(baustein.id)
    }

    func setze(_ baustein: Lernbaustein, erledigt neu: Bool) {
        if neu { erledigt.insert(baustein.id) } else { erledigt.remove(baustein.id) }
        UserDefaults.standard.set(erledigt.sorted(), forKey: Lernfortschritt.schluessel)
    }

    /// Erledigte Bausteine einer Stufe, für die Zeile „1 von 7 erledigt“.
    func anzahlErledigt(_ stufe: Lernstufe) -> Int {
        Lernbaustein.fuer(stufe).filter(istErledigt).count
    }
}
