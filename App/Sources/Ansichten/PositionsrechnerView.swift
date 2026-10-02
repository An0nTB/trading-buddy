import SwiftUI
import TradingCore

/// Positionsgrößen-Rechner vor dem Trade (F6, Doc 18): Größe aus Risiko und Stop, dazu die Rückrichtung.
/// Eigenständig, ohne AppModell: Wer die Seite einbindet, gibt Kontostand und Kontowährung mit.
struct PositionsrechnerView: View {
    let waehrung: String
    @State private var konto: Decimal?
    @State private var risikoArt = RisikoArt.prozent
    @State private var risikoWert: Decimal? = 1
    @State private var stopArt = StopArt.punkte
    @State private var stopWert: Decimal?
    @State private var einstieg: Decimal?
    @State private var vorlage = Vorlage.indexCFD
    @State private var instrument = Positionsrechnung.Instrument.indexCFD
    @State private var umrechnung: Decimal? = 1
    @State private var kosten: Decimal? = 0
    @State private var eigeneGroesse: Decimal?
    @Environment(\.thema) private var thema

    init(kontogroesse: Decimal?, waehrung: String) {
        self.waehrung = waehrung
        _konto = State(initialValue: kontogroesse)
    }

    enum RisikoArt: Hashable { case prozent, betrag }
    enum StopArt: Hashable, CaseIterable { case kurs, punkte, pips, prozent }
    enum Vorlage: Hashable, CaseIterable { case forexLot, indexCFD, aktie }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Positionsrechner", untertitel: waehrung)
                Karte("Konto und Risiko") {
                    zahlFeld("Kontostand", $konto)
                    HStack {
                        Auswahlknopf("Risiko", anzeige: risikoArt == .prozent ? "%" : waehrung, auswahl: $risikoArt) {
                            Text("Prozent vom Konto").tag(RisikoArt.prozent)
                            Text("Fester Betrag").tag(RisikoArt.betrag)
                        }
                        zahlFeld("Risiko je Trade", $risikoWert)
                    }
                }
                Karte("Stop") {
                    Auswahlknopf("Stop als", anzeige: name(stopArt), auswahl: $stopArt) {
                        ForEach(StopArt.allCases, id: \.self) { Text(verbatim: name($0)).tag($0) }
                    }
                    if stopArt == .kurs || stopArt == .prozent { zahlFeld("Einstieg", $einstieg) }
                    zahlFeld(stopArt == .kurs ? "Stopkurs" : "Abstand", $stopWert)
                }
                Karte("Instrument") {
                    Auswahlknopf("Vorlage", anzeige: name(vorlage), auswahl: $vorlage) {
                        ForEach(Vorlage.allCases, id: \.self) { Text(verbatim: name($0)).tag($0) }
                    }
                    zahlFeld("Kontraktgröße", feld(\.kontraktgroesse))
                    zahlFeld("Kleinster Schritt", feld(\.schritt))
                    if stopArt == .pips { zahlFeld("Pipgröße", feld(\.pipGroesse)) }
                    zahlFeld("Umrechnung in \(waehrung)", $umrechnung)
                    zahlFeld("Kosten je Einheit in \(waehrung)", $kosten)
                }
                ergebnisBereich
                Karte("Rückrichtung: Was riskiert diese Größe?") {
                    zahlFeld("Größe", $eigeneGroesse)
                    if let groesse = eigeneGroesse, let r = try? rechnung?.risikoBei(groesse: groesse) {
                        Text(verbatim: "\(Format.betrag(r.betrag, waehrung)) · \(Format.prozent(r.prozent / 100))")
                            .font(Schrift.zahlGross)
                            .foregroundStyle(thema.text)
                    }
                }
                Pflichthinweis()
            }
            .padding(Abstand.seitenrand)
        }
        .onChange(of: vorlage) { _, neu in instrument = vorlagenInstrument(neu) }
    }

    @ViewBuilder private var ergebnisBereich: some View {
        if let rechnung {
            switch Result(catching: { try rechnung.berechne() }) {
            case .success(let e):
                LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
                    Kachel(titel: "Größe", wert: Format.lots(e.groesse),
                           zusatz: String(localized: "rechnerisch \(Format.zahl(e.roheGroesse, stellen: 4))"),
                           farbe: e.unterMinimum ? thema.verlust : thema.akzent)
                    Kachel(titel: "Risiko bis Stop", wert: Format.betrag(e.tatsaechlichesRisiko, waehrung),
                           zusatz: String(localized: "\(Format.prozent(e.tatsaechlichesRisikoProzent / 100)) vom Konto, geplant \(Format.betrag(e.risikoBetrag, waehrung))"))
                    Kachel(titel: "Risiko je Einheit", wert: Format.betrag(e.risikoJeEinheit, waehrung))
                }
                if e.unterMinimum {
                    Text("Schon die kleinste Größe riskiert \(Format.betrag(e.risikoBeiMinimum, waehrung)). Stop enger setzen oder den Trade auslassen.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.verlust)
                }
            case .failure(let fehler):
                hinweis(text(fehler))
            }
        } else {
            hinweis("Kontostand, Risiko und Stop eintragen.")
        }
    }

    /// Die Rechnung aus den Feldern; nil, solange ein Pflichtfeld leer ist.
    private var rechnung: Positionsrechnung? {
        guard let konto, let risikoWert, let stopWert else { return nil }
        let stop: Positionsrechnung.StopAbstand
        switch stopArt {
        case .kurs:
            guard let einstieg else { return nil }
            stop = .kurs(einstieg: einstieg, stop: stopWert)
        case .punkte: stop = .punkte(stopWert)
        case .pips: stop = .pips(stopWert)
        case .prozent:
            guard let einstieg else { return nil }
            stop = .prozent(stopWert, einstieg: einstieg)
        }
        return Positionsrechnung(kontogroesse: konto,
                                 risiko: risikoArt == .prozent ? .prozent(risikoWert) : .betrag(risikoWert),
                                 stopAbstand: stop, instrument: instrument,
                                 umrechnung: umrechnung ?? 1, kostenJeEinheit: kosten ?? 0)
    }

    private func zahlFeld(_ titel: LocalizedStringKey, _ wert: Binding<Decimal?>) -> some View {
        LabeledContent(titel) {
            TextField(titel, value: wert, format: .number.precision(.fractionLength(0...6)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
                .labelsHidden()
        }
        .font(Schrift.fliesstext)
        .foregroundStyle(thema.text)
    }

    /// Bindung an ein Feld des Instruments; ein leeres Feld lässt den bisherigen Wert stehen.
    private func feld(_ pfad: WritableKeyPath<Positionsrechnung.Instrument, Decimal>) -> Binding<Decimal?> {
        Binding(get: { instrument[keyPath: pfad] },
                set: { if let neu = $0 { instrument[keyPath: pfad] = neu } })
    }

    private func hinweis(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func text(_ fehler: Error) -> LocalizedStringKey {
        switch fehler as? Positionsrechnung.Fehler {
        case .kontogroesseUngueltig: "Der Kontostand muss größer als null sein."
        case .risikoUngueltig: "Das Risiko muss größer als null sein und darf den Kontostand nicht übersteigen."
        case .stopAbstandUngueltig: "Der Stop braucht einen Abstand größer als null."
        case .instrumentUngueltig: "Kontraktgröße, Schritt, Pipgröße und Umrechnung müssen größer als null sein."
        case .groesseUngueltig, nil: "Die Eingaben ergeben keine Rechnung."
        }
    }

    private func vorlagenInstrument(_ vorlage: Vorlage) -> Positionsrechnung.Instrument {
        switch vorlage {
        case .forexLot: .forexLot
        case .indexCFD: .indexCFD
        case .aktie: .aktie
        }
    }

    private func name(_ art: StopArt) -> String {
        switch art {
        case .kurs: String(localized: "Stopkurs")
        case .punkte: String(localized: "Punkte")
        case .pips: String(localized: "Pips")
        case .prozent: String(localized: "Prozent vom Einstieg")
        }
    }

    private func name(_ vorlage: Vorlage) -> String {
        switch vorlage {
        case .forexLot: String(localized: "Forex, Standardlot")
        case .indexCFD: String(localized: "Index-CFD, 1 je Punkt")
        case .aktie: String(localized: "Aktie, Stück")
        }
    }
}
