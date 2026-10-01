import SwiftUI
import TradingCore
import TradingStore

/// Trades (Doc 10, Reihe 4 und 6): am Mac und iPad Tabelle mit Inspektor rechts,
/// am iPhone Liste mit zwei Zeilen je Trade und Detailseite.
struct TradesView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif
    @State private var suche = ""
    @State private var nurMitMuster = false
    @State private var nurOhneStop = false
    @State private var auswahl: Trade.ID?
    @State private var inspektorOffen = true
    @State private var sortierung = [KeyPathComparator(\Trade.closeTime, order: .reverse)]

    private var gefiltert: [Trade] {
        let muster = modell.musterJeTrade
        return modell.trades.filter { trade in
            if nurMitMuster, muster[trade.id] == nil { return false }
            if nurOhneStop, trade.stopLoss != nil { return false }
            if !suche.isEmpty, !trade.symbol.localizedCaseInsensitiveContains(suche), !trade.id.contains(suche) {
                return false
            }
            return true
        }
        .sorted(using: sortierung)
    }

    private var ausgewaehlterTrade: Trade? {
        modell.trades.first { $0.id == auswahl }
    }

    /// Am iPhone zeigt die Liste eine Detailseite, kein Inspektor.
    private var inspektorSichtbar: Binding<Bool> {
        #if os(iOS)
        if breite == .compact { return .constant(false) }
        #endif
        return $inspektorOffen
    }

    var body: some View {
        let liste = gefiltert
        let muster = modell.musterJeTrade
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Kopfzeile("Trades", untertitel: String(localized: "\(liste.count) von \(modell.trades.count)")) {
                Toggle("Nur mit Muster", isOn: $nurMitMuster)
                Toggle("Stop fehlt (\(modell.ohneStop))", isOn: $nurOhneStop)
            }
            .toggleStyle(.button)
            .padding(.horizontal, Abstand.seitenrand)
            if liste.isEmpty {
                KeineTrades()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(iOS)
                if breite == .compact {
                    tradeListe(liste, muster)
                } else {
                    tradeTabelle(liste, muster)
                }
                #else
                tradeTabelle(liste, muster)
                #endif
                Summenzeile(trades: liste, waehrung: modell.waehrung)
                    .padding(.horizontal, Abstand.seitenrand)
                    .padding(.bottom, Abstand.kachelAbstand)
            }
        }
        .padding(.top, Abstand.seitenrand)
        .searchable(text: $suche, prompt: "Instrument oder Ticket")
        .inspector(isPresented: inspektorSichtbar) {
            Group {
                if let trade = ausgewaehlterTrade {
                    ScrollView {
                        TradeInspektor(trade: trade, muster: muster[trade.id] ?? [],
                                       waehrung: modell.waehrung, konto: modell.konto)
                            .padding(Abstand.kachelInnen)
                    }
                } else {
                    ContentUnavailableView("Kein Trade gewählt", systemImage: "cursorarrow.click",
                                           description: Text("Wähle eine Zeile, um Zeiten, Kurse, Kosten und Fehlermuster zu sehen."))
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

    /// Tabelle mit Spalten Geschlossen, Instrument, Richtung, Lots, R, Netto, Hinweise; Klick wählt für den Inspektor.
    /// Die Spalte Setup kommt mit dem Journal-Paket.
    private func tradeTabelle(_ liste: [Trade], _ muster: [String: [Fehlermuster]]) -> some View {
        Table(liste, selection: $auswahl, sortOrder: $sortierung) {
            TableColumn("Geschlossen", value: \.closeTime) { trade in
                Text(verbatim: Format.zeit(trade.closeTime))
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 120)
            TableColumn("Instrument", value: \.symbol) { trade in
                Text(verbatim: trade.symbol)
            }
            TableColumn("Richtung", value: \.side.rawValue) { trade in
                Text(verbatim: Format.richtung(trade.side))
            }
            .width(min: 70, ideal: 80)
            TableColumn("Lots", value: \.lots) { trade in
                Text(verbatim: Format.lots(trade.lots))
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60)
            .alignment(.numeric)
            TableColumn("R") { trade in
                if trade.rMultiple == nil {
                    Text("kein Stop")
                        .foregroundStyle(thema.textSchwach)
                } else {
                    Text(verbatim: Format.r(trade.rMultiple))
                        .monospacedDigit()
                }
            }
            .width(min: 70, ideal: 80)
            .alignment(.numeric)
            TableColumn("Netto", value: \.netProfit) { trade in
                Text(verbatim: Format.geld(trade.netProfit, modell.waehrung))
                    .monospacedDigit()
                    .foregroundStyle(thema.vorzeichen(trade.netProfit))
            }
            .width(min: 90, ideal: 100)
            .alignment(.numeric)
            TableColumn("Hinweise") { trade in
                HStack(spacing: Abstand.raster) {
                    ForEach(muster[trade.id] ?? [], id: \.self) { MusterChip(muster: $0) }
                }
            }
        }
    }

    /// iPhone: Liste mit zwei Zeilen je Trade, Tippen öffnet die Detailseite.
    private func tradeListe(_ liste: [Trade], _ muster: [String: [Fehlermuster]]) -> some View {
        List(liste) { trade in
            NavigationLink(value: trade.id) {
                TradeZeile(trade: trade, muster: muster[trade.id] ?? [], waehrung: modell.waehrung)
            }
            .listRowBackground(thema.flaeche)
        }
        .scrollContentBackground(.hidden)
        .navigationDestination(for: Trade.ID.self) { id in
            if let trade = modell.trades.first(where: { $0.id == id }) {
                ScrollView {
                    TradeInspektor(trade: trade, muster: muster[id] ?? [],
                                   waehrung: modell.waehrung, konto: modell.konto)
                        .padding(Abstand.seitenrand)
                }
                .background(thema.grund)
                .navigationTitle("Trade")
            }
        }
    }
}

/// Inspektor eines Trades (Doc 10, Reihe 4): Zeiten, Kurse, Kosten, Stop-Hinweis, Journal, Fehlermuster.
/// Stop nachtragen und Journalfelder kommen mit der zweiten Migration in TradingStore.
struct TradeInspektor: View {
    let trade: Trade
    let muster: [Fehlermuster]
    let waehrung: String
    let konto: Konto?
    @Environment(\.thema) private var thema

    var body: some View {
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
                    zeile("Stop laut Export", trade.stopLoss.map(Format.kurs) ?? String(localized: "kein Stop"))
                    zeile("Ziel", trade.takeProfit.map(Format.kurs) ?? "–")
                    zeile("Risiko (1 R)", trade.risk.map { Format.betrag($0, waehrung) } ?? "–")
                }
                Group {
                    zeile("Brutto", Format.geld(trade.profit, waehrung), farbe: thema.vorzeichen(trade.profit))
                    zeile("Kommission", Format.geld(trade.commission, waehrung))
                    zeile("Swap", Format.geld(trade.swap, waehrung))
                    zeile("Netto", Format.geld(trade.netProfit, waehrung), farbe: thema.vorzeichen(trade.netProfit), fett: true)
                    zeile("R", Format.r(trade.rMultiple), farbe: trade.rMultiple.map(thema.vorzeichen))
                }
            }
            if trade.stopLoss == nil {
                Karte("Stop beim Einstieg fehlt") {
                    Text("Im Export steht nur der letzte Stop-Loss. Ohne Stop kein R. Nachtragen kommt mit dem Journal-Paket.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            Karte("Journal") {
                Text("Setup, Regeltreue, Zustand 1 bis 5, Marktumfeld und der Grund in einem Satz kommen mit dem Journal-Paket (zweite Migration in TradingStore).")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            if !muster.isEmpty {
                Karte("Fehlermuster") {
                    ForEach(muster, id: \.self) { eintrag in
                        VStack(alignment: .leading, spacing: Abstand.raster) {
                            MusterChip(muster: eintrag)
                            Text(verbatim: eintrag.regel)
                                .font(Schrift.beschriftung)
                                .foregroundStyle(thema.textSchwach)
                        }
                    }
                }
            }
        }
    }

    private var untertitel: String {
        var teile = [String(localized: "Ticket \(trade.id)")]
        if let konto {
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

/// Eine Zeile der Trade-Liste am iPhone: Instrument und Richtung, darunter Zeit, Lots und Haltedauer; rechts Netto und R.
struct TradeZeile: View {
    let trade: Trade
    let muster: [Fehlermuster]
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: "\(trade.symbol) · \(Format.richtung(trade.side))")
                    .font(Schrift.fliesstext.weight(.semibold))
                    .foregroundStyle(thema.text)
                Text(verbatim: "\(Format.zeit(trade.closeTime)) · \(Format.lots(trade.lots)) Lots · \(Format.dauer(trade.holdingTime))")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                if !muster.isEmpty {
                    HStack(spacing: Abstand.raster) {
                        ForEach(muster, id: \.self) { MusterChip(muster: $0) }
                    }
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
