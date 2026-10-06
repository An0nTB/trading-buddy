import Charts
import SwiftUI
import TradingCore

/// Die Seiten des Berichts in fester Reihenfolge, je eine A4-Seite.
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
    let bericht: Zeitraumbericht
    let kontext: BerichtKontext

    var body: some View {
        BerichtRahmen(kontext: kontext, seitentitel: seite.titel, nummer: seite.rawValue + 1,
                      anzahl: BerichtSeite.allCases.count) {
            inhalt
        }
    }

    @ViewBuilder private var inhalt: some View {
        switch seite {
        case .ueberblick: BerichtUeberblick(bericht: bericht, kontext: kontext)
        case .verhalten: BerichtVerhalten(bericht: bericht, kontext: kontext)
        case .tagebuchUndSteuer: BerichtTagebuchUndSteuer(bericht: bericht, kontext: kontext)
        }
    }
}

/// A4-Blatt mit Kopf, Inhalt und Fuß; gemeinsam für Zeitraumbericht und Steuer-Orientierung.
struct BerichtRahmen<Inhalt: View>: View {
    let kontext: BerichtKontext
    let seitentitel: String
    let nummer: Int
    let anzahl: Int
    /// Zusätzliche Zeile im Fuß, etwa „Orientierung, keine Steuerberatung“.
    var fusshinweis: String?
    @ViewBuilder var inhalt: () -> Inhalt
    @Environment(\.thema) private var thema

    var body: some View {
        // Kopf und Fuß liegen über dem Inhalt und decken ihn ab: Läuft der Inhalt doch zu lang, wird er
        // abgeschnitten, nie der Fuß mit dem Hinweis „Keine Kauf- oder Verkaufsempfehlung“.
        inhalt()
            .padding(.top, BerichtMass.kopfReserve)
            .padding(.bottom, BerichtMass.fussReserve + (fusshinweis == nil ? 0 : Abstand.raster * 3))
            .frame(width: BerichtMass.breite, height: BerichtMass.seite.height - 2 * BerichtMass.randOben,
                   alignment: .topLeading)
            .clipped()
            .overlay(alignment: .top) {
                BerichtKopf(kontext: kontext, seitentitel: seitentitel)
                    .background(thema.flaeche)
            }
            .overlay(alignment: .bottom) {
                BerichtFuss(kontext: kontext, nummer: nummer, anzahl: anzahl, hinweis: fusshinweis)
                    .padding(.top, Abstand.raster * 2)
                    .background(thema.flaeche)
            }
            .padding(.horizontal, BerichtMass.randSeitlich)
            .padding(.vertical, BerichtMass.randOben)
            .frame(width: BerichtMass.seite.width, height: BerichtMass.seite.height)
            .background(thema.flaeche)
            .clipped()
    }
}

struct BerichtKopf: View {
    let kontext: BerichtKontext
    let seitentitel: String
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: kontext.titel)
                    .font(BerichtSchrift.titel)
                    .foregroundStyle(thema.text)
                Spacer()
                Text(verbatim: "Henry")
                    .font(BerichtSchrift.abschnitt)
                    .foregroundStyle(thema.akzent)
            }
            Text(verbatim: [kontext.spanneText, kontext.konto, kontext.waehrung, seitentitel].joined(separator: " · "))
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
    var hinweis: String?
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
            if let hinweis {
                Text(verbatim: hinweis)
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
    let bericht: Zeitraumbericht
    let kontext: BerichtKontext

    var body: some View {
        let auswertung = bericht.auswertung
        VStack(alignment: .leading, spacing: BerichtMass.abschnittAbstand) {
            BerichtAbschnitt(titel: "Kennzahlen", untertitel: untertitel) {
                if auswertung.trades.isEmpty {
                    BerichtHinweis(String(localized: "Kein Trade geschlossen \(kontext.inDerSpanne)."))
                } else {
                    BerichtKennzahlen(auswertung: auswertung, waehrung: kontext.waehrung, vergleichsname: kontext.vergleichsname)
                }
            }
            if case .woche = kontext.art {
                BerichtWochentage(tage: bericht.tage, kontext: kontext)
            }
            if case .jahr = kontext.art {
                BerichtJahresmonate(tage: bericht.tage, kontext: kontext)
            }
            if !auswertung.kapitalverlauf.punkte.isEmpty {
                BerichtAbschnitt(titel: "Kapitalverlauf",
                                 untertitel: String(localized: "Summe der Netto-Ergebnisse nach jedem Trade im Berichtszeitraum, ohne Ein- und Auszahlungen.")) {
                    // Im Jahresbericht stehen zwei Reihen Monatskacheln darüber; die Kurve wird flacher, damit
                    // die besten und schlechtesten Trades noch auf die Seite passen.
                    BerichtKapitalkurve(punkte: auswertung.kapitalverlauf.punkte, hoehe: kontext.art.istJahr ? 100 : 150)
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
        var text = String(localized: "Ein Trade zählt zum Berichtszeitraum, in dem er geschlossen wurde. Vergleich mit dem gleich langen Zeitraum davor (\(kontext.vergleichsname)).")
        if k.anzahl > 0 && !k.genugDaten {
            text += " " + String(localized: "Unter \(Kennzahlen.mindestanzahl) Trades: Die Zahlen beschreiben nur, sie belegen noch kein Muster.")
        }
        return text
    }
}

/// Acht Kacheln in zwei Reihen, mit dem Wert der gleich langen Spanne davor als Zusatz.
struct BerichtKennzahlen: View {
    let auswertung: Auswertung
    let waehrung: String
    /// „Vormonat“, „Vorwoche“ oder „Vorzeitraum“.
    let vergleichsname: String
    @Environment(\.thema) private var thema

    var body: some View {
        let k = auswertung.kennzahlen
        let vor = auswertung.kennzahlenVorzeitraum
        Grid(horizontalSpacing: Abstand.raster * 2, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                BerichtKachel(titel: "Netto", wert: Format.geld(k.netto, waehrung),
                              zusatz: vorher(Format.geld(vor.netto, waehrung)), farbe: thema.vorzeichen(k.netto))
                BerichtKachel(titel: "Trades", wert: "\(k.anzahl)",
                              zusatz: vorher("\(vor.anzahl)"))
                BerichtKachel(titel: "Trefferquote", wert: Format.prozent(k.trefferquote),
                              zusatz: vorher(Format.prozent(vor.trefferquote)))
                BerichtKachel(titel: "Profitfaktor", wert: Format.zahl(k.profitfaktor),
                              zusatz: vorher(Format.zahl(vor.profitfaktor)))
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

    private func vorher(_ wert: String) -> String {
        vergleichsname + " " + wert
    }
}

/// Wochenbericht: Netto und Anzahl je Tag, Montag bis Sonntag; Tage ohne geschlossenen Trade mit Strich.
struct BerichtWochentage: View {
    let tage: [Zeitraumbericht.Tagesergebnis]
    let kontext: BerichtKontext
    @Environment(\.thema) private var thema
    private static let namen = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        let ergebnisse = Dictionary(tage.map { ($0.tag, $0) }, uniquingKeysWith: { erstes, _ in erstes })
        BerichtAbschnitt(titel: "Tage",
                         untertitel: String(localized: "Netto und Anzahl der an diesem Tag geschlossenen Trades.")) {
            HStack(spacing: Abstand.raster) {
                ForEach(Array(wochentage.enumerated()), id: \.offset) { eintrag in
                    kachel(nummer: eintrag.offset, tag: eintrag.element, ergebnis: ergebnisse[eintrag.element])
                }
            }
            .frame(width: BerichtMass.breite)
        }
    }

    /// Sieben Kalendertage ab dem Montag der Woche, in der Zeitzone des Nutzers.
    private var wochentage: [Journaltag] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = kontext.zeitzone
        return (0..<7).compactMap { versatz in
            kalender.date(byAdding: .day, value: versatz, to: kontext.zeitraum.von)
                .map { Journaltag($0, zeitzone: kontext.zeitzone) }
        }
    }

    private func kachel(nummer: Int, tag: Journaltag, ergebnis: Zeitraumbericht.Tagesergebnis?) -> some View {
        let name = Self.namen[nummer % Self.namen.count]
        let datum = String(format: "%02d.%02d.", tag.tag, tag.monat)
        return BerichtKachel(titel: "\(name) \(datum)",
                             wert: ergebnis.map { Format.geld($0.netto, kontext.waehrung) } ?? "–",
                             zusatz: ergebnis.map { String(localized: "\($0.anzahl) Trades") },
                             farbe: ergebnis.map { thema.vorzeichen($0.netto) })
    }
}

/// Jahresbericht: Netto und Anzahl je Kalendermonat in zwei Reihen zu sechs Kacheln; Monate ohne
/// geschlossenen Trade mit Strich. Summiert die Tagesergebnisse des Kerns, rechnet also nichts neu.
struct BerichtJahresmonate: View {
    let tage: [Zeitraumbericht.Tagesergebnis]
    let kontext: BerichtKontext
    @Environment(\.thema) private var thema

    private struct Monat {
        var anzahl = 0
        var netto: Decimal = 0
    }

    var body: some View {
        var monate: [Int: Monat] = [:]
        for tag in tage {
            monate[tag.tag.monat, default: Monat()].anzahl += tag.anzahl
            monate[tag.tag.monat, default: Monat()].netto += tag.netto
        }
        return BerichtAbschnitt(titel: "Monate",
                                untertitel: String(localized: "Netto und Anzahl der in diesem Monat geschlossenen Trades.")) {
            VStack(spacing: Abstand.raster) {
                ForEach([1, 7], id: \.self) { erster in
                    HStack(spacing: Abstand.raster) {
                        ForEach(erster..<(erster + 6), id: \.self) { nummer in
                            kachel(nummer: nummer, monat: monate[nummer])
                        }
                    }
                }
            }
            .frame(width: BerichtMass.breite)
        }
    }

    private func kachel(nummer: Int, monat: Monat?) -> some View {
        var kalender = Calendar(identifier: .gregorian)
        kalender.locale = Locale.current
        let namen = kalender.shortStandaloneMonthSymbols
        let name = namen.indices.contains(nummer - 1) ? namen[nummer - 1] : String(nummer)
        return BerichtKachel(titel: LocalizedStringKey(name),
                             wert: monat.map { Format.geld($0.netto, kontext.waehrung) } ?? "–",
                             zusatz: monat.map { String(localized: "\($0.anzahl) Trades") },
                             farbe: monat.map { thema.vorzeichen($0.netto) })
    }
}

/// Kontostand nach jedem Trade, beginnend bei null.
struct BerichtKapitalkurve: View {
    let punkte: [Decimal]
    var hoehe: CGFloat = 150
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
        .frame(width: BerichtMass.breite, height: hoehe)
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
                    Text(verbatim: Format.richtung(trade.richtung))
                        .foregroundStyle(thema.textSchwach)
                    Spacer(minLength: Abstand.raster)
                    Text(verbatim: Format.r(trade.rMultiple))
                        .foregroundStyle(thema.textSchwach)
                    // Einzelbetrag in der Währung des Trades (z. B. USD bei BTC/USD), nie mit dem Zeichen der Kontowährung.
                    Text(verbatim: Format.geld(trade.netProfit, trade.waehrung(kontowaehrung: waehrung)))
                        .foregroundStyle(thema.vorzeichen(trade.netProfit))
                }
                .font(BerichtSchrift.tabelle)
                .foregroundStyle(thema.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
