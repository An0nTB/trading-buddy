import Foundation
import TradingCore

// Namen für den Monatsbericht. Alles sachlich (Doc 02 Zeile 43): Zahlen, Steuer und Regelverstöße
// bekommen keinen Henry-Ton (Entscheidung 49).

extension Regelverstoss.Art {
    var berichtTitel: String {
        switch self {
        case .tagesverlust: String(localized: "Höchster Tagesverlust überschritten")
        case .tradesJeTag: String(localized: "Mehr Trades am Tag als erlaubt")
        case .stoppNachVerlusten: String(localized: "Weitergehandelt nach Verlusten in Folge")
        case .risikoJeTrade: String(localized: "Risiko je Trade über der Grenze")
        case .manuell: String(localized: "Im Journal als nicht regeltreu markiert")
        }
    }
}

extension Aufteilung {
    var berichtTitel: String {
        switch self {
        case .symbol: String(localized: "Instrument")
        case .richtung: String(localized: "Richtung")
        case .wochentag: String(localized: "Wochentag")
        case .stunde: String(localized: "Stunde der Eröffnung")
        case .tradeNummerAmTag: String(localized: "Trade am Tag")
        case .nachVorherigem: String(localized: "Nach dem vorherigen Trade")
        case .haltedauer: String(localized: "Haltedauer")
        }
    }

    /// Schlüssel einer Gruppe im Klartext (Schlüsselformat siehe `Gruppe.schluessel`).
    func berichtSchluessel(_ schluessel: String) -> String {
        if schluessel == Gruppe.ohneUhrzeit { return String(localized: "ohne Uhrzeit") }
        switch self {
        case .symbol:
            return schluessel
        case .richtung:
            return schluessel == Side.buy.rawValue ? String(localized: "Long") : String(localized: "Short")
        case .wochentag:
            // ISO: 1 = Montag; `weekdaySymbols` beginnt mit Sonntag.
            guard let nummer = Int(schluessel), (1...7).contains(nummer) else { return schluessel }
            var kalender = Calendar(identifier: .gregorian)
            kalender.locale = Locale.current
            return kalender.standaloneWeekdaySymbols[nummer % 7]
        case .stunde:
            guard let stunde = Int(schluessel) else { return schluessel }
            return String(localized: "\(stunde) bis \(stunde + 1) Uhr")
        case .tradeNummerAmTag:
            return String(localized: "\(schluessel). Trade des Tages")
        case .nachVorherigem:
            switch schluessel {
            case "erster": return String(localized: "erster Trade")
            case "nachGewinn": return String(localized: "nach einem Gewinn")
            case "nachVerlust": return String(localized: "nach einem Verlust")
            case "nachBreakeven": return String(localized: "nach einem Trade ohne Ergebnis")
            default: return schluessel
            }
        case .haltedauer:
            switch Haltedauerklasse(rawValue: schluessel) {
            case .unter5Minuten: return String(localized: "unter 5 Minuten")
            case .unter1Stunde: return String(localized: "5 bis 60 Minuten")
            case .unter1Tag: return String(localized: "1 bis 24 Stunden")
            case .ueber1Tag: return String(localized: "über einen Tag")
            case nil: return schluessel
            }
        }
    }
}

extension Verlusttopf {
    /// Name im PDF; Krypto ohne Haltefrist, die rechnet die Steuer-Seite der App.
    var berichtTitel: String {
        switch self {
        case .aktien: String(localized: "Aktien")
        case .allgemein: String(localized: "Allgemein (Fonds, Anleihen, Derivate, CFDs)")
        case .krypto: String(localized: "Krypto (vor Haltefrist)")
        case .nichtZugeordnet: String(localized: "Nicht zugeordnet")
        }
    }
}

extension Reviewziel.Status {
    /// Wie auf der Seite Review-Ziele; `verfehlt` über `default` (Entscheidung 28).
    var berichtTitel: String {
        switch self {
        case .offen: String(localized: "offen")
        case .erreicht: String(localized: "erreicht")
        case .verworfen: String(localized: "verworfen")
        default: String(localized: "verfehlt")
        }
    }
}
