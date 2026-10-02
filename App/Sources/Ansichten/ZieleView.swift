import Charts
import SwiftUI
import TradingCore
import TradingStore

/// Seite „Ziele“ (Tim 02.10.2026 03:20 UTC: eigene Seite in der Seitenleiste; Entwurf design/Ziele_Entwurf.png,
/// Variante A): links offene und erledigte Ziele, rechts das Formular für genau ein neues Ziel, die Bilanz der
/// letzten Monate und die Review-Schritte; am iPhone untereinander. Offene Ziele mit abgelaufener Frist setzt
/// der Speicher beim Start und beim Öffnen der Seite auf „verfehlt“ (AP9 #75); sie stehen hier oben zur
/// Beurteilung, bis ein Urteil von Hand fällt.
struct ZieleView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif
    @State private var filter: Zielfilter = .alle
    @State private var neuesZiel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Review-Ziele", untertitel: untertitel) {
                    Button("Neues Ziel", systemImage: "plus") { neuesZiel = true }
                        .disabled(modell.konto == nil)
                    Picker("Anzeigen", selection: $filter) {
                        ForEach(Zielfilter.allCases, id: \.self) { wahl in
                            Text(wahl.titel).tag(wahl)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if modell.konto == nil {
                    Platzhalter(titel: "Ziele gehören zu einem Konto", symbol: "target",
                                text: "Importiere zuerst einen Kontoauszug. Danach legst du nach jedem Review genau ein messbares Ziel für den nächsten Zeitraum an.")
                } else {
                    ZieleKacheln(ziele: modell.ziele)
                    inhalt
                }
            }
            .padding(Abstand.seitenrand)
        }
        .task { modell.schliesseAbgelaufeneZiele() }
        .sheet(isPresented: $neuesZiel) { ZielFormular() }
    }

    private var untertitel: String {
        let offen = Zielbilanz.offen(modell.ziele).count
        let zuBeurteilen = Zielbilanz.zuBeurteilen(modell.ziele).count
        let stand = zuBeurteilen > 0
            ? String(localized: "\(offen) offen, \(zuBeurteilen) zu beurteilen")
            : String(localized: "\(offen) offen")
        return stand + " · " + String(localized: "Rezept Punkt 6 und 7: ein Ziel je Review")
    }

    @ViewBuilder
    private var inhalt: some View {
        #if os(iOS)
        if breite == .compact {
            linkeSpalte
            rechteSpalte
        } else {
            zweiSpalten
        }
        #else
        zweiSpalten
        #endif
    }

    private var zweiSpalten: some View {
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            linkeSpalte
                .frame(maxWidth: .infinity, alignment: .leading)
            rechteSpalte
                .frame(width: Abstand.inspektor)
        }
    }

    private var linkeSpalte: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            if filter != .erledigt {
                OffeneZieleKarte(ziele: modell.ziele)
            }
            if filter != .offen {
                ErledigteZieleKarte(ziele: modell.ziele)
            }
        }
    }

    private var rechteSpalte: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            NeuesZielKarte()
            ZielbilanzKarte(ziele: modell.ziele)
            ReviewSchritteKarte()
        }
    }
}

/// Vier Kacheln: offene Ziele, erreicht und verfehlt im laufenden Jahr, Ziele ohne Lücke in Folge.
private struct ZieleKacheln: View {
    let ziele: [Reviewziel]
    @Environment(\.thema) private var thema

    var body: some View {
        let jahr = Calendar.current.component(.year, from: Date())
        let offen = Zielbilanz.offen(ziele)
        let zuBeurteilen = Zielbilanz.zuBeurteilen(ziele).count
        let imJahr = Zielbilanz.imJahr(ziele, jahr)
        let erreicht = imJahr.filter { $0.status == .erreicht }.count
        let verfehlt = imJahr.filter { $0.status == .verfehlt }.count
        let folge = Zielbilanz.inFolge(ziele)
        LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Offen", wert: String(offen.count),
                   zusatz: offenZusatz(offen, zuBeurteilen: zuBeurteilen),
                   farbe: zuBeurteilen > 0 ? thema.akzent : nil)
            Kachel(titel: "Erreicht \(String(jahr))",
                   wert: erreicht + verfehlt > 0 ? String(localized: "\(erreicht) von \(erreicht + verfehlt)") : "0",
                   zusatz: erreichtZusatz(erreicht: erreicht, verfehlt: verfehlt, jahr: jahr),
                   farbe: erreicht > 0 ? thema.gewinn : nil)
            Kachel(titel: "Verfehlt \(String(jahr))", wert: String(verfehlt),
                   zusatz: verfehltZusatz(verfehlt: verfehlt, automatisch: zuBeurteilen),
                   farbe: verfehlt > 0 ? thema.verlust : nil)
            Kachel(titel: "In Folge", wert: String(folge.anzahl), zusatz: folgeZusatz(folge))
        }
    }

    private func offenZusatz(_ offen: [Reviewziel], zuBeurteilen: Int) -> String {
        if zuBeurteilen > 0 {
            return String(localized: "\(zuBeurteilen) mit abgelaufener Frist, Urteil offen")
        }
        if let erstes = offen.first {
            return String(localized: "nächstes Ende \(Format.datum(Zielbilanz.letzterTag(erstes)))")
        }
        return String(localized: "nach dem Review genau eins anlegen")
    }

    private func erreichtZusatz(erreicht: Int, verfehlt: Int, jahr: Int) -> String {
        let beurteilt = erreicht + verfehlt
        guard beurteilt > 0 else { return String(localized: "noch kein Urteil in \(String(jahr))") }
        let anteil = Decimal(erreicht) / Decimal(beurteilt)
        return String(localized: "\(Format.prozent(anteil)) der beurteilten Ziele")
    }

    private func verfehltZusatz(verfehlt: Int, automatisch: Int) -> String {
        if automatisch > 0 {
            return String(localized: "\(automatisch) davon automatisch (Frist abgelaufen)")
        }
        return verfehlt > 0 ? String(localized: "alle von Hand beurteilt") : String(localized: "keins")
    }

    private func folgeZusatz(_ folge: (anzahl: Int, seit: Date?)) -> String {
        if let seit = folge.seit, folge.anzahl > 1 {
            return String(localized: "Ziele ohne Lücke · seit \(Format.datum(seit))")
        }
        return String(localized: "Ziele ohne Lücke zwischen den Zeiträumen")
    }
}

/// Karte „Offen“: zuerst die Ziele mit abgelaufener Frist samt den drei Urteilen, dann die laufenden.
private struct OffeneZieleKarte: View {
    let ziele: [Reviewziel]
    @Environment(\.thema) private var thema
    @AppStorage(Ton.schluessel) private var ton = Ton.bro

    var body: some View {
        let zuBeurteilen = Zielbilanz.zuBeurteilen(ziele)
        let offen = Zielbilanz.offen(ziele)
        Karte("Offen") {
            if !zuBeurteilen.isEmpty {
                abschnitt("Frist abgelaufen, Urteil offen")
                ForEach(zuBeurteilen, id: \.id) { ziel in
                    UrteilZeile(ziel: ziel)
                    Divider()
                }
            }
            if offen.isEmpty, zuBeurteilen.isEmpty {
                Text(verbatim: ton.text("Kein offenes Ziel. Lege nach dem Review genau ein messbares Ziel für den nächsten Zeitraum an.",
                                        bro: "Kein Ziel, kein Plan, Bro. Nach dem Review genau ein messbares Ziel für den nächsten Zeitraum anlegen."))
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else if !offen.isEmpty {
                if !zuBeurteilen.isEmpty {
                    abschnitt("Laufend")
                }
                ForEach(Array(offen.enumerated()), id: \.element.id) { eintrag in
                    ZielZeile(ziel: eintrag.element)
                    if eintrag.offset < offen.count - 1 {
                        Divider()
                    }
                }
            }
            Text("Läuft die Frist ohne Abhaken ab, setzt der Speicher das Ziel beim nächsten Start auf „Verfehlt“ (Frist abgelaufen, nicht als erreicht abgehakt). „Erreicht“ und „Verfehlt“ fragen nach dem Ergebnis in einem Satz; Wiederöffnen bleibt im Menü möglich.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func abschnitt(_ titel: LocalizedStringKey) -> some View {
        Text(titel)
            .font(Schrift.beschriftung.weight(.semibold))
            .foregroundStyle(thema.textSchwach)
            .textCase(.uppercase)
    }
}

/// Zeile für ein Ziel mit abgelaufener Frist: Text, Zeitraum, Messung und die drei Urteile als Knöpfe.
private struct UrteilZeile: View {
    let ziel: Reviewziel
    @Environment(\.thema) private var thema
    @State private var urteil: Urteilwahl?

    /// Gewählter Status für das Blatt „Ziel abhaken“ (`Reviewziel.Status` ist nicht Identifiable).
    private struct Urteilwahl: Identifiable {
        let status: Reviewziel.Status
        var id: String { status.rawValue }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Abstand.raster * 3) {
                beschreibung
                Spacer(minLength: 0)
                knoepfe
            }
            VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                beschreibung
                knoepfe
            }
        }
        .sheet(item: $urteil) { wahl in
            AbhakenBlatt(ziel: ziel, status: wahl.status)
        }
    }

    private var beschreibung: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: ziel.text)
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.text)
            HStack(spacing: Abstand.raster * 2) {
                Text(verbatim: Zielformat.zeitraum(ziel))
                if let messung = Zielformat.messung(ziel) {
                    Text(verbatim: messung)
                }
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            Text("Zeitraum vorbei, bitte beurteilen")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.akzent)
        }
    }

    private var knoepfe: some View {
        HStack(spacing: Abstand.raster * 2) {
            ForEach(Zielformat.abhakStatus, id: \.self) { status in
                Button(Zielformat.titel(status)) { urteil = Urteilwahl(status: status) }
                    .buttonStyle(.bordered)
                    .tint(Zielformat.farbe(status, thema))
            }
        }
        .controlSize(.small)
    }
}

/// Karte „Erledigt“: beurteilte Ziele nach Monat des Zeitraumendes, neueste zuerst, mit Ergebnis.
private struct ErledigteZieleKarte: View {
    let ziele: [Reviewziel]
    @Environment(\.thema) private var thema
    @State private var alleSichtbar = false

    private static let vorschau = 8

    var body: some View {
        let beurteilt = Zielbilanz.beurteilt(ziele)
        let sichtbar = alleSichtbar ? beurteilt : Array(beurteilt.prefix(Self.vorschau))
        let monate = Zielbilanz.nachMonat(sichtbar)
        Karte("Erledigt") {
            if beurteilt.isEmpty {
                Text("Noch kein abgehaktes Ziel. Das nächste Review hakt das offene Ziel ab und setzt genau ein neues.")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            }
            ForEach(monate, id: \.monat) { gruppe in
                Text(verbatim: Format.monat(gruppe.monat))
                    .font(Schrift.beschriftung.weight(.semibold))
                    .foregroundStyle(thema.textSchwach)
                    .textCase(.uppercase)
                ForEach(gruppe.ziele, id: \.id) { ziel in
                    ZielZeile(ziel: ziel)
                }
            }
            if beurteilt.count > Self.vorschau {
                Button(alleSichtbar ? String(localized: "Weniger anzeigen")
                                    : String(localized: "Alle \(beurteilt.count) anzeigen")) { alleSichtbar.toggle() }
                    .buttonStyle(.plain)
                    .foregroundStyle(thema.akzent)
            }
        }
    }
}

/// Karte „Neues Ziel“: dasselbe Formular wie das Blatt, immer sichtbar (Tims Wahl Variante A).
private struct NeuesZielKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var entwurf = ZielEntwurf()
    @State private var fehler: String?

    var body: some View {
        Karte("Neues Ziel") {
            TextField("z. B. Höchstens 2 Revanche-Trades", text: $entwurf.text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Picker("Zeitraum", selection: $entwurf.zeitraum) {
                ForEach(Zielzeitraum.allCases, id: \.self) { wahl in
                    Text(wahl.titel).tag(wahl)
                }
            }
            if entwurf.zeitraum == .eigener {
                DatePicker("Von", selection: $entwurf.von, displayedComponents: .date)
                DatePicker("Bis einschließlich", selection: $entwurf.bisEinschliesslich, in: entwurf.von..., displayedComponents: .date)
            } else {
                LabeledContent("Gilt", value: Zielformat.zeitraum(von: entwurf.spanne.von, bis: entwurf.spanne.bis))
            }
            TextField("Messgröße, z. B. Revanche-Trades", text: $entwurf.messgroesse)
                .textFieldStyle(.roundedBorder)
            TextField("Zielwert, z. B. 2", value: $entwurf.zielwert, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Leeren") { entwurf = ZielEntwurf(); fehler = nil }
                    .disabled(entwurf.leer)
                Spacer()
                Button("Ziel anlegen") { anlegen() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entwurf.gueltig || modell.konto == nil)
            }
            if let fehler {
                Text(verbatim: fehler)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.verlust)
            }
            Text("Genau ein messbares Ziel je Review (Rezept Punkt 7), so formuliert, dass das nächste Review es mit einer Zahl prüfen kann. Export und Claude-Connector lesen die Ziele mit.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func anlegen() {
        do {
            try modell.legeZielAn(entwurf.ziel)
            entwurf = ZielEntwurf()
            fehler = nil
        } catch {
            fehler = Zielfehler.text(error)
        }
    }
}

/// Karte „Bilanz“: abgehakte Ziele je Monat des Zeitraumendes, gestapelt nach Urteil, letzte sechs Monate.
private struct ZielbilanzKarte: View {
    let ziele: [Reviewziel]
    @Environment(\.thema) private var thema

    var body: some View {
        let werte = Zielbilanz.jeMonat(ziele)
        let gesamt = werte.reduce(0) { $0 + $1.anzahl }
        let urteile = Zielformat.abhakStatus
        Karte("Bilanz") {
            if gesamt == 0 {
                Text("Noch kein abgehaktes Ziel in den letzten sechs Monaten.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                Chart(werte) { wert in
                    BarMark(x: .value("Monat", wert.monat, unit: .month),
                            y: .value("Ziele", wert.anzahl))
                        .foregroundStyle(by: .value("Urteil", Zielformat.titel(wert.status)))
                        .cornerRadius(Diagramm.balkenEndeRadius)
                }
                .chartForegroundStyleScale(domain: urteile.map { Zielformat.titel($0) },
                                           range: urteile.map { Zielformat.farbe($0, thema) })
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(thema.textSchwach)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(thema.linie)
                        AxisValueLabel().foregroundStyle(thema.textSchwach)
                    }
                }
                .chartLegend(position: .bottom, spacing: Abstand.raster)
                .frame(height: 150)
            }
            Text("Zählt abgehakte Ziele nach dem Ende ihres Zeitraums, letzte sechs Monate. Keine Wertung der Trades selbst, nur ob du dein Ziel gehalten hast.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }
}

/// Karte „Im Review“: die drei Schritte aus dem Rezept, als Erinnerung neben dem Formular.
private struct ReviewSchritteKarte: View {
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Im Review") {
            schritt(1, "Fälliges Ziel beurteilen, Ergebnis in einem Satz.")
            schritt(2, "Kennzahlen und Fehlermuster des Zeitraums ansehen.")
            schritt(3, "Genau ein neues Ziel für den nächsten Zeitraum anlegen.")
            Text("Wochen- oder Monatsreview, Rezept Punkt 6 und 7. Der Claude-Connector liest Ziele und Ergebnisse mit, ändern kann er sie nicht.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func schritt(_ nummer: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
            Text(verbatim: "\(nummer).")
                .font(Schrift.fliesstext.weight(.semibold))
                .foregroundStyle(thema.akzent)
            Text(text)
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.text)
        }
    }
}

/// Zahlen zu den Zielen eines Kontos, ohne Oberfläche.
enum Zielbilanz {
    /// Vom Speicher auf „verfehlt“ gesetzt (Frist abgelaufen) und noch ohne Urteil von Hand.
    static func zuBeurteilen(_ ziele: [Reviewziel]) -> [Reviewziel] {
        ziele.filter { istAutomatischVerfehlt($0) }
    }

    /// Offene Ziele, frühester Beginn zuerst (Reihenfolge des Speichers).
    static func offen(_ ziele: [Reviewziel]) -> [Reviewziel] {
        ziele.filter { $0.status == .offen }
    }

    /// Erledigte Ziele mit Urteil von Hand, spätestes Zeitraumende zuerst.
    static func beurteilt(_ ziele: [Reviewziel]) -> [Reviewziel] {
        ziele.filter { $0.status != .offen && !istAutomatischVerfehlt($0) }
            .sorted { $0.bis > $1.bis }
    }

    static func istAutomatischVerfehlt(_ ziel: Reviewziel) -> Bool {
        ziel.status == .verfehlt && ziel.ergebnis == Journal.fristAbgelaufen
    }

    /// Letzter Tag des Zeitraums (`bis` ist ausschließlich).
    static func letzterTag(_ ziel: Reviewziel, kalender: Calendar = .current) -> Date {
        kalender.date(byAdding: .day, value: -1, to: ziel.bis) ?? ziel.bis
    }

    /// Ziele, deren Zeitraum im Jahr `jahr` endet.
    static func imJahr(_ ziele: [Reviewziel], _ jahr: Int, kalender: Calendar = .current) -> [Reviewziel] {
        ziele.filter { kalender.component(.year, from: letzterTag($0, kalender: kalender)) == jahr }
    }

    struct Monatsgruppe {
        let monat: Date
        let ziele: [Reviewziel]
    }

    /// Gruppiert nach Monat des Zeitraumendes, in der Reihenfolge der Eingabe (erstes Vorkommen).
    static func nachMonat(_ ziele: [Reviewziel], kalender: Calendar = .current) -> [Monatsgruppe] {
        var gruppen: [Monatsgruppe] = []
        for ziel in ziele {
            guard let monat = kalender.dateInterval(of: .month, for: letzterTag(ziel, kalender: kalender))?.start else { continue }
            if let index = gruppen.firstIndex(where: { $0.monat == monat }) {
                gruppen[index] = Monatsgruppe(monat: monat, ziele: gruppen[index].ziele + [ziel])
            } else {
                gruppen.append(Monatsgruppe(monat: monat, ziele: [ziel]))
            }
        }
        return gruppen
    }

    struct Monatswert: Identifiable {
        let monat: Date
        let status: Reviewziel.Status
        let anzahl: Int
        var id: String { "\(monat.timeIntervalSinceReferenceDate)-\(status.rawValue)" }
    }

    /// Je Monat (Ende des Zeitraums) die Zahl der abgehakten Ziele je Urteil, die letzten `monate` Monate bis `jetzt`.
    static func jeMonat(_ ziele: [Reviewziel], monate: Int = 6, jetzt: Date = Date(),
                        kalender: Calendar = .current) -> [Monatswert] {
        guard let aktuell = kalender.dateInterval(of: .month, for: jetzt)?.start else { return [] }
        let abgehakt = ziele.filter { $0.status != .offen }
        var werte: [Monatswert] = []
        for versatz in (0..<monate).reversed() {
            guard let start = kalender.date(byAdding: .month, value: -versatz, to: aktuell),
                  let intervall = kalender.dateInterval(of: .month, for: start) else { continue }
            let imMonat = abgehakt.filter { intervall.contains(letzterTag($0, kalender: kalender)) }
            for status in Zielformat.abhakStatus {
                werte.append(Monatswert(monat: start, status: status,
                                        anzahl: imMonat.filter { $0.status == status }.count))
            }
        }
        return werte
    }

    /// Wie viele Ziele lückenlos aufeinander folgen (Beginn höchstens einen Tag nach dem Ende des vorigen),
    /// vom jüngsten Ziel rückwärts gezählt; verworfene zählen nicht. `seit` ist der Beginn des ältesten in der Kette.
    static func inFolge(_ ziele: [Reviewziel], kalender: Calendar = .current) -> (anzahl: Int, seit: Date?) {
        let kette = ziele.filter { $0.status != .verworfen }.sorted { $0.von < $1.von }
        guard var aktuell = kette.last else { return (0, nil) }
        var anzahl = 1
        for ziel in kette.dropLast().reversed() {
            let luecke = kalender.dateComponents([.day], from: ziel.bis, to: aktuell.von).day ?? Int.max
            guard luecke <= 1 else { break }
            anzahl += 1
            aktuell = ziel
        }
        return (anzahl, aktuell.von)
    }
}
