import SwiftUI
import TradingCore
import TradingNews

/// Was die Seite zeigt: alles, nur die Merkliste oder nur den Markt.
enum Nachrichtenfilter: String, CaseIterable, Hashable {
    case alle, merkliste, markt

    var titel: String {
        switch self {
        case .alle: String(localized: "Alle")
        case .merkliste: String(localized: "Merkliste")
        case .markt: String(localized: "Markt")
        }
    }
}

/// Seite „Nachrichten“ (Doc 26, R6; Tims Entscheidungen 02.10.2026): Meldungen zur Merkliste und zum Markt,
/// nur Überschrift, Anriss, Quelle, Zeit und Link, der im Browser öffnet. Rechts Merkliste und Quellen
/// (Tims Wahl 02:54 UTC: rechte Spalte, bestätigt 03:12 UTC), am iPhone darunter. Entwurf: design/Nachrichten_Entwurf.png.
struct NachrichtenView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var breite
    #endif
    @State private var filter = Nachrichtenfilter.alle
    /// Stand beim Öffnen der Seite; was danach kam, ist „neu“. Ohne früheren Besuch: die letzten 24 Stunden.
    @State private var gesehenBis = Date.now.addingTimeInterval(-86_400)

    var body: some View {
        let dienst = modell.nachrichten
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Nachrichten", untertitel: untertitel(dienst)) {
                    kopfRechts(dienst)
                }
                if dienst.aktiv {
                    NachrichtenKacheln(dienst: dienst, gesehenBis: gesehenBis)
                    inhalt(dienst)
                } else {
                    AusKarte(dienst: dienst)
                }
            }
            .padding(Abstand.seitenrand)
        }
        .task { await starte(dienst) }
        .onDisappear { dienst.markiereGesehen() }
    }

    private func untertitel(_ dienst: Nachrichtendienst) -> String {
        guard dienst.aktiv else { return String(localized: "Merkliste und Markt · aus") }
        if let stand = dienst.letzterAbruf {
            return String(localized: "Merkliste und Markt · Stand \(Format.uhrzeit(stand)) · Abruf beim Öffnen und auf Knopf")
        }
        return String(localized: "Merkliste und Markt · Abruf beim Öffnen und auf Knopf")
    }

    @ViewBuilder
    private func kopfRechts(_ dienst: Nachrichtendienst) -> some View {
        if dienst.laedt {
            ProgressView()
                .controlSize(.small)
        }
        Button {
            Task { await dienst.aktualisiere() }
        } label: {
            Label("Aktualisieren", systemImage: "arrow.clockwise")
        }
        .disabled(!dienst.aktiv || dienst.laedt)
        Auswahlknopf("Anzeige", anzeige: filter.titel, auswahl: $filter) {
            ForEach(Nachrichtenfilter.allCases, id: \.self) { wahl in
                Text(verbatim: wahl.titel).tag(wahl)
            }
        }
    }

    @ViewBuilder
    private func inhalt(_ dienst: Nachrichtendienst) -> some View {
        #if os(iOS)
        if breite == .compact {
            linkeSpalte(dienst)
            rechteSpalte(dienst)
        } else {
            zweiSpalten(dienst)
        }
        #else
        zweiSpalten(dienst)
        #endif
    }

    private func zweiSpalten(_ dienst: Nachrichtendienst) -> some View {
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            linkeSpalte(dienst)
                .frame(maxWidth: .infinity, alignment: .leading)
            rechteSpalte(dienst)
                .frame(width: Abstand.inspektor)
        }
    }

    private func linkeSpalte(_ dienst: Nachrichtendienst) -> some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            if filter != .markt {
                MerklisteMeldungen(dienst: dienst, gesehenBis: gesehenBis)
            }
            if filter != .merkliste {
                MarktMeldungen(dienst: dienst, gesehenBis: gesehenBis)
            }
        }
    }

    private func rechteSpalte(_ dienst: Nachrichtendienst) -> some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            MerklisteKarte(dienst: dienst)
            QuellenKarte(dienst: dienst)
        }
    }

    private func starte(_ dienst: Nachrichtendienst) async {
        if let gesehen = dienst.gesehenBis { gesehenBis = gesehen }
        await dienst.starte()
        dienst.ergaenzeVorschlaege(trades: modell.alleTrades,
                                   offeneSymbole: Array(Set(modell.offenePositionen.map(\.symbol))))
        await dienst.aktualisiere(wennAelterAls: 15 * 60)
    }
}

/// Karte, solange die Nachrichten aus sind: erklärt die Quellen und schaltet ein.
private struct AusKarte: View {
    let dienst: Nachrichtendienst
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Nachrichten sind aus") {
            VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                Text("Nach dem Einschalten holt die App Überschriften von finanzen.net, Börse Frankfurt, wallstreet-online, finanznachrichten.de, EZB und Fed (RSS, ohne Schlüssel), US-Firmennachrichten über Alpaca News und Meldungen zur Merkliste über Marketaux (beide mit Schlüssel aus dem Schlüsselbund). Jede Verbindung geht direkt von deinem Gerät zum Anbieter; die App zeigt nur Überschrift, Anriss, Quelle, Zeit und Link.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                Toggle("Nachrichten abrufen", isOn: Binding(get: { dienst.aktiv }, set: { dienst.setzeAktiv($0) }))
                    .toggleStyle(.switch)
            }
        }
    }
}

/// Vier Kacheln: neu seit dem letzten Besuch, Merkliste, Quellen, Marketaux-Budget.
private struct NachrichtenKacheln: View {
    let dienst: Nachrichtendienst
    let gesehenBis: Date

    var body: some View {
        let neu = dienst.meldungen.filter { $0.zeit > gesehenBis }.count
        let neuMerkliste = dienst.zurMerkliste.filter { $0.zeit > gesehenBis }.count
        let offen = dienst.vorschlaege.count
        LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Neu seit letztem Besuch", wert: String(neu),
                   zusatz: String(localized: "Meldungen · \(neuMerkliste) zur Merkliste"))
            Kachel(titel: "Merkliste", wert: String(dienst.aktiveEintraege.count),
                   zusatz: offen == 0 ? String(localized: "Begriffe · keine Vorschläge offen")
                                      : String(localized: "Begriffe · \(offen) Vorschläge offen"))
            Kachel(titel: "Quellen", wert: String(dienst.aktiveQuellen), zusatz: quellenText)
            Kachel(titel: "Marketaux heute", wert: marketauxWert, zusatz: marketauxZusatz)
        }
    }

    private var quellenText: String {
        let rss = Nachrichtendienst.rssQuellen.filter { dienst.istAn($0) }.count
        let weitere = [Nachrichtendienst.alpaca, Nachrichtendienst.marketaux].filter { dienst.istAn($0) }
        return ([String(localized: "\(rss) RSS")] + weitere).joined(separator: " · ")
    }

    private var marketauxWert: String {
        guard dienst.istAn(Nachrichtendienst.marketaux), let rest = dienst.marketauxRest else { return "–" }
        return String(Marketaux.abrufeJeTagGratis - rest)
    }

    private var marketauxZusatz: String {
        guard dienst.istAn(Nachrichtendienst.marketaux) else { return String(localized: "Quelle aus") }
        guard dienst.marketauxRest != nil else { return String(localized: "noch kein Abruf") }
        return String(localized: "von \(Marketaux.abrufeJeTagGratis) Abrufen · \(Marketaux.artikelJeAbruf) Artikel je Begriff")
    }
}

/// Karte „Zur Merkliste“: je aktivem Eintrag die passenden Meldungen, drei voraus, auf Wunsch alle.
private struct MerklisteMeldungen: View {
    let dienst: Nachrichtendienst
    let gesehenBis: Date
    @State private var offen: Set<String> = []
    @Environment(\.thema) private var thema

    private static let vorschau = 3

    var body: some View {
        let eintraege = dienst.aktiveEintraege
        Karte("Zur Merkliste") {
            if eintraege.isEmpty {
                Text("Noch keine Merkliste. Rechts Vorschläge aus dem Journal bestätigen oder einen Begriff eintragen.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                    ForEach(Array(eintraege.enumerated()), id: \.element.id) { paar in
                        if paar.offset > 0 { Divider() }
                        gruppe(paar.element)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gruppe(_ eintrag: Merklisteneintrag) -> some View {
        let alle = dienst.zuordnung[eintrag.id] ?? []
        let zeigeAlle = offen.contains(eintrag.id)
        let gezeigt = zeigeAlle ? alle : Array(alle.prefix(Self.vorschau))
        HStack(spacing: Abstand.raster * 2) {
            Kapsel(text: eintrag.begriff, betont: true)
            if eintrag.anzeigename != eintrag.begriff {
                Text(verbatim: eintrag.anzeigename)
                    .font(Schrift.fliesstext.weight(.semibold))
            }
            Kapsel(text: Nachrichtenformat.herkunft(eintrag.herkunft))
            Spacer()
            Text(verbatim: Nachrichtenformat.zusammenfassung(alle))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        if alle.isEmpty {
            Text("keine Meldung in den letzten 14 Tagen")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        } else {
            ForEach(gezeigt) { meldung in
                MeldungZeile(meldung: meldung, neu: meldung.zeit > gesehenBis)
            }
            if alle.count > Self.vorschau {
                Button {
                    if zeigeAlle { offen.remove(eintrag.id) } else { offen.insert(eintrag.id) }
                } label: {
                    Text(verbatim: zeigeAlle ? String(localized: "Weniger zeigen")
                                             : String(localized: "Weitere \(alle.count - Self.vorschau) Meldungen zeigen"))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.akzent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Karte „Markt allgemein“: Meldungen, die zu keinem Begriff der Merkliste passen.
private struct MarktMeldungen: View {
    let dienst: Nachrichtendienst
    let gesehenBis: Date
    @State private var alleZeigen = false
    @Environment(\.thema) private var thema

    private static let vorschau = 8
    private static let hoechstens = 60

    var body: some View {
        let alle = dienst.markt
        let gezeigt = Array(alle.prefix(alleZeigen ? Self.hoechstens : Self.vorschau))
        Karte("Markt allgemein") {
            if alle.isEmpty {
                Text(verbatim: dienst.laedt ? String(localized: "Meldungen werden geladen …")
                                            : String(localized: "Noch keine Meldungen. „Aktualisieren“ holt die Feeds; je Quelle höchstens alle 15 Minuten."))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                    ForEach(gezeigt) { meldung in
                        MeldungZeile(meldung: meldung, neu: meldung.zeit > gesehenBis)
                    }
                }
                fusszeile(alle.count)
            }
        }
    }

    private func fusszeile(_ anzahl: Int) -> some View {
        HStack(spacing: Abstand.raster * 2) {
            if anzahl > Self.vorschau {
                Button {
                    alleZeigen.toggle()
                } label: {
                    Text(verbatim: alleZeigen ? String(localized: "Weniger zeigen")
                                              : String(localized: "Weitere \(min(anzahl, Self.hoechstens) - Self.vorschau) Meldungen zeigen"))
                        .foregroundStyle(thema.akzent)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Zwischenspeicher 14 Tage, Älteres fällt weg")
                .foregroundStyle(thema.textSchwach)
        }
        .font(Schrift.beschriftung)
    }
}

/// Eine Meldung: Überschrift, Anriss, Quelle, Zeit, Symbole; Klick öffnet den Link im Browser (nie eingebettet).
struct MeldungZeile: View {
    let meldung: Meldung
    var neu = false
    var kompakt = false
    @Environment(\.thema) private var thema
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: Abstand.raster * 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(neu ? thema.akzent : thema.linie)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                Text(verbatim: meldung.titel)
                    .font(kompakt ? Schrift.beschriftung.weight(.semibold) : Schrift.fliesstext.weight(.semibold))
                    .foregroundStyle(thema.text)
                    .lineLimit(2)
                if !kompakt, let anriss = meldung.anriss, !anriss.isEmpty {
                    Text(verbatim: anriss)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                        .lineLimit(2)
                }
                fusszeile
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openURL(meldung.link) }
    }

    private var fusszeile: some View {
        HStack(spacing: Abstand.raster * 2) {
            Kapsel(text: meldung.quelle)
            Text(verbatim: Nachrichtenformat.zeit(meldung.zeit))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            ForEach(meldung.symbole.prefix(3), id: \.self) { symbol in
                Kapsel(text: symbol, betont: true)
            }
            Spacer()
            if !kompakt {
                Label("Im Browser öffnen", systemImage: "arrow.up.right")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.akzent)
            }
        }
    }
}

/// Rechte Spalte: aktive Begriffe, Vorschläge aus dem Journal zum Bestätigen oder Ablehnen, Eingabe.
private struct MerklisteKarte: View {
    let dienst: Nachrichtendienst
    @State private var eingabe = ""
    @State private var art: Merklisteneintrag.Art?
    @Environment(\.thema) private var thema

    var body: some View {
        let aktive = dienst.aktiveEintraege
        let vorschlaege = dienst.vorschlaege
        Karte("Merkliste") {
            VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                abschnitt("Aktiv", zusatz: String(localized: "\(aktive.count) von \(Merkliste.empfohleneHoechstzahl) empfohlen"),
                          warnung: aktive.count > Merkliste.empfohleneHoechstzahl)
                if aktive.isEmpty {
                    Text("Noch leer. Vorschläge unten bestätigen oder einen Begriff eintragen.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    ForEach(aktive) { eintrag in
                        aktivZeile(eintrag)
                    }
                }
                if !vorschlaege.isEmpty {
                    abschnitt("Vorschläge aus dem Journal", zusatz: String(vorschlaege.count), warnung: false)
                    ForEach(vorschlaege) { eintrag in
                        vorschlagZeile(eintrag)
                    }
                }
                eingabeZeile
                if let fehler = dienst.merklisteFehler {
                    Text(verbatim: fehler)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.verlust)
                }
                Text("Abgelehnte Vorschläge kommen nicht wieder. Ein Begriff zieht Meldungen aus allen Quellen; Marketaux fragt je Begriff 3 Artikel ab und zählt einen Abruf.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    private func abschnitt(_ titel: LocalizedStringKey, zusatz: String, warnung: Bool) -> some View {
        HStack {
            Text(titel)
                .font(Schrift.beschriftung.weight(.semibold))
                .foregroundStyle(thema.textSchwach)
                .textCase(.uppercase)
            Spacer()
            Text(verbatim: zusatz)
                .font(Schrift.beschriftung)
                .foregroundStyle(warnung ? thema.verlust : thema.textSchwach)
        }
    }

    private func aktivZeile(_ eintrag: Merklisteneintrag) -> some View {
        HStack(spacing: Abstand.raster * 2) {
            Kapsel(text: eintrag.begriff, betont: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: eintrag.anzeigename != eintrag.begriff ? eintrag.anzeigename : Nachrichtenformat.art(eintrag.art))
                    .font(Schrift.beschriftung)
                Text(verbatim: Nachrichtenformat.herkunft(eintrag.herkunft))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Spacer()
            Button {
                dienst.entferne(eintrag.id)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(thema.textSchwach)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Entfernen"))
        }
    }

    private func vorschlagZeile(_ eintrag: Merklisteneintrag) -> some View {
        HStack(spacing: Abstand.raster * 2) {
            Kapsel(text: eintrag.begriff)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: Nachrichtenformat.art(eintrag.art))
                    .font(Schrift.beschriftung)
                Text(verbatim: Nachrichtenformat.herkunft(eintrag.herkunft))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Spacer()
            Button {
                dienst.setzeStatus(eintrag.id, .aktiv)
            } label: {
                Image(systemName: "checkmark")
                    .foregroundStyle(thema.gewinn)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Bestätigen"))
            Button {
                dienst.setzeStatus(eintrag.id, .abgelehnt)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(thema.verlust)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Ablehnen"))
        }
    }

    private var eingabeZeile: some View {
        HStack(spacing: Abstand.raster * 2) {
            TextField("Symbol, ISIN, Name oder Stichwort", text: $eingabe)
                .textFieldStyle(.roundedBorder)
                .onSubmit { hinzufuegen() }
            Auswahlknopf("Art", anzeige: artText, auswahl: $art, mitHintergrund: false) {
                Text("automatisch").tag(Merklisteneintrag.Art?.none)
                ForEach(Merklisteneintrag.Art.allCases, id: \.self) { wahl in
                    Text(verbatim: Nachrichtenformat.art(wahl)).tag(Optional(wahl))
                }
            }
            Button("Hinzufügen", action: hinzufuegen)
                .disabled(eingabe.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var artText: String {
        art.map(Nachrichtenformat.art) ?? String(localized: "automatisch")
    }

    private func hinzufuegen() {
        if dienst.fuegeHinzu(eingabe, art: art) {
            eingabe = ""
        }
    }
}

/// Rechte Spalte: Hauptschalter, RSS-Anbieter, Alpaca News, Marketaux mit Tagesbudget; Schlüssel nur im Schlüsselbund.
private struct QuellenKarte: View {
    let dienst: Nachrichtendienst
    @State private var alpacaHinterlegt = Schluesselbund.vorhanden()
    @State private var marketauxHinterlegt = Schluesselbund.textVorhanden(dienst: Schluesselbund.dienstMarketaux)
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Quellen") {
            VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                Toggle("Nachrichten abrufen", isOn: Binding(get: { dienst.aktiv }, set: { dienst.setzeAktiv($0) }))
                    .toggleStyle(.switch)
                Divider()
                ForEach(Nachrichtendienst.rssQuellen, id: \.self) { quelle in
                    quellenZeile(quelle, untertitel: String(localized: "RSS: \(Nachrichtendienst.feedTitel(quelle))"),
                                 fehler: dienst.fehlerText(quelle))
                }
                Divider()
                quellenZeile(Nachrichtendienst.alpaca, untertitel: alpacaText, fehler: dienst.fehlerText(Nachrichtendienst.alpaca))
                quellenZeile(Nachrichtendienst.marketaux, untertitel: marketauxText, fehler: dienst.fehlerText(Nachrichtendienst.marketaux))
                if let rest = dienst.marketauxRest, dienst.istAn(Nachrichtendienst.marketaux) {
                    ProgressView(value: Double(Marketaux.abrufeJeTagGratis - rest), total: Double(Marketaux.abrufeJeTagGratis))
                        .tint(thema.akzent)
                }
                Text("Schlüssel liegen nur im Schlüsselbund: Einstellungen › Kurse. Zusammenfassen von Meldungen läuft über den Connector in Claude, nicht in der App.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .onAppear {
            alpacaHinterlegt = Schluesselbund.vorhanden()
            marketauxHinterlegt = Schluesselbund.textVorhanden(dienst: Schluesselbund.dienstMarketaux)
        }
    }

    private var alpacaText: String {
        alpacaHinterlegt ? String(localized: "US-Firmen, Benzinga · Schlüssel im Schlüsselbund")
                         : String(localized: "US-Firmen, Benzinga · kein Schlüssel (Einstellungen › Kurse)")
    }

    private var marketauxText: String {
        guard marketauxHinterlegt else { return String(localized: "Merkliste weltweit · kein Schlüssel (Einstellungen › Kurse)") }
        guard let rest = dienst.marketauxRest else { return String(localized: "Merkliste weltweit · noch kein Abruf heute") }
        return String(localized: "Merkliste weltweit · \(Marketaux.abrufeJeTagGratis - rest) von \(Marketaux.abrufeJeTagGratis) Abrufen heute")
    }

    private func quellenZeile(_ quelle: String, untertitel: String, fehler: String?) -> some View {
        HStack(alignment: .top, spacing: Abstand.raster * 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: quelle)
                    .font(Schrift.fliesstext)
                Text(verbatim: untertitel)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                if let fehler {
                    Text(verbatim: fehler)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.verlust)
                        .lineLimit(2)
                }
            }
            Spacer()
            Toggle(quelle, isOn: Binding(get: { dienst.istAn(quelle) }, set: { dienst.setzeQuelle(quelle, an: $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// Karte in der Übersicht: die drei neuesten Meldungen zur Merkliste, „Alle“ springt zur Seite.
/// Erscheint nur, wenn die Nachrichten eingeschaltet sind; beim Start der App läuft nichts.
struct NachrichtenKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let dienst = modell.nachrichten
        if dienst.aktiv {
            let neueste = Array(dienst.zurMerkliste.prefix(3))
            Karte("Nachrichten zur Merkliste", aktion: { modell.bereich = .nachrichten }) {
                if dienst.aktiveEintraege.isEmpty {
                    Text("Noch keine Merkliste. Auf der Seite „Nachrichten“ Vorschläge aus dem Journal bestätigen.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                } else if neueste.isEmpty {
                    Text("Keine Meldung zur Merkliste in den letzten 14 Tagen.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                        ForEach(neueste) { meldung in
                            MeldungZeile(meldung: meldung, kompakt: true)
                        }
                    }
                }
            }
            .task {
                await dienst.starte()
                await dienst.aktualisiere(wennAelterAls: 60 * 60)
            }
        }
    }
}

/// Texte für die Nachrichtenseite.
enum Nachrichtenformat {
    /// „gerade eben“, „vor 12 Min.“, „09:05“, „gestern 22:10“, sonst „30.09., 17:40“.
    static func zeit(_ datum: Date, jetzt: Date = .now) -> String {
        let minuten = Int(jetzt.timeIntervalSince(datum) / 60)
        if minuten < 1 { return String(localized: "gerade eben") }
        if minuten < 60 { return String(localized: "vor \(minuten) Min.") }
        let kalender = Calendar.current
        if kalender.isDateInToday(datum) { return Format.uhrzeit(datum) }
        if kalender.isDateInYesterday(datum) { return String(localized: "gestern \(Format.uhrzeit(datum))") }
        return Format.zeit(datum)
    }

    static func herkunft(_ herkunft: Merklisteneintrag.Herkunft) -> String {
        switch herkunft {
        case .offenePosition: String(localized: "offene Position")
        case .letzteTage: String(localized: "letzte \(Merkliste.vorschlagTage) Tage")
        case .vonHand: String(localized: "von Hand")
        }
    }

    static func art(_ art: Merklisteneintrag.Art) -> String {
        switch art {
        case .symbol: String(localized: "Symbol")
        case .isin: String(localized: "ISIN")
        case .name: String(localized: "Name")
        case .stichwort: String(localized: "Stichwort")
        }
    }

    /// „3 Meldungen · finanzen.net, Benzinga“.
    static func zusammenfassung(_ meldungen: [Meldung]) -> String {
        guard !meldungen.isEmpty else { return String(localized: "keine Meldung") }
        var gesehen = Set<String>()
        let quellen = meldungen.map(\.quelle).filter { gesehen.insert($0).inserted }.prefix(3).joined(separator: ", ")
        let anzahl = meldungen.count == 1 ? String(localized: "1 Meldung") : String(localized: "\(meldungen.count) Meldungen")
        return anzahl + " · " + quellen
    }
}
