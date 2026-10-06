import SwiftUI
import TradingAssistant
import TradingCore

// Tagesseite (P7, Doc 18 F4, Entwurf design/Tagesseite_Entwurf.png vom 02.10.2026): Plan vor dem Handel,
// Rückblick, Verfassung, Trades des Tages, Screenshots, verpasste Trades, dazu die Karten Planwirkung
// und Verpasste Trades. Notiz und verpasste Trades gelten für alle Konten, Trades für das gewählte Konto.

/// Seite „Tag“: speichert im Journal (Migration v8, AP9). Nur wenn die Datenbank nicht geöffnet
/// werden konnte, arbeitet sie flüchtig und sagt das.
struct TagView: View {
    @Environment(AppModell.self) private var modell
    @State private var ablage: (any TagAblage)?

    var body: some View {
        Group {
            if let ablage {
                TagSeite(ablage: ablage)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard ablage == nil else { return }
            ablage = modell.journal.map { JournalTagAblage($0) } ?? FluechtigeTagAblage.gemeinsam
            raeumeBilderAuf()
        }
    }

    /// Einmal je App-Start: Bilddateien ohne Verweis entfernen (Doc 28, offener Punkt; Tim 02.10.2026).
    private func raeumeBilderAuf() {
        guard !Self.aufgeraeumt, let journal = modell.journal,
              let behalten = try? journal.bilddateien() else { return }
        Self.aufgeraeumt = true
        _ = Bilderordner.raeumeAuf(behalten: behalten)
    }

    @MainActor private static var aufgeraeumt = false
}

/// Inhalt der Tagesseite gegen eine beliebige Ablage.
struct TagSeite: View {
    @Environment(AppModell.self) private var modell
    @State private var tagModell: TagModell
    /// Stand von `tagModell.aenderungen`, der schon im Export steht.
    @State private var exportiert = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif

    init(ablage: any TagAblage) {
        _tagModell = State(initialValue: TagModell(ablage: ablage, zeitzone: .current))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                TagKopf(tagModell: tagModell)
                if !tagModell.ablage.dauerhaft {
                    Label("Die Datenbank ließ sich nicht öffnen. Einträge auf dieser Seite gehen beim Beenden der App verloren.",
                          systemImage: "exclamationmark.circle")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(.secondary)
                }
                if zweiSpalten {
                    // Beide Spalten gleich breit, ohne Mindestbreite (Regeln zum Startabsturz).
                    // Vorher drückte layoutPriority(1) die rechte Spalte zusammen (Tim 02.10.2026).
                    HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
                        linkeSpalte
                            .frame(maxWidth: .infinity)
                        rechteSpalte
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    linkeSpalte
                    rechteSpalte
                }
                TagAuswertungen(tagModell: tagModell)
                Pflichthinweis()
            }
            .padding(Abstand.seitenrand)
        }
        .task(id: tagModell.aenderungen) { await exportiereNachPause() }
        // Sprung aus dem Ergebnis-Kalender: den gewählten Tag zeigen und den Wunsch abräumen.
        .onAppear { springe(zu: modell.tagSprung) }
        .onChange(of: modell.tagSprung) { _, neu in springe(zu: neu) }
        .onDisappear {
            tagModell.sichere()
            exportiereGeaendert()
        }
        #if os(macOS)
        // ⌘Q ruft onDisappear nicht auf; ohne das fehlen die letzten bis zu 2 s Text (Beta-Punkt 12).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            tagModell.sichere()
            exportiereGeaendert()
        }
        #endif
        .alert("Fehler", isPresented: fehlerSichtbar) {
            Button("OK") { tagModell.fehler = nil }
        } message: {
            Text(verbatim: tagModell.fehler ?? "")
        }
    }

    private var linkeSpalte: some View {
        VStack(spacing: Abstand.kachelAbstand) {
            PlanKarte(tagModell: tagModell)
            RueckblickKarte(tagModell: tagModell)
            VerfassungKarte(tagModell: tagModell)
        }
    }

    private var rechteSpalte: some View {
        VStack(spacing: Abstand.kachelAbstand) {
            TagTradesKarte(trades: tradesDesTages)
            TagBilderKarte(tagModell: tagModell)
            VerpassteListeKarte(tagModell: tagModell)
        }
    }

    private var zweiSpalten: Bool {
        #if os(iOS)
        breite != .compact
        #else
        true
        #endif
    }

    /// Am gewählten Tag eröffnete Trades des Kontos, nach Eröffnung sortiert.
    private var tradesDesTages: [Trade] {
        let tag = tagModell.tag
        let zeitzone = tagModell.zeitzone
        // Eröffnungstag aus dem Kern (0.22.0): Trades nur mit Datum landen auch westlich von UTC am Buchungstag.
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        return modell.alleTrades
            .filter { Journaltag($0.eroeffnungstag(kalender), zeitzone: zeitzone) == tag }
            .sorted { ($0.openTime, $0.id) < ($1.openTime, $1.id) }
    }

    private var fehlerSichtbar: Binding<Bool> {
        Binding(get: { tagModell.fehler != nil }, set: { if !$0 { tagModell.fehler = nil } })
    }

    private func springe(zu tag: Journaltag?) {
        guard let tag else { return }
        modell.tagSprung = nil
        tagModell.wechsle(zu: tag)
    }

    /// Schreibt den Export erst nach einer Pause, damit nicht jedes automatische Sichern ihn neu schreibt.
    private func exportiereNachPause() async {
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        exportiereGeaendert()
    }

    private func exportiereGeaendert() {
        guard tagModell.aenderungen != exportiert else { return }
        exportiert = tagModell.aenderungen
        modell.exportiere()
    }
}

/// Titel mit Datum, Blättern, „Heute“ und Datumswahl.
struct TagKopf: View {
    let tagModell: TagModell

    var body: some View {
        Kopfzeile("Tag", untertitel: untertitel) {
            HStack(spacing: Abstand.raster * 2) {
                Button("Vorheriger Tag", systemImage: "chevron.left") {
                    tagModell.wechsle(zu: tagModell.tag.verschoben(um: -1, zeitzone: tagModell.zeitzone))
                }
                .labelStyle(.iconOnly)
                Button("Heute") {
                    tagModell.wechsle(zu: Journaltag(Date(), zeitzone: tagModell.zeitzone))
                }
                .disabled(tagModell.istHeute)
                Button("Nächster Tag", systemImage: "chevron.right") {
                    tagModell.wechsle(zu: tagModell.tag.verschoben(um: 1, zeitzone: tagModell.zeitzone))
                }
                .labelStyle(.iconOnly)
                DatePicker("Datum", selection: datum, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                FragBradKnopf(.tag, tag: tagModell.tag.beginn(in: tagModell.zeitzone)) // Frag Brad (Doc 31)
            }
            .buttonStyle(.bordered)
        }
    }

    private var untertitel: String {
        let beginn = tagModell.tag.beginn(in: tagModell.zeitzone)
        return beginn.formatted(.dateTime.weekday(.wide).day(.twoDigits).month(.twoDigits).year())
    }

    private var datum: Binding<Date> {
        Binding(get: { tagModell.tag.beginn(in: tagModell.zeitzone) },
                set: { tagModell.wechsle(zu: Journaltag($0, zeitzone: tagModell.zeitzone)) })
    }
}

/// Plan vor dem Handel mit dem Zeitpunkt des ersten Speicherns.
struct PlanKarte: View {
    @Bindable var tagModell: TagModell
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Plan vor dem Handel") {
            if let erstellt = tagModell.entwurf.planErstellt {
                Kapsel(text: String(localized: "gespeichert \(Format.uhrzeit(erstellt))"), betont: true)
            }
            TagTextfeld(text: $tagModell.entwurf.plan,
                        platzhalter: "Marktlage, Szenarien, was heute nicht passieren soll")
                .task(id: tagModell.entwurf.plan) { await sichereNachPause() }
            Text("Der Zeitpunkt des ersten Speicherns bleibt, auch wenn du den Plan später änderst. Ein geleerter Plan verliert ihn. Für die Planwirkung zählt der Plan nur, wenn er vor dem ersten Trade des Tages gespeichert war.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func sichereNachPause() async {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        tagModell.sichere()
    }
}

struct RueckblickKarte: View {
    @Bindable var tagModell: TagModell

    var body: some View {
        Karte("Rückblick") {
            TagTextfeld(text: $tagModell.entwurf.rueckblick,
                        platzhalter: "Was lief nach Plan, was nicht, was nehme ich mit")
                .task(id: tagModell.entwurf.rueckblick) {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    tagModell.sichere()
                }
        }
    }
}

/// Mehrzeiliges Feld mit Platzhalter auf der Fläche der Karte.
struct TagTextfeld: View {
    @Binding var text: String
    let platzhalter: LocalizedStringKey
    @Environment(\.thema) private var thema

    var body: some View {
        TextField(platzhalter, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(3...12)
            .font(Schrift.fliesstext)
            .foregroundStyle(thema.text)
            .padding(Abstand.raster * 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
    }
}

/// Verfassung 1 bis 5; ein Klick auf die gewählte Zahl hebt die Wahl auf.
struct VerfassungKarte: View {
    let tagModell: TagModell
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Verfassung") {
            HStack(spacing: Abstand.raster * 2) {
                ForEach(1...5, id: \.self) { wert in
                    let gewaehlt = tagModell.entwurf.verfassung == wert
                    Button {
                        tagModell.waehleVerfassung(wert)
                    } label: {
                        Text(verbatim: "\(wert)")
                            .font(Schrift.fliesstext.weight(gewaehlt ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Abstand.raster * 2)
                            .foregroundStyle(gewaehlt ? thema.textAufAkzent : thema.text)
                            .background(gewaehlt ? thema.akzent : thema.flaeche2,
                                        in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
                            .contentShape(RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(gewaehlt ? .isSelected : [])
                }
            }
            HStack {
                Text("schlecht")
                Spacer()
                Text("freiwillig")
                Spacer()
                Text("sehr gut")
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        }
    }
}

/// Trades des Kontos, die an diesem Tag eröffnet wurden; ein Klick springt in die Trade-Tabelle.
struct TagTradesKarte: View {
    let trades: [Trade]
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @AppStorage(Ton.schluessel) private var ton = Ton.henry

    var body: some View {
        Karte("Trades an diesem Tag") {
            if trades.isEmpty {
                Text(verbatim: leerText)
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                ForEach(trades) { trade in
                    Button {
                        modell.zeigeTrade(trade.id)
                    } label: {
                        HStack {
                            Text(verbatim: "\(Format.uhrzeit(trade.openTime)) · \(trade.symbol) \(Format.richtung(trade.richtung))")
                                .foregroundStyle(thema.text)
                            Spacer()
                            Text(verbatim: Format.geld(trade.netProfit, trade.waehrung(kontowaehrung: modell.waehrung)))
                                .font(Schrift.tabelle)
                                .foregroundStyle(thema.vorzeichen(trade.netProfit))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("In Trades zeigen")
                    Divider()
                }
                let stand = angleich
                HStack {
                    Text("Netto").fontWeight(.semibold)
                    Spacer()
                    Text(verbatim: Format.geld(netto(stand), modell.waehrung))
                        .font(Schrift.tabelle.weight(.semibold))
                        .foregroundStyle(thema.vorzeichen(netto(stand)))
                }
                if let hinweis = hinweis(stand) {
                    Text(verbatim: hinweis)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }
    }

    /// Trades in Kontowährung über die EZB-Referenzkurse am Schlusstag (TradingCore 0.19.0, zweiter
    /// Gegencheck W1, Tim 02.10.2026 13:07 UTC „Umrechnen“). Einzelbeträge oben bleiben in der Tradewährung.
    private var angleich: Waehrungsangleich {
        Waehrungsangleich(trades, kontowaehrung: modell.waehrung, kurse: modell.ezb.kurse)
    }

    /// Summe in Kontowährung; Trades ohne Kurs fehlen darin und stehen im Hinweis.
    private func netto(_ angleich: Waehrungsangleich) -> Decimal {
        angleich.trades.map(\.netProfit).reduce(0, +)
    }

    private func hinweis(_ angleich: Waehrungsangleich) -> String? {
        if !angleich.ohneKurs.isEmpty {
            let waehrungen = Set(angleich.ohneKurs.map { $0.waehrung(kontowaehrung: modell.waehrung) })
                .sorted().joined(separator: ", ")
            let anzahl = angleich.ohneKurs.count
            return String(localized: "Ohne EZB-Kurs nicht im Netto enthalten: \(anzahl) in \(waehrungen).")
        }
        guard !angleich.umgerechnet.isEmpty else { return nil }
        return String(localized: "Netto in \(modell.waehrung); Fremdwährung mit EZB-Kurs am Schlusstag umgerechnet (Näherung).")
    }

    /// Text Nr. 11 in der Fassung für Henry (Tim 02.10.2026 11:04 UTC); passt auf jeden Tag.
    private var leerText: String {
        guard modell.konto != nil else { return String(localized: "Noch kein Konto importiert.") }
        return ton.text("Keine Trades an diesem Tag im gewählten Konto.",
                        henry: "Kein Handel an diesem Tag. Geduld ist auch eine Position.")
    }
}
