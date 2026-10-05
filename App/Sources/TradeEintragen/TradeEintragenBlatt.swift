import SwiftUI
import TradingCore
import TradingStore

/// Knopf „Trade eintragen“ mit eigenem Blatt, für die Kopfzeile der Trades.
struct TradeEintragenKnopf: View {
    @State private var offen = false

    var body: some View {
        Button("Trade eintragen") { offen = true }
            .buttonStyle(.borderedProminent)
            .sheet(isPresented: $offen) { TradeEintragenBlatt() }
    }
}

/// Formular „Trade eintragen“ nach der Vorlage des Browser-Journals (Doc 02 Nr. 63): Zeit, Asset, Markterwartung,
/// Abrechnung (Schein oder direkt), Setup, Zeiteinheit, Größe und Kurse, Stop als Kurs oder Risiko, Gebühren, Konto,
/// Plan eingehalten, Gedanken. Kein Chart-Link; nur geschlossene Trades.
struct TradeEintragenBlatt: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen
    @State private var entwurf = TradeEntwurf()
    @State private var hebelprodukt: Hebelprodukt?
    @State private var fehler: String?
    @State private var vorbelegt = false

    var body: some View {
        NavigationStack {
            Form {
                zeitAbschnitt
                assetAbschnitt
                setupAbschnitt
                ausfuehrungAbschnitt
                risikoAbschnitt
                kontoAbschnitt
                reviewAbschnitt
                ergebnisAbschnitt
            }
            .formStyle(.grouped)
            .navigationTitle("Neuer Trade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schliessen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Trade sichern") { sichern() }
                        .disabled(!entwurf.speicherbar)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .onAppear(perform: vorbelegen)
    }

    // MARK: Abschnitte

    private var zeitAbschnitt: some View {
        Section("Zeit") {
            DatePicker("Einstieg", selection: $entwurf.einstieg, displayedComponents: [.date, .hourAndMinute])
            Toggle("Ausstiegszeit bekannt", isOn: $entwurf.ausstiegBekannt)
            if entwurf.ausstiegBekannt {
                DatePicker("Ausstieg", selection: $entwurf.ausstieg, in: entwurf.einstieg...,
                           displayedComponents: [.date, .hourAndMinute])
            } else {
                hinweis("Ohne Ausstiegszeit zählt der Trade nur mit Datum; Uhrzeit- und Haltedauer-Auswertungen lassen ihn aus.")
            }
        }
    }

    private var assetAbschnitt: some View {
        Section("Asset") {
            HStack {
                TextField("Asset", text: $entwurf.symbol, prompt: Text("SAP, DAX, Gold …"))
                    .onSubmit(pruefeHebelprodukt)
                if !modell.bekannteSymbole.isEmpty {
                    Menu("Bekannte") {
                        ForEach(modell.bekannteSymbole, id: \.self) { symbol in
                            Button(symbol) {
                                entwurf.symbol = symbol
                                pruefeHebelprodukt()
                            }
                        }
                    }
                    .fixedSize()
                }
            }
            if let hebelprodukt {
                hinweisText(Self.hebelText(hebelprodukt))
            }
            Picker("Richtung (Markterwartung)", selection: $entwurf.markterwartung) {
                Text("Long").tag(Side.buy)
                Text("Short").tag(Side.sell)
            }
            .pickerStyle(.segmented)
            Picker("Abrechnung", selection: $entwurf.schein) {
                Text("Schein gekauft").tag(true)
                Text("Direkt gehandelt").tag(false)
            }
            .pickerStyle(.segmented)
            if entwurf.schein {
                hinweis("Knock-out, Optionsschein, Zertifikat: Gewinn bei steigendem Scheinpreis, auch bei Short.")
            } else {
                hinweis("Aktie, CFD, Future: Short dreht das Vorzeichen.")
            }
            if !entwurf.schein {
                Picker("Assetklasse", selection: $entwurf.produktart) {
                    Text("Ohne Angabe").tag(Produktart.unbekannt)
                    ForEach(Produktartformat.waehlbar, id: \.self) { art in
                        Text(verbatim: Produktartformat.titel(art)).tag(art)
                    }
                }
            }
        }
        .onChange(of: entwurf.symbol) { _, _ in
            if hebelprodukt != nil, Hebelprodukt.erkenne(entwurf.symbol) == nil { hebelprodukt = nil }
        }
    }

    private var setupAbschnitt: some View {
        Section("Setup") {
            Picker("Setup", selection: $entwurf.setup) {
                Text("Ohne").tag("")
                ForEach(setupNamen, id: \.self) { name in
                    Text(verbatim: name).tag(name)
                }
            }
            Picker("Zeiteinheit", selection: $entwurf.zeiteinheit) {
                Text("Ohne").tag("")
                ForEach(TradeEntwurf.zeiteinheiten, id: \.self) { einheit in
                    Text(verbatim: einheit).tag(einheit)
                }
            }
        }
    }

    private var ausfuehrungAbschnitt: some View {
        Section("Ausführung") {
            zahlFeld("Größe", hilfe: "Stück bzw. € je Punkt", $entwurf.groesse)
            zahlFeld("Entry", hilfe: entwurf.schein ? "Kaufkurs des Scheins" : "Einstiegskurs", $entwurf.einstiegskurs)
            zahlFeld("Exit", hilfe: entwurf.schein ? "Verkaufskurs des Scheins, 0 bei Knock-out" : "Ausstiegskurs",
                     $entwurf.ausstiegskurs)
            zahlFeld("Gebühren", hilfe: "Summe aller Gebühren, positiv", $entwurf.gebuehren)
        }
    }

    private var risikoAbschnitt: some View {
        Section("Stop") {
            Picker("Stop als", selection: $entwurf.stopArt) {
                Text("Kurs").tag(TradeEntwurf.StopArt.kurs)
                Text("Risiko in \(waehrung)").tag(TradeEntwurf.StopArt.risiko)
            }
            .pickerStyle(.segmented)
            switch entwurf.stopArt {
            case .kurs:
                zahlFeld("Stop-Kurs", hilfe: "optional", $entwurf.stopKurs)
            case .risiko:
                zahlFeld("Risiko", hilfe: "optional, ergibt R und den Stop", $entwurf.risiko)
            }
            if entwurf.eigenesRisiko == nil {
                hinweisText(standardRisikoText)
            }
        }
    }

    private var kontoAbschnitt: some View {
        Section("Konto") {
            Picker("Konto", selection: $entwurf.kontowahl) {
                ForEach(modell.konten, id: \.id) { konto in
                    if let id = konto.id {
                        Text(verbatim: "\(konto.broker) · \(konto.kontoname)").tag(TradeEntwurf.Kontowahl.bestehend(id))
                    }
                }
                Text("Neues Konto für Handeinträge").tag(TradeEntwurf.Kontowahl.neu)
            }
            if entwurf.kontowahl == .neu {
                TextField("Name des Kontos", text: $entwurf.neuerKontoname, prompt: Text("z. B. Comdirect Depot"))
                Picker("Währung", selection: $entwurf.neueWaehrung) {
                    ForEach(TradeEntwurf.waehrungen, id: \.self) { code in
                        Text(verbatim: code).tag(code)
                    }
                }
            } else {
                LabeledContent("Währung", value: waehrung)
            }
            hinweis("Beträge in der Währung des Kontos.")
        }
    }

    private var reviewAbschnitt: some View {
        Section("Review") {
            Toggle("Plan eingehalten", isOn: $entwurf.planEingehalten)
            TextField("Gedanken", text: $entwurf.gedanken,
                      prompt: Text("Was war die Idee, wie hast du dich gefühlt, was würdest du anders machen?"),
                      axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var ergebnisAbschnitt: some View {
        Section("Ergebnis") {
            if let netto = entwurf.netto {
                LabeledContent("Netto nach Gebühren") {
                    Text(verbatim: Format.geld(netto, waehrung))
                        .foregroundStyle(netto < 0 ? thema.verlust : thema.text)
                }
                LabeledContent("Ergebnis in R", value: rText)
            } else {
                hinweis("Ergebnis erscheint, sobald Größe, Entry und Exit stehen.")
            }
            ForEach(entwurf.hinderungsgruende, id: \.self) { grund in
                Text(verbatim: grund)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.verlust)
            }
            if let fehler {
                Text(verbatim: fehler)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.verlust)
            }
        }
    }

    // MARK: Bausteine

    private func zahlFeld(_ titel: LocalizedStringKey, hilfe: LocalizedStringKey, _ wert: Binding<Decimal?>) -> some View {
        LabeledContent {
            TextField(titel, value: wert, format: .number.precision(.fractionLength(0...6)))
                .multilineTextAlignment(.trailing)
                .labelsHidden()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(titel)
                Text(hilfe)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    private func hinweis(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func hinweisText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    // MARK: Werte

    /// Setups aus dem Playbook, dazu ein Name aus einem früheren Eintrag, falls die Karte fehlt.
    private var setupNamen: [String] {
        var namen = modell.playbook.map(\.name)
        if !entwurf.setup.isEmpty, !namen.contains(entwurf.setup) { namen.append(entwurf.setup) }
        return namen
    }

    /// Währung des gewählten Kontos, bei neuem Konto die gewählte.
    private var waehrung: String {
        if case .bestehend(let id) = entwurf.kontowahl, let konto = modell.konten.first(where: { $0.id == id }) {
            return konto.waehrung
        }
        return entwurf.neueWaehrung
    }

    private var standardRisiko: (betrag: Decimal, herkunft: Risikoherkunft)? {
        modell.standardRisiko(setup: entwurf.setup, kontowahl: entwurf.kontowahl)
    }

    private var standardRisikoText: String {
        guard let standard = standardRisiko else {
            return String(localized: "Ohne Stop und ohne Standard-Risiko bleibt R offen.")
        }
        let betrag = Format.betrag(standard.betrag, waehrung)
        return standard.herkunft == .setup
            ? String(localized: "Ohne Stop rechnet Henry mit dem Standard-Risiko des Setups: \(betrag) (angenommen).")
            : String(localized: "Ohne Stop rechnet Henry mit dem Standard-Risiko des Kontos: \(betrag) (angenommen).")
    }

    private var rText: String {
        let r = entwurf.rWert(standardRisiko: standardRisiko?.betrag)
        guard r != nil else { return "–" }
        let text = Format.r(r)
        return entwurf.eigenesRisiko == nil ? String(localized: "\(text) (angenommen)") : text
    }

    static func hebelText(_ produkt: Hebelprodukt) -> String {
        let richtung = Format.richtung(produkt.markterwartung)
        return String(localized: "Erkannt: Hebelprodukt \(richtung) auf \(produkt.basiswert). Abrechnung und Richtung sind vorgestellt.")
    }

    // MARK: Handlungen

    private func vorbelegen() {
        guard !vorbelegt else { return }
        vorbelegt = true
        if let id = modell.konto?.id { entwurf.kontowahl = .bestehend(id) }
    }

    private func pruefeHebelprodukt() {
        hebelprodukt = entwurf.uebernimmHebelprodukt()
    }

    private func sichern() {
        guard let trade = entwurf.trade, entwurf.speicherbar else { return }
        do {
            try modell.speichereManuellenTrade(trade, angaben: entwurf.angaben, kontowahl: entwurf.kontowahl,
                                               neuerKontoname: entwurf.neuerKontoname, waehrung: entwurf.neueWaehrung)
            schliessen()
        } catch {
            fehler = Importlesung.fehlertext(error)
        }
    }
}
