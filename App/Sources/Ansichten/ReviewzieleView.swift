import SwiftUI
import TradingCore
import TradingStore

// Review-Ziele (Rezept Punkt 6 und 7, Entscheidung 28 vom 02.10.2026): Nach jeder Wochen- oder
// Monatsauswertung genau ein messbares Ziel für den nächsten Zeitraum; das nächste Review hakt es ab.
// Gespeichert je Konto in TradingStore (Migration v4, AP9 #37), gelesen von Export und Connector (AP12);
// eingegeben wird es nur hier. Ort in der App: Karte auf der Übersicht und die Seite „Ziele“ in der
// Seitenleiste (ZieleView.swift; Tim 02.10.2026 03:20 UTC). Hier liegen die gemeinsamen Bausteine.

/// Karte auf der Übersicht: offene Ziele des Kontos; im Monatsfilter die Ziele, die den Monat berühren.
struct ZieleKarte: View {
    @AppStorage(Ton.schluessel) private var ton = Ton.henry
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var neuesZiel = false

    var body: some View {
        let ziele = sichtbareZiele
        Karte("Review-Ziele", aktion: { modell.bereich = .ziele }) {
            if ziele.isEmpty {
                Text(verbatim: leerText)
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                ForEach(ziele, id: \.id) { ziel in
                    ZielZeile(ziel: ziel, kompakt: true)
                }
            }
            Button("Ziel anlegen…", systemImage: "plus") { neuesZiel = true }
                .buttonStyle(.plain)
                .foregroundStyle(thema.akzent)
                .disabled(modell.konto == nil)
        }
        .sheet(isPresented: $neuesZiel) { ZielFormular() }
    }

    private var sichtbareZiele: [Reviewziel] {
        switch modell.zeitraum {
        case .alle:
            return Array(modell.offeneZiele.prefix(3))
        case .monat(let monat):
            guard let intervall = Calendar.current.dateInterval(of: .month, for: monat) else { return [] }
            return Array(modell.ziele.filter { $0.von < intervall.end && $0.bis > intervall.start }.prefix(3))
        }
    }

    private var leerText: String {
        if modell.konto == nil {
            return String(localized: "Ziele gehören zu einem Konto. Importiere zuerst einen Kontoauszug.")
        }
        switch modell.zeitraum {
        case .alle: return ton.text("Kein offenes Ziel. Lege nach dem Review genau ein messbares Ziel für den nächsten Zeitraum an.",
                                    henry: "Kein offenes Ziel. Wer keines hat, verfehlt auch keines. Nach dem Review genau ein messbares Ziel für den nächsten Zeitraum anlegen.")
        case .monat: return String(localized: "Kein Ziel berührt diesen Monat.")
        }
    }
}

/// Eine Zielzeile: Text, Zeitraum, Messung, Status; Menü zum Abhaken, Wiederöffnen und Löschen.
struct ZielZeile: View {
    let ziel: Reviewziel
    var kompakt = false
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var abhaken: Abhakwahl?
    @State private var loeschenGefragt = false

    /// Gewählter Status für das Blatt „Ziel abhaken“ (`Reviewziel.Status` ist nicht Identifiable).
    private struct Abhakwahl: Identifiable {
        let status: Reviewziel.Status
        var id: String { status.rawValue }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Abstand.raster * 2) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: ziel.text)
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                HStack(spacing: Abstand.raster * 2) {
                    Text(verbatim: Zielformat.zeitraum(ziel))
                    if let messung = Zielformat.messung(ziel) {
                        Text(verbatim: messung)
                    }
                    if ziel.status == .offen, ziel.bis <= Date() {
                        Text("Zeitraum vorbei, abhaken")
                            .foregroundStyle(thema.akzent)
                    }
                }
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                if !kompakt, let ergebnis = ziel.ergebnis, !ergebnis.isEmpty {
                    Text(verbatim: ergebnis)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.text)
                }
            }
            Spacer(minLength: 0)
            Statuskapsel(status: ziel.status)
            Menu {
                if ziel.status == .offen {
                    ForEach(Zielformat.abhakStatus, id: \.self) { status in
                        Button(Zielformat.titel(status)) { abhaken = Abhakwahl(status: status) }
                    }
                } else {
                    Button("Wieder öffnen") { modell.setzeZielstatus(ziel, .offen, ergebnis: nil) }
                }
                Divider()
                Button("Löschen…", role: .destructive) { loeschenGefragt = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(thema.akzent)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .accessibilityLabel("Aktionen zum Ziel")
        }
        .sheet(item: $abhaken) { wahl in
            AbhakenBlatt(ziel: ziel, status: wahl.status)
        }
        .confirmationDialog("Ziel löschen?", isPresented: $loeschenGefragt, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { modell.loescheZiel(ziel) }
        } message: {
            Text(verbatim: ziel.text)
        }
    }
}

/// Status als Kapsel in der Farbe des Urteils.
struct Statuskapsel: View {
    let status: Reviewziel.Status
    @Environment(\.thema) private var thema

    var body: some View {
        let farbe = Zielformat.farbe(status, thema)
        // Text in thema.text, die Farbe nur im Grund und als Punkt (Doc 55 J22).
        HStack(spacing: Abstand.raster) {
            Circle().fill(farbe).frame(width: 6, height: 6)
            Text(verbatim: Zielformat.titel(status))
        }
        .font(Schrift.beschriftung)
        .padding(.horizontal, Abstand.raster * 2)
        .padding(.vertical, Abstand.raster)
        .background(farbe.opacity(0.18), in: Capsule())
        .foregroundStyle(thema.text)
    }
}

/// Welche Karten die Seite „Ziele“ zeigt.
enum Zielfilter: CaseIterable, Hashable {
    case offen, erledigt, alle

    var titel: LocalizedStringKey {
        switch self {
        case .offen: "Offen"
        case .erledigt: "Erledigt"
        case .alle: "Alle"
        }
    }

    func passt(_ ziel: Reviewziel) -> Bool {
        switch self {
        case .offen: ziel.status == .offen
        case .erledigt: ziel.status != .offen
        case .alle: true
        }
    }
}

/// Vorgaben für den Zeitraum eines neuen Ziels: Kalenderwoche oder Monat in der Zeitzone des Nutzers.
enum Zielzeitraum: CaseIterable, Hashable {
    case dieseWoche, naechsteWoche, dieserMonat, naechsterMonat, eigener

    var titel: LocalizedStringKey {
        switch self {
        case .dieseWoche: "Diese Woche"
        case .naechsteWoche: "Nächste Woche"
        case .dieserMonat: "Dieser Monat"
        case .naechsterMonat: "Nächster Monat"
        case .eigener: "Eigener Zeitraum"
        }
    }

    /// Beginn einschließlich, Ende ausschließlich (wie `Reviewziel.von` und `bis`).
    func spanne(von eigenVon: Date, bisEinschliesslich: Date, jetzt: Date = Date(),
                kalender: Calendar = .current) -> (von: Date, bis: Date) {
        switch self {
        case .dieseWoche: return Self.einheit(.weekOfYear, ab: jetzt, versatz: 0, kalender)
        case .naechsteWoche: return Self.einheit(.weekOfYear, ab: jetzt, versatz: 1, kalender)
        case .dieserMonat: return Self.einheit(.month, ab: jetzt, versatz: 0, kalender)
        case .naechsterMonat: return Self.einheit(.month, ab: jetzt, versatz: 1, kalender)
        case .eigener:
            let start = kalender.startOfDay(for: eigenVon)
            let letzter = kalender.startOfDay(for: bisEinschliesslich)
            let ende = kalender.date(byAdding: .day, value: 1, to: letzter) ?? start
            return (start, ende)
        }
    }

    private static func einheit(_ einheit: Calendar.Component, ab jetzt: Date, versatz: Int,
                                _ kalender: Calendar) -> (von: Date, bis: Date) {
        guard let aktuell = kalender.dateInterval(of: einheit, for: jetzt) else { return (jetzt, jetzt) }
        guard versatz != 0,
              let start = kalender.date(byAdding: einheit, value: versatz, to: aktuell.start),
              let spaeter = kalender.dateInterval(of: einheit, for: start)
        else { return (aktuell.start, aktuell.end) }
        return (spaeter.start, spaeter.end)
    }
}

/// Eingaben für ein neues Ziel, gemeinsam für das Blatt `ZielFormular` und die Karte „Neues Ziel“ der Seite.
struct ZielEntwurf {
    var text = ""
    var zeitraum: Zielzeitraum = .naechsteWoche
    var von = Calendar.current.startOfDay(for: Date())
    var bisEinschliesslich = Calendar.current.date(byAdding: .day, value: 6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    var messgroesse = ""
    var zielwert: Decimal?

    var spanne: (von: Date, bis: Date) {
        zeitraum.spanne(von: von, bisEinschliesslich: bisEinschliesslich)
    }

    var gueltig: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && spanne.von < spanne.bis
    }

    /// Noch nichts eingetragen (für den Knopf „Leeren“).
    var leer: Bool {
        text.isEmpty && messgroesse.isEmpty && zielwert == nil && zeitraum == .naechsteWoche
    }

    /// Das Ziel zum Speichern; die Speicherung prüft Text und Zeitraum noch einmal.
    var ziel: Reviewziel {
        let spanne = self.spanne
        let messung = messgroesse.trimmingCharacters(in: .whitespacesAndNewlines)
        return Reviewziel(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                          von: spanne.von, bis: spanne.bis,
                          messgroesse: messung.isEmpty ? nil : messung, zielwert: zielwert)
    }
}

/// Blatt „Neues Ziel“ (Übersicht, Kopfzeile der Seite, iPhone).
struct ZielFormular: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen
    @State private var entwurf = ZielEntwurf()
    @State private var fehler: String?
    /// Konto beim Öffnen; dort wird das Ziel angelegt, auch nach einem Kontowechsel (Codex-Review M5).
    @State private var kontoId: Int64?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ziel") {
                    ZielKontoZeile(kontoId: kontoId)
                    TextField("z. B. Höchstens 2 Revanche-Trades", text: $entwurf.text, axis: .vertical)
                        .lineLimit(2...4)
                    Text("Genau ein messbares Ziel je Zeitraum, so formuliert, dass das nächste Review es mit einer Zahl prüfen kann.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                Section("Zeitraum") {
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
                }
                Section("Messung (freiwillig)") {
                    TextField("Messgröße, z. B. Revanche-Trades", text: $entwurf.messgroesse)
                    TextField("Zielwert, z. B. 2", value: $entwurf.zielwert, format: .number.precision(.fractionLength(0...2)))
                }
                if let fehler {
                    Section {
                        Text(verbatim: fehler)
                            .foregroundStyle(thema.verlust)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Neues Ziel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { anlegen() }
                        .disabled(!entwurf.gueltig)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 460)
        #endif
        .onAppear { if kontoId == nil { kontoId = modell.konto?.id } }
    }

    private func anlegen() {
        do {
            try modell.legeZielAn(entwurf.ziel, konto: kontoId)
            schliessen()
        } catch {
            fehler = Zielfehler.text(error)
        }
    }
}

/// Blatt „Ziel abhaken“: Urteil wählen, Ergebnis in einem Satz.
struct AbhakenBlatt: View {
    let ziel: Reviewziel
    @State private var status: Reviewziel.Status
    @State private var ergebnis = ""
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen

    init(ziel: Reviewziel, status: Reviewziel.Status) {
        self.ziel = ziel
        _status = State(initialValue: status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ziel") {
                    Text(verbatim: ziel.text)
                    Text(verbatim: Zielformat.zeitraum(ziel))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                Section("Urteil") {
                    Picker("Status", selection: $status) {
                        ForEach(Zielformat.abhakStatus, id: \.self) { wahl in
                            Text(verbatim: Zielformat.titel(wahl)).tag(wahl)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextField("Ergebnis, z. B. 1 Revanche-Trade statt höchstens 2", text: $ergebnis, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ziel abhaken")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let text = ergebnis.trimmingCharacters(in: .whitespacesAndNewlines)
                        modell.setzeZielstatus(ziel, status, ergebnis: text.isEmpty ? nil : text)
                        schliessen()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
    }
}

/// Texte und Farben für Ziele.
enum Zielformat {
    static func zeitraum(_ ziel: Reviewziel) -> String {
        zeitraum(von: ziel.von, bis: ziel.bis)
    }

    /// Ganzer Monat „Oktober 2026“, ganze Woche „KW 41, 05.10. bis 11.10.2026“, sonst „von bis einschließlich“.
    static func zeitraum(von: Date, bis: Date, kalender: Calendar = .current) -> String {
        if let monat = kalender.dateInterval(of: .month, for: von), monat.start == von, monat.end == bis {
            return Format.monat(von)
        }
        let letzterTag = kalender.date(byAdding: .day, value: -1, to: bis) ?? bis
        if let woche = kalender.dateInterval(of: .weekOfYear, for: von), woche.start == von, woche.end == bis {
            let kw = kalender.component(.weekOfYear, from: von)
            return String(localized: "KW \(kw), \(tag(von)) bis \(Format.datum(letzterTag))")
        }
        return String(localized: "\(Format.datum(von)) bis \(Format.datum(letzterTag))")
    }

    /// Messgröße und Zielwert, z. B. „Revanche-Trades: höchstens 2“ ohne Wertung: „Revanche-Trades: 2“.
    static func messung(_ ziel: Reviewziel) -> String? {
        let wert = ziel.zielwert.map { $0.formatted(.number.precision(.fractionLength(0...2))) }
        switch (ziel.messgroesse, wert) {
        case (let groesse?, let wert?): return "\(groesse): \(wert)"
        case (let groesse?, nil): return groesse
        case (nil, let wert?): return String(localized: "Zielwert \(wert)")
        case (nil, nil): return nil
        }
    }

    /// Statusname; „verfehlt“ läuft über `default`, weil offen ist, ob der Fall im Paket bleibt (Entscheidung 28).
    static func titel(_ status: Reviewziel.Status) -> String {
        switch status {
        case .offen: String(localized: "Offen")
        case .erreicht: String(localized: "Erreicht")
        case .verworfen: String(localized: "Verworfen")
        default: status.rawValue.capitalized
        }
    }

    static func farbe(_ status: Reviewziel.Status, _ thema: Thema) -> Color {
        switch status {
        case .offen: thema.akzent
        case .erreicht: thema.gewinn
        case .verworfen: thema.textSchwach
        default: thema.verlust
        }
    }

    /// Urteile zum Abhaken: alle Status außer „offen“, in der Reihenfolge des Pakets.
    static var abhakStatus: [Reviewziel.Status] {
        Reviewziel.Status.allCases.filter { $0 != .offen }
    }

    /// Tag und Monat ohne Jahr, z. B. „05.10.“.
    private static func tag(_ datum: Date) -> String {
        datum.formatted(.dateTime.day(.twoDigits).month(.twoDigits))
    }
}

/// Fehler rund um Ziele in Klartext; `SpeicherFehler` bringt keine eigene Beschreibung mit.
/// Konto, zu dem ein Zielentwurf gehört, mit Hinweis, wenn inzwischen ein anderes Konto gewählt ist
/// (Codex-Review 04.10.2026, M5).
struct ZielKontoZeile: View {
    let kontoId: Int64?
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        if let kontoId, let konto = modell.konten.first(where: { $0.id == kontoId }) {
            LabeledContent("Konto") { Text(verbatim: konto.kontoname) }
            if kontoId != modell.konto?.id {
                Text("Der Entwurf gehört zu „\(konto.kontoname)“, nicht zum gerade gewählten Konto; angelegt wird er dort.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.warnung)
            }
        }
    }
}

enum Zielfehler: Error {
    case keinKonto

    static func text(_ fehler: Error) -> String {
        switch fehler {
        case Zielfehler.keinKonto:
            return String(localized: "Ziele gehören zu einem Konto. Importiere zuerst einen Kontoauszug.")
        case SpeicherFehler.ungueltigerWert(let grund):
            return grund
        case SpeicherFehler.unbekannterWert(let wert):
            return String(localized: "Die Datenbank enthält einen unbekannten Zielstatus: \(wert)")
        default:
            return fehler.localizedDescription
        }
    }
}
