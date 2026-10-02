import Charts
import SwiftUI
import TradingCore

/// Merkmale der Aufschlüsselung auf der Kennzahlen-Seite (Doc 10, Reihe 4): die Kern-Aufteilungen plus „Setup“
/// aus dem Journal, das der Rechenkern nicht kennt.
enum Aufschluesselungswahl: String, CaseIterable, Identifiable {
    case instrument, richtung, setup, wochentag, stunde, haltedauer

    var id: String { rawValue }

    var titel: LocalizedStringKey {
        switch self {
        case .instrument: "Instrument"
        case .richtung: "Richtung"
        case .setup: "Setup"
        case .wochentag: "Wochentag"
        case .stunde: "Stunde"
        case .haltedauer: "Haltedauer"
        }
    }

    var aufteilung: Aufteilung? {
        switch self {
        case .instrument: .symbol
        case .richtung: .richtung
        case .wochentag: .wochentag
        case .stunde: .stunde
        case .haltedauer: .haltedauer
        case .setup: nil
        }
    }
}

/// Lesbare Namen für die Schlüssel der Gruppen aus `Kennzahlen.aufschluesseln` und für Setups.
enum Gruppenname {
    static let ohneSetup = "ohneSetup"

    static func text(_ schluessel: String, _ wahl: Aufschluesselungswahl) -> String {
        if schluessel == Gruppe.ohneUhrzeit { return String(localized: "ohne Uhrzeit") }
        switch wahl {
        case .instrument: return schluessel
        case .richtung: return Side(rawValue: schluessel).map(Format.richtung) ?? schluessel
        case .setup: return schluessel == ohneSetup ? String(localized: "ohne Setup") : schluessel
        case .wochentag: return wochentag(schluessel)
        case .stunde: return Int(schluessel).map { String(localized: "\(String(format: "%02d", $0)) Uhr") } ?? schluessel
        case .haltedauer: return haltedauer(schluessel)
        }
    }

    static func wochentag(_ schluessel: String) -> String {
        switch schluessel {
        case "1": String(localized: "Montag")
        case "2": String(localized: "Dienstag")
        case "3": String(localized: "Mittwoch")
        case "4": String(localized: "Donnerstag")
        case "5": String(localized: "Freitag")
        case "6": String(localized: "Samstag")
        case "7": String(localized: "Sonntag")
        default: schluessel
        }
    }

    static func haltedauer(_ schluessel: String) -> String {
        switch Haltedauerklasse(rawValue: schluessel) {
        case .unter5Minuten?: String(localized: "unter 5 Minuten")
        case .unter1Stunde?: String(localized: "unter 1 Stunde")
        case .unter1Tag?: String(localized: "unter 1 Tag")
        case .ueber1Tag?: String(localized: "über 1 Tag")
        case nil: schluessel
        }
    }

    static func reihenfolge(_ schluessel: String) -> String {
        switch schluessel {
        case "erster": String(localized: "Erster Trade")
        case "nachGewinn": String(localized: "Nach Gewinn")
        case "nachVerlust": String(localized: "Nach Verlust")
        case "nachBreakeven": String(localized: "Nach Null")
        case Gruppe.ohneUhrzeit: String(localized: "ohne Uhrzeit")
        default: String(localized: "\(schluessel). Trade des Tages")
        }
    }
}

/// Eine Zeile der Aufschlüsselung: Name der Gruppe und ihre Kennzahlen.
struct Gruppenzeile: Identifiable {
    let id: String
    let name: String
    let kennzahlen: Kennzahlen
}

/// Aufschlüsselung mit Umschalter (Doc 10, Reihe 4): Netto je Gruppe als Balken links und rechts der Nulllinie,
/// daneben die Tabelle mit Trades, Trefferquote, Netto, Erwartung und R. Setup kommt aus dem Journal.
struct AufschluesselungKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var wahl = Aufschluesselungswahl.instrument

    var body: some View {
        let zeilen = zeilen(wahl)
        Karte("Aufschlüsselung") {
            Picker("Merkmal", selection: $wahl) {
                ForEach(Aufschluesselungswahl.allCases) { Text($0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if zeilen.count <= 1 {
                Text("Nur eine Gruppe im gewählten Zeitraum. Ein anderes Merkmal oder ein längerer Zeitraum zeigt Unterschiede.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
                        balken(zeilen).frame(maxWidth: .infinity)
                        tabelle(zeilen).frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                        balken(zeilen)
                        tabelle(zeilen)
                    }
                }
            }
            Text("Netto nach Kosten je Gruppe im gewählten Zeitraum. Wochentag und Stunde nach der Eröffnung in deiner Zeitzone. Unter \(Kennzahlen.mindestanzahl) Trades je Gruppe beschreibt die Zahl nur.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func zeilen(_ wahl: Aufschluesselungswahl) -> [Gruppenzeile] {
        if let aufteilung = wahl.aufteilung {
            return Kennzahlen.aufschluesseln(modell.angeglicheneTrades, nach: aufteilung, zeitzone: .current)
                .map { Gruppenzeile(id: $0.schluessel, name: Gruppenname.text($0.schluessel, wahl), kennzahlen: $0.kennzahlen) }
        }
        let gruppen = Dictionary(grouping: modell.angeglicheneTrades) { modell.journaleintraege[$0.id]?.setup ?? Gruppenname.ohneSetup }
        return gruppen.keys.sorted().map { schluessel in
            Gruppenzeile(id: schluessel, name: Gruppenname.text(schluessel, wahl),
                         kennzahlen: Kennzahlen(trades: gruppen[schluessel] ?? []))
        }
    }

    private func balken(_ zeilen: [Gruppenzeile]) -> some View {
        Chart(zeilen) { zeile in
            BarMark(x: .value("Netto", Format.double(zeile.kennzahlen.netto)), y: .value("Gruppe", zeile.name))
                .foregroundStyle(zeile.kennzahlen.netto < 0 ? thema.verlust : thema.gewinn)
                .cornerRadius(Diagramm.balkenEndeRadius)
            RuleMark(x: .value("Null", 0.0))
                .foregroundStyle(thema.linie)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(thema.text)
            }
        }
        .frame(height: max(120, CGFloat(zeilen.count) * (Diagramm.balkenMax + Abstand.raster)))
    }

    private func tabelle(_ zeilen: [Gruppenzeile]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Gruppe")
                Text("Trades").gridColumnAlignment(.trailing)
                Text("Treffer").gridColumnAlignment(.trailing)
                Text("Netto").gridColumnAlignment(.trailing)
                Text("Ø R").gridColumnAlignment(.trailing)
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            ForEach(zeilen) { zeile in
                Kennzahlenzeile(name: zeile.name, kennzahlen: zeile.kennzahlen, waehrung: modell.waehrung)
            }
        }
    }
}

/// Eine Tabellenzeile mit Trades, Trefferquote, Netto und Erwartung in R.
struct Kennzahlenzeile: View {
    let name: String
    let kennzahlen: Kennzahlen
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        GridRow {
            Text(verbatim: name)
                .foregroundStyle(thema.text)
                .lineLimit(1)
            Text(verbatim: "\(kennzahlen.anzahl)")
                .font(Schrift.tabelle)
                .foregroundStyle(kennzahlen.genugDaten ? thema.text : thema.textSchwach)
            Text(verbatim: Format.prozent(kennzahlen.trefferquote))
                .font(Schrift.tabelle)
                .foregroundStyle(thema.text)
            Text(verbatim: Format.geld(kennzahlen.netto, waehrung))
                .font(Schrift.tabelle)
                .foregroundStyle(thema.vorzeichen(kennzahlen.netto))
            Text(verbatim: Format.r(kennzahlen.erwartungswertR))
                .font(Schrift.tabelle)
                .foregroundStyle(kennzahlen.erwartungswertR.map(thema.vorzeichen) ?? thema.textSchwach)
        }
    }
}

/// Reihenfolge-Effekte (Doc 10, Reihe 4; R5 Kapitel 08): Ergebnis nach dem vorherigen Trade und nach der
/// Trade-Nummer am Tag. Zeigt, ob Revanche-Trades oder späte Trades am Tag Geld kosten.
struct ReihenfolgeKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let nachVorherigem = gruppen(.nachVorherigem)
        let nummer = gruppen(.tradeNummerAmTag)
        Karte("Reihenfolge-Effekte") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
                    teil("Nach dem vorherigen Trade", nachVorherigem).frame(maxWidth: .infinity, alignment: .leading)
                    teil("Trade-Nummer am Tag", nummer).frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    teil("Nach dem vorherigen Trade", nachVorherigem)
                    teil("Trade-Nummer am Tag", nummer)
                }
            }
            Text("Vorheriger Trade nach Schlusszeit und Trade-Nummer nach Eröffnung je Tag, beides innerhalb der gefilterten Trades und in deiner Zeitzone. Ab dem achten Trade eines Tages zusammengefasst.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func gruppen(_ aufteilung: Aufteilung) -> [Gruppenzeile] {
        guard aufteilung == .nachVorherigem else { return tradeNummern() }
        let reihenfolge = ["erster", "nachGewinn", "nachVerlust", "nachBreakeven"]
        return Kennzahlen.aufschluesseln(modell.angeglicheneTrades, nach: aufteilung, zeitzone: .current)
            .sorted { (reihenfolge.firstIndex(of: $0.schluessel) ?? 9) < (reihenfolge.firstIndex(of: $1.schluessel) ?? 9) }
            .map { Gruppenzeile(id: $0.schluessel, name: Gruppenname.reihenfolge($0.schluessel), kennzahlen: $0.kennzahlen) }
    }

    /// Trade-Nummer am Tag wie im Kern (`Aufteilung.tradeNummerAmTag`: Reihenfolge nach Eröffnung, Tag in der
    /// Zeitzone des Nutzers, Trades ohne Uhrzeit getrennt), hier nachgerechnet, weil ab dem achten Trade eine
    /// Sammelgruppe entsteht und der Kern die Nummer je Trade nicht herausgibt.
    private func tradeNummern() -> [Gruppenzeile] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = .current
        var zaehler: [Date: Int] = [:]
        var jeNummer: [Int: [Trade]] = [:]
        var ohneUhrzeit: [Trade] = []
        for trade in modell.angeglicheneTrades.sorted(by: { ($0.openTime, $0.id) < ($1.openTime, $1.id) }) {
            guard !trade.nurDatum else {
                ohneUhrzeit.append(trade)
                continue
            }
            let tag = kalender.startOfDay(for: trade.openTime)
            let nummer = (zaehler[tag] ?? 0) + 1
            zaehler[tag] = nummer
            jeNummer[min(nummer, 8), default: []].append(trade)
        }
        var ergebnis = jeNummer.keys.sorted().map { nummer in
            Gruppenzeile(id: "\(nummer)",
                         name: nummer == 8 ? String(localized: "ab dem 8. Trade des Tages") : Gruppenname.reihenfolge("\(nummer)"),
                         kennzahlen: Kennzahlen(trades: jeNummer[nummer] ?? []))
        }
        if !ohneUhrzeit.isEmpty {
            ergebnis.append(Gruppenzeile(id: Gruppe.ohneUhrzeit, name: Gruppenname.reihenfolge(Gruppe.ohneUhrzeit),
                                         kennzahlen: Kennzahlen(trades: ohneUhrzeit)))
        }
        return ergebnis
    }

    private func teil(_ titel: LocalizedStringKey, _ zeilen: [Gruppenzeile]) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(titel)
                .font(.headline)
                .foregroundStyle(thema.text)
            Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
                GridRow {
                    Text("Gruppe")
                    Text("Trades").gridColumnAlignment(.trailing)
                    Text("Treffer").gridColumnAlignment(.trailing)
                    Text("Netto").gridColumnAlignment(.trailing)
                    Text("Ø R").gridColumnAlignment(.trailing)
                }
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                ForEach(zeilen) { zeile in
                    Kennzahlenzeile(name: zeile.name, kennzahlen: zeile.kennzahlen, waehrung: modell.waehrung)
                }
            }
        }
    }
}

/// Playbook-Auswertung (Doc 18 F3, Doc 23; TradingCore 0.11.0): je Setup Kennzahlen, Regeltreue (Anteil der Trades
/// mit allen Häkchen) und Netto mit gegen ohne vollständige Checkliste; je Kriterium der Effekt auf die Erwartung.
struct PlaybookAuswertungKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let auswertung = modell.playbookAuswertung
        let waehrung = modell.waehrung
        Karte("Playbook") {
            if auswertung.setups.allSatisfy({ $0.kennzahlen.anzahl == 0 }) {
                Text("Noch kein Trade im Zeitraum trägt ein Setup aus dem Playbook. Setup im Inspektor der Trade-Liste wählen, Kriterien abhaken.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                setupTabelle(auswertung, waehrung)
                kriterien(auswertung, waehrung)
            }
            if !auswertung.unbekannteSetups.isEmpty {
                Text(verbatim: String(localized: "Setups ohne Karte: ")
                     + auswertung.unbekannteSetups.keys.sorted().map { "\($0) (\(auswertung.unbekannteSetups[$0]?.anzahl ?? 0))" }.joined(separator: ", "))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Text("Regeltreue: Anteil der Trades, bei denen alle Kriterien der Karte abgehakt sind. Effekt: Erwartung je Trade mit dem Kriterium minus ohne; unter \(Kennzahlen.mindestanzahl) Trades je Seite nur beschreibend.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func setupTabelle(_ auswertung: PlaybookAuswertung, _ waehrung: String) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Setup")
                Text("Trades").gridColumnAlignment(.trailing)
                Text("Netto").gridColumnAlignment(.trailing)
                Text("Regeltreue").gridColumnAlignment(.trailing)
                Text("Ø mit allen Häkchen").gridColumnAlignment(.trailing)
                Text("Ø ohne").gridColumnAlignment(.trailing)
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            ForEach(auswertung.setups.filter { $0.kennzahlen.anzahl > 0 }, id: \.setup) { je in
                GridRow {
                    Text(verbatim: je.setup).foregroundStyle(thema.text).lineLimit(1)
                    Text(verbatim: "\(je.kennzahlen.anzahl)").font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: Format.geld(je.kennzahlen.netto, waehrung))
                        .font(Schrift.tabelle)
                        .foregroundStyle(thema.vorzeichen(je.kennzahlen.netto))
                    Text(verbatim: Format.prozent(je.regeltreue)).font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: erwartung(je.vollstaendig, waehrung)).font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: erwartung(je.unvollstaendig, waehrung)).font(Schrift.tabelle).foregroundStyle(thema.text)
                }
            }
        }
    }

    @ViewBuilder
    private func kriterien(_ auswertung: PlaybookAuswertung, _ waehrung: String) -> some View {
        let liste = auswertung.kriterien.filter { $0.erfuellt.anzahl > 0 && $0.nichtErfuellt.anzahl > 0 }.prefix(6)
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text("Kriterien mit dem größten Effekt")
                    .font(.headline)
                    .foregroundStyle(thema.text)
                ForEach(Array(liste), id: \.kriterium.id) { je in
                    HStack(alignment: .top, spacing: Abstand.raster * 2) {
                        Text(verbatim: "\(je.setup) · \(je.kriterium.text)")
                            .foregroundStyle(thema.text)
                        Spacer()
                        Text(verbatim: String(localized: "mit \(erwartung(je.erfuellt, waehrung)) (\(je.erfuellt.anzahl)) · ohne \(erwartung(je.nichtErfuellt, waehrung)) (\(je.nichtErfuellt.anzahl))"))
                            .font(Schrift.tabelle)
                            .foregroundStyle(je.genugDaten ? thema.text : thema.textSchwach)
                        Text(verbatim: je.effekt.map { Format.geld($0, waehrung) } ?? "–")
                            .font(Schrift.tabelle.weight(.semibold))
                            .foregroundStyle(je.effekt.map(thema.vorzeichen) ?? thema.textSchwach)
                    }
                    .font(Schrift.beschriftung)
                }
            }
        }
    }

    private func erwartung(_ kennzahlen: Kennzahlen, _ waehrung: String) -> String {
        kennzahlen.erwartungswert.map { Format.geld($0, waehrung) } ?? "–"
    }
}
