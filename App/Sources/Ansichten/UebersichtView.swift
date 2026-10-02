import Charts
import SwiftUI
import TradingCore

/// Übersicht (Doc 10, Reihe 1 und 6): Filter, vier Kacheln, Kapitalkurve, Fehlermuster, Review-Ziele, letzte Trades.
/// Mit gesetzten Handelsregeln (P6) dazu Regel-Ampel, Disziplin-Kurve neben der Kapitalkurve, Challenge-Karte und Tagesverlust-Balken;
/// mit offenen Positionen die Karte „Offene Positionen“ mit Kursen (P10); dazu „Nächste Termine“ (TradingCalendar, Doc 25).
struct UebersichtView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let kennzahlen = modell.kennzahlen
        let verlauf = modell.kapitalverlauf
        let waehrung = modell.waehrung
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Übersicht") { Filterleiste() }
                if modell.alleTrades.isEmpty {
                    KeineTrades()
                    if modell.konto != nil {
                        KurseKarte()
                        NaechsteTermineKarte()
                        NachrichtenKarte()
                        ZieleKarte()
                    }
                } else {
                    HStack(spacing: Abstand.raster * 2) {
                        Kapsel(text: String(localized: "\(kennzahlen.anzahl) Trades"), betont: true)
                        StichprobenHinweis(anzahl: kennzahlen.anzahl)
                        MischwaehrungHinweis()
                    }
                    LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
                        Kachel(titel: "Netto",
                               wert: Format.geld(kennzahlen.netto, waehrung),
                               zusatz: String(localized: "Kosten \(Format.betrag(kennzahlen.kosten, waehrung))"),
                               farbe: thema.vorzeichen(kennzahlen.netto))
                        Kachel(titel: "Trefferquote",
                               wert: Format.prozent(kennzahlen.trefferquote),
                               zusatz: String(localized: "\(kennzahlen.gewinner) von \(kennzahlen.anzahl)"))
                        Kachel(titel: "Profitfaktor",
                               wert: Format.zahl(kennzahlen.profitfaktor),
                               zusatz: String(localized: "\(Format.r(kennzahlen.erwartungswertR)) je Trade"))
                        Kachel(titel: "Max. Drawdown",
                               wert: Format.geld(-verlauf.maxDrawdown, waehrung),
                               zusatz: String(localized: "Verlustserie \(verlauf.laengsteVerlustserie)"),
                               farbe: verlauf.maxDrawdown > 0 ? thema.verlust : nil)
                    }
                    KurseKarte()
                    NaechsteTermineKarte()
                    NachrichtenKarte()
                    if modell.regeln.leer {
                        Kapitalkurve(punkte: verlauf.punkte)
                    } else {
                        RegelAmpelKarte()
                        Kurvenpaar {
                            Kapitalkurve(punkte: verlauf.punkte)
                        } rechts: {
                            DisziplinKarte()
                        }
                        ChallengeKarte()
                        TagesverlustKarte()
                    }
                    FehlermusterKarte()
                    ZieleKarte()
                    LetzteTradesKarte()
                }
                Pflichthinweis()
            }
            .padding(Abstand.seitenrand)
        }
    }
}

/// Hinweis, wenn Trades in anderer Währung als das Konto vorliegen (Kern 0.17.0 `Trade.waehrung`, Gegencheck A4):
/// Kennzahlen und Kurven summieren Beträge ohne Umrechnung, nur die Steuer-Seite rechnet mit EZB-Kursen um.
struct MischwaehrungHinweis: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let stand = modell.waehrungsstand
        if !stand.leer {
            let liste = stand.waehrungen.joined(separator: ", ")
            let konto = modell.waehrung
            let umgerechnet = String(localized:
                "\(stand.umgerechnet) Trades in \(liste) zum EZB-Kurs des Schlusstags in \(konto) umgerechnet (Näherung)")
            let fehlend = String(localized: "\(stand.ohneKurs) ohne Kurs nicht in den Summen")
            let text = stand.ohneKurs == 0 ? umgerechnet + "." : umgerechnet + "; " + fehlend + "."
            Label(text, systemImage: stand.ohneKurs == 0 ? "info.circle" : "exclamationmark.triangle")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }
}

/// Filter Zeitraum und Instrument; die Währung ist die des Kontos (Umrechnung kommt später).
struct Filterleiste: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        @Bindable var modell = modell
        HStack(spacing: Abstand.raster * 2) {
            Auswahlknopf("Zeitraum", anzeige: zeitraumText, auswahl: $modell.zeitraum) {
                Text("Alle Monate").tag(Zeitraum.alle)
                ForEach(modell.monate, id: \.self) { monat in
                    Text(verbatim: Format.monat(monat)).tag(Zeitraum.monat(monat))
                }
            }
            Auswahlknopf("Instrument", anzeige: instrumentText, auswahl: $modell.instrument) {
                Text("Alle Instrumente").tag(String?.none)
                ForEach(modell.symbole, id: \.self) { symbol in
                    Text(verbatim: symbol).tag(String?.some(symbol))
                }
            }
            Text(verbatim: modell.waehrung)
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                .padding(.horizontal, Abstand.raster * 2)
                .padding(.vertical, Abstand.raster)
                .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
        }
    }

    private var zeitraumText: String {
        switch modell.zeitraum {
        case .alle: String(localized: "Alle Monate")
        case .monat(let monat): Format.monat(monat)
        }
    }

    private var instrumentText: String {
        modell.instrument ?? String(localized: "Alle Instrumente")
    }
}

/// Kontostand nach jedem Trade, Start bei 0 (Netto nach Kosten, aufsummiert).
struct Kapitalkurve: View {
    let punkte: [Decimal]
    @Environment(\.thema) private var thema

    private struct Punkt: Identifiable {
        let id: Int
        let wert: Double
    }

    private var daten: [Punkt] {
        [Punkt(id: 0, wert: 0)] + punkte.enumerated().map { Punkt(id: $0.offset + 1, wert: Format.double($0.element)) }
    }

    var body: some View {
        let daten = self.daten
        Karte("Kapitalkurve") {
            Chart(daten) { punkt in
                if punkt.id == 0 {
                    RuleMark(y: .value("Null", 0.0))
                        .foregroundStyle(thema.linie)
                }
                LineMark(x: .value("Trade", punkt.id), y: .value("Kontostand", punkt.wert))
                    .foregroundStyle(thema.akzent)
                    .lineStyle(StrokeStyle(lineWidth: Diagramm.linie))
                if punkt.id == daten.count - 1 {
                    PointMark(x: .value("Trade", punkt.id), y: .value("Kontostand", punkt.wert))
                        .foregroundStyle(thema.akzent)
                        .symbolSize(Diagramm.marker * Diagramm.marker)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(thema.linie)
                    AxisValueLabel().foregroundStyle(thema.textSchwach)
                }
            }
            .frame(height: 160)
            Text("Netto nach Kosten, aufsummiert je Trade im gewählten Zeitraum. Start bei 0, weil der Auszug kein Startkapital kennt.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }
}

/// Die vier teuersten Fehlermuster im Zeitraum, Sprung zur Fehlermuster-Seite.
struct FehlermusterKarte: View {
    @AppStorage(Ton.schluessel) private var ton = Ton.henry
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let befunde = Array(modell.befunde.sorted { $0.netto < $1.netto }.prefix(4))
        Karte("Fehlermuster", aktion: { modell.bereich = .fehlermuster }) {
            if befunde.isEmpty {
                Text(verbatim: ton.text("Keine Regel hat im gewählten Zeitraum angeschlagen.", henry: "Keine Regel angeschlagen. So soll es sein."))
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                ForEach(befunde, id: \.muster) { befund in
                    HStack {
                        Text(verbatim: befund.muster.titel)
                            .foregroundStyle(thema.text)
                        Spacer()
                        Text(verbatim: BefundText.kurz(befund, waehrung: modell.waehrung))
                            .font(Schrift.tabelle)
                            .foregroundStyle(thema.textSchwach)
                    }
                }
            }
        }
    }
}

/// Die fünf zuletzt geschlossenen Trades, Sprung zur Trade-Liste.
struct LetzteTradesKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let letzte = Array(modell.tradesNeuesteZuerst.prefix(5))
        Karte("Letzte Trades", aktion: { modell.bereich = .trades }) {
            ForEach(letzte) { trade in
                HStack(spacing: Abstand.raster * 2) {
                    Text(verbatim: "\(trade.symbol) \(Format.richtung(trade.side))")
                        .foregroundStyle(thema.text)
                    Text(verbatim: Format.zeit(trade.closeTime))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                    Spacer()
                    // Einzelbetrag in der Währung des Trades (Zweiter Gegencheck W1): BTC/USD nicht als Euro.
                    Text(verbatim: Format.geld(trade.netProfit, trade.waehrung(kontowaehrung: modell.waehrung)))
                        .font(Schrift.tabelle)
                        .foregroundStyle(thema.vorzeichen(trade.netProfit))
                }
            }
        }
    }
}
