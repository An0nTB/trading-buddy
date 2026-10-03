import SwiftUI
import TradingClock

/// Börsenuhr (Stand-Doc 15, Wunsch Tim 01.10.2026): je Börse offen oder geschlossen, nächste Öffnung oder
/// Schließung, Feiertag und verkürzter Tag, dazu der heutige Handelstag als Balken in der Ortszeit des Nutzers.
/// Die Seite ist nicht in AP10 gezeichnet; Aufbau wie die Übersicht (Kopfzeile, Karte, Hinweise).
struct BoersenuhrView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var verwalten = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { kontext in
            let jetzt = kontext.date
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    Kopfzeile("Börsenuhr", untertitel: untertitel(jetzt)) {
                        Button("Börsen verwalten", systemImage: "slider.horizontal.3") { verwalten = true }
                    }
                    if let uhr = modell.boersen.uhr, !uhr.boersen.isEmpty {
                        BoersenKarte(uhr: uhr, jetzt: jetzt)
                        BoersenHinweise(uhr: uhr)
                    } else {
                        ContentUnavailableView("Börsenuhr nicht verfügbar", systemImage: "clock.badge.exclamationmark",
                                               description: Text(verbatim: modell.boersen.fehler ?? ""))
                    }
                }
                .padding(Abstand.seitenrand)
            }
        }
        .sheet(isPresented: $verwalten) { BoersenVerwaltenBlatt() }
    }

    private func untertitel(_ jetzt: Date) -> String {
        guard let uhr = modell.boersen.uhr else { return "" }
        let offen = uhr.boersen.filter { $0.istOffen(jetzt) }.count
        return String(localized: "\(offen) von \(uhr.boersen.count) offen · deine Zeit \(Format.uhrzeit(jetzt)) (\(Boersenformat.ort(.current)))")
    }
}

/// Spaltenbreiten der Börsenliste am Mac und iPad.
private enum Spalten {
    static let name: CGFloat = 170
    static let status: CGFloat = 270
}

/// Alle gewählten Börsen untereinander: Zustand, Tagesbalken, nächster Wechsel.
private struct BoersenKarte: View {
    let uhr: Boersenuhr
    let jetzt: Date
    @Environment(\.thema) private var thema
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif

    /// Am iPhone (schmale Breite) stapeln sich die Spalten einer Börse untereinander.
    private var kompakt: Bool {
        #if os(iOS)
        breite == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Karte(verbatim: String(localized: "Heute, \(Format.datum(jetzt))")) {
            if !kompakt {
                Zeitachse()
            }
            ForEach(uhr.boersen) { boerse in
                Divider()
                BoersenZeile(boerse: boerse, status: boerse.status(jetzt), jetzt: jetzt, kompakt: kompakt)
            }
        }
    }
}

/// Stundenmarken über den Tagesbalken, auf die Balkenspalte ausgerichtet.
private struct Zeitachse: View {
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(spacing: Abstand.kachelAbstand) {
            Text("Börse")
                .frame(width: Spalten.name, alignment: .leading)
            GeometryReader { geo in
                ForEach([0, 6, 12, 18, 24], id: \.self) { stunde in
                    Text(verbatim: String(format: "%02d", stunde))
                        .monospacedDigit()
                        .position(x: min(max(geo.size.width * CGFloat(stunde) / 24, 10), geo.size.width - 10),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 16)
            Text("Nächster Wechsel")
                .frame(width: Spalten.status, alignment: .leading)
        }
        .font(Schrift.beschriftung)
        .foregroundStyle(thema.textSchwach)
    }
}

/// Eine Börse: Punkt und Name mit Ortszeit, Tagesbalken, Zustand als Kapseln und der nächste Wechsel.
private struct BoersenZeile: View {
    let boerse: Boerse
    let status: Boersenstatus
    let jetzt: Date
    let kompakt: Bool
    @Environment(\.thema) private var thema

    var body: some View {
        if kompakt {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                HStack(alignment: .top) {
                    name
                    Spacer()
                    zustand
                }
                Tagesbalken(boerse: boerse, jetzt: jetzt)
                wechsel
            }
            .padding(.vertical, Abstand.raster)
        } else {
            HStack(alignment: .center, spacing: Abstand.kachelAbstand) {
                name
                    .frame(width: Spalten.name, alignment: .leading)
                Tagesbalken(boerse: boerse, jetzt: jetzt)
                VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                    zustand
                    wechsel
                }
                .frame(width: Spalten.status, alignment: .leading)
            }
            .padding(.vertical, Abstand.raster)
        }
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: Abstand.raster / 2) {
            HStack(spacing: Abstand.raster) {
                Circle()
                    .fill(status.offen ? thema.gewinn : thema.textSchwach)
                    .frame(width: 8, height: 8)
                Text(verbatim: boerse.name)
                    .foregroundStyle(thema.text)
                    .lineLimit(1)
            }
            Text(verbatim: "\(Boersenformat.ort(boerse.timeZone)) · \(Boersenformat.uhrzeit(jetzt, in: boerse.timeZone))")
                .font(Schrift.beschriftung)
                .monospacedDigit()
                .foregroundStyle(thema.textSchwach)
                .lineLimit(1)
        }
        .help(boerse.hinweise.map(\.uebersetzt).joined(separator: " "))
    }

    private var zustand: some View {
        HStack(spacing: Abstand.raster) {
            Kapsel(text: status.offen ? String(localized: "Offen") : String(localized: "Geschlossen"), betont: status.offen)
            if status.offen, let art = boerse.sitzungsart(bei: jetzt), art != .kern {
                Kapsel(text: art.titel)
            }
            if let feiertag = status.feiertag {
                Kapsel(text: String(localized: "Feiertag: \(feiertag.uebersetzt)"))
            } else if let verkuerzt = status.verkuerzt {
                Kapsel(text: String(localized: "Verkürzt: \(verkuerzt.uebersetzt)"))
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var wechsel: some View {
        Text(verbatim: wechselText)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            .lineLimit(2)
    }

    private var wechselText: String {
        if boerse.durchgehend {
            return String(localized: "Rund um die Uhr, auch am Wochenende")
        }
        guard let wechsel = status.naechsterWechsel else {
            return String(localized: "Keine Sitzung in den nächsten 400 Tagen")
        }
        let wann = Boersenformat.wann(wechsel, ab: jetzt)
        let text = status.offen ? String(localized: "Schließt \(wann)") : String(localized: "Öffnet \(wann)")
        guard status.datenGueltig else {
            return text + String(localized: " · Feiertage nur bis \(Boersenformat.tag(boerse.datenGueltigBis)) gepflegt")
        }
        return text
    }
}

/// Der heutige Tag in der Ortszeit des Nutzers als Balken: Sitzungen gefüllt, der Strich ist jetzt.
/// Diagrammregeln aus Doc 10: Balken höchstens 24 pt, Datenende 4 pt gerundet.
private struct Tagesbalken: View {
    let boerse: Boerse
    let jetzt: Date
    @Environment(\.thema) private var thema

    var body: some View {
        let kalender = Calendar.current
        let anfang = kalender.startOfDay(for: jetzt)
        let ende = kalender.date(byAdding: .day, value: 1, to: anfang) ?? anfang.addingTimeInterval(86_400)
        let sitzungen = boerse.sitzungen(von: anfang, bis: ende)
        let arten = Array(Sitzungsart.allCases.filter(boerse.sitzungsarten.contains).reversed())
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Abstand.radiusKnopf / 2)
                    .fill(thema.flaeche2)
                // Zusatzsitzungen (vor-, nachbörslich, Nacht) getönt, der Kernhandel darüber im Akzent.
                ForEach(arten, id: \.self) { art in
                    ForEach(Array(sitzungenDerArt(art, von: anfang, bis: ende).enumerated()), id: \.offset) { eintrag in
                        let von = position(eintrag.element.beginn, anfang: anfang, ende: ende, breite: geo.size.width)
                        let bis = position(eintrag.element.ende, anfang: anfang, ende: ende, breite: geo.size.width)
                        // Nebenzeiten getönt mit 1,5-pt-Rand im Akzent: der Ton allein lag auf Fläche 2 bei 1,3 bis 1,5:1 (Doc 55 J26).
                        RoundedRectangle(cornerRadius: Diagramm.balkenEndeRadius)
                            .fill(art == .kern ? thema.akzent : thema.akzentTint)
                            .overlay(RoundedRectangle(cornerRadius: Diagramm.balkenEndeRadius)
                                .strokeBorder(thema.akzent, lineWidth: art == .kern ? 0 : 1.5))
                            .frame(width: max(bis - von, 2))
                            .offset(x: von)
                    }
                }
                Rectangle()
                    .fill(thema.text)
                    .frame(width: 2)
                    .offset(x: position(jetzt, anfang: anfang, ende: ende, breite: geo.size.width) - 1)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(Text("Handelszeiten heute"))
        .accessibilityValue(Text(verbatim: Boersenformat.sitzungen(sitzungen)))
    }

    private func sitzungenDerArt(_ art: Sitzungsart, von: Date, bis: Date) -> [Sitzung] {
        boerse.mitSitzungsarten([art]).sitzungen(von: von, bis: bis)
    }

    private func position(_ zeitpunkt: Date, anfang: Date, ende: Date, breite: CGFloat) -> CGFloat {
        let anteil = zeitpunkt.timeIntervalSince(anfang) / ende.timeIntervalSince(anfang)
        return breite * CGFloat(min(max(anteil, 0), 1))
    }
}

/// Erklärung unter der Liste: was der Balken zeigt und wie weit die Feiertage gepflegt sind.
private struct BoersenHinweise: View {
    let uhr: Boersenuhr
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text("Balken: Handelszeiten heute in deiner Ortszeit, Strich: jetzt. Nur der fortlaufende Handel, ohne Auktionen und ohne vor- und nachbörslichen Handel.")
            if let bis = uhr.boersen.compactMap(\.datenGueltigBis).min() {
                Text("Feiertage und verkürzte Tage sind bis \(Boersenformat.tag(bis)) gepflegt. Forex ohne Feiertage und Krypto ohne Wartungspausen sind Annahmen.")
            }
        }
        .font(Schrift.beschriftung)
        .foregroundStyle(thema.textSchwach)
    }
}

/// Blatt „Börsen verwalten“ über der Börsenuhr; derselbe Inhalt steht am Mac in den Einstellungen.
struct BoersenVerwaltenBlatt: View {
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        NavigationStack {
            Form { BoersenEinstellungen() }
                .formStyle(.grouped)
                .navigationTitle("Börsen verwalten")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { schliessen() }
                    }
                }
        }
        #if os(macOS)
        .onExitCommand { schliessen() } // Esc schließt (Doc 55 J16)
        .frame(minWidth: 700, minHeight: 560)
        #endif
    }
}

/// Zeiten und Orte für die Börsenuhr.
enum Boersenformat {
    /// Uhrzeit in einer anderen Zeitzone, z. B. die Ortszeit der Börse.
    static func uhrzeit(_ zeitpunkt: Date, in zone: TimeZone) -> String {
        zeitpunkt.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
    }

    /// Ortsname aus dem IANA-Namen: „Europe/Berlin“ → „Berlin“, „America/New_York“ → „New York“.
    static func ort(_ zone: TimeZone) -> String {
        let letzter = zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier
        return letzter.replacingOccurrences(of: "_", with: " ")
    }

    /// „heute um 17:30 (in 2 Std., 14 Min.)“, „morgen um 09:00 (…)“, sonst „Mo, 06.10., 09:00 (…)“.
    static func wann(_ zeitpunkt: Date, ab jetzt: Date) -> String {
        let kalender = Calendar.current
        let uhr = Format.uhrzeit(zeitpunkt)
        let tag: String
        if kalender.isDateInToday(zeitpunkt) {
            tag = String(localized: "heute um \(uhr)")
        } else if kalender.isDateInTomorrow(zeitpunkt) {
            tag = String(localized: "morgen um \(uhr)")
        } else {
            tag = zeitpunkt.formatted(.dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits)) + ", " + uhr
        }
        return String(localized: "\(tag) (in \(Format.dauer(zeitpunkt.timeIntervalSince(jetzt))))")
    }

    static func tag(_ tag: Kalendertag?) -> String {
        guard let tag else { return "–" }
        return String(format: "%02d.%02d.%04d", tag.tag, tag.monat, tag.jahr)
    }

    /// Sitzungen als Text für die Bedienungshilfen: „09:00 bis 17:30“.
    static func sitzungen(_ sitzungen: [Sitzung]) -> String {
        guard !sitzungen.isEmpty else { return String(localized: "heute geschlossen") }
        return sitzungen.map { "\(Format.uhrzeit($0.beginn)) bis \(Format.uhrzeit($0.ende))" }.joined(separator: ", ")
    }
}

/// Handelszeiten als Text für Listen: „Mo–Fr 09:00–17:30“, „rund um die Uhr“.
enum Handelszeitformat {
    static func zusammenfassung(_ boerse: Boerse) -> String {
        if boerse.durchgehend { return String(localized: "rund um die Uhr") }
        let aktiv = boerse.handelszeiten.filter { boerse.sitzungsarten.contains($0.art) }
        return aktiv.map { zeit in
            zeit.art == .kern ? text(zeit) : zeit.art.titel.lowercased() + " " + text(zeit)
        }.joined(separator: ", ")
    }

    static func text(_ zeit: Handelszeit) -> String {
        var text = "\(tage(zeit.tage)) \(zeit.beginn)–\(zeit.ende)"
        if zeit.endeNachTagen == 1 {
            text += String(localized: " (Ende am Folgetag)")
        } else if zeit.endeNachTagen > 1 {
            text += String(localized: " (Ende nach \(zeit.endeNachTagen) Tagen)")
        }
        return text
    }

    /// „Mo–Fr“ für zusammenhängende Tage ab drei Tagen, sonst „Mo, Mi, Fr“.
    static func tage(_ tage: [Wochentag]) -> String {
        let alle = Wochentag.allCases
        let indizes = tage.compactMap { alle.firstIndex(of: $0) }.sorted()
        guard let erster = indizes.first, let letzter = indizes.last else { return "–" }
        if indizes.count > 2, indizes.count == letzter - erster + 1 {
            return "\(alle[erster].rawValue)–\(alle[letzter].rawValue)"
        }
        return indizes.map { alle[$0].rawValue }.joined(separator: ", ")
    }
}

extension Sitzungsart {
    /// Name in der Oberfläche (Entscheidung U8: Kernhandel plus zuschaltbare Sitzungen).
    var titel: String {
        switch self {
        case .kern: String(localized: "Kernhandel")
        case .vorboerslich: String(localized: "Vorbörslich")
        case .nachboerslich: String(localized: "Nachbörslich")
        case .nacht: String(localized: "Nacht")
        }
    }
}
