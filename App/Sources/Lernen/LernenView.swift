import SwiftUI

/// Was links gewählt ist: der Lernpfad oder ein Baustein (Kapitel, wahlweise ab einem Abschnitt).
enum Lernauswahl: Hashable, Identifiable {
    case lernpfad
    case baustein(Lernbaustein)

    var id: String {
        switch self {
        case .lernpfad: "lernpfad"
        case .baustein(let baustein): baustein.id
        }
    }

    var kapitel: Lernkapitel {
        switch self {
        case .lernpfad: .lernpfad
        case .baustein(let baustein): Lernkapitel.kapitel(baustein.kapitel) ?? .lernpfad
        }
    }

    var abschnitt: Int? {
        if case .baustein(let baustein) = self { return baustein.abschnitt }
        return nil
    }
}

/// Seite „Lernen“ (Recherche R5, Lernpfad 12): Stufen-Schalter oben, links die Bausteine der Stufe mit
/// Erledigt-Haken, rechts das Kapitel. Fortgeschritten zeigt auch die Grundlagen-Abschnitte, Profi alles.
/// Am iPhone wird aus der linken Liste eine Seite, das Kapitel öffnet sich darüber.
/// Lerntexte sachlich, keine Anlageberatung (Hinweis unter jedem Kapitel); Inhalte in App/Resources/Lernen.
struct LernenView: View {
    @AppStorage("lernen.stufe") private var stufe = Lernstufe.grundlagen
    @State private var auswahl = Lernauswahl.lernpfad
    @State private var fortschritt = Lernfortschritt()
    @Environment(\.thema) private var thema
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if breite == .compact {
                kompakt
            } else {
                breit
            }
            #else
            breit
            #endif
        }
        .environment(fortschritt)
    }

    /// Mac und iPad: Liste links, Kapitel rechts.
    private var breit: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Kopfzeile("Lernen", untertitel: String(localized: "Trading-Wissen in drei Stufen · Stand 01.10.2026")) {
                stufenwahl
                    .frame(maxWidth: 360)
            }
            HStack(alignment: .top, spacing: Abstand.seitenrand) {
                BausteinListe(stufe: stufe, auswahl: $auswahl)
                    .frame(width: 280)
                KapitelSeite(auswahl: auswahl, stufe: stufe) { stufe = .profi }
            }
        }
        .padding(Abstand.seitenrand)
    }

    #if os(iOS)
    /// iPhone: Stufe wählen, Bausteine als Liste, Kapitel als eigene Seite.
    private var kompakt: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Kopfzeile("Lernen")
                .padding(.horizontal, Abstand.seitenrand)
            stufenwahl
                .padding(.horizontal, Abstand.seitenrand)
            BausteinListeKompakt(stufe: stufe)
        }
        .navigationDestination(for: Lernauswahl.self) { ziel in
            KapitelSeite(auswahl: ziel, stufe: stufe) { stufe = .profi }
                .padding(.horizontal, Abstand.seitenrand)
                .background(thema.grund)
                .environment(fortschritt) // die Zielseite liegt im Stapel, nicht unter dieser Ansicht
                .navigationTitle(Text(verbatim: ziel.kapitel.titel))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    #endif

    private var stufenwahl: some View {
        Picker("Stufe", selection: $stufe) {
            ForEach(Lernstufe.allCases) { stufe in
                Text(stufe.titel).tag(stufe)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Mac und iPad: Lernpfad oben, dann die Bausteine der Stufe als Knöpfe (eigene Zeilen statt List,
/// damit Auswahl und Haken die Farbwelt tragen).
struct BausteinListe: View {
    let stufe: Lernstufe
    @Binding var auswahl: Lernauswahl
    @Environment(Lernfortschritt.self) private var fortschritt
    @Environment(\.thema) private var thema

    var body: some View {
        let bausteine = Lernbaustein.fuer(stufe)
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                zeile(.lernpfad) {
                    Label("Lernpfad: Stufen und Reihenfolge", systemImage: "map")
                        .font(Schrift.fliesstext)
                        .foregroundStyle(auswahl == .lernpfad ? thema.akzent : thema.text)
                }
                (Text(stufe.titel) + Text(verbatim: " · \(fortschritt.anzahlErledigt(stufe)) von \(bausteine.count) erledigt"))
                    .font(Schrift.beschriftung)
                    .textCase(.uppercase)
                    .foregroundStyle(thema.textSchwach)
                    .padding(.horizontal, Abstand.kachelAbstand)
                    .padding(.top, Abstand.kachelAbstand)
                    .padding(.bottom, Abstand.raster)
                ForEach(bausteine) { baustein in
                    zeile(.baustein(baustein)) {
                        BausteinZeile(baustein: baustein, gewaehlt: auswahl == .baustein(baustein))
                    }
                }
            }
            .padding(Abstand.raster + 2)
        }
        .background(thema.flaeche, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
        .overlay(RoundedRectangle(cornerRadius: Abstand.radiusKachel).strokeBorder(thema.kachelRand, lineWidth: 1))
    }

    private func zeile<Inhalt: View>(_ ziel: Lernauswahl, @ViewBuilder inhalt: () -> Inhalt) -> some View {
        Button {
            auswahl = ziel
        } label: {
            inhalt()
                .padding(.horizontal, Abstand.kachelAbstand)
                .padding(.vertical, Abstand.raster + 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(auswahl == ziel ? thema.akzentTint : .clear,
                            in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
                .contentShape(RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
        }
        .buttonStyle(.plain)
    }
}

#if os(iOS)
/// iPhone: dieselben Einträge als List mit Navigation.
struct BausteinListeKompakt: View {
    let stufe: Lernstufe
    @Environment(Lernfortschritt.self) private var fortschritt
    @Environment(\.thema) private var thema

    var body: some View {
        let bausteine = Lernbaustein.fuer(stufe)
        List {
            NavigationLink(value: Lernauswahl.lernpfad) {
                Label("Lernpfad: Stufen und Reihenfolge", systemImage: "map")
            }
            Section {
                ForEach(bausteine) { baustein in
                    NavigationLink(value: Lernauswahl.baustein(baustein)) {
                        BausteinZeile(baustein: baustein, gewaehlt: false)
                    }
                }
            } header: {
                Text(stufe.titel) + Text(verbatim: " · \(fortschritt.anzahlErledigt(stufe)) von \(bausteine.count) erledigt")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}
#endif

/// Eine Zeile der Bausteinliste: Titel, Kapitel darunter, rechts der Erledigt-Haken.
struct BausteinZeile: View {
    let baustein: Lernbaustein
    let gewaehlt: Bool
    @Environment(Lernfortschritt.self) private var fortschritt
    @Environment(\.thema) private var thema

    var body: some View {
        let kapitel = Lernkapitel.kapitel(baustein.kapitel)
        HStack(spacing: Abstand.raster * 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: baustein.titel)
                    .font(Schrift.fliesstext.weight(.medium))
                    .foregroundStyle(gewaehlt ? thema.akzent : thema.text)
                Text(verbatim: "Kapitel \(baustein.kapitel) · \(kapitel?.titel ?? "")")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: fortschritt.istErledigt(baustein) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(fortschritt.istErledigt(baustein) ? thema.akzent : thema.linie)
                .accessibilityLabel(fortschritt.istErledigt(baustein) ? Text("Erledigt") : Text("Offen"))
        }
        .help(Text(verbatim: kapitel?.kurz ?? ""))
    }
}

/// Rechte Seite: Kapiteltitel, Stufen-Marken, der Text der gewählten Stufe, Hinweis auf ausgeblendete
/// Abschnitte, Selbsttest, Quellen und Pflichthinweis. Springt beim Wechsel zum Abschnitt des Bausteins.
struct KapitelSeite: View {
    let auswahl: Lernauswahl
    let stufe: Lernstufe
    let zeigeProfi: () -> Void
    @State private var bloecke: [Markdownblock] = []
    @State private var geladen = false
    @Environment(\.thema) private var thema

    var body: some View {
        let kapitel = auswahl.kapitel
        let seite = Seitenblock.seite(bloecke, stufe: stufe, mitSelbsttest: kapitel.nummer > 0)
        ScrollViewReader { leser in
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    kopf(kapitel)
                        .id("kopf")
                    if geladen, bloecke.isEmpty {
                        Text("Kapitel nicht gefunden. Die Datei fehlt im App-Paket.")
                            .font(Schrift.fliesstext)
                            .foregroundStyle(thema.textSchwach)
                    }
                    ForEach(seite) { block in
                        switch block {
                        case .markdown(let block):
                            MarkdownBlockView(block: block)
                        case .ausgeblendet(let titel, let ab):
                            AusgeblendetHinweis(titel: titel, ab: ab, zeigeProfi: zeigeProfi)
                        case .selbsttest:
                            SelbsttestKarte(kapitel: kapitel.nummer)
                        }
                    }
                    LernenPflichthinweis()
                        .padding(.top, Abstand.raster)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Abstand.seitenrand)
            }
            .textSelection(.enabled)
            .task(id: auswahl) {
                bloecke = kapitel.markdown().map(MarkdownParser.bloecke) ?? []
                geladen = true
                // Erst nach dem Layout springen, sonst kennt der Leser den Anker noch nicht.
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation {
                    leser.scrollTo(auswahl.abschnitt.map { "abschnitt-\($0)" } ?? "kopf", anchor: .top)
                }
            }
        }
    }

    private func kopf(_ kapitel: Lernkapitel) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: kapitel.titel)
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
            HStack(spacing: Abstand.raster * 2) {
                if kapitel.nummer > 0 {
                    Text("Kapitel \(kapitel.nummer)")
                }
                ForEach(kapitel.stufen) { StufenMarke(stufe: $0) }
                Text("Recherche R5, Stand 01.10.2026")
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        }
    }
}

/// „Ab Stufe Profi: 7. Kelly …“ mit Knopf, der die Stufe hochschaltet.
struct AusgeblendetHinweis: View {
    let titel: [String]
    let ab: Lernstufe
    let zeigeProfi: () -> Void
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
            (Text("Ab Stufe ") + Text(ab.titel) + Text(verbatim: ": \(titel.joined(separator: ", "))"))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: zeigeProfi) {
                Text(ab.titel) + Text(" anzeigen")
            }
            .buttonStyle(.plain)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.akzent)
        }
        .padding(Abstand.kachelInnen)
        .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
    }
}

/// Erfolgskriterien des Kapitels (Lernpfad) zum Abhaken; der Stand bleibt auf dem Gerät (Lernfortschritt).
struct SelbsttestKarte: View {
    let kapitel: Int
    @Environment(Lernfortschritt.self) private var fortschritt
    @Environment(\.thema) private var thema

    var body: some View {
        let bausteine = Lernbaustein.fuer(kapitel: kapitel)
        if !bausteine.isEmpty {
            Karte("Selbsttest") {
                ForEach(bausteine) { baustein in
                    Button {
                        fortschritt.setze(baustein, erledigt: !fortschritt.istErledigt(baustein))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
                            Image(systemName: fortschritt.istErledigt(baustein) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(fortschritt.istErledigt(baustein) ? thema.akzent : thema.textSchwach)
                            Text(verbatim: baustein.erfolgskriterium)
                                .font(Schrift.fliesstext)
                                .foregroundStyle(thema.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            StufenMarke(stufe: baustein.stufe)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(fortschritt.istErledigt(baustein) ? Text("Erledigt") : Text("Offen"))
                }
                Text("Erfolgskriterien aus dem Lernpfad. Der Haken bleibt auf diesem Gerät gespeichert.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }
}

/// Pflichthinweis unter jedem Kapitel (R5 Kapitel 13, Abschnitt 6).
struct LernenPflichthinweis: View {
    @Environment(\.thema) private var thema

    var body: some View {
        Text("Keine Anlageberatung. Die Kapitel ordnen ein und erklären; sie empfehlen kein Produkt und keinen Trade.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }
}
