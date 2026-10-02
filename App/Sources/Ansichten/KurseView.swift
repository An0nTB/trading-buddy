import SwiftUI
import TradingCore
import TradingQuotes

/// Karte „Offene Positionen“ auf der Übersicht (P10, Stand-Doc 20): offene Positionen des letzten MT4-Auszugs und
/// offene Käufe aus der Positionsbildung mit aktuellem Kurs, Buchgewinn, Alter des Kurses und Zuordnungshinweis.
/// Ohne eingeschaltete Kurse stehen die Werte laut Auszug; ein Knopf schaltet die Kurse ein.
struct KurseKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var zuordnungenZeigen = false

    var body: some View {
        let positionen = modell.offenePositionen
        if !positionen.isEmpty {
            TimelineView(.periodic(from: .now, by: 5)) { kontext in
                Karte("Offene Positionen") {
                    ForEach(positionen) { position in
                        zeile(position, jetzt: kontext.date)
                    }
                    fusszeile(positionen, jetzt: kontext.date)
                }
            }
            .sheet(isPresented: $zuordnungenZeigen) {
                ZuordnungenBlatt(symbole: Array(Set(positionen.map(\.symbol))).sorted())
            }
        }
    }

    @ViewBuilder private func zeile(_ p: OffenePosition, jetzt: Date) -> some View {
        let kurse = modell.kurse
        let wahl = kurse.zuordnung(fuer: p.symbol)
        let eintrag = kurse.stand.kurse[p.symbol]
        let bewertung = eintrag?.kurs.bewertungskurs(kaufposition: p.seite == .buy).map { p.bewertung(kurs: $0) }
        let waehrung = p.waehrung ?? modell.waehrung
        HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                HStack(spacing: Abstand.raster) {
                    Text(verbatim: "\(p.symbol) \(Format.richtung(p.seite))")
                        .foregroundStyle(thema.text)
                    Text(verbatim: Format.lots(p.menge))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                    if case .vorschlag = wahl {
                        Kapsel(text: String(localized: "Vorschlag"))
                    }
                    if eintrag?.naeherung != nil || bewertung?.unsicher == true {
                        Kapsel(text: String(localized: "Näherung"), betont: true)
                    }
                }
                Text(verbatim: untertitel(p, eintrag: eintrag, wahl: wahl, jetzt: jetzt))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(veraltet(eintrag, jetzt: jetzt) ? thema.verlust : thema.textSchwach)
            }
            Spacer()
            if let netto = bewertung?.netto {
                Text(verbatim: Format.geld(netto, waehrung))
                    .font(Schrift.tabelle)
                    .foregroundStyle(thema.vorzeichen(netto))
            } else if let laut = p.ergebnisLautAuszug {
                Text(verbatim: Format.geld(laut, waehrung))
                    .font(Schrift.tabelle)
                    .foregroundStyle(thema.textSchwach)
            } else {
                Text("–")
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { AnalyseMenuePunkt(symbol: p.symbol) }
    }

    private func untertitel(_ p: OffenePosition, eintrag: Kursstand.Eintrag?, wahl: Zuordnungswahl, jetzt: Date) -> String {
        var teile = [String(localized: "Einstieg \(Format.kurs(p.einstieg))")]
        if let eintrag, let preis = eintrag.kurs.bewertungskurs(kaufposition: p.seite == .buy) {
            let alter = Int(eintrag.kurs.alter(jetzt: jetzt).rounded())
            let wann = alter < 60 ? String(localized: "vor \(alter) s") : String(localized: "vor \(alter / 60) Min.")
            teile.append(String(localized: "Kurs \(Format.kurs(preis)) (\(wann), \(modell.kurse.quellenname(eintrag.kurs.quelle)))"))
            if let hinweis = eintrag.naeherung { teile.append(hinweis.uebersetzt) }
        } else if let grund = modell.kurse.stand.ohneQuelle[p.symbol] ?? wahl.grund {
            teile.append(grund.uebersetzt)
        } else if let auszugskurs = p.auszugskurs {
            teile.append(String(localized: "Kurs laut Auszug \(Format.kurs(auszugskurs))"))
            if let zuordnung = wahl.zuordnung {
                teile.append(modell.kurse.aktiv
                    ? String(localized: "wartet auf \(modell.kurse.quellenname(zuordnung.quelle))")
                    : String(localized: "Kurse aus"))
            }
        } else if let zuordnung = wahl.zuordnung {
            teile.append(modell.kurse.aktiv
                ? String(localized: "wartet auf \(modell.kurse.quellenname(zuordnung.quelle))")
                : String(localized: "Kurse aus"))
        }
        return teile.joined(separator: " · ")
    }

    private func veraltet(_ eintrag: Kursstand.Eintrag?, jetzt: Date) -> Bool {
        eintrag?.kurs.istVeraltet(jetzt: jetzt) ?? false
    }

    @ViewBuilder private func fusszeile(_ positionen: [OffenePosition], jetzt: Date) -> some View {
        let kurse = modell.kurse
        let bewertungen = positionen.compactMap { p in
            kurse.stand.kurse[p.symbol]?.kurs.bewertungskurs(kaufposition: p.seite == .buy).map { p.bewertung(kurs: $0) }
        }
        HStack(spacing: Abstand.raster * 2) {
            if let summe = OffeneBewertung.summe(bewertungen), bewertungen.count == positionen.count {
                Text("Summe \(Format.geld(summe, modell.waehrung))")
                    .font(Schrift.tabelle)
                    .foregroundStyle(thema.vorzeichen(summe))
            } else if !bewertungen.isEmpty {
                Text("Summe unvollständig: nicht jede Position hat einen Kurs in derselben Währung.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Spacer()
            if !kurse.aktiv {
                Button("Kurse einschalten") { kurse.setzeAktiv(true) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Zuordnungen…") { zuordnungenZeigen = true }
                .buttonStyle(.bordered)
        }
        if kurse.aktiv, !kurse.stand.verbindungen.isEmpty {
            HStack(spacing: Abstand.raster * 2) {
                ForEach(kurse.stand.verbindungen.keys.sorted(), id: \.self) { id in
                    Kapsel(text: Verbindungstext.kurz(kurse.quellenname(id), kurse.stand.verbindungen[id]),
                           betont: kurse.stand.verbindungen[id] == .verbunden)
                }
            }
        }
        Text(verbatim: hinweis(positionen))
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func hinweis(_ positionen: [OffenePosition]) -> String {
        var teile: [String] = []
        if let auszug = modell.offenerAuszug {
            teile.append(String(localized: "Offen laut MT4-Auszug vom \(Format.datum(auszug.importlauf.stichtag)); was seither geschlossen wurde, kennt die App erst nach dem nächsten Import."))
        }
        if positionen.contains(where: { $0.waehrung != nil }) {
            teile.append(String(localized: "Offene Käufe aus Ausführungen: Stück mal Kurs gegen den Einstand, Kurs in der Währung der Ausführung."))
        }
        teile.append(modell.kurse.aktiv
            ? String(localized: "Buchgewinn aus der Kursbewegung, ohne Kosten der Schließung; Kauf zum Geldkurs, Verkauf zum Briefkurs bewertet. Kurse über 30 s alt werden rot.")
            : String(localized: "Kurse sind aus: Die App verbindet sich erst nach dem Einschalten mit Kraken, Coinbase, Binance oder Alpaca."))
        return teile.joined(separator: " ")
    }
}

enum Verbindungstext {
    static func kurz(_ name: String, _ status: Verbindungsstatus?) -> String {
        switch status {
        case .verbunden: String(localized: "\(name) verbunden")
        case .getrennt: String(localized: "\(name) getrennt, verbindet neu")
        case .beendet(let grund): String(localized: "\(name) beendet: \(grund.uebersetzt)")
        case .none: name
        }
    }

    static func lang(_ status: Verbindungsstatus) -> String {
        switch status {
        case .verbunden: String(localized: "verbunden")
        case .getrennt(let grund): String(localized: "getrennt (\(grund)), verbindet sich neu")
        case .beendet(let grund): String(localized: "beendet: \(grund.uebersetzt)")
        }
    }
}

/// Blatt „Zuordnungen“: je offenem Symbol Quelle, Quellsymbol und Hinweis „Näherung“; Vorschlag des Pakets
/// als Vorgabe, eigene Zuordnung überstimmt ihn, „Vorschlag“ stellt ihn wieder her.
struct ZuordnungenBlatt: View {
    let symbole: [String]
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        NavigationStack {
            Form {
                if symbole.isEmpty {
                    Text("Keine offene Position, nichts zuzuordnen.")
                        .foregroundStyle(thema.textSchwach)
                }
                ForEach(symbole, id: \.self) { symbol in
                    Section(symbol) {
                        ZuordnungZeile(symbol: symbol)
                    }
                }
                Section {
                    Text("Quellen: Kraken, Coinbase, Binance (Krypto, ohne Schlüssel), Alpaca (US-Aktien, Schlüssel in den Einstellungen unter „Kurse“). CFDs und Devisen des Brokers haben keinen freien Kurs; eine Zuordnung auf den Basiswert gilt als Näherung. Deutsche Kurse sind noch nicht angebunden.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Kurszuordnungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { schliessen() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 420)
        #endif
    }
}

/// Eine Zuordnung im Blatt: Entwurf mit Übernehmen, damit kein halbes Quellsymbol den Beobachter neu startet.
struct ZuordnungZeile: View {
    let symbol: String
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var quelle = "kraken"
    @State private var quellSymbol = ""
    @State private var naeherung = ""
    @State private var geladen = false

    private static let quellen = ["kraken", "coinbase", "binance", "alpaca"]

    var body: some View {
        let wahl = modell.kurse.zuordnung(fuer: symbol)
        Group {
            Picker("Quelle", selection: $quelle) {
                ForEach(Self.quellen, id: \.self) { id in
                    Text(verbatim: modell.kurse.quellenname(id)).tag(id)
                }
            }
            TextField("Symbol bei der Quelle", text: $quellSymbol, prompt: Text(verbatim: beispiel))
            TextField("Hinweis „Näherung“ (leer, wenn der Kurs passt)", text: $naeherung)
            HStack {
                statusText(wahl)
                Spacer()
                if case .eigene = wahl {
                    Button("Vorschlag") {
                        modell.kurse.entferneZuordnung(symbol: symbol)
                        geladen = false
                    }
                }
                Button("Übernehmen") {
                    let bereinigt = quellSymbol.trimmingCharacters(in: .whitespaces)
                    let hinweis = naeherung.trimmingCharacters(in: .whitespaces)
                    modell.kurse.setzeZuordnung(Kurszuordnung(journalSymbol: symbol, quelle: quelle, quellSymbol: bereinigt,
                                                              naeherung: hinweis.isEmpty ? nil : hinweis))
                }
                .disabled(quellSymbol.trimmingCharacters(in: .whitespaces).isEmpty || unveraendert(wahl))
            }
        }
        .onAppear { lade(wahl) }
        .onChange(of: modell.kurse.eigene.count) { lade(modell.kurse.zuordnung(fuer: symbol)) }
    }

    private var beispiel: String {
        switch quelle {
        case "alpaca": "AAPL"
        case "binance": "BTCUSDT"
        case "coinbase": "BTC-EUR"
        default: "BTC/EUR"
        }
    }

    private func statusText(_ wahl: Zuordnungswahl) -> some View {
        let text: String
        switch wahl {
        case .eigene: text = String(localized: "Eigene Zuordnung")
        case .vorschlag: text = String(localized: "Vorschlag des Pakets")
        case .ohneQuelle(let grund): text = grund
        }
        return Text(verbatim: text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func unveraendert(_ wahl: Zuordnungswahl) -> Bool {
        guard let z = wahl.zuordnung else { return false }
        return z.quelle == quelle && z.quellSymbol == quellSymbol.trimmingCharacters(in: .whitespaces)
            && (z.naeherung ?? "") == naeherung.trimmingCharacters(in: .whitespaces)
    }

    private func lade(_ wahl: Zuordnungswahl) {
        if let z = wahl.zuordnung {
            quelle = z.quelle
            quellSymbol = z.quellSymbol
            naeherung = z.naeherung ?? ""
        } else if !geladen {
            quelle = "kraken"
            quellSymbol = ""
            naeherung = ""
        }
        geladen = true
    }
}

/// Reiter „Kurse“ der Einstellungen: Schalter, Quellen mit Status, Alpaca-Schlüssel im Schlüsselbund, Zuordnungen.
struct KurseEinstellungen: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var schluesselID = ""
    @State private var geheimnis = ""
    @State private var hinterlegt = Schluesselbund.vorhanden()
    @State private var meldung: String?
    @State private var zuordnungenZeigen = false
    @State private var marketauxToken = ""
    @State private var marketauxHinterlegt = Schluesselbund.textVorhanden(dienst: Schluesselbund.dienstMarketaux)
    @State private var marketauxMeldung: String?

    var body: some View {
        let kurse = modell.kurse
        Section("Kurse") {
            Toggle("Kurse offener Trades abrufen", isOn: Binding(get: { kurse.aktiv }, set: { kurse.setzeAktiv($0) }))
            Text("Krypto in Echtzeit über Kraken, Coinbase oder Binance ohne Schlüssel; US-Aktien in Echtzeit über Alpaca (Teilmarkt IEX, bis 30 Symbole) mit Schlüssel. Jede Verbindung geht direkt von deinem Gerät zum Anbieter. Die App weiß nur aus dem letzten Import, was offen ist.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            if kurse.aktiv {
                ForEach(kurse.quellen.map { $0.id }, id: \.self) { id in
                    LabeledContent(kurse.quellenname(id)) {
                        Text(verbatim: kurse.stand.verbindungen[id].map(Verbindungstext.lang) ?? String(localized: "nicht gebraucht"))
                            .foregroundStyle(thema.textSchwach)
                    }
                }
            }
        }
        Section("Alpaca (US-Aktien)") {
            LabeledContent("Stand") {
                Text(verbatim: hinterlegt ? String(localized: "Schlüssel im Schlüsselbund hinterlegt") : String(localized: "kein Schlüssel"))
                    .foregroundStyle(thema.textSchwach)
            }
            SecureField("Schlüssel-ID (API Key ID)", text: $schluesselID)
            SecureField("Geheimnis (Secret Key)", text: $geheimnis)
            HStack {
                Button("Im Schlüsselbund speichern", action: speichern)
                    .disabled(schluesselID.trimmingCharacters(in: .whitespaces).isEmpty || geheimnis.isEmpty)
                if hinterlegt {
                    Button("Entfernen", role: .destructive, action: entfernen)
                }
            }
            if let meldung {
                Text(verbatim: meldung)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Text("Der Schlüssel liegt nur im Schlüsselbund dieses Geräts, nie in einer Datei oder im Export. Einen Schlüssel bekommst du im Alpaca-Konto unter „API Keys“; ein Paper-Konto reicht für Kurse. Derselbe Schlüssel holt auch die Firmen-Nachrichten (Alpaca News).")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        Section("Marketaux (Nachrichten zur Merkliste)") {
            LabeledContent("Stand") {
                Text(verbatim: marketauxHinterlegt ? String(localized: "Token im Schlüsselbund hinterlegt") : String(localized: "kein Token"))
                    .foregroundStyle(thema.textSchwach)
            }
            SecureField("API-Token", text: $marketauxToken)
            HStack {
                Button("Im Schlüsselbund speichern", action: marketauxSpeichern)
                    .disabled(marketauxToken.trimmingCharacters(in: .whitespaces).isEmpty)
                if marketauxHinterlegt {
                    Button("Entfernen", role: .destructive, action: marketauxEntfernen)
                }
            }
            if let marketauxMeldung {
                Text(verbatim: marketauxMeldung)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Text("Gratis-Konto mit 100 Abrufen am Tag, je Abruf drei Artikel. Die App zählt die Abrufe mit und hört bei der Grenze auf. Ohne Token laufen nur die deutschen RSS-Quellen und Alpaca News.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        Section("Zuordnungen") {
            Button("Zuordnungen der offenen Symbole…") { zuordnungenZeigen = true }
            Text("\(kurse.eigene.count) eigene Zuordnungen gespeichert; alles andere folgt dem Vorschlag des Pakets.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        .sheet(isPresented: $zuordnungenZeigen) {
            ZuordnungenBlatt(symbole: Array(Set(modell.offenePositionen.map(\.symbol))).sorted())
                .environment(modell)
        }
    }

    private func speichern() {
        do {
            try Schluesselbund.speichere(AlpacaSchluessel(schluesselID: schluesselID.trimmingCharacters(in: .whitespaces),
                                                          geheimnis: geheimnis))
            schluesselID = ""
            geheimnis = ""
            hinterlegt = true
            meldung = Ton.aktuell.text("Gespeichert. Alpaca verbindet sich neu.", henry: "Hinterlegt. Alpaca verbindet sich neu.")
            modell.kurse.neustart()
            modell.nachrichten.neustart()
        } catch let fehler as Schluesselbund.Fehler {
            meldung = fehler.text
        } catch {
            meldung = error.localizedDescription
        }
    }

    private func entfernen() {
        do {
            try Schluesselbund.loesche()
            hinterlegt = false
            meldung = Ton.aktuell.text("Entfernt.", henry: "Zurückgezogen.")
            modell.kurse.neustart()
            modell.nachrichten.neustart()
        } catch let fehler as Schluesselbund.Fehler {
            meldung = fehler.text
        } catch {
            meldung = error.localizedDescription
        }
    }

    private func marketauxSpeichern() {
        do {
            try Schluesselbund.speichereText(marketauxToken.trimmingCharacters(in: .whitespaces),
                                             dienst: Schluesselbund.dienstMarketaux)
            marketauxToken = ""
            marketauxHinterlegt = true
            marketauxMeldung = Ton.aktuell.text("Gespeichert. Marketaux wird beim nächsten Abruf genutzt.", henry: "Hinterlegt. Marketaux wird beim nächsten Abruf genutzt.")
            modell.nachrichten.neustart()
        } catch let fehler as Schluesselbund.Fehler {
            marketauxMeldung = fehler.text
        } catch {
            marketauxMeldung = error.localizedDescription
        }
    }

    private func marketauxEntfernen() {
        do {
            try Schluesselbund.loescheText(dienst: Schluesselbund.dienstMarketaux)
            marketauxHinterlegt = false
            marketauxMeldung = Ton.aktuell.text("Entfernt.", henry: "Zurückgezogen.")
            modell.nachrichten.neustart()
        } catch let fehler as Schluesselbund.Fehler {
            marketauxMeldung = fehler.text
        } catch {
            marketauxMeldung = error.localizedDescription
        }
    }
}
