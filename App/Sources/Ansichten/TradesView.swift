import SwiftUI
import TradingCalendar
import TradingCore
import TradingStore

/// Eine Zeile der Trade-Tabelle: der Trade mit seinem Setup aus dem Journal und seinen Fehlermustern.
struct TradeZeileDaten: Identifiable {
    var trade: Trade
    var setup: String
    var muster: [Fehlermuster]
    /// Termine in der Haltezeit, die eine Währung des Symbols betreffen (Doc 18 F9); leer ohne Treffer.
    var termine: [Termin] = []
    /// Der Stop stammt aus dem Journal (Stop beim Einstieg) und ersetzt den aus dem Export (Entscheidung 8).
    var stopAusJournal = false
    var id: String { trade.id }
}

/// Trades (Doc 10, Reihe 4 und 6): am Mac und iPad Tabelle mit Inspektor rechts,
/// am iPhone Liste mit zwei Zeilen je Trade und Detailseite.
struct TradesView: View {
    @AppStorage(Ton.schluessel) private var ton = Ton.henry
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif
    @State private var suche = ""
    @State private var nurMitMuster = false
    @State private var nurOhneStop = false
    @State private var inspektorOffen = true
    @State private var sortierung = [KeyPathComparator(\TradeZeileDaten.trade.closeTime, order: .reverse)]
    /// Spalten per Rechtsklick auf den Tabellenkopf ein- und ausblenden; die Wahl bleibt je Fenster gespeichert.
    @SceneStorage("tradesSpalten") private var spalten: TableColumnCustomization<TradeZeileDaten>

    private var gefiltert: [TradeZeileDaten] {
        let muster = modell.musterJeTrade
        let eintraege = modell.journaleintraege
        let musterFilter = modell.musterFilter
        let termine = modell.termineJeTrade
        let nurUeberTermin = modell.nurUeberTermin
        return modell.trades.compactMap { trade -> TradeZeileDaten? in
            let zeile = TradeZeileDaten(trade: trade, setup: eintraege[trade.id]?.setup ?? "", muster: muster[trade.id] ?? [],
                                        termine: termine[trade.id] ?? [],
                                        stopAusJournal: eintraege[trade.id]?.stopEinstieg != nil)
            if nurMitMuster, zeile.muster.isEmpty { return nil }
            if nurUeberTermin, zeile.termine.isEmpty { return nil }
            if let musterFilter, !zeile.muster.contains(musterFilter) { return nil }
            if nurOhneStop, trade.stopLoss != nil { return nil }
            if !suche.isEmpty, !trade.symbol.localizedCaseInsensitiveContains(suche), !trade.id.contains(suche),
               !zeile.setup.localizedCaseInsensitiveContains(suche) {
                return nil
            }
            return zeile
        }
        .sorted(using: sortierung)
    }

    private var ausgewaehlterTrade: Trade? {
        modell.trades.first { $0.id == modell.tradeAuswahl }
    }

    /// Am iPhone zeigt die Liste eine Detailseite, kein Inspektor.
    private var inspektorSichtbar: Binding<Bool> {
        #if os(iOS)
        if breite == .compact { return .constant(false) }
        #endif
        return $inspektorOffen
    }

    var body: some View {
        @Bindable var modell = modell
        let liste = gefiltert
        let muster = modell.musterJeTrade
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Kopfzeile("Trades", untertitel: String(localized: "\(liste.count) von \(modell.trades.count)")) {
                #if os(macOS)
                // Suchfeld in der Kopfzeile statt in der Symbolleiste: dort überdeckte es den Kopf des Inspektors.
                TextField("Instrument, Setup oder Ticket", text: $suche)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                #endif
                Toggle("Nur mit Muster", isOn: $nurMitMuster)
                Toggle("Stop fehlt (\(modell.ohneStop))", isOn: $nurOhneStop)
                Toggle("Über Termin gehalten", isOn: $modell.nurUeberTermin)
            }
            .toggleStyle(.button)
            .padding(.horizontal, Abstand.seitenrand)
            if let musterFilter = modell.musterFilter {
                Button {
                    modell.musterFilter = nil
                } label: {
                    HStack(spacing: Abstand.raster) {
                        Text("Nur \(musterFilter.titel)")
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(Schrift.beschriftung)
                    .padding(.horizontal, Abstand.raster * 2)
                    .padding(.vertical, Abstand.raster)
                    .background(thema.akzentTint, in: Capsule())
                    .foregroundStyle(thema.text)
                }
                .buttonStyle(.plain)
                .help("Filter aufheben")
                .padding(.horizontal, Abstand.seitenrand)
            }
            if liste.isEmpty {
                KeineTrades()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                if breite == .compact {
                    tradeListe(liste, muster)
                } else {
                    tradeTabelle(liste)
                }
                #else
                tradeTabelle(liste)
                #endif
                Summenzeile(trades: liste.map(\.trade), waehrung: modell.waehrung)
                    .padding(.horizontal, Abstand.seitenrand)
                    .padding(.bottom, Abstand.kachelAbstand)
            }
        }
        .padding(.top, Abstand.seitenrand)
        #if os(iOS)
        .searchable(text: $suche, prompt: "Instrument, Setup oder Ticket")
        #endif
        .inspector(isPresented: inspektorSichtbar) {
            Group {
                if let trade = ausgewaehlterTrade {
                    ScrollView {
                        TradeInspektor(trade: trade, muster: muster[trade.id] ?? [], waehrung: trade.waehrung(kontowaehrung: modell.waehrung))
                            .padding(Abstand.kachelInnen)
                    }
                } else {
                    ContentUnavailableView(ton.text("Kein Trade gewählt", henry: "Bitte einen Trade wählen."), systemImage: "cursorarrow.click",
                                           description: Text("Wähle eine Zeile, um Zeiten, Kurse, Kosten, Journal und Fehlermuster zu sehen."))
                }
            }
            .inspectorColumnWidth(min: 280, ideal: Abstand.inspektor, max: 440)
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspektorOffen.toggle()
                } label: {
                    Label("Inspektor", systemImage: "sidebar.trailing")
                }
            }
        }
        #endif
    }

    /// Tabelle mit Spalten Eröffnet, Geschlossen, Instrument, Richtung, Setup, Lots, SL, TP, R, Netto, Hinweise; Klick wählt für den Inspektor.
    private func tradeTabelle(_ liste: [TradeZeileDaten]) -> some View {
        @Bindable var modell = modell
        return Table(liste, selection: $modell.tradeAuswahl, sortOrder: $sortierung, columnCustomization: $spalten) {
            TableColumn("Eröffnet", value: \.trade.openTime) { zeile in
                // Ausführungszeitpunkt; bei Pending Orders also die Aktivierung (Tim, 02.10.2026 03:10 UTC).
                Text(verbatim: Format.zeit(zeile.trade.openTime))
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 120)
            .customizationID("eroeffnet")
            TableColumn("Geschlossen", value: \.trade.closeTime) { zeile in
                Text(verbatim: Format.zeit(zeile.trade.closeTime))
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 120)
            .customizationID("geschlossen")
            TableColumn("Instrument", value: \.trade.symbol) { zeile in
                HStack(spacing: Abstand.raster) {
                    Text(verbatim: zeile.trade.symbol)
                    if !zeile.termine.isEmpty {
                        Image(systemName: "calendar")
                            .foregroundStyle(thema.textSchwach)
                            .help(Text(verbatim: Terminformat.imTrade(zeile.termine)))
                    }
                }
            }
            .width(min: 90, ideal: 100)
            .customizationID("instrument")
            TableColumn("Richtung", value: \.trade.side.rawValue) { zeile in
                Text(verbatim: Format.richtung(zeile.trade.side))
            }
            .width(min: 70, ideal: 80)
            .customizationID("richtung")
            TableColumn("Setup", value: \.setup) { zeile in
                Text(verbatim: zeile.setup)
            }
            .width(min: 80, ideal: 120)
            .customizationID("setup")
            TableColumn("Lots", value: \.trade.lots) { zeile in
                Text(verbatim: Format.lots(zeile.trade.lots))
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60)
            .alignment(.numeric)
            .customizationID("lots")
            // Gruppe, weil der Spalten-Builder höchstens zehn Einträge nimmt (SL und TP: Tim, 02.10.2026 03:10 UTC).
            Group {
                TableColumn("SL") { zeile in
                    stopZelle(zeile)
                }
                .width(min: 70, ideal: 90)
                .alignment(.numeric)
                .customizationID("sl")
                TableColumn("TP") { zeile in
                    Text(verbatim: zeile.trade.takeProfit.map(Format.kurs) ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(zeile.trade.takeProfit == nil ? thema.textSchwach : thema.text)
                }
                .width(min: 70, ideal: 90)
                .alignment(.numeric)
                .customizationID("tp")
            }
            TableColumn("R") { zeile in
                if zeile.trade.rMultiple == nil {
                    Text("kein Stop")
                        .foregroundStyle(thema.textSchwach)
                } else {
                    Text(verbatim: Format.r(zeile.trade.rMultiple))
                        .monospacedDigit()
                }
            }
            .width(min: 70, ideal: 80)
            .alignment(.numeric)
            .customizationID("r")
            TableColumn("Netto", value: \.trade.netProfit) { zeile in
                // Betrag in der Währung des Trades (Zweiter Gegencheck W1); die Summenzeile bleibt Kontowährung.
                Text(verbatim: Format.geld(zeile.trade.netProfit, zeile.trade.waehrung(kontowaehrung: modell.waehrung)))
                    .monospacedDigit()
                    .foregroundStyle(thema.vorzeichen(zeile.trade.netProfit))
            }
            .width(min: 90, ideal: 100)
            .alignment(.numeric)
            .customizationID("netto")
            TableColumn("Hinweise") { zeile in
                MusterChips(muster: zeile.muster)
            }
            .width(min: 170, ideal: 220)
            .customizationID("hinweise")
        }
        .contextMenu(forSelectionType: String.self) { ids in
            // Frag Brad (Doc 31): nur bei genau einem Trade
            if ids.count == 1, let id = ids.first, let zeile = liste.first(where: { $0.id == id }) {
                FragBradMenuePunkt(trade: zeile.trade)
                AnalyseMenuePunkt(trade: zeile.trade) // Menü „Analyse“ (Doc 38, A5)
            }
        }
    }

    /// Stop wie in der R-Spalte gerechnet: aus dem Journal (Punkt) oder aus dem Export; „–“ ohne Stop.
    @ViewBuilder
    private func stopZelle(_ zeile: TradeZeileDaten) -> some View {
        if let stop = zeile.trade.stopLoss {
            HStack(spacing: Abstand.raster / 2) {
                Text(verbatim: Format.kurs(stop))
                    .monospacedDigit()
                if zeile.stopAusJournal {
                    Circle()
                        .fill(thema.akzent)
                        .frame(width: 5, height: 5)
                }
            }
            .help(zeile.stopAusJournal ? Text("Stop beim Einstieg aus dem Journal") : Text("Stop laut Export"))
        } else {
            Text(verbatim: "–")
                .foregroundStyle(thema.textSchwach)
        }
    }

    /// iPhone: Liste mit zwei Zeilen je Trade, Tippen öffnet die Detailseite.
    private func tradeListe(_ liste: [TradeZeileDaten], _ muster: [String: [Fehlermuster]]) -> some View {
        List(liste) { zeile in
            NavigationLink(value: zeile.id) {
                TradeZeile(trade: zeile.trade, muster: zeile.muster, waehrung: zeile.trade.waehrung(kontowaehrung: modell.waehrung), setup: zeile.setup,
                           ueberTermin: !zeile.termine.isEmpty)
            }
            .listRowBackground(thema.flaeche)
        }
        .scrollContentBackground(.hidden)
        .navigationDestination(for: TradeZeileDaten.ID.self) { id in
            if let trade = modell.trades.first(where: { $0.id == id }) {
                ScrollView {
                    TradeInspektor(trade: trade, muster: muster[id] ?? [], waehrung: trade.waehrung(kontowaehrung: modell.waehrung))
                        .padding(Abstand.seitenrand)
                }
                .background(thema.grund)
                .navigationTitle("Trade")
            }
        }
    }
}

/// Inspektor eines Trades (Doc 10, Reihe 4): Zeiten, Kurse, Kosten, Stop nachtragen, Journal, Fehlermuster.
/// Am Mac sind Stop und Journal Eingabefelder, am iPhone nur Anzeige (Doc 10, iPhone V1 nur lesen).
struct TradeInspektor: View {
    let trade: Trade
    let muster: [Fehlermuster]
    let waehrung: String
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let eintrag = modell.journaleintrag(trade)
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: "\(trade.symbol) · \(Format.richtung(trade.side))")
                    .font(Schrift.titel)
                    .foregroundStyle(thema.text)
                Text(verbatim: untertitel)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
                Group {
                    zeile("Einstieg", "\(Format.uhrzeit(trade.openTime)) · \(Format.kurs(trade.openPrice))")
                    zeile("Ausstieg", "\(Format.uhrzeit(trade.closeTime)) · \(Format.kurs(trade.closePrice))")
                    zeile("Lots", Format.lots(trade.lots))
                    zeile("Haltedauer", Format.dauer(trade.holdingTime))
                    zeile("Stop laut Export", modell.stopLautExport(trade).map(Format.kurs) ?? String(localized: "kein Stop"))
                    if let stop = eintrag?.stopEinstieg {
                        zeile("Stop beim Einstieg", Format.kurs(stop), fett: true)
                    }
                    zeile("Ziel", trade.takeProfit.map(Format.kurs) ?? "–")
                    zeile("Risiko (1 R)", trade.risk.map { Format.betrag($0, waehrung) } ?? "–")
                }
                Group {
                    zeile("Brutto", Format.geld(trade.profit, waehrung), farbe: thema.vorzeichen(trade.profit))
                    zeile("Kommission", Format.geld(trade.commission, waehrung))
                    zeile("Swap", Format.geld(trade.swap, waehrung))
                    zeile("Netto", Format.geld(trade.netProfit, waehrung), farbe: thema.vorzeichen(trade.netProfit), fett: true)
                    zeile("R", Format.r(trade.rMultiple), farbe: trade.rMultiple.map(thema.vorzeichen))
                    zeile("Termine", terminText)
                }
            }
            AusstiegKarte(trade: trade, waehrung: waehrung) // Ausstiegsanalyse B3 (Doc 39)
            #if os(macOS)
            if let eintrag {
                JournalEingabe(trade: trade, eintrag: eintrag)
                    .id(trade.id)
            }
            #else
            JournalAnzeige(trade: trade, eintrag: eintrag)
            #endif
            TradeBilderKarte(trade: trade) // Screenshots zum Trade (Tagesseite-Thread, Doc 28)
            if !muster.isEmpty {
                Karte("Fehlermuster") {
                    ForEach(muster, id: \.self) { befundMuster in
                        VStack(alignment: .leading, spacing: Abstand.raster) {
                            MusterChip(muster: befundMuster, kurz: false)
                            Text(verbatim: befundMuster.regel)
                                .font(Schrift.beschriftung)
                                .foregroundStyle(thema.textSchwach)
                        }
                    }
                }
            }
        }
    }

    /// Termine der Währungen des Symbols in der Haltezeit (Doc 18 F9), sonst warum keiner steht.
    private var terminText: String {
        let gefunden = modell.termine.termine(fuer: trade)
        if !gefunden.isEmpty { return Terminformat.imTrade(gefunden) }
        if Terminkalender.waehrungen(symbol: trade.symbol).isEmpty { return String(localized: "keine Währung erkannt") }
        return modell.termine.abgedeckt(trade) ? String(localized: "keiner in der Haltezeit") : String(localized: "Zeitraum nicht erfasst")
    }

    private var untertitel: String {
        var teile = [String(localized: "Ticket \(trade.id)")]
        if let konto = modell.konto {
            teile.append("\(konto.broker) · \(konto.kontoname)")
        }
        teile.append(Format.datum(trade.closeTime))
        return teile.joined(separator: " · ")
    }

    private func zeile(_ titel: LocalizedStringKey, _ wert: String, farbe: Color? = nil, fett: Bool = false) -> some View {
        GridRow {
            Text(titel)
                .foregroundStyle(thema.textSchwach)
                .gridColumnAlignment(.leading)
            Text(verbatim: wert)
                .font(fett ? Schrift.tabelle.weight(.semibold) : Schrift.tabelle)
                .foregroundStyle(farbe ?? thema.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
    }
}

#if os(macOS)
/// Stop nachtragen und Journalfelder (Doc 10, Reihe 4; Entscheidung 8). Auswahlfelder speichern sofort,
/// Textfelder bei Enter, beim Verlassen des Feldes und beim Wechsel des Trades. Ohne Angaben wird nichts gespeichert.
struct JournalEingabe: View {
    let trade: Trade
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var eintrag: Journaleintrag
    @FocusState private var fokus: Feld?

    private enum Feld: Hashable {
        case stop, setup, marktumfeld, grund
    }

    init(trade: Trade, eintrag: Journaleintrag) {
        self.trade = trade
        _eintrag = State(initialValue: eintrag)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Karte("Stop nachtragen") {
                LabeledContent("Stop beim Einstieg") {
                    TextField("wie im Export", value: $eintrag.stopEinstieg,
                              format: .number.precision(.fractionLength(0...5)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .focused($fokus, equals: .stop)
                }
                Text(stopHinweis)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Karte("Journal") {
                LabeledContent("Setup") {
                    HStack(spacing: Abstand.raster) {
                        TextField("z. B. Ausbruch", text: text(\.setup))
                            .textFieldStyle(.roundedBorder)
                            .focused($fokus, equals: .setup)
                        if !modell.playbook.isEmpty {
                            // Karte aus dem Playbook wählen; freier Text bleibt möglich (Setups ohne Karte).
                            Menu {
                                ForEach(modell.playbook, id: \.name) { karte in
                                    Button(action: { waehleSetup(karte.name) }) { Text(verbatim: karte.name) }
                                }
                            } label: {
                                Image(systemName: "book.closed")
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .fixedSize()
                            .help("Setup aus dem Playbook wählen")
                        }
                    }
                }
                if !modell.bekannteSetups.isEmpty {
                    Text(verbatim: String(localized: "Bisher: ") + modell.bekannteSetups.joined(separator: ", "))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                // Regler mit Beschriftung darüber: im 320-pt-Inspektor passt der Zustand-Regler (sechs Segmente)
                // nicht neben eine Beschriftung, LabeledContent drückte sie weg (Tims Screenshot 01.10.2026).
                Feldblock("Regeltreue") {
                    Picker("Regeltreue", selection: $eintrag.regeltreue) {
                        Text("offen").tag(Bool?.none)
                        Text("Ja").tag(Bool?.some(true))
                        Text("Nein").tag(Bool?.some(false))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Feldblock("Zustand") {
                    Picker("Zustand", selection: $eintrag.zustand) {
                        Text("offen").tag(Int?.none)
                        ForEach(1...5, id: \.self) { stufe in
                            Text(verbatim: "\(stufe)").tag(Int?.some(stufe))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                LabeledContent("Marktumfeld") {
                    TextField("z. B. Trend, Seitwärts, Nachrichten", text: text(\.marktumfeld))
                        .textFieldStyle(.roundedBorder)
                        .focused($fokus, equals: .marktumfeld)
                }
                LabeledContent("Grund") {
                    TextField("Warum dieser Einstieg, ein Satz", text: text(\.grund), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($fokus, equals: .grund)
                }
                Text("Zustand: 1 schlecht bis 5 sehr gut. Regeltreue: nach den eigenen Regeln gehandelt?")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            ChecklisteKarte(trade: trade, setupName: eintrag.bereinigt.setup)
        }
        .onChange(of: eintrag.regeltreue) { speichern() }
        .onChange(of: eintrag.zustand) { speichern() }
        .onChange(of: fokus) { alt, _ in
            if alt != nil { speichern() }
        }
        .onSubmit { speichern() }
        .onDisappear { speichern() }
    }

    private var stopHinweis: LocalizedStringKey {
        if modell.stopLautExport(trade) == nil {
            return "Im Export steht kein Stop. Trage den Stop vom Einstieg ein, dann rechnen Risiko und R."
        }
        return "Der Export zeigt nur den letzten Stop. War er beim Einstieg anders, trage ihn hier ein; Risiko und R rechnen damit."
    }

    /// Textfeld auf ein freiwilliges Feld: leer heißt `nil`.
    private func text(_ feld: WritableKeyPath<Journaleintrag, String?>) -> Binding<String> {
        Binding(
            get: { eintrag[keyPath: feld] ?? "" },
            set: { eintrag[keyPath: feld] = $0.isEmpty ? nil : $0 }
        )
    }

    private func speichern() {
        let bereinigt = eintrag.bereinigt
        guard !bereinigt.gleicheAngaben(wie: modell.journaleintraege[bereinigt.ticket]) else { return }
        modell.speichereJournal(bereinigt)
    }

    private func waehleSetup(_ name: String) {
        eintrag.setup = name
        speichern()
    }
}

/// Karte des Setups aus dem Playbook zum Trade (Doc 18 F3, Doc 23): Status, Kriterien als Häkchen, Regeln der
/// Karte. Häkchen speichern sofort (AP9 #59, `setzeCheckliste`), das Setup landet dabei im Journal.
struct ChecklisteKarte: View {
    let trade: Trade
    let setupName: String?
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        if let karte = modell.setupKarte(setupName) {
            let erfuellt = modell.checklisten[trade.id]?.erfuellt ?? []
            let anzahl = karte.kriterien.filter { erfuellt.contains($0.id) }.count
            Karte(verbatim: String(localized: "Checkliste \(karte.name)")) {
                HStack(spacing: Abstand.raster * 2) {
                    Kapsel(text: Setupformat.status(karte.status), betont: karte.status == .aktiv)
                    Text(verbatim: String(localized: "\(anzahl) von \(karte.kriterien.count) erfüllt"))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                if karte.kriterien.isEmpty {
                    Text("Die Karte hat noch keine Kriterien. Ergänze sie unter Einstellungen › Playbook.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    ForEach(karte.kriterien, id: \.id) { kriterium in
                        Toggle(isOn: haken(kriterium, karte: karte)) {
                            Text(verbatim: kriterium.text)
                                .foregroundStyle(thema.text)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                regeln(karte)
            }
        } else if let setupName, !setupName.isEmpty {
            Text("Zu „\(setupName)“ gibt es keine Karte im Playbook. Lege sie unter Einstellungen › Playbook an, dann kannst du hier Kriterien abhaken.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func haken(_ kriterium: Kriterium, karte: Setup) -> Binding<Bool> {
        Binding(
            get: { modell.checklisten[trade.id]?.erfuellt.contains(kriterium.id) ?? false },
            set: { an in
                var liste = modell.checklisten[trade.id] ?? Checkliste(setup: karte.name)
                liste.setup = karte.name
                if an { liste.erfuellt.insert(kriterium.id) } else { liste.erfuellt.remove(kriterium.id) }
                modell.setzeCheckliste(liste, trade: trade)
            }
        )
    }

    @ViewBuilder
    private func regeln(_ karte: Setup) -> some View {
        if karte.stopRegel != nil || karte.zielRegel != nil || karte.marktumfeld != nil {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                if let stop = karte.stopRegel { regelZeile("Stop", stop) }
                if let ziel = karte.zielRegel { regelZeile("Ziel", ziel) }
                if let umfeld = karte.marktumfeld { regelZeile("Umfeld", umfeld) }
            }
        }
    }

    private func regelZeile(_ titel: LocalizedStringKey, _ wert: String) -> some View {
        HStack(alignment: .top, spacing: Abstand.raster) {
            Text(titel)
                .foregroundStyle(thema.textSchwach)
                .frame(width: 48, alignment: .leading)
            Text(verbatim: wert)
                .foregroundStyle(thema.text)
        }
        .font(Schrift.beschriftung)
    }
}
#else
/// iPhone: Journal nur lesen (Doc 10, iPhone V1). Eintragen geht am Mac.
struct JournalAnzeige: View {
    let trade: Trade
    let eintrag: Journaleintrag?
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Journal") {
            if let eintrag, !eintrag.ohneAngaben {
                VStack(alignment: .leading, spacing: Abstand.raster) {
                    if let setup = eintrag.setup { angabe("Setup", setup) }
                    if let regeltreue = eintrag.regeltreue {
                        angabe("Regeltreue", regeltreue ? String(localized: "Ja") : String(localized: "Nein"))
                    }
                    if let zustand = eintrag.zustand { angabe("Zustand", "\(zustand) von 5") }
                    if let marktumfeld = eintrag.marktumfeld { angabe("Marktumfeld", marktumfeld) }
                    if let grund = eintrag.grund { angabe("Grund", grund) }
                }
                if let karte = modell.setupKarte(eintrag.setup), !karte.kriterien.isEmpty {
                    checkliste(karte)
                }
            } else if trade.stopLoss == nil {
                Text("Keine Journalangaben, Stop fehlt. Eintragen geht am Mac.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                Text("Keine Journalangaben. Eintragen geht am Mac.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    private func angabe(_ titel: LocalizedStringKey, _ wert: String) -> some View {
        HStack(alignment: .top) {
            Text(titel)
                .foregroundStyle(thema.textSchwach)
            Spacer()
            Text(verbatim: wert)
                .foregroundStyle(thema.text)
                .multilineTextAlignment(.trailing)
        }
        .font(Schrift.fliesstext)
    }

    /// Kriterien der Playbook-Karte mit den am Mac gesetzten Häkchen (Doc 18 F3), nur lesen.
    private func checkliste(_ karte: Setup) -> some View {
        let erfuellt = modell.checklisten[trade.id]?.erfuellt ?? []
        return VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: String(localized: "Checkliste \(karte.name) · \(karte.kriterien.filter { erfuellt.contains($0.id) }.count) von \(karte.kriterien.count) erfüllt"))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            ForEach(karte.kriterien, id: \.id) { kriterium in
                Label {
                    Text(verbatim: kriterium.text).foregroundStyle(thema.text)
                } icon: {
                    Image(systemName: erfuellt.contains(kriterium.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(erfuellt.contains(kriterium.id) ? thema.gewinn : thema.textSchwach)
                }
                .font(Schrift.beschriftung)
            }
        }
    }
}
#endif

/// Eine Zeile der Trade-Liste am iPhone: Instrument und Richtung, darunter Zeit, Setup, Lots und Haltedauer; rechts Netto und R.
struct TradeZeile: View {
    let trade: Trade
    let muster: [Fehlermuster]
    let waehrung: String
    var setup = ""
    var ueberTermin = false
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: "\(trade.symbol) · \(Format.richtung(trade.side))")
                    .font(Schrift.fliesstext.weight(.semibold))
                    .foregroundStyle(thema.text)
                Text(verbatim: zweiteZeile)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                if !muster.isEmpty {
                    MusterChips(muster: muster, maxAnzahl: 3)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Abstand.raster) {
                Text(verbatim: Format.geld(trade.netProfit, waehrung))
                    .font(Schrift.tabelle.weight(.semibold))
                    .foregroundStyle(thema.vorzeichen(trade.netProfit))
                if trade.rMultiple == nil {
                    Text("kein Stop")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    Text(verbatim: Format.r(trade.rMultiple))
                        .font(Schrift.beschriftung)
                        .monospacedDigit()
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }
        .padding(.vertical, Abstand.raster)
    }

    private var zweiteZeile: String {
        var teile = [Format.zeit(trade.closeTime)]
        if !setup.isEmpty { teile.append(setup) }
        teile.append("\(Format.lots(trade.lots)) Lots")
        teile.append(Format.dauer(trade.holdingTime))
        if ueberTermin { teile.append(String(localized: "über Termin gehalten")) }
        return teile.joined(separator: " · ")
    }
}

/// Summenzeile unter Tabelle oder Liste: Anzahl, Ø R, Netto, Trades ohne Stop.
struct Summenzeile: View {
    let trades: [Trade]
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        let kennzahlen = Kennzahlen(trades: trades)
        let ohneStop = trades.filter { $0.stopLoss == nil }.count
        HStack(spacing: Abstand.kachelAbstand) {
            Text("Summe")
                .foregroundStyle(thema.textSchwach)
            Text("\(kennzahlen.anzahl) Trades")
                .foregroundStyle(thema.textSchwach)
            Spacer()
            Text(verbatim: "Ø \(Format.r(kennzahlen.erwartungswertR))")
                .font(Schrift.tabelle)
                .foregroundStyle(thema.textSchwach)
            Text(verbatim: Format.geld(kennzahlen.netto, waehrung))
                .font(Schrift.tabelle.weight(.semibold))
                .foregroundStyle(thema.vorzeichen(kennzahlen.netto))
            Text("\(ohneStop) ohne Stop")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        .font(Schrift.fliesstext)
    }
}
