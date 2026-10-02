import Charts
import SwiftUI
import TradingCore

/// Die Seiten des Monatsberichts in fester Reihenfolge, je eine A4-Seite.
enum BerichtSeite: Int, CaseIterable {
    case ueberblick
    case verhalten
    case tagebuchUndSteuer

    var titel: String {
        switch self {
        case .ueberblick: String(localized: "Überblick")
        case .verhalten: String(localized: "Regeln und Muster")
        case .tagebuchUndSteuer: String(localized: "Ziele, Tagebuch und Steuer")
        }
    }
}

/// Eine A4-Seite: Kopf, Inhalt, Fuß. Inhalte sind gekürzt (höchstens drei beste und schlechteste Trades,
/// drei Muster, sechs Fehlermuster, fünf Ziele), damit nichts über den Seitenrand läuft.
struct BerichtSeitenansicht: View {
    let seite: BerichtSeite
    let bericht: Monatsbericht
    let kontext: BerichtKontext
    @Environment(\.thema) private var thema

    var body: some View {
        // Kopf und Fuß liegen über dem Inhalt und decken ihn ab: Läuft der Inhalt doch zu lang, wird er
        // abgeschnitten, nie der Fuß mit dem Hinweis „Keine Kauf- oder Verkaufsempfehlung“.
        inhalt
            .padding(.top, BerichtMass.kopfReserve)
            .padding(.bottom, BerichtMass.fussReserve)
            .frame(width: BerichtMass.breite, height: BerichtMass.seite.height - 2 * BerichtMass.randOben,
                   alignment: .topLeading)
            .clipped()
            .overlay(alignment: .top) {
                BerichtKopf(kontext: kontext, seitentitel: seite.titel)
                    .background(thema.flaeche)
            }
            .overlay(alignment: .bottom) {
                BerichtFuss(kontext: kontext, nummer: seite.rawValue + 1, anzahl: BerichtSeite.allCases.count)
                    .padding(.top, Abstand.raster * 2)
                    .background(thema.flaeche)
            }
            .padding(.horizontal, BerichtMass.randSeitlich)
            .padding(.vertical, BerichtMass.randOben)
            .frame(width: BerichtMass.seite.width, height: BerichtMass.seite.height)
            .background(thema.flaeche)
            .clipped()
    }

    @ViewBuilder private var inhalt: some View {
        switch seite {
        case .ueberblick: BerichtUeberblick(bericht: bericht, kontext: kontext)
        case .verhalten: BerichtVerhalten(bericht: bericht, kontext: kontext)
        case .tagebuchUndSteuer: BerichtTagebuchUndSteuer(bericht: bericht, kontext: kontext)
        }
    }
}

struct BerichtKopf: View {
    let kontext: BerichtKontext
    let seitentitel: String
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: String(localized: "Monatsbericht \(kontext.monatsname)"))
                    .font(BerichtSchrift.titel)
                    .foregroundStyle(thema.text)
                Spacer()
                Text(verbatim: "Brad")
                    .font(BerichtSchrift.abschnitt)
                    .foregroundStyle(thema.akzent)
            }
            Text(verbatim: kontext.konto + " · " + kontext.waehrung + " · " + seitentitel)
                .font(BerichtSchrift.text)
                .foregroundStyle(thema.textSchwach)
        }
        .frame(width: BerichtMass.breite, alignment: .leading)
    }
}

struct BerichtFuss: View {
    let kontext: BerichtKontext
    let nummer: Int
    let anzahl: Int
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(thema.linie)
                .frame(height: 0.5)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: String(localized: "Erstellt am \(Format.datum(kontext.erstellt)) · Zeiten in \(kontext.zeitzone.identifier)"))
                Spacer()
                Text(verbatim: String(localized: "Seite \(nummer) von \(anzahl)"))
            }
            Text("Beschreibt vergangene Trades. Keine Kauf- oder Verkaufsempfehlung, keine Prognose.")
        }
        .font(BerichtSchrift.klein)
        .foregroundStyle(thema.textSchwach)
        .frame(width: BerichtMass.breite, alignment: .leading)
    }
}

// MARK: Seite 1: Überblick

struct BerichtUeberblick: View {
    let bericht: Monatsbericht
    let kontext: BerichtKontext

    var body: some View {
        let auswertung = bericht.auswertung
        VStack(alignment: .leading, spacing: BerichtMass.abschnittAbstand) {
            BerichtAbschnitt(titel: "Kennzahlen", untertitel: untertitel) {
                if auswertung.trades.isEmpty {
                    BerichtHinweis(String(localized: "In diesem Monat wurde kein Trade geschlossen."))
                } else {
                    BerichtKennzahlen(auswertung: auswertung, waehrung: kontext.waehrung)
                }
            }
            if !auswertung.kapitalverlauf.punkte.isEmpty {
                BerichtAbschnitt(titel: "Kapitalverlauf",
                                 untertitel: String(localized: "Summe der Netto-Ergebnisse nach jedem Trade des Monats, ohne Ein- und Auszahlungen.")) {
                    BerichtKapitalkurve(punkte: auswertung.kapitalverlauf.punkte)
                }
            }
            HStack(alignment: .top, spacing: Abstand.kachelAbstand * 2) {
                BerichtTradeliste(titel: "Beste Trades", trades: bericht.beste, waehrung: kontext.waehrung)
                BerichtTradeliste(titel: "Schlechteste Trades", trades: bericht.schlechteste, waehrung: kontext.waehrung)
            }
            .frame(width: BerichtMass.breite, alignment: .leading)
        }
    }

    private var untertitel: String {
        let k = bericht.auswertung.kennzahlen
        var text = String(localized: "Ein Trade zählt zum Monat, in dem er geschlossen wurde. Vergleich mit dem Vormonat.")
        if k.anzahl > 0 && !k.genugDaten {
            text += " " + String(localized: "Unter \(Kennzahlen.mindestanzahl) Trades: Die Zahlen beschreiben nur, sie belegen noch kein Muster.")
        }
        return text
    }
}

/// Acht Kacheln in zwei Reihen, mit dem Wert des Vormonats als Zusatz.
struct BerichtKennzahlen: View {
    let auswertung: Auswertung
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        let k = auswertung.kennzahlen
        let vor = auswertung.kennzahlenVorzeitraum
        Grid(horizontalSpacing: Abstand.raster * 2, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                BerichtKachel(titel: "Netto", wert: Format.geld(k.netto, waehrung),
                              zusatz: vormonat(Format.geld(vor.netto, waehrung)), farbe: thema.vorzeichen(k.netto))
                BerichtKachel(titel: "Trades", wert: "\(k.anzahl)",
                              zusatz: vormonat("\(vor.anzahl)"))
                BerichtKachel(titel: "Trefferquote", wert: Format.prozent(k.trefferquote),
                              zusatz: vormonat(Format.prozent(vor.trefferquote)))
                BerichtKachel(titel: "Profitfaktor", wert: Format.zahl(k.profitfaktor),
                              zusatz: vormonat(Format.zahl(vor.profitfaktor)))
            }
            GridRow {
                BerichtKachel(titel: "Erwartung je Trade", wert: k.erwartungswert.map { Format.geld($0, waehrung) } ?? "–",
                              zusatz: String(localized: "\(Format.r(k.erwartungswertR)) bei \(k.anzahlMitR) Trades mit Stop"),
                              farbe: thema.vorzeichen(k.erwartungswert ?? 0))
                BerichtKachel(titel: "Kosten", wert: Format.betrag(k.kosten, waehrung),
                              zusatz: String(localized: "Kostenquote \(Format.prozent(k.kostenquote))"))
                BerichtKachel(titel: "Max. Drawdown", wert: Format.geld(-auswertung.kapitalverlauf.maxDrawdown, waehrung),
                              zusatz: String(localized: "Verlustserie \(auswertung.kapitalverlauf.laengsteVerlustserie), Gewinnserie \(auswertung.kapitalverlauf.laengsteGewinnserie)"),
                              farbe: auswertung.kapitalverlauf.maxDrawdown > 0 ? thema.verlust : nil)
                BerichtKachel(titel: "Haltedauer Gewinner", wert: Format.dauer(k.haltedauerGewinner),
                              zusatz: String(localized: "Verlierer \(Format.dauer(k.haltedauerVerlierer))"))
            }
        }
        .frame(width: BerichtMass.breite)
    }

    private func vormonat(_ wert: String) -> String {
        String(localized: "Vormonat \(wert)")
    }
}

/// Kontostand nach jedem Trade, beginnend bei null.
struct BerichtKapitalkurve: View {
    let punkte: [Decimal]
    @Environment(\.thema) private var thema

    private struct Punkt: Identifiable {
        var id: Int
        var wert: Double
    }

    var body: some View {
        let verlauf: [Punkt] = punkte.enumerated().map { Punkt(id: $0.offset + 1, wert: Format.double($0.element)) }
        let daten: [Punkt] = [Punkt(id: 0, wert: 0)] + verlauf
        Chart {
            RuleMark(y: .value("Null", 0.0))
                .foregroundStyle(thema.linie)
            ForEach(daten) { punkt in
                LineMark(x: .value("Trade", punkt.id), y: .value("Kontostand", punkt.wert))
                    .foregroundStyle(thema.akzent)
                    .lineStyle(StrokeStyle(lineWidth: Diagramm.linie * 0.75))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .frame(width: BerichtMass.breite, height: 150)
    }
}

/// Bis zu drei Trades mit Schlussdatum, Instrument, Richtung, R und Netto.
struct BerichtTradeliste: View {
    let titel: LocalizedStringKey
    let trades: [Trade]
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(titel)
                .font(BerichtSchrift.abschnitt)
                .foregroundStyle(thema.text)
            Rectangle()
                .fill(thema.linie)
                .frame(height: 0.5)
            if trades.isEmpty {
                BerichtHinweis(String(localized: "Keine Trades"))
            }
            ForEach(trades) { trade in
                HStack(spacing: Abstand.raster * 2) {
                    Text(verbatim: Format.datum(trade.closeTime))
                    Text(verbatim: trade.symbol)
                        .lineLimit(1)
                    Text(verbatim: Format.richtung(trade.side))
                        .foregroundStyle(thema.textSchwach)
                    Spacer(minLength: Abstand.raster)
                    Text(verbatim: Format.r(trade.rMultiple))
                        .foregroundStyle(thema.textSchwach)
                    Text(verbatim: Format.geld(trade.netProfit, waehrung))
                        .foregroundStyle(thema.vorzeichen(trade.netProfit))
                }
                .font(BerichtSchrift.tabelle)
                .foregroundStyle(thema.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
