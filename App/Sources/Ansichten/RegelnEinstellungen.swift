import SwiftUI
import TradingCore
import TradingStore

/// Reiter „Regeln“ der Einstellungen (P6; Doc 18 F1 und F10, Entscheidung 27): eigene Grenzen und
/// Prop-Firm-Regeln je Konto. Anders als die übrigen Reiter mit Speichern-Knopf: Die Regeln liegen in der
/// Datenbank (AP9, Migration v5), die Speicherung lehnt Grenzen ab, die keine sind, und ein Entwurf lässt
/// sich verwerfen. Geprüft wird nach jedem Import, nicht live (E3).
struct RegelnEinstellungen: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var entwurf = Handelsregeln()
    @State private var geladenFuer: Int64?
    @State private var meldung: String?
    @State private var meldungIstFehler = false
    @State private var vorlagenHinweis: String?

    var body: some View {
        if let konto = modell.konto {
            Group {
                Section {
                    LabeledContent("Konto") { Text(verbatim: "\(konto.broker) · \(konto.kontoname)") }
                    hinweis("Regeln gelten je Konto; das Konto wechselst du im Hauptfenster. Geprüft wird nach jedem Import, nicht live. Beträge in \(konto.waehrung).")
                }
                Section("Eigene Regeln") {
                    betragsgrenze("Höchster Tagesverlust", $entwurf.maxTagesverlust, standard: 100, einheit: konto.waehrung)
                    hinweis("Danach keine neuen Trades am selben Tag. Zählt realisiert netto, Tag in deiner Zeitzone.")
                    anzahlgrenze("Höchstens Trades je Tag", $entwurf.maxTradesJeTag, standard: 3)
                    anzahlgrenze("Stopp nach Verlusten in Folge", $entwurf.stoppNachVerlusten, standard: 2)
                    hinweis("Ein Gewinner oder ein neuer Tag setzt die Zählung zurück.")
                    betragsgrenze("Höchstes Risiko je Trade", $entwurf.maxRisikoJeTrade, standard: 50, einheit: konto.waehrung)
                    hinweis("Abstand Einstieg bis Stop; ein Verlust über der Grenze zählt auch ohne Stop.")
                }
                Section("Prop-Firm") {
                    Toggle("Konto bei einer Prop-Firm", isOn: propFirmAn)
                    if entwurf.propFirm != nil {
                        propFirmFelder(waehrung: konto.waehrung)
                    }
                }
                Section {
                    HStack {
                        Button("Verwerfen") {
                            laden()
                            meldung = nil
                        }
                        .disabled(!geaendert)
                        Spacer()
                        Button("Speichern", action: speichern)
                            .buttonStyle(.borderedProminent)
                            .disabled(!geaendert)
                    }
                    if let meldung {
                        Text(verbatim: meldung)
                            .font(Schrift.beschriftung)
                            .foregroundStyle(meldungIstFehler ? thema.verlust : thema.textSchwach)
                    }
                }
            }
            .onAppear(perform: ladenFallsNoetig)
            .onChange(of: modell.konto?.id) { laden() }
        } else {
            Text("Regeln gehören zu einem Konto. Importiere zuerst einen Kontoauszug.")
                .foregroundStyle(thema.textSchwach)
        }
    }

    private var geaendert: Bool { entwurf != modell.regeln }

    // MARK: Prop-Firm

    private var propFirmAn: Binding<Bool> {
        Binding(get: { entwurf.propFirm != nil },
                set: { an in
                    if an {
                        if entwurf.propFirm == nil { entwurf.propFirm = PropFirmRegeln(name: "", startkapital: 100_000) }
                    } else {
                        entwurf.propFirm = nil
                        vorlagenHinweis = nil
                    }
                })
    }

    /// Bindung an die Prop-Firm-Regeln des Entwurfs; nur benutzt, solange `propFirm` gesetzt ist.
    private var pf: Binding<PropFirmRegeln> {
        Binding(get: { entwurf.propFirm ?? PropFirmRegeln(name: "", startkapital: 0) },
                set: { entwurf.propFirm = $0 })
    }

    /// Konsistenzanteil als Prozent im Formular, im Modell als Anteil (0,5 statt 50).
    private var konsistenzProzent: Binding<Decimal?> {
        Binding(get: { entwurf.propFirm?.konsistenzMaxAnteil.map { $0 * 100 } },
                set: { neu in entwurf.propFirm?.konsistenzMaxAnteil = neu.map { $0 / 100 } })
    }

    @ViewBuilder private func propFirmFelder(waehrung: String) -> some View {
        vorlageUndKopf(waehrung: waehrung)
        verlustgrenzen(waehrung: waehrung)
        zieleUndVerhalten(waehrung: waehrung)
    }

    @ViewBuilder private func vorlageUndKopf(waehrung: String) -> some View {
        let pf = self.pf
        Menu("Vorlage übernehmen") {
            ForEach(Firmenvorlage.firmen, id: \.self) { firma in
                Section(firma) {
                    ForEach(Firmenvorlage.alle.filter { $0.firma == firma }) { vorlage in
                        Button(vorlage.name) { uebernehmen(vorlage) }
                    }
                }
            }
        }
        hinweis("Eine Vorlage füllt alle Felder aus den Regeln der Firma; danach kannst du jedes Feld ändern.")
        if let vorlagenHinweis {
            hinweis(verbatim: vorlagenHinweis)
        }
        TextField("Name", text: pf.name, prompt: Text("z. B. FTMO 2-Step 100K Phase 1"))
        LabeledContent("Startkapital") {
            HStack {
                TextField("Startkapital", value: pf.startkapital, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160)
                    .labelsHidden()
                Text(verbatim: waehrung).foregroundStyle(thema.textSchwach)
            }
        }
        LabeledContent("Zeitzone der Firma") {
            HStack {
                TextField("Zeitzone", text: pf.zeitzone)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .labelsHidden()
                Menu("Häufige") {
                    ForEach(Firmenvorlage.zeitzonen, id: \.self) { zone in
                        Button(zone) { pf.zeitzone.wrappedValue = zone }
                    }
                }
                .fixedSize()
            }
        }
        if TimeZone(identifier: pf.wrappedValue.zeitzone) == nil {
            hinweis(verbatim: String(localized: "Unbekannte Zeitzone; erwartet wird ein Name wie Europe/Prague."), fehler: true)
        }
        LabeledContent("Tageswechsel") {
            HStack {
                TextField("Minuten nach Mitternacht", value: pf.tageswechselMinuten, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .labelsHidden()
                Text("Minuten nach Mitternacht, also \(Self.uhrzeit(pf.wrappedValue.tageswechselMinuten)) Ortszeit")
                    .foregroundStyle(thema.textSchwach)
            }
        }
        hinweis("FTMO und FundedNext 00:00, Topstep 17:00 Chicago, Apex 18:00 New York.")
    }

    @ViewBuilder private func verlustgrenzen(waehrung: String) -> some View {
        let pf = self.pf
        let start = pf.wrappedValue.startkapital
        betragsgrenze("Höchster Tagesverlust", pf.maxTagesverlust, standard: start * 5 / 100, einheit: waehrung, prozentVon: start)
        betragsgrenze("Höchster Gesamtverlust", pf.maxGesamtverlust, standard: start / 10, einheit: waehrung, prozentVon: start)
        Picker("Gesamtgrenze", selection: pf.gesamtverlustart) {
            Text("Fest ab Startkapital").tag(PropFirmRegeln.Gesamtverlustart.statisch)
            Text("Nachgezogen zum Tagesende").tag(PropFirmRegeln.Gesamtverlustart.nachgezogenTagesende)
        }
        .pickerStyle(.segmented)
        if pf.wrappedValue.gesamtverlustart == .nachgezogenTagesende {
            betragsgrenze("Grenze bleibt stehen ab Saldo", pf.einfrierenBeiSaldo, standard: start, einheit: waehrung)
            hinweis("Topstep: beim Startkapital. Apex: Start plus 100. Aus: Die Grenze folgt dem höchsten Tagesend-Saldo ohne Ende.")
        }
        hinweis("Tagesverlust und Gesamtgrenze prüft die App auf Schlusssalden, ohne Equity zwischen den Trades: Ein gemeldeter Verstoß ist sicher, ein fehlender nicht.")
    }

    @ViewBuilder private func zieleUndVerhalten(waehrung: String) -> some View {
        let pf = self.pf
        let start = pf.wrappedValue.startkapital
        betragsgrenze("Gewinnziel", pf.gewinnziel, standard: start / 10, einheit: waehrung, prozentVon: start)
        anzahlgrenze("Mindest-Handelstage", pf.mindestHandelstage, standard: 4)
        Picker("Ein Handelstag zählt bei", selection: pf.handelstagzaehlung) {
            Text("Eröffnung").tag(PropFirmRegeln.Handelstagzaehlung.eroeffnung)
            Text("Ergebnis ungleich 0").tag(PropFirmRegeln.Handelstagzaehlung.ergebnis)
            Text("Gewinntag").tag(PropFirmRegeln.Handelstagzaehlung.gewinntag)
        }
        .pickerStyle(.segmented)
        if pf.wrappedValue.handelstagzaehlung == .gewinntag {
            betragsgrenze("Gewinntag ab Tagesgewinn", pf.mindestTagesgewinn, standard: start * 5 / 1000, einheit: waehrung, prozentVon: start)
            hinweis("Aus: Jeder Tag mit Gewinn zählt.")
        }
        betragsgrenze("Bester Tag höchstens", konsistenzProzent, standard: 50, einheit: "%")
        if pf.wrappedValue.konsistenzMaxAnteil != nil {
            Picker("Bezogen auf", selection: pf.konsistenzbezug) {
                Text("Nettogewinn").tag(PropFirmRegeln.Konsistenzbezug.nettogewinn)
                Text("Summe der Gewinntage").tag(PropFirmRegeln.Konsistenzbezug.summeGewinntage)
            }
            .pickerStyle(.segmented)
        }
        Toggle("Kein Halten über den Tageswechsel", isOn: pf.keinHaltenUeberTageswechsel)
        Toggle("Kein Halten übers Wochenende", isOn: pf.keinHaltenUeberWochenende)
        betragsgrenze("Höchstens Lots je Trade", pf.maxLotsJeTrade, standard: 1, einheit: nil)
        Toggle("Stop-Loss ist Pflicht", isOn: pf.stopPflicht)
    }

    private func uebernehmen(_ vorlage: Firmenvorlage) {
        let bisher = entwurf.propFirm?.startkapital ?? 0
        let start = bisher > 0 ? bisher : vorlage.startkapital
        entwurf.propFirm = vorlage.regeln(startkapital: start)
        vorlagenHinweis = vorlage.hinweis
    }

    // MARK: Felder

    /// Schalter plus Betragsfeld: aus heißt `nil` (Regel aus), an setzt den Vorschlag ein.
    private func betragsgrenze(_ titel: LocalizedStringKey, _ wert: Binding<Decimal?>, standard: Decimal,
                               einheit: String?, prozentVon: Decimal? = nil) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Toggle(titel, isOn: an(wert, standard: standard))
            if let aktuell = wert.wrappedValue {
                HStack {
                    TextField(titel, value: wert, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160)
                        .labelsHidden()
                    if let einheit {
                        Text(verbatim: einheit).foregroundStyle(thema.textSchwach)
                    }
                    if let prozentVon, prozentVon > 0 {
                        Text("entspricht \(Format.prozent(aktuell / prozentVon)) vom Startkapital")
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                }
            }
        }
    }

    private func anzahlgrenze(_ titel: LocalizedStringKey, _ wert: Binding<Int?>, standard: Int) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Toggle(titel, isOn: an(wert, standard: standard))
            if wert.wrappedValue != nil {
                TextField(titel, value: wert, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                    .labelsHidden()
            }
        }
    }

    private func an<Z>(_ wert: Binding<Z?>, standard: Z) -> Binding<Bool> {
        Binding(get: { wert.wrappedValue != nil },
                set: { wert.wrappedValue = $0 ? standard : nil })
    }

    private func hinweis(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func hinweis(verbatim text: String, fehler: Bool = false) -> some View {
        Text(verbatim: text)
            .font(Schrift.beschriftung)
            .foregroundStyle(fehler ? thema.verlust : thema.textSchwach)
    }

    private static func uhrzeit(_ minuten: Int) -> String {
        let m = max(0, min(minuten, 24 * 60 - 1))
        return String(format: "%02ld:%02ld", m / 60, m % 60)
    }

    // MARK: Laden und Speichern

    private func laden() {
        entwurf = modell.regeln
        geladenFuer = modell.konto?.id
        vorlagenHinweis = nil
    }

    private func ladenFallsNoetig() {
        if geladenFuer != modell.konto?.id { laden() }
    }

    private func speichern() {
        do {
            try modell.speichereRegeln(entwurf)
            entwurf = modell.regeln
            meldung = entwurf.leer
                ? String(localized: "Gespeichert, keine Regel aktiv.")
                : Ton.aktuell.text("Gespeichert. Die Übersicht zeigt jetzt Regel-Ampel und Disziplin-Kurve.",
                                   henry: "Festgehalten. Die Übersicht zeigt jetzt Regel-Ampel und Disziplin-Kurve.")
            meldungIstFehler = false
        } catch {
            meldung = Regelfehler.text(error)
            meldungIstFehler = true
        }
    }
}

/// Fehler rund um die Regeln; übersetzt auch die Ablehnungen der Speicherung (kein `LocalizedError`).
enum Regelfehler: Error {
    case keinKonto

    static func text(_ fehler: Error) -> String {
        switch fehler {
        case Regelfehler.keinKonto:
            return String(localized: "Regeln gehören zu einem Konto. Importiere zuerst einen Kontoauszug.")
        case SpeicherFehler.ungueltigerWert(let grund):
            return grund
        case SpeicherFehler.unbekannterWert(let wert):
            return String(localized: "Die Datenbank enthält eine unbekannte Angabe in den Regeln: \(wert)")
        default:
            return fehler.localizedDescription
        }
    }
}

/// Vorlage einer Prop-Firm (Stand-Doc 21): Prozentwerte, aus denen die App beim Übernehmen Beträge rechnet.
/// `geprueft`: am 02.10.2026 gegen die Firmenseite gelesen; sonst Werte aus der Recherche, vom Nutzer zu prüfen.
/// Beträge stehen hier als Prozent vom Startkapital, weil die Firmen so rechnen; `PropFirmRegeln` kennt nur Beträge.
struct Firmenvorlage: Identifiable, Sendable {
    enum Einfrieren: Sendable {
        case nie, startkapital
        case startPlus(Decimal)
    }

    let firma: String
    let name: String
    let geprueft: Bool
    let quelle: String
    var startkapital: Decimal = 100_000
    var zeitzone = "Europe/Prague"
    var tageswechselMinuten = 0
    var tagesverlustProzent: Decimal?
    var gesamtverlustProzent: Decimal?
    /// Fester Betrag statt Prozent (Topstep nennt Dollar je Kontogröße).
    var gesamtverlustBetrag: Decimal?
    var gesamtverlustart = PropFirmRegeln.Gesamtverlustart.statisch
    var einfrieren = Einfrieren.nie
    var gewinnzielProzent: Decimal?
    var mindestHandelstage: Int?
    var handelstagzaehlung = PropFirmRegeln.Handelstagzaehlung.eroeffnung
    var mindestTagesgewinnProzent: Decimal?
    var konsistenzMaxAnteil: Decimal?
    var konsistenzbezug = PropFirmRegeln.Konsistenzbezug.nettogewinn
    var keinHaltenUeberTageswechsel = false
    var keinHaltenUeberWochenende = false
    var bemerkung: String?

    var id: String { firma + " " + name }

    func regeln(startkapital start: Decimal) -> PropFirmRegeln {
        func betrag(_ prozent: Decimal?) -> Decimal? { prozent.map { start * $0 / 100 } }
        let einfrierenBei: Decimal?
        switch einfrieren {
        case .nie: einfrierenBei = nil
        case .startkapital: einfrierenBei = start
        case .startPlus(let plus): einfrierenBei = start + plus
        }
        return PropFirmRegeln(name: "\(firma) \(name)", startkapital: start, zeitzone: zeitzone,
                              tageswechselMinuten: tageswechselMinuten,
                              maxTagesverlust: betrag(tagesverlustProzent),
                              maxGesamtverlust: gesamtverlustBetrag ?? betrag(gesamtverlustProzent),
                              gesamtverlustart: gesamtverlustart, einfrierenBeiSaldo: einfrierenBei,
                              gewinnziel: betrag(gewinnzielProzent), mindestHandelstage: mindestHandelstage,
                              handelstagzaehlung: handelstagzaehlung,
                              mindestTagesgewinn: betrag(mindestTagesgewinnProzent),
                              konsistenzMaxAnteil: konsistenzMaxAnteil, konsistenzbezug: konsistenzbezug,
                              keinHaltenUeberTageswechsel: keinHaltenUeberTageswechsel,
                              keinHaltenUeberWochenende: keinHaltenUeberWochenende,
                              maxLotsJeTrade: nil, stopPflicht: false)
    }

    var hinweis: String {
        let basis = geprueft
            ? String(localized: "\(firma) \(name): am 02.10.2026 gegen \(quelle) geprüft. Prozentwerte sind mit dem Startkapital umgerechnet; bei anderem Startkapital die Vorlage neu übernehmen.")
            : String(localized: "\(firma) \(name): ungeprüft. Werte aus der Recherche vom 02.10.2026 (\(quelle)); mit dem Dashboard der Firma vergleichen.")
        return bemerkung.map { basis + " " + $0 } ?? basis
    }

    static let zeitzonen = ["Europe/Prague", "Europe/Athens", "Europe/London", "America/New_York", "America/Chicago", "UTC"]

    /// Firmen in der Reihenfolge der Vorlagen, jede einmal.
    static var firmen: [String] {
        var gesehen: [String] = []
        for vorlage in alle where !gesehen.contains(vorlage.firma) { gesehen.append(vorlage.firma) }
        return gesehen
    }

    private static let ftmo = "ftmo.com/en/trading-objectives"
    private static let fundedNext = "fundednext.com/general-rules/cfds/trading-objectives"
    private static let the5ers = "help.the5ers.com"
    private static let serverzeit = String(localized: "Tageswechsel 00:00 Serverzeit (GMT+2/+3), hier als Europe/Athens.")

    static let alle: [Firmenvorlage] = [
        Firmenvorlage(firma: "FTMO", name: "2-Step Challenge (Phase 1)", geprueft: true, quelle: ftmo,
                      tagesverlustProzent: 5, gesamtverlustProzent: 10, gewinnzielProzent: 10, mindestHandelstage: 4),
        Firmenvorlage(firma: "FTMO", name: "2-Step Verification (Phase 2)", geprueft: true, quelle: ftmo,
                      tagesverlustProzent: 5, gesamtverlustProzent: 10, gewinnzielProzent: 5, mindestHandelstage: 4),
        Firmenvorlage(firma: "FTMO", name: "2-Step FTMO Account", geprueft: true, quelle: ftmo,
                      tagesverlustProzent: 5, gesamtverlustProzent: 10),
        Firmenvorlage(firma: "FTMO", name: "1-Step Challenge", geprueft: true, quelle: ftmo,
                      tagesverlustProzent: 3, gesamtverlustProzent: 10, gesamtverlustart: .nachgezogenTagesende,
                      gewinnzielProzent: 10, konsistenzMaxAnteil: 0.5, konsistenzbezug: .summeGewinntage,
                      bemerkung: String(localized: "Ob die nachgezogene Grenze beim Startkapital stehen bleibt, nennt die Seite nicht; hier läuft sie weiter.")),
        Firmenvorlage(firma: "FTMO", name: "1-Step Account", geprueft: true, quelle: ftmo,
                      tagesverlustProzent: 3, gesamtverlustProzent: 10, gesamtverlustart: .nachgezogenTagesende,
                      konsistenzMaxAnteil: 0.5, konsistenzbezug: .summeGewinntage),
        Firmenvorlage(firma: "FundedNext", name: "Stellar 2-Step Phase 1", geprueft: true, quelle: fundedNext,
                      zeitzone: "Europe/Athens", tagesverlustProzent: 5, gesamtverlustProzent: 10, gewinnzielProzent: 8,
                      mindestHandelstage: 5, handelstagzaehlung: .ergebnis, bemerkung: serverzeit),
        Firmenvorlage(firma: "FundedNext", name: "Stellar 2-Step Phase 2", geprueft: true, quelle: fundedNext,
                      zeitzone: "Europe/Athens", tagesverlustProzent: 5, gesamtverlustProzent: 10, gewinnzielProzent: 5,
                      mindestHandelstage: 5, handelstagzaehlung: .ergebnis, bemerkung: serverzeit),
        Firmenvorlage(firma: "FundedNext", name: "Stellar 1-Step", geprueft: true, quelle: fundedNext,
                      zeitzone: "Europe/Athens", tagesverlustProzent: 3, gesamtverlustProzent: 6, gewinnzielProzent: 10,
                      mindestHandelstage: 2, handelstagzaehlung: .ergebnis, bemerkung: serverzeit),
        Firmenvorlage(firma: "FundedNext", name: "Stellar Lite Phase 1", geprueft: true, quelle: fundedNext,
                      zeitzone: "Europe/Athens", tagesverlustProzent: 4, gesamtverlustProzent: 8, gewinnzielProzent: 8,
                      mindestHandelstage: 5, handelstagzaehlung: .ergebnis, bemerkung: serverzeit),
        Firmenvorlage(firma: "FundedNext", name: "Stellar Lite Phase 2", geprueft: true, quelle: fundedNext,
                      zeitzone: "Europe/Athens", tagesverlustProzent: 4, gesamtverlustProzent: 8, gewinnzielProzent: 4,
                      mindestHandelstage: 5, handelstagzaehlung: .ergebnis, bemerkung: serverzeit),
        Firmenvorlage(firma: "FundedNext", name: "Stellar Instant", geprueft: true, quelle: fundedNext,
                      zeitzone: "Europe/Athens", gesamtverlustProzent: 6, gesamtverlustart: .nachgezogenTagesende,
                      bemerkung: String(localized: "Kein Tageslimit. Ob und wo die nachgezogene Grenze stehen bleibt, nennt die Seite nicht.")),
        Firmenvorlage(firma: "The5ers", name: "High Stakes Step 1", geprueft: true, quelle: the5ers,
                      zeitzone: "Europe/Athens", tagesverlustProzent: 5, gesamtverlustProzent: 10, gewinnzielProzent: 10,
                      mindestHandelstage: 3, handelstagzaehlung: .gewinntag, mindestTagesgewinnProzent: 0.5,
                      bemerkung: String(localized: "Zeitzone des Tageswechsels nennt die Seite nicht; hier Serverzeit als Europe/Athens angenommen.")),
        Firmenvorlage(firma: "The5ers", name: "High Stakes Step 2", geprueft: true, quelle: the5ers,
                      zeitzone: "Europe/Athens", tagesverlustProzent: 5, gesamtverlustProzent: 10, gewinnzielProzent: 5,
                      mindestHandelstage: 3, handelstagzaehlung: .gewinntag, mindestTagesgewinnProzent: 0.5,
                      bemerkung: String(localized: "Zeitzone des Tageswechsels nennt die Seite nicht; hier Serverzeit als Europe/Athens angenommen.")),
        Firmenvorlage(firma: "Topstep", name: "50K Combine", geprueft: false, quelle: "help.topstep.com",
                      startkapital: 50_000, zeitzone: "America/Chicago", tageswechselMinuten: 17 * 60,
                      gesamtverlustBetrag: 2_000, gesamtverlustart: .nachgezogenTagesende, einfrieren: .startkapital,
                      handelstagzaehlung: .gewinntag, keinHaltenUeberTageswechsel: true, keinHaltenUeberWochenende: true,
                      bemerkung: String(localized: "Tagesverlust-Grenze pausiert bei Topstep nur, darum hier aus. Gewinnziel aus dem Dashboard eintragen; die Konsistenzregel bezieht Topstep aufs Gewinnziel, das kennt die Prüfung noch nicht. Glattstellen bis 15:10 Chicago prüft die App erst ab 17:00.")),
        Firmenvorlage(firma: "Apex", name: "Konto mit EOD-Drawdown", geprueft: false, quelle: "apextraderfunding.com/help-center",
                      startkapital: 50_000, zeitzone: "America/New_York", tageswechselMinuten: 18 * 60,
                      gesamtverlustart: .nachgezogenTagesende, einfrieren: .startPlus(100),
                      handelstagzaehlung: .gewinntag, konsistenzMaxAnteil: 0.5,
                      keinHaltenUeberTageswechsel: true, keinHaltenUeberWochenende: true,
                      bemerkung: String(localized: "Gesamtgrenze aus dem Dashboard eintragen; sie friert bei Start plus 100 ein. Glattstellen bis 16:59 New York prüft die App erst ab 18:00.")),
    ]
}
