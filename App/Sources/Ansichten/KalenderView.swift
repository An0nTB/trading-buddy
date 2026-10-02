import SwiftUI
import TradingCalendar
import TradingCore

/// Seite „Kalender“ (Stand-Doc 25, Doc 18 F9): nächste Wirtschaftstermine in der Zeit des Nutzers und die Trades
/// des gewählten Zeitraums, die über einen Termin ihrer Währung gehalten wurden. Daten aus dem Paket TradingCalendar
/// (Zinsentscheide Fed, EZB, BoE, BoJ, SNB; US-Arbeitsmarkt und -Inflation), keine Prognose- oder Ist-Werte.
/// Entwurf: design/Kalender_Entwurf.png, Tims Wahl 02.10.2026 02:28 UTC: Seite, Karte in der Übersicht, Inspektor.
struct KalenderView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        @Bindable var dienst = modell.termine
        let meine = modell.meineWaehrungen
        let filter: Set<String>? = dienst.nurMeineWaehrungen && !meine.isEmpty ? meine : nil
        TimelineView(.periodic(from: .now, by: 60)) { kontext in
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    Kopfzeile("Kalender", untertitel: String(localized: "Zinsentscheide Fed, EZB, BoE, BoJ, SNB · US-Arbeitsmarkt und -Inflation · Zeiten in deiner Zeit")) {
                        Auswahlknopf("Währungen", anzeige: anzeige(dienst.nurMeineWaehrungen), auswahl: $dienst.nurMeineWaehrungen) {
                            Text("Meine Währungen").tag(true)
                            Text("Alle Währungen").tag(false)
                        }
                    }
                    if let fehler = dienst.fehler {
                        Platzhalter(titel: "Termine nicht lesbar", symbol: "calendar.badge.exclamationmark",
                                    text: "Die Termindateien des Pakets TradingCalendar ließen sich nicht lesen: \(fehler)")
                    } else {
                        WaehrungsZeile(meine: meine, gefiltert: filter != nil)
                        kacheln(jetzt: kontext.date, filter: filter)
                        NaechsteTermineListe(jetzt: kontext.date, filter: filter, meine: meine)
                        TerminTradesKarte()
                        Quellenhinweis()
                    }
                }
                .padding(Abstand.seitenrand)
            }
        }
    }

    private func anzeige(_ nurMeine: Bool) -> String {
        nurMeine ? String(localized: "Meine Währungen") : String(localized: "Alle Währungen")
    }

    @ViewBuilder private func kacheln(jetzt: Date, filter: Set<String>?) -> some View {
        let kommende = modell.termine.naechste(ab: jetzt, waehrungen: filter)
        let kalender = Calendar.current
        let inWoche = kommende.filter { $0.beginn < jetzt.addingTimeInterval(7 * 86_400) }
        let jahresende = kalender.date(from: DateComponents(year: kalender.component(.year, from: jetzt) + 1)) ?? jetzt
        let bisJahresende = kommende.filter { $0.beginn < jahresende }
        let termine = modell.termineJeTrade
        let mitTermin = modell.trades.filter { termine[$0.id] != nil }
        // Summe in der Anzeigewährung (W3, B4); die Zahl der Trades zählt auch die ohne Kurs.
        let kennzahlen = Kennzahlen(trades: modell.angeglicheneTrades.filter { termine[$0.id] != nil })
        LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Nächster Termin",
                   wert: kommende.first.map(Terminformat.institution) ?? "–",
                   zusatz: kommende.first.map { "\($0.titel.uebersetzt) · \(Terminformat.wann($0, ab: jetzt))" }
                       ?? String(localized: "keiner in den Daten"))
            Kachel(titel: "Nächste 7 Tage",
                   wert: String(inWoche.count),
                   zusatz: inWoche.isEmpty ? String(localized: "kein Termin") : Terminformat.waehrungen(inWoche))
            Kachel(titel: "Bis Jahresende",
                   wert: String(bisJahresende.count),
                   zusatz: Terminformat.vorlaeufig(bisJahresende))
            Kachel(titel: "Über Termin gehalten",
                   wert: String(localized: "\(mitTermin.count) Trades"),
                   zusatz: mitTermin.isEmpty
                       ? String(localized: "im gewählten Zeitraum keiner")
                       : String(localized: "Netto \(Format.geld(kennzahlen.netto, modell.summenwaehrung)) · Treffer \(Format.prozent(kennzahlen.trefferquote))"),
                   farbe: mitTermin.isEmpty ? nil : thema.vorzeichen(kennzahlen.netto))
        }
    }
}

/// Zeile unter der Kopfzeile: welche Währungen das Konto betrifft und welche der Filter zeigt.
private struct WaehrungsZeile: View {
    let meine: Set<String>
    let gefiltert: Bool
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(spacing: Abstand.raster * 2) {
            Text(verbatim: text)
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            ForEach(Terminkalender.gefuehrteWaehrungen.sorted(), id: \.self) { waehrung in
                Kapsel(text: waehrung, betont: meine.contains(waehrung))
            }
        }
    }

    private var text: String {
        if meine.isEmpty { return String(localized: "Keine Währung aus den Symbolen erkannt, alle Termine werden gezeigt:") }
        return gefiltert
            ? String(localized: "Meine Währungen aus den Symbolen der Trades:")
            : String(localized: "Alle Währungen, meine hervorgehoben:")
    }
}

/// Karte „Nächste Termine“ auf der Kalender-Seite: nach Tagen gruppiert, zuerst zwölf, auf Wunsch alle.
private struct NaechsteTermineListe: View {
    let jetzt: Date
    let filter: Set<String>?
    let meine: Set<String>
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var alleZeigen = false
    private let vorschau = 12

    private struct Tagesgruppe: Identifiable {
        let tag: Date
        let termine: [Termin]
        var id: Date { tag }
    }

    var body: some View {
        let kommende = modell.termine.naechste(ab: jetzt, waehrungen: filter)
        let gezeigt = alleZeigen ? kommende : Array(kommende.prefix(vorschau))
        let gruppen = Dictionary(grouping: gezeigt, by: Terminformat.tagesdatum)
            .map { Tagesgruppe(tag: $0.key, termine: $0.value) }
            .sorted { $0.tag < $1.tag }
        Karte("Nächste Termine") {
            if kommende.isEmpty {
                Text("Keine Termine ab heute in den Daten. Die Jahresdateien enden mit dem letzten gepflegten Jahr.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                ForEach(Array(gruppen.enumerated()), id: \.element.id) { eintrag in
                    if eintrag.offset > 0 { Divider() }
                    tagesblock(eintrag.element)
                }
                if kommende.count > vorschau {
                    Button {
                        alleZeigen.toggle()
                    } label: {
                        Text(verbatim: alleZeigen
                             ? String(localized: "Weniger zeigen")
                             : String(localized: "Alle \(kommende.count) Termine zeigen"))
                    }
                    .buttonStyle(.plain)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.akzent)
                }
            }
        }
    }

    private func tagesblock(_ gruppe: Tagesgruppe) -> some View {
        let heute = Calendar.current.isDateInToday(gruppe.tag)
        return VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: Terminformat.tag(gruppe.tag))
                .font(Schrift.beschriftung.weight(heute ? .semibold : .regular))
                .foregroundStyle(heute ? thema.akzent : thema.textSchwach)
            ForEach(gruppe.termine) { termin in
                TerminZeile(termin: termin, jetzt: jetzt, meine: meine)
            }
        }
    }
}

/// Ein Termin als Zeile: Uhrzeit in der Zeit des Nutzers (oder „ganztägig“), Titel, Ortszeit und Hinweis,
/// Kapseln für Quelle, Währungen (meine hervorgehoben) und „vorläufig“. Kompakt für die Übersicht.
struct TerminZeile: View {
    let termin: Termin
    let jetzt: Date
    let meine: Set<String>
    var kompakt = false
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
            Text(verbatim: kompakt ? Terminformat.kurzerTag(termin) : Terminformat.zeit(termin))
                .font(Schrift.tabelle.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(termin.ganztaegig && !kompakt ? thema.textSchwach : thema.text)
                .frame(width: kompakt ? 92 : 68, alignment: .leading)
            VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                Text(verbatim: termin.titel.uebersetzt)
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                Text(verbatim: untertitel)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Spacer(minLength: Abstand.raster)
            HStack(spacing: Abstand.raster) {
                if !kompakt {
                    Kapsel(text: Terminformat.institution(termin))
                }
                ForEach(termin.waehrungen.sorted(), id: \.self) { waehrung in
                    Kapsel(text: waehrung, betont: meine.contains(waehrung))
                }
                if termin.vorlaeufig {
                    Kapsel(text: String(localized: "vorläufig"))
                }
            }
        }
        .padding(.vertical, Abstand.raster / 2)
    }

    private var untertitel: String {
        var teile: [String] = []
        if kompakt, !termin.ganztaegig {
            teile.append(Calendar.current.isDateInToday(termin.beginn)
                         ? String(localized: "in \(Format.dauer(termin.beginn.timeIntervalSince(jetzt)))")
                         : Format.uhrzeit(termin.beginn))
        }
        teile.append(Terminformat.ort(termin))
        if let hinweis = termin.hinweis { teile.append(hinweis.uebersetzt) }
        return teile.joined(separator: " · ")
    }
}

/// Karte „Nächste Termine“ auf der Übersicht: die nächsten drei Termine der Währungen des Kontos
/// (ohne erkannte Währung alle), „Alle“ springt zur Kalender-Seite.
struct NaechsteTermineKarte: View {
    @Environment(AppModell.self) private var modell

    var body: some View {
        let meine = modell.meineWaehrungen
        TimelineView(.periodic(from: .now, by: 60)) { kontext in
            let kommende = Array(modell.termine.naechste(ab: kontext.date, waehrungen: meine.isEmpty ? nil : meine).prefix(3))
            if !kommende.isEmpty {
                Karte("Nächste Termine", aktion: { modell.bereich = .kalender }) {
                    ForEach(kommende) { termin in
                        TerminZeile(termin: termin, jetzt: kontext.date, meine: meine, kompakt: true)
                    }
                }
            }
        }
    }
}

/// Karte „Über Termin gehalten“: Trades des gewählten Zeitraums mit einem Termin ihrer Währung in der Haltezeit,
/// Kennzahlen gegen die übrigen Trades, Sprung in die Trade-Tabelle mit Filter.
private struct TerminTradesKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    private let vorschau = 8

    var body: some View {
        let termine = modell.termineJeTrade
        let mit = modell.trades.filter { termine[$0.id] != nil }.sorted { $0.closeTime > $1.closeTime }
        let ohne = modell.trades.filter { termine[$0.id] == nil }
        let sprung: (() -> Void)? = mit.isEmpty ? nil : {
            modell.nurUeberTermin = true
            modell.bereich = .trades
        }
        Karte("Über Termin gehalten", aktion: sprung) {
            if mit.isEmpty {
                Text("Im gewählten Zeitraum lief kein Trade über einen Termin seiner Währung.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                Text(verbatim: zusammenfassung(mit, ohne))
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                tabelle(Array(mit.prefix(vorschau)), termine)
                if mit.count > vorschau {
                    Text("\(mit.count - vorschau) weitere unter „Trades“ mit dem Filter „Über Termin gehalten“.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            Text("Zählt Termine zwischen Eröffnung und Schließung, die eine Währung des Symbols betreffen (EURUSD: EUR und USD, GER40: EUR). Symbole ohne Währungskürzel zählen nicht. Einschätzung, ab zehn Trades belastbarer.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func zusammenfassung(_ mit: [Trade], _ ohne: [Trade]) -> String {
        // Netto in der Anzeigewährung (W3, B4): dieselben Trades nach Umrechnung, ohne die ohne Kurs.
        let ids = Set(mit.map(\.id))
        let kennzahlen = Kennzahlen(trades: modell.angeglicheneTrades.filter { ids.contains($0.id) })
        var text = String(localized: "\(mit.count) von \(mit.count + ohne.count) Trades liefen über einen Termin ihrer Währung: Netto \(Format.geld(kennzahlen.netto, modell.summenwaehrung)), Trefferquote \(Format.prozent(kennzahlen.trefferquote))")
        if !ohne.isEmpty {
            text += String(localized: " (sonst \(Format.prozent(Kennzahlen(trades: ohne).trefferquote)))")
        }
        return text + "."
    }

    @ViewBuilder private func tabelle(_ trades: [Trade], _ termine: [String: [Termin]]) -> some View {
        #if os(macOS)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                kopf("Geschlossen")
                kopf("Symbol")
                kopf("Termin")
                kopf("Haltedauer")
                kopf("Netto", rechts: true)
            }
            Divider()
            ForEach(trades, id: \.id) { trade in
                GridRow {
                    zelle(Format.zeit(trade.closeTime), trade)
                    zelle(trade.symbol, trade)
                    zelle(Terminformat.imTrade(termine[trade.id] ?? []), trade)
                    zelle(Format.dauer(trade.holdingTime), trade)
                    zelle(Format.geld(trade.netProfit, trade.waehrung(kontowaehrung: modell.waehrung)), trade, farbe: thema.vorzeichen(trade.netProfit))
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        #else
        ForEach(trades, id: \.id) { trade in
            Button {
                zeige(trade)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                        Text(verbatim: "\(trade.symbol) · \(Format.zeit(trade.closeTime))")
                            .font(Schrift.fliesstext)
                            .foregroundStyle(thema.text)
                        Text(verbatim: "\(Terminformat.imTrade(termine[trade.id] ?? [])) · \(Format.dauer(trade.holdingTime))")
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                    Spacer()
                    Text(verbatim: Format.geld(trade.netProfit, trade.waehrung(kontowaehrung: modell.waehrung)))
                        .font(Schrift.tabelle)
                        .monospacedDigit()
                        .foregroundStyle(thema.vorzeichen(trade.netProfit))
                }
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    /// Zelle der Mac-Tabelle; Klick wählt den Trade in der Trade-Tabelle.
    private func zelle(_ text: String, _ trade: Trade, farbe: Color? = nil) -> some View {
        Text(verbatim: text)
            .font(Schrift.tabelle)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(farbe ?? thema.text)
            .contentShape(Rectangle())
            .onTapGesture { zeige(trade) }
    }

    private func zeige(_ trade: Trade) {
        modell.tradeAuswahl = trade.id
        modell.bereich = .trades
    }

    private func kopf(_ titel: LocalizedStringKey, rechts: Bool = false) -> some View {
        Text(titel)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            .gridColumnAlignment(rechts ? .trailing : .leading)
    }
}

/// Fußzeile der Kalender-Seite: Quelle, Stand und Abdeckung der Jahresdateien.
private struct Quellenhinweis: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        Text(verbatim: text(modell.termine))
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func text(_ dienst: Termindienst) -> String {
        var teile: [String] = []
        if let stand = dienst.stand {
            teile.append(String(localized: "Quelle: Paket TradingCalendar, Stand \(stand)"))
        }
        let zins = dienst.jahre(mit: .zinsentscheid)
        if let erstes = zins.first, let letztes = zins.last {
            teile.append(String(localized: "Zinsentscheide \(String(erstes)) bis \(String(letztes))"))
        }
        let inflation = dienst.jahre(mit: .inflation)
        let us = dienst.jahre(mit: .arbeitsmarkt).filter(inflation.contains)
        if let erstes = us.first, let letztes = us.last {
            teile.append(String(localized: "US-Arbeitsmarkt und -Inflation \(String(erstes)) bis \(String(letztes)), spätere Jahre veröffentlicht die BLS erst später"))
        }
        teile.append(String(localized: "Fed-Termine gelten bis zur vorigen Sitzung als vorläufig (Fed-Kalender). Keine Prognose- und Ist-Werte"))
        return teile.joined(separator: ". ") + "."
    }
}

/// Texte für Termine: Quelle, Zeiten in der Zeit des Nutzers und in der Ortszeit der Quelle, Tagesüberschriften.
enum Terminformat {
    /// Kürzel der Quelle für Kapseln: fed → Fed, bls → BLS.
    static func institution(_ termin: Termin) -> String {
        switch termin.institution {
        case "fed": "Fed"
        case "ezb": "EZB"
        case "boe": "BoE"
        case "boj": "BoJ"
        case "snb": "SNB"
        case "bls": "BLS"
        default: termin.institution.uppercased()
        }
    }

    /// Kalendertag eines Termins in der Zeit des Nutzers; ganztägige Termine zählen am Tag ihrer Zeitzone
    /// (BoJ in Tokio beginnt in Berlin schon am Vorabend).
    static func tagesdatum(_ termin: Termin) -> Date {
        guard termin.ganztaegig else { return Calendar.current.startOfDay(for: termin.beginn) }
        var quelle = Calendar(identifier: .gregorian)
        quelle.timeZone = termin.zeitzone
        let teile = quelle.dateComponents([.year, .month, .day], from: termin.beginn)
        return Calendar.current.date(from: teile) ?? termin.beginn
    }

    /// Tagesüberschrift: „Heute, Fr 02.10.“, „Morgen, Sa 03.10.“, sonst „Fr 30.10.“.
    static func tag(_ datum: Date) -> String {
        let kurz = datum.formatted(.dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits))
        let kalender = Calendar.current
        if kalender.isDateInToday(datum) { return String(localized: "Heute, \(kurz)") }
        if kalender.isDateInTomorrow(datum) { return String(localized: "Morgen, \(kurz)") }
        return kurz
    }

    /// Uhrzeit in der Zeit des Nutzers oder „ganztägig“.
    static func zeit(_ termin: Termin) -> String {
        termin.ganztaegig ? String(localized: "ganztägig") : Format.uhrzeit(termin.beginn)
    }

    /// Für die Übersicht: „heute 14:30“, „morgen 09:30“, sonst „Mi 14.10.“; ganztägig nur der Tag.
    static func kurzerTag(_ termin: Termin) -> String {
        let tag = tagesdatum(termin)
        let kalender = Calendar.current
        let kurz = tag.formatted(.dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits))
        if termin.ganztaegig { return kalender.isDateInToday(tag) ? String(localized: "heute") : kurz }
        if kalender.isDateInToday(tag) { return String(localized: "heute \(Format.uhrzeit(termin.beginn))") }
        if kalender.isDateInTomorrow(tag) { return String(localized: "morgen \(Format.uhrzeit(termin.beginn))") }
        return kurz
    }

    /// „heute um 14:30 (in 3 Std., 12 Min.)“ oder „ganztägig, Fr 30.10.“.
    static func wann(_ termin: Termin, ab jetzt: Date) -> String {
        if termin.ganztaegig {
            return String(localized: "ganztägig, \(tag(tagesdatum(termin)))")
        }
        return Boersenformat.wann(termin.beginn, ab: jetzt)
    }

    /// Ortszeit der Quelle: „08:30 New York“, bei ganztägigen „ganzer Tag in Tokyo“.
    static func ort(_ termin: Termin) -> String {
        let ort = Boersenformat.ort(termin.zeitzone)
        return termin.ganztaegig
            ? String(localized: "ganzer Tag in \(ort)")
            : "\(Boersenformat.uhrzeit(termin.beginn, in: termin.zeitzone)) \(ort)"
    }

    /// Betroffene Währungen einer Liste, sortiert: „EUR, USD“.
    static func waehrungen(_ termine: [Termin]) -> String {
        Set(termine.flatMap(\.waehrungen)).sorted().joined(separator: ", ")
    }

    /// „alle bestätigt“ oder „2 vorläufig“.
    static func vorlaeufig(_ termine: [Termin]) -> String {
        let anzahl = termine.filter(\.vorlaeufig).count
        return anzahl == 0 ? String(localized: "alle bestätigt") : String(localized: "\(anzahl) vorläufig")
    }

    /// Termine in der Haltezeit eines Trades: „Fed-Zinsentscheid 17.09., 20:00“, bei mehreren „+1“.
    static func imTrade(_ termine: [Termin]) -> String {
        guard let erster = termine.first else { return "–" }
        let zeit = erster.ganztaegig
            ? tagesdatum(erster).formatted(.dateTime.day(.twoDigits).month(.twoDigits))
            : Format.zeit(erster.beginn)
        let text = "\(erster.titel.uebersetzt) \(zeit)"
        return termine.count > 1 ? "\(text) +\(termine.count - 1)" : text
    }
}
