import Foundation
import TradingCore
import TradingStore

/// Reiter der Seite „Auswertung“ (vorher „Kennzahlen“; Tim 05.10.2026, Doc 02 Nr. 65).
enum Auswertungsreiter: String, CaseIterable, Identifiable {
    case ueberblick, zeit, setups, verhalten, risiko

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .ueberblick: String(localized: "Überblick")
        case .zeit: String(localized: "Zeit")
        case .setups: String(localized: "Setups")
        case .verhalten: String(localized: "Verhalten")
        case .risiko: String(localized: "Risiko")
        }
    }
}

/// Auswahl für den Drill-down: Klick auf Zelle, Balken oder Kuchenstück zeigt diese Trades (IDs aus dem Kern).
struct Drilldown: Identifiable, Equatable {
    let titel: String
    let tradeIDs: [String]

    var id: String { titel + "|" + tradeIDs.joined(separator: ",") }
}

/// Eine Gruppe für Balkendiagramme: Name, Netto, Anzahl, Ø R und die Trades dahinter.
struct Balkenwert: Identifiable, Equatable {
    let id: String
    let name: String
    let netto: Decimal
    let anzahl: Int
    let durchschnittR: Decimal?
    let tradeIDs: [String]

    init(id: String, name: String, trades: [Trade]) {
        let kennzahlen = Kennzahlen(trades: trades)
        self.id = id
        self.name = name
        netto = kennzahlen.netto
        anzahl = kennzahlen.anzahl
        durchschnittR = kennzahlen.erwartungswertR
        tradeIDs = trades.map(\.id)
    }

    init(id: String, name: String, netto: Decimal, anzahl: Int, durchschnittR: Decimal?, tradeIDs: [String]) {
        self.id = id
        self.name = name
        self.netto = netto
        self.anzahl = anzahl
        self.durchschnittR = durchschnittR
        self.tradeIDs = tradeIDs
    }
}

/// Kosten eines Fehlermusters in Geld und R, aus den Befunden der App (gleiche Quelle wie die Seite Fehlermuster).
/// Eigener Typ, weil `Tiefenanalyse.fehlermusterKosten` eine `Auswertung` mit Zeitspanne braucht und die
/// Fehlermuster-Seite ihre Befunde mit den gelöschten Orders des Filters prüft.
struct Musterkosten: Identifiable, Equatable {
    let muster: Fehlermuster
    let anzahl: Int
    let netto: Decimal
    let summeR: Decimal?
    let tradeIDs: [String]

    var id: String { muster.rawValue }
}

/// Frei vergebene Merkmale eines Trades für die Merkmalauswertung des Kerns.
enum Merkmalart: String, CaseIterable, Identifiable {
    case tags, zustand, marktumfeld, setup

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .tags: String(localized: "Tags")
        case .zustand: String(localized: "Zustand")
        case .marktumfeld: String(localized: "Marktumfeld")
        case .setup: String(localized: "Setup")
        }
    }
}

/// Daten der Auswertungsseite aus dem `AppModell`: Setups, Merkmale, Regeltreue, Musterkosten und Gruppen.
/// Beträge immer aus `angeglicheneTrades` (Anzeigewährung), wie Übersicht und Kennzahlen (Doc 40 W3).
@MainActor
enum Auswertungsquelle {
    /// Setup-Name je Trade-ID aus dem Journal; leere Namen fehlen.
    static func setups(_ modell: AppModell) -> [String: String] {
        var ergebnis: [String: String] = [:]
        for (ticket, eintrag) in modell.journaleintraege {
            if let setup = eintrag.setup?.trimmingCharacters(in: .whitespacesAndNewlines), !setup.isEmpty {
                ergebnis[ticket] = setup
            }
        }
        return ergebnis
    }

    /// Merkmale je Trade-ID für die gewählte Art. Tags liest der beobachtbare Modellzustand, Zustand, Marktumfeld
    /// und Setup das Journal.
    static func merkmale(_ modell: AppModell, art: Merkmalart) -> [String: [String]] {
        switch art {
        case .tags:
            return modell.tradeTags
        case .zustand:
            var ergebnis: [String: [String]] = [:]
            for (ticket, eintrag) in modell.journaleintraege {
                if let zustand = eintrag.zustand { ergebnis[ticket] = [zustandName(zustand)] }
            }
            return ergebnis
        case .marktumfeld:
            var ergebnis: [String: [String]] = [:]
            for (ticket, eintrag) in modell.journaleintraege {
                if let umfeld = eintrag.marktumfeld?.trimmingCharacters(in: .whitespacesAndNewlines), !umfeld.isEmpty {
                    ergebnis[ticket] = [umfeld]
                }
            }
            return ergebnis
        case .setup:
            return setups(modell).mapValues { [$0] }
        }
    }

    static func zustandName(_ zustand: Int) -> String {
        String(localized: "Zustand \(zustand) von 5")
    }

    /// Anteil der Trades ohne Regelverstoß (eigene und Prop-Firm-Regeln, wie Disziplin und Monatsbericht), 0 bis 1.
    /// `nil` ohne eingestellte Regeln: Dann fehlt die Regeltreue im Score und der Kern verteilt die Gewichte neu.
    static func regeltreue(_ modell: AppModell) -> Decimal? {
        guard !modell.regeln.leer else { return nil }
        let trades = modell.angeglicheneTrades
        guard !trades.isEmpty else { return nil }
        let verletzt = modell.verletzteTrades
        let treu = trades.filter { !verletzt.contains($0.id) }.count
        return Decimal(treu) / Decimal(trades.count)
    }

    /// Kosten je Fehlermuster, teuerstes zuerst; Muster ohne Trades fehlen.
    static func musterkosten(_ modell: AppModell) -> [Musterkosten] {
        let kosten = modell.befunde.filter { !$0.trades.isEmpty }.map {
            Musterkosten(muster: $0.muster, anzahl: $0.trades.count, netto: $0.netto, summeR: $0.summeR,
                         tradeIDs: $0.trades)
        }
        return kosten.sorted { $0.netto < $1.netto }
    }

    /// Gruppen je Schlüssel, nach Netto absteigend; `name` macht aus dem Schlüssel den Text.
    static func gruppen(_ trades: [Trade], schluessel: (Trade) -> String?, name: (String) -> String) -> [Balkenwert] {
        var jeSchluessel: [String: [Trade]] = [:]
        for trade in trades {
            guard let s = schluessel(trade) else { continue }
            jeSchluessel[s, default: []].append(trade)
        }
        let werte = jeSchluessel.keys.map { Balkenwert(id: $0, name: name($0), trades: jeSchluessel[$0] ?? []) }
        return werte.sorted { $0.netto != $1.netto ? $0.netto > $1.netto : $0.name < $1.name }
    }

    /// Wochentag (1 = Montag) oder Stunde der Eröffnung aus den Zellen der Heatmap, damit Balken und Heatmap
    /// dieselben Trades zählen.
    static func zusammengefasst(_ heatmap: Tiefenanalyse.Heatmap, nachWochentag: Bool) -> [Balkenwert] {
        var jeSchluessel: [Int: [Tiefenanalyse.HeatmapZelle]] = [:]
        for zelle in heatmap.zellen {
            jeSchluessel[nachWochentag ? zelle.wochentag : zelle.stunde, default: []].append(zelle)
        }
        return jeSchluessel.keys.sorted().map { schluessel in
            let zellen = jeSchluessel[schluessel] ?? []
            let netto: Decimal = zellen.map(\.netto).reduce(0, +)
            let anzahl = zellen.map(\.anzahl).reduce(0, +)
            let mitR = zellen.map(\.anzahlMitR).reduce(0, +)
            var summeR: Decimal = 0
            for zelle in zellen {
                if let r = zelle.durchschnittR { summeR += r * Decimal(zelle.anzahlMitR) }
            }
            let name = nachWochentag ? Gruppenname.wochentag("\(schluessel)") : stundeName(schluessel)
            return Balkenwert(id: "\(schluessel)", name: name, netto: netto, anzahl: anzahl,
                              durchschnittR: mitR > 0 ? summeR / Decimal(mitR) : nil,
                              tradeIDs: zellen.flatMap(\.tradeIDs))
        }
    }

    static func stundeName(_ stunde: Int) -> String {
        String(localized: "\(String(format: "%02d", stunde)) Uhr")
    }

    /// Kurzname des Wochentags für die Heatmap, 1 = Montag.
    static func wochentagKurz(_ tag: Int) -> String {
        switch tag {
        case 1: String(localized: "Mo")
        case 2: String(localized: "Di")
        case 3: String(localized: "Mi")
        case 4: String(localized: "Do")
        case 5: String(localized: "Fr")
        case 6: String(localized: "Sa")
        default: String(localized: "So")
        }
    }

    /// Name eines Anteils im Donut.
    static func anteilName(_ anteil: Tiefenanalyse.Anteil) -> String {
        switch anteil.art {
        case .rest: return String(localized: "Rest")
        case .ohne: return String(localized: "ohne Zuordnung")
        case .eintrag: break
        }
        switch anteil.schluessel {
        case "gewinner": return String(localized: "Gewinner")
        case "verlierer": return String(localized: "Verlierer")
        case "breakeven": return String(localized: "Null")
        case Side.buy.rawValue: return Format.richtung(.buy)
        case Side.sell.rawValue: return Format.richtung(.sell)
        default: return Fehlermuster(rawValue: anteil.schluessel)?.titel ?? anteil.schluessel
        }
    }

    /// Text einer Dimension bei Stärken und Schwächen.
    static func gruppenName(_ befund: Tiefenanalyse.Gruppenbefund) -> String {
        switch befund.dimension {
        case .wochentag: return Gruppenname.wochentag(befund.schluessel)
        case .stunde: return Int(befund.schluessel).map(stundeName) ?? befund.schluessel
        case .haltedauer: return Gruppenname.haltedauer(befund.schluessel)
        case .symbol: return befund.schluessel
        case .setup: return String(localized: "Setup \(befund.schluessel)")
        case .monat: return monatName(befund.schluessel)
        }
    }

    /// „JJJJ-MM“ als „Oktober 2026“.
    static func monatName(_ schluessel: String) -> String {
        let teile = schluessel.split(separator: "-")
        guard teile.count == 2, let jahr = Int(teile[0]), let monat = Int(teile[1]) else { return schluessel }
        return monatName(jahr: jahr, monat: monat)
    }

    static func monatName(jahr: Int, monat: Int) -> String {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = .current
        guard let datum = kalender.date(from: DateComponents(year: jahr, month: monat, day: 15)) else {
            return "\(monat)/\(jahr)"
        }
        return Format.monat(datum)
    }
}
