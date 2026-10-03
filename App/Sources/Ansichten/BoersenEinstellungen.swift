import SwiftUI
import TradingClock
import UniformTypeIdentifiers

/// Einstellungen der Börsenuhr (Stand-Doc 15, U6 und U7): angezeigte Börsen und ihre Reihenfolge,
/// Handelszeiten, eigene Börsen, Feiertagskalender. Abschnitte für ein `Form`; benutzt im Blatt
/// „Börsen verwalten“ und in den Einstellungen.
struct BoersenEinstellungen: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var bearbeitung: Bearbeitung?
    @State private var dateiWaehlen = false

    private enum Bearbeitung: Identifiable {
        case boerse(String)
        case neueBoerse
        case neuerKalender

        var id: String {
            switch self {
            case .boerse(let id): "boerse-\(id)"
            case .neueBoerse: "neue-boerse"
            case .neuerKalender: "neuer-kalender"
            }
        }
    }

    var body: some View {
        let verwaltung = modell.boersen
        Group {
            Section("Angezeigte Börsen") {
                ForEach(verwaltung.angezeigt, id: \.self) { id in
                    if let boerse = verwaltung.boerse(id) {
                        BoersenEintrag(boerse: boerse, sichtbar: true) { bearbeitung = .boerse(id) }
                    }
                }
                .onMove { verwaltung.verschiebe(von: $0, nach: $1) }
                Text("Reihenfolge mit den Pfeilen oder durch Ziehen. Die letzte Börse lässt sich nicht ausblenden.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            if !verwaltung.ausgeblendet.isEmpty {
                Section("Weitere Börsen") {
                    ForEach(verwaltung.ausgeblendet) { boerse in
                        BoersenEintrag(boerse: boerse, sichtbar: false) { bearbeitung = .boerse(boerse.id) }
                    }
                }
            }
            Section("Eigene Börsen") {
                Button("Eigene Börse anlegen…", systemImage: "plus") { bearbeitung = .neueBoerse }
                Button("Datei hinzufügen (Börse oder Feiertagskalender)…", systemImage: "doc.badge.plus") { dateiWaehlen = true }
                Text("Dateien im Format 1 als JSON, beschrieben in Packages/TradingClock/README.md. Die mitgelieferten Börsen bleiben unverändert; deine Auswahl liegt in den Einstellungen der App.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Section("Feiertagskalender") {
                if verwaltung.auswahl.kalender.isEmpty {
                    Text("Noch kein eigener Kalender. Ein Kalender gilt zusätzlich zu den Feiertagen einer Börse; die Zuordnung steht bei der Börse unter „Einrichten“.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                ForEach(verwaltung.auswahl.kalender) { kalender in
                    KalenderEintrag(kalender: kalender)
                }
                Button("Kalender anlegen…", systemImage: "calendar.badge.plus") { bearbeitung = .neuerKalender }
            }
            if let fehler = verwaltung.fehler {
                Section {
                    Label(fehler, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(thema.verlust)
                }
            }
            if !verwaltung.probleme.isEmpty {
                Section("Übersprungene Einträge") {
                    ForEach(verwaltung.probleme, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.circle")
                            .foregroundStyle(thema.textSchwach)
                    }
                    Text("Diese Einträge der gespeicherten Auswahl nimmt die Uhr nicht, etwa nach einer nachträglich geänderten Datei. Löschen oder neu anlegen behebt es.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }
        .sheet(item: $bearbeitung) { bearbeitung in
            switch bearbeitung {
            case .boerse(let id): BoerseEinrichten(boerse: verwaltung.boerse(id))
            case .neueBoerse: BoerseEinrichten(boerse: nil)
            case .neuerKalender: KalenderFormular()
            }
        }
        .fileImporter(isPresented: $dateiWaehlen, allowedContentTypes: [.json]) { ergebnis in
            switch ergebnis {
            case .success(let url):
                let zugriff = url.startAccessingSecurityScopedResource()
                defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
                do {
                    verwaltung.importiere(daten: try Data(contentsOf: url))
                } catch {
                    verwaltung.melde(error.localizedDescription)
                }
            case .failure(let problem):
                verwaltung.melde(problem.localizedDescription)
            }
        }
    }
}

/// Eine Börse in den Listen: Name mit Kapseln, Ort und Handelszeiten, Knöpfe für Reihenfolge und Sichtbarkeit.
private struct BoersenEintrag: View {
    let boerse: Boerse
    let sichtbar: Bool
    let einrichten: () -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let verwaltung = modell.boersen
        let anzahlKalender = verwaltung.kalender(fuer: boerse.id).count
        HStack(spacing: Abstand.kachelAbstand) {
            VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                HStack(spacing: Abstand.raster) {
                    Text(verbatim: boerse.name)
                        .foregroundStyle(thema.text)
                    if verwaltung.istEigene(boerse.id) {
                        Kapsel(text: String(localized: "eigene"))
                    }
                    if verwaltung.istAngepasst(boerse.id) {
                        Kapsel(text: String(localized: "Zeiten angepasst"))
                    }
                    if anzahlKalender > 0 {
                        Kapsel(text: anzahlKalender == 1 ? String(localized: "1 Kalender") : String(localized: "\(anzahlKalender) Kalender"))
                    }
                }
                Text(verbatim: "\(Boersenformat.ort(boerse.timeZone)) · \(Handelszeitformat.zusammenfassung(boerse))")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                    .lineLimit(2)
                let zusatz = boerse.verfuegbareSitzungsarten.filter { $0 != .kern }
                if !zusatz.isEmpty {
                    // Entscheidung U8: Kernhandel immer, Zusatzsitzungen je Börse zuschaltbar.
                    HStack(spacing: Abstand.raster * 2) {
                        Text("Mitrechnen:")
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                        ForEach(zusatz, id: \.self) { art in
                            Toggle(isOn: sitzungsartBinding(art)) { Text(verbatim: art.titel) }
                                .toggleStyle(.button)
                                .font(Schrift.beschriftung)
                        }
                    }
                }
            }
            Spacer()
            if sichtbar {
                Button { verwaltung.verschiebe(boerse.id, um: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(verwaltung.angezeigt.first == boerse.id)
                    .help("Nach oben")
                    .accessibilityLabel(Text("Nach oben")) // Doc 55 J15
                Button { verwaltung.verschiebe(boerse.id, um: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(verwaltung.angezeigt.last == boerse.id)
                    .help("Nach unten")
                    .accessibilityLabel(Text("Nach unten"))
                Button("Ausblenden") { verwaltung.blendeAus(boerse.id) }
                    .disabled(verwaltung.angezeigt.count == 1)
            } else {
                Button("Anzeigen") { verwaltung.zeige(boerse.id) }
            }
            Button("Einrichten…", action: einrichten)
        }
        .buttonStyle(.borderless)
    }

    private func sitzungsartBinding(_ art: Sitzungsart) -> Binding<Bool> {
        Binding(get: { modell.boersen.sitzungsarten(boerse.id).contains(art) },
                set: { modell.boersen.setzeSitzungsart(art, boerse: boerse.id, an: $0) })
    }
}

/// Ein Feiertagskalender in der Liste: Name, Land, Umfang, Zuordnung, Löschen.
private struct KalenderEintrag: View {
    let kalender: Feiertagskalender
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let verwaltung = modell.boersen
        let boersen = verwaltung.verfuegbar?.boersen
            .filter { verwaltung.kalender(fuer: $0.id).contains(kalender.id) }
            .map(\.name) ?? []
        HStack(spacing: Abstand.kachelAbstand) {
            VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                HStack(spacing: Abstand.raster) {
                    Text(verbatim: kalender.name)
                        .foregroundStyle(thema.text)
                    if let land = kalender.land {
                        Kapsel(text: land)
                    }
                }
                Text(verbatim: zusatz(boersen))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                    .lineLimit(2)
            }
            Spacer()
            Button("Löschen", role: .destructive) { verwaltung.loescheKalender(kalender.id) }
                .buttonStyle(.borderless)
        }
    }

    private func zusatz(_ boersen: [String]) -> String {
        var teile = [String(localized: "\(kalender.feiertage.count) Feiertage")]
        if !kalender.verkuerzteTage.isEmpty {
            teile.append(String(localized: "\(kalender.verkuerzteTage.count) verkürzte Tage"))
        }
        if let bis = kalender.datenGueltigBis {
            teile.append(String(localized: "gepflegt bis \(Boersenformat.tag(bis))"))
        }
        if boersen.isEmpty {
            teile.append(String(localized: "keiner Börse zugeordnet"))
        } else {
            teile.append(String(localized: "gilt für \(boersen.joined(separator: ", "))"))
        }
        return teile.joined(separator: " · ")
    }
}

/// Eine Handelszeit im Formular: Tage, Beginn, Ende, Ende nach Tagen. Die Uhrzeiten liegen als Datum
/// am 1. Januar 2001 in UTC vor, damit der DatePicker genau HH:MM zeigt und speichert.
private struct Sitzungszeile: Identifiable {
    let id = UUID()
    var tage: Set<Wochentag> = [.montag, .dienstag, .mittwoch, .donnerstag, .freitag]
    var beginn = Sitzungszeile.datum(9, 0)
    var ende = Sitzungszeile.datum(17, 30)
    var endeNachTagen = 0
    /// Kernhandel oder Zusatzsitzung; bleibt beim Bearbeiten mitgelieferter Zeiten erhalten.
    var art: Sitzungsart = .kern
    /// Erster Tag der Sitzung (Nasdaq-Nacht ab 06.12.2026); nicht bearbeitbar, bleibt erhalten.
    var gueltigAb: Kalendertag?

    static let utc: Calendar = {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(secondsFromGMT: 0)!
        return kalender
    }()

    init() {}

    init(_ zeit: Handelszeit) {
        tage = Set(zeit.tage)
        beginn = Self.datum(zeit.beginn.stunde, zeit.beginn.minute)
        ende = Self.datum(zeit.ende.stunde, zeit.ende.minute)
        endeNachTagen = zeit.endeNachTagen
        art = zeit.art
        gueltigAb = zeit.gueltigAb
    }

    func handelszeit() throws -> Handelszeit {
        let geordnet = Wochentag.allCases.filter { tage.contains($0) }
        return Handelszeit(tage: geordnet, beginn: try Self.uhrzeit(beginn), ende: try Self.uhrzeit(ende),
                           endeNachTagen: endeNachTagen, art: art, gueltigAb: gueltigAb)
    }

    static func datum(_ stunde: Int, _ minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: stunde, minute: minute)) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static func uhrzeit(_ datum: Date) throws -> Uhrzeit {
        let teile = utc.dateComponents([.hour, .minute], from: datum)
        return try Uhrzeit(stunde: teile.hour ?? 0, minute: teile.minute ?? 0)
    }
}

/// Blatt „Einrichten“: Handelszeiten (bei mitgelieferten Börsen als Anpassung, Feiertage bleiben),
/// bei eigenen Börsen auch Name und Zeitzone, dazu die Zuordnung der Feiertagskalender.
private struct BoerseEinrichten: View {
    let vorhandene: Boerse?
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen
    @State private var name: String
    @State private var zeitzone: String
    @State private var zeiten: [Sitzungszeile]
    @State private var fehler: String?

    init(boerse: Boerse?) {
        vorhandene = boerse
        _name = State(initialValue: boerse?.name ?? "")
        _zeitzone = State(initialValue: boerse?.zeitzone ?? TimeZone.current.identifier)
        _zeiten = State(initialValue: boerse.map { $0.handelszeiten.map(Sitzungszeile.init) } ?? [Sitzungszeile()])
    }

    var body: some View {
        let verwaltung = modell.boersen
        let eigene = vorhandene.map { verwaltung.istEigene($0.id) } ?? true
        let durchgehend = vorhandene?.durchgehend ?? false
        NavigationStack {
            Form {
                Section("Börse") {
                    if eigene {
                        TextField("Name", text: $name)
                        ZeitzonenFeld(zeitzone: $zeitzone)
                    } else {
                        LabeledContent("Name") { Text(verbatim: vorhandene?.name ?? "") }
                        LabeledContent("Zeitzone") { Text(verbatim: zeitzone) }
                    }
                    if durchgehend {
                        Text("Rund um die Uhr geöffnet; Handelszeiten gelten hier nicht.")
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                }
                if !durchgehend {
                    Section("Handelszeiten in Ortszeit der Börse") {
                        ForEach($zeiten) { $zeile in
                            SitzungsEditor(zeile: $zeile) { zeiten.removeAll { $0.id == zeile.id } }
                        }
                        Button("Sitzung hinzufügen", systemImage: "plus") { zeiten.append(Sitzungszeile()) }
                        if !eigene, let vorhandene, verwaltung.istAngepasst(vorhandene.id) {
                            Button("Vorgabe wiederherstellen") {
                                if let vorgabe = verwaltung.vorgabe(vorhandene.id) {
                                    zeiten = vorgabe.map(Sitzungszeile.init)
                                }
                            }
                        }
                        Text("Feiertage der Börse gelten weiter. Für Sitzungen über Mitternacht das Ende auf den Folgetag setzen. Mehrere Sitzungen für Mittagspausen.")
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                        if (vorhandene?.verfuegbareSitzungsarten.count ?? 1) > 1 {
                            Text("Diese Börse hat Zusatzsitzungen (vor- oder nachbörslich, Nacht). Eigene Zeiten ersetzen alle Sitzungen; die Art je Zeile entscheidet, ob die Schalter in der Liste sie zuschalten.")
                                .font(Schrift.beschriftung)
                                .foregroundStyle(thema.textSchwach)
                        }
                    }
                }
                if let vorhandene, !verwaltung.auswahl.kalender.isEmpty {
                    Section("Zusätzliche Feiertagskalender") {
                        ForEach(verwaltung.auswahl.kalender) { kalender in
                            Toggle(kalender.name, isOn: Binding(
                                get: { verwaltung.kalender(fuer: vorhandene.id).contains(kalender.id) },
                                set: { verwaltung.ordneKalender(kalender.id, boerse: vorhandene.id, zu: $0) }))
                        }
                    }
                }
                if eigene, let vorhandene {
                    Section {
                        Button("Börse löschen", role: .destructive) {
                            verwaltung.loescheEigene(vorhandene.id)
                            schliessen()
                        }
                    }
                }
                if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(thema.verlust)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(vorhandene?.name ?? String(localized: "Eigene Börse"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { sichern() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    private func sichern() {
        let verwaltung = modell.boersen
        do {
            let handelszeiten = try zeiten.map { try $0.handelszeit() }
            if let vorhandene, !verwaltung.istEigene(vorhandene.id) {
                verwaltung.setzeZeiten(vorhandene.id, handelszeiten)
            } else {
                let bezeichnung = name.trimmingCharacters(in: .whitespaces)
                guard !bezeichnung.isEmpty else {
                    fehler = String(localized: "Name fehlt.")
                    return
                }
                var boerse: Boerse
                if let vorhandene {
                    boerse = vorhandene
                    boerse.name = bezeichnung
                    boerse.zeitzone = zeitzone
                    boerse.handelszeiten = handelszeiten
                    try boerse.pruefe()
                } else {
                    boerse = try Boerse(id: verwaltung.freieKennung(aus: bezeichnung), name: bezeichnung,
                                        zeitzone: zeitzone, handelszeiten: handelszeiten,
                                        stand: Kalendertag(.now, in: .current),
                                        hinweise: [String(localized: "In der App angelegt, ohne Feiertage.")])
                }
                verwaltung.speichereEigene(boerse)
            }
            if let problem = verwaltung.fehler {
                fehler = problem
            } else {
                schliessen()
            }
        } catch {
            fehler = Boersenverwaltung.text(error)
        }
    }
}

/// Eine Zeile Handelszeit: sieben Tagesknöpfe, Beginn, Ende, Ende nach Tagen, Entfernen.
private struct SitzungsEditor: View {
    @Binding var zeile: Sitzungszeile
    let entfernen: () -> Void
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            HStack(spacing: Abstand.raster) {
                ForEach(Wochentag.allCases, id: \.self) { tag in
                    Toggle(tag.rawValue, isOn: tagBinding(tag))
                        .toggleStyle(.button)
                }
                Spacer()
                Button(role: .destructive, action: entfernen) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Sitzung entfernen")
                .accessibilityLabel(Text("Sitzung entfernen"))
            }
            HStack(spacing: Abstand.kachelAbstand) {
                DatePicker("Beginn", selection: $zeile.beginn, displayedComponents: .hourAndMinute)
                DatePicker("Ende", selection: $zeile.ende, displayedComponents: .hourAndMinute)
                Stepper(endeText, value: $zeile.endeNachTagen, in: 0...6)
            }
            .environment(\.timeZone, Sitzungszeile.utc.timeZone)
            HStack(spacing: Abstand.kachelAbstand) {
                Picker("Art", selection: $zeile.art) {
                    ForEach(Sitzungsart.allCases, id: \.self) { art in
                        Text(verbatim: art.titel).tag(art)
                    }
                }
                .pickerStyle(.menu)
                if let ab = zeile.gueltigAb {
                    Text(verbatim: String(localized: "gilt ab \(Boersenformat.tag(ab))"))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }
        .padding(.vertical, Abstand.raster)
    }

    private var endeText: String {
        switch zeile.endeNachTagen {
        case 0: String(localized: "Ende am selben Tag")
        case 1: String(localized: "Ende am Folgetag")
        default: String(localized: "Ende nach \(zeile.endeNachTagen) Tagen")
        }
    }

    private func tagBinding(_ tag: Wochentag) -> Binding<Bool> {
        Binding(get: { zeile.tage.contains(tag) },
                set: { an in if an { zeile.tage.insert(tag) } else { zeile.tage.remove(tag) } })
    }
}

/// Zeitzone als IANA-Name mit Vorschlägen; geprüft wird gegen `TimeZone(identifier:)`.
private struct ZeitzonenFeld: View {
    @Binding var zeitzone: String
    @Environment(\.thema) private var thema

    static let haeufig = ["Europe/Berlin", "Europe/London", "Europe/Zurich", "America/New_York", "America/Chicago",
                          "Asia/Tokyo", "Asia/Hong_Kong", "Asia/Shanghai", "Asia/Singapore", "Australia/Sydney", "UTC"]

    var body: some View {
        HStack {
            TextField("Zeitzone (IANA-Name, z. B. Europe/Berlin)", text: $zeitzone)
                .autocorrectionDisabled()
            Menu {
                ForEach(Self.haeufig, id: \.self) { zone in
                    Button(zone) { zeitzone = zone }
                }
            } label: {
                Image(systemName: "globe")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .help("Häufige Zeitzonen")
            .accessibilityLabel(Text("Häufige Zeitzonen"))
        }
        if TimeZone(identifier: zeitzone) == nil {
            Text("Unbekannte Zeitzone.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.verlust)
        }
    }
}

/// Formular für einen eigenen Feiertagskalender: Name, Land, Feiertage mit Datum und Name.
private struct KalenderFormular: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen
    @State private var name = ""
    @State private var land = ""
    @State private var tage: [Feiertagszeile] = [Feiertagszeile()]
    @State private var fehler: String?

    private struct Feiertagszeile: Identifiable {
        let id = UUID()
        var datum = Calendar.current.startOfDay(for: .now)
        var name = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kalender") {
                    TextField("Name, z. B. Feiertage Schweiz", text: $name)
                    TextField("Land nach ISO 3166, z. B. CH (optional)", text: $land)
                }
                Section("Feiertage") {
                    ForEach($tage) { $zeile in
                        HStack(spacing: Abstand.kachelAbstand) {
                            DatePicker("Datum", selection: $zeile.datum, displayedComponents: .date)
                                .labelsHidden()
                            TextField("Name des Feiertags", text: $zeile.name)
                            Button(role: .destructive) {
                                tage.removeAll { $0.id == zeile.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Feiertag entfernen")
                            .accessibilityLabel(Text("Feiertag entfernen"))
                        }
                    }
                    Button("Feiertag hinzufügen", systemImage: "plus") { tage.append(Feiertagszeile()) }
                    Text("Zeilen ohne Namen werden übergangen. Verkürzte Tage und Quellen lassen sich über eine Kalender-Datei (JSON) mitgeben.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(thema.verlust)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Feiertagskalender")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { sichern() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 440)
        #endif
    }

    private func sichern() {
        let verwaltung = modell.boersen
        let bezeichnung = name.trimmingCharacters(in: .whitespaces)
        guard !bezeichnung.isEmpty else {
            fehler = String(localized: "Name fehlt.")
            return
        }
        let feiertage = tage.compactMap { zeile -> Feiertag? in
            let feiertagsname = zeile.name.trimmingCharacters(in: .whitespaces)
            guard !feiertagsname.isEmpty else { return nil }
            return Feiertag(datum: Kalendertag(zeile.datum, in: .current), name: feiertagsname)
        }
        guard !feiertage.isEmpty else {
            fehler = String(localized: "Mindestens ein Feiertag mit Namen.")
            return
        }
        let laenderkuerzel = land.trimmingCharacters(in: .whitespaces).uppercased()
        do {
            let kalender = try Feiertagskalender(
                id: verwaltung.freieKalenderKennung(aus: bezeichnung), name: bezeichnung,
                land: laenderkuerzel.isEmpty ? nil : laenderkuerzel,
                feiertage: feiertage.sorted { $0.datum < $1.datum },
                datenGueltigBis: feiertage.map(\.datum).max(),
                stand: Kalendertag(.now, in: .current),
                hinweise: [String(localized: "In der App angelegt.")])
            verwaltung.speichereKalender(kalender)
            if let problem = verwaltung.fehler {
                fehler = problem
            } else {
                schliessen()
            }
        } catch {
            fehler = Boersenverwaltung.text(error)
        }
    }
}
