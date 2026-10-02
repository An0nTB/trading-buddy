import SwiftUI
import TradingCore

/// Verpasste Trades des Tages: Liste mit Grund und Schätzung, Erfassen und Bearbeiten im Blatt.
struct VerpassteListeKarte: View {
    let tagModell: TagModell
    @Environment(\.thema) private var thema
    @State private var bearbeiten: VerpasstAuswahl?

    var body: some View {
        Karte("Verpasste Trades") {
            if tagModell.verpasst.isEmpty {
                Text("Ein Setup gesehen und nicht gehandelt? Erfasse es mit Grund, dann zeigt die Auswertung, was dich zögern lässt.")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                ForEach(tagModell.verpasst) { eintrag in
                    Button {
                        bearbeiten = VerpasstAuswahl(eintrag: eintrag, neu: false)
                    } label: {
                        VerpasstZeile(eintrag: eintrag)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Löschen", systemImage: "trash", role: .destructive) {
                            tagModell.loesche(eintrag)
                        }
                    }
                    Divider()
                }
            }
            Button("Verpassten Trade erfassen…", systemImage: "plus") {
                bearbeiten = VerpasstAuswahl(eintrag: tagModell.neuerVerpasster(), neu: true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(thema.akzent)
        }
        .sheet(item: $bearbeiten) { auswahl in
            VerpasstFormular(tagModell: tagModell, eintrag: auswahl.eintrag, neu: auswahl.neu,
                             setups: setups)
        }
    }

    @Environment(AppModell.self) private var modell
    private var setups: [String] { modell.bekannteSetups }
}

struct VerpasstAuswahl: Identifiable {
    let eintrag: VerpassterTrade
    let neu: Bool
    var id: String { eintrag.id }
}

struct VerpasstZeile: View {
    let eintrag: VerpassterTrade
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                Text(verbatim: kopf)
                    .foregroundStyle(thema.text)
                Text(verbatim: unterzeile)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Spacer()
            Text(verbatim: Format.r(eintrag.ergebnisR))
                .font(Schrift.tabelle)
                .foregroundStyle(eintrag.grund == .regelSperre ? thema.textSchwach : thema.text)
        }
        .contentShape(Rectangle())
    }

    private var kopf: String {
        var teile = [Format.uhrzeit(eintrag.zeit), "\(eintrag.symbol) \(Format.richtung(eintrag.seite))"]
        if let setup = eintrag.setup, !setup.isEmpty { teile.append(setup) }
        return teile.joined(separator: " · ")
    }

    private var unterzeile: String {
        eintrag.grund == .regelSperre
            ? String(localized: "Regelsperre · gewollt verpasst")
            : eintrag.grund.titel
    }
}

/// Blatt „Verpassten Trade erfassen“ (auch zum Bearbeiten).
struct VerpasstFormular: View {
    let tagModell: TagModell
    let neu: Bool
    let setups: [String]
    @State private var eintrag: VerpassterTrade
    @State private var setupText: String
    @State private var fehler: String?
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen

    init(tagModell: TagModell, eintrag: VerpassterTrade, neu: Bool, setups: [String]) {
        self.tagModell = tagModell
        self.neu = neu
        self.setups = setups
        _eintrag = State(initialValue: eintrag)
        _setupText = State(initialValue: eintrag.setup ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Zeit", selection: $eintrag.zeit)
                    TextField("Symbol", text: $eintrag.symbol, prompt: Text(verbatim: "DE40"))
                    Picker("Richtung", selection: $eintrag.seite) {
                        Text("Long").tag(Side.buy)
                        Text("Short").tag(Side.sell)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField("Setup (freiwillig)", text: $setupText)
                        if !setups.isEmpty {
                            Menu {
                                ForEach(setups, id: \.self) { setup in
                                    Button(setup) { setupText = setup }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .menuStyle(.button)
                            .fixedSize()
                            .accessibilityLabel(Text("Bekannte Setups"))
                        }
                    }
                }
                Section {
                    Picker("Grund", selection: $eintrag.grund) {
                        ForEach(VerpassterTrade.Grund.allCases, id: \.self) { grund in
                            Text(verbatim: grund.titel).tag(grund)
                        }
                    }
                    TextField("Geschätztes Ergebnis in R (freiwillig)", value: $eintrag.ergebnisR,
                              format: .number.precision(.fractionLength(0...2)))
                    TextField("Notiz", text: $eintrag.notiz, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("„Regelsperre“ heißt: deine eigene Regel hat den Trade verboten. Er zählt als gewollt verpasst und nicht zum entgangenen Ergebnis.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                if let fehler {
                    Section {
                        Text(verbatim: fehler)
                            .foregroundStyle(thema.verlust)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(neu ? "Verpassten Trade erfassen" : "Verpassten Trade bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { sichern() }
                        .disabled(symbol.isEmpty)
                }
                if !neu {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Löschen", role: .destructive) {
                            tagModell.loesche(eintrag)
                            schliessen()
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    private var symbol: String { eintrag.symbol.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func sichern() {
        var fertig = eintrag
        fertig.symbol = symbol.uppercased()
        let setup = setupText.trimmingCharacters(in: .whitespacesAndNewlines)
        fertig.setup = setup.isEmpty ? nil : setup
        fertig.notiz = eintrag.notiz.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try tagModell.speichere(fertig)
            schliessen()
        } catch {
            fehler = error.localizedDescription
        }
    }
}
