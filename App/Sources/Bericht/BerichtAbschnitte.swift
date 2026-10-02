import SwiftUI
import TradingCore

// MARK: Seite 2: Regeln und Muster

struct BerichtVerhalten: View {
    let bericht: Zeitraumbericht
    let kontext: BerichtKontext

    var body: some View {
        VStack(alignment: .leading, spacing: BerichtMass.abschnittAbstand) {
            BerichtRegeln(bericht: bericht, kontext: kontext)
            BerichtFehlermuster(auswertung: bericht.auswertung, waehrung: kontext.waehrung)
            BerichtMusterFinder(bericht: bericht, waehrung: kontext.waehrung)
        }
    }
}

/// Disziplin und Regelverstöße je Art. Sachlich, ohne Wertung (Doc 02 Zeile 43).
struct BerichtRegeln: View {
    let bericht: Zeitraumbericht
    let kontext: BerichtKontext
    @Environment(\.thema) private var thema

    var body: some View {
        let d = bericht.disziplin
        let arten = Regelverstoss.Art.allCases.filter { bericht.anzahl($0) > 0 }
        BerichtAbschnitt(titel: "Handelsregeln",
                         untertitel: String(localized: "Geprüft über alle Trades des Kontos, gezählt an Trades im Berichtszeitraum.")) {
            if !kontext.regelnHinterlegt {
                BerichtHinweis(String(localized: "Für dieses Konto sind keine eigenen Regeln hinterlegt. Gezählt sind nur Trades, die im Journal als nicht regeltreu markiert sind."))
            }
            HStack(spacing: Abstand.raster * 2) {
                BerichtKachel(titel: "Regeltreu", wert: "\(d.regeltreu)",
                              zusatz: String(localized: "Netto \(Format.geld(d.nettoRegeltreu, kontext.waehrung))"))
                BerichtKachel(titel: "Mit Verstoß", wert: "\(d.verletzt)",
                              zusatz: String(localized: "Netto \(Format.geld(d.nettoVerletzt, kontext.waehrung))"),
                              farbe: d.verletzt > 0 ? thema.verlust : nil)
                BerichtKachel(titel: "Anteil regeltreu", wert: Format.prozent(d.quote),
                              zusatz: d.genugDaten ? nil : String(localized: "unter \(Kennzahlen.mindestanzahl) Trades"))
            }
            .frame(width: BerichtMass.breite)
            ForEach(arten, id: \.self) { art in
                BerichtZeile(titel: art.berichtTitel, wert: String(localized: "\(bericht.anzahl(art)) Trades"),
                             farbe: thema.verlust)
            }
            ForEach(propFirmArten, id: \.self) { art in
                BerichtZeile(titel: String(localized: "Prop-Firm: \(art.titel)"),
                             wert: String(localized: "\(propFirmAnzahl(art)) Trades"), farbe: thema.verlust)
            }
            if arten.isEmpty && propFirmArten.isEmpty && kontext.regelnHinterlegt {
                BerichtHinweis(String(localized: "Keine Regelverstöße \(kontext.inDerSpanne)."))
            }
        }
    }
}

extension BerichtRegeln {
    /// Prop-Firm-Verstöße der Spanne je Art (aus `Zeitraumbericht.propFirmVerstoesse`), Trades einfach gezählt.
    var propFirmArten: [PropFirmPruefung.Art] {
        PropFirmPruefung.Art.allCases.filter { propFirmAnzahl($0) > 0 }
    }

    func propFirmAnzahl(_ art: PropFirmPruefung.Art) -> Int {
        Set(bericht.propFirmVerstoesse.filter { $0.art == art }.map(\.trade)).count
    }
}

/// Fehlermuster der Spanne, wie auf der Seite Fehlermuster (gleicher Kurztext), teuerstes zuerst.
struct BerichtFehlermuster: View {
    static let hoechstens = 6
    let auswertung: Auswertung
    let waehrung: String

    var body: some View {
        let befunde = auswertung.befunde.sorted { $0.netto < $1.netto }
        BerichtAbschnitt(titel: "Fehlermuster",
                         untertitel: String(localized: "Regeln aus dem Journal-Wissen (R5), Standardschwellen.")) {
            if befunde.isEmpty {
                BerichtHinweis(String(localized: "Keine Fehlermuster im Berichtszeitraum."))
            }
            ForEach(Array(befunde.prefix(Self.hoechstens).enumerated()), id: \.offset) { eintrag in
                BerichtBefundZeile(befund: eintrag.element, ohne: auswertung.ohne(eintrag.element), waehrung: waehrung)
            }
            if befunde.count > Self.hoechstens {
                BerichtHinweis(String(localized: "Dazu \(befunde.count - Self.hoechstens) weitere; alle auf der Seite Fehlermuster."))
            }
        }
    }
}

struct BerichtBefundZeile: View {
    let befund: Befund
    /// Kennzahlen ohne die Trades des Befunds, nur bei Regelbrüchen je Trade.
    let ohne: Kennzahlen?
    let waehrung: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            BerichtZeile(titel: befund.muster.titel, wert: BefundText.kurz(befund, waehrung: waehrung))
            if let ohne {
                BerichtHinweis(String(localized: "Ohne diese Trades: Netto \(Format.geld(ohne.netto, waehrung))"))
            }
        }
    }
}

/// Die stärksten Unterschiede laut Muster-Finder mit Zufallsanteil (Doc 18 F5).
struct BerichtMusterFinder: View {
    let bericht: Zeitraumbericht
    let waehrung: String

    var body: some View {
        BerichtAbschnitt(titel: "Muster-Finder",
                         untertitel: String(localized: "Gruppen, deren Netto je Trade sich am deutlichsten vom Rest unterscheidet. Beschreibt vergangene Trades, keine Prognose.")) {
            if bericht.muster.isEmpty {
                BerichtHinweis(String(localized: "Kein Muster: Verglichen wird erst, wenn eine Gruppe und der Rest je mindestens \(Kennzahlen.mindestanzahl) Trades haben. Im Berichtszeitraum: \(bericht.auswertung.trades.count) Trades."))
            } else {
                ForEach(Array(bericht.muster.enumerated()), id: \.offset) { eintrag in
                    BerichtMusterZeile(muster: eintrag.element, trades: bericht.auswertung.trades, waehrung: waehrung)
                }
                BerichtHinweis(String(localized: "Zufallsanteil: Wie oft eine zufällig gezogene Gruppe gleicher Größe einen mindestens so großen Unterschied zeigt (1.000 Ziehungen). Klein heißt: mit Zufall schwer zu erklären. Bei mehreren Vergleichen tritt ein kleiner Wert auch zufällig auf."))
            }
        }
    }
}

struct BerichtMusterZeile: View {
    let muster: Muster
    let trades: [Trade]
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        let zufall = muster.zufallsanteil(trades: trades)
        let gruppe = muster.aufteilung.berichtTitel + ": " + muster.aufteilung.berichtSchluessel(muster.schluessel)
        VStack(alignment: .leading, spacing: 1) {
            BerichtZeile(titel: gruppe, wert: String(localized: "\(Format.geld(muster.effekt, waehrung)) je Trade"),
                         farbe: thema.vorzeichen(muster.effekt))
            BerichtHinweis(String(localized: "\(muster.anzahl) Trades mit \(Format.geld(muster.erwartungswert, waehrung)) je Trade, übrige \(muster.anzahlRest) mit \(Format.geld(muster.erwartungswertRest, waehrung)). Zufallsanteil \(Format.prozent(zufall))."))
        }
    }
}

// MARK: Seite 3: Ziele, Tagebuch und Steuer

struct BerichtTagebuchUndSteuer: View {
    let bericht: Zeitraumbericht
    let kontext: BerichtKontext

    var body: some View {
        VStack(alignment: .leading, spacing: BerichtMass.abschnittAbstand) {
            BerichtZiele(ziele: bericht.ziele)
            BerichtTagebuch(planwirkung: bericht.planwirkung, verpasste: bericht.verpasste, waehrung: kontext.waehrung)
            BerichtSteuer(bericht: bericht, kontext: kontext)
            BerichtDatenhinweise(bericht: bericht, kontext: kontext)
        }
    }
}

struct BerichtZiele: View {
    static let hoechstens = 5
    let ziele: [Reviewziel]
    @Environment(\.thema) private var thema

    var body: some View {
        BerichtAbschnitt(titel: "Review-Ziele") {
            if ziele.isEmpty {
                BerichtHinweis(String(localized: "Keine Ziele, deren Zeitraum den Berichtszeitraum berührt."))
            }
            ForEach(Array(ziele.prefix(Self.hoechstens).enumerated()), id: \.offset) { eintrag in
                VStack(alignment: .leading, spacing: 1) {
                    BerichtZeile(titel: eintrag.element.text, wert: eintrag.element.status.berichtTitel,
                                 farbe: farbe(eintrag.element.status))
                    BerichtHinweis(zusatz(eintrag.element), zeilen: 2)
                }
            }
            if ziele.count > Self.hoechstens {
                BerichtHinweis(String(localized: "Dazu \(ziele.count - Self.hoechstens) weitere auf der Seite Review-Ziele."))
            }
        }
    }

    private func zusatz(_ ziel: Reviewziel) -> String {
        var teile = [Zielformat.zeitraum(ziel)]
        if let messung = Zielformat.messung(ziel) { teile.append(messung) }
        if let ergebnis = ziel.ergebnis, !ergebnis.isEmpty {
            teile.append(String(localized: "Ergebnis: \(ergebnis)"))
        }
        return teile.joined(separator: " · ")
    }

    private func farbe(_ status: Reviewziel.Status) -> Color {
        switch status {
        case .offen: thema.akzent
        case .erreicht: thema.gewinn
        case .verworfen: thema.textSchwach
        default: thema.verlust
        }
    }
}

/// Planwirkung und verpasste Trades aus der Tagesseite.
struct BerichtTagebuch: View {
    let planwirkung: Planwirkung
    let verpasste: VerpassteAuswertung
    let waehrung: String

    var body: some View {
        BerichtAbschnitt(titel: "Tagebuch",
                         untertitel: String(localized: "Ein Tag zählt mit Plan, wenn der Plan vor dem ersten Trade des Tages gespeichert war. Tage ohne Trades fallen heraus.")) {
            BerichtZeile(titel: String(localized: "Mit Plan: \(planwirkung.tageMitPlan) Tage, \(planwirkung.tradesMitPlan) Trades"),
                         wert: String(localized: "\(geld(planwirkung.nettoJeTagMitPlan)) je Tag"))
            BerichtZeile(titel: String(localized: "Ohne Plan: \(planwirkung.tageOhnePlan) Tage, \(planwirkung.tradesOhnePlan) Trades"),
                         wert: String(localized: "\(geld(planwirkung.nettoJeTagOhnePlan)) je Tag"))
            if !planwirkung.genugDaten {
                BerichtHinweis(String(localized: "Unter \(Planwirkung.mindestTage) Tagen je Seite: beschreibt nur, belegt nichts."))
            }
            BerichtZeile(titel: String(localized: "Verpasste Trades: \(verpasste.anzahl), davon \(verpasste.gewollt) wegen Regelsperre"),
                         wert: String(localized: "\(Format.r(verpasste.entgangenR)) geschätzt"))
            if !verpasste.jeGrund.isEmpty {
                BerichtHinweis(verpasste.jeGrund.map { "\($0.grund.titel) \($0.anzahl)" }.joined(separator: " · "))
            }
        }
    }

    private func geld(_ wert: Decimal?) -> String {
        wert.map { Format.geld($0, waehrung) } ?? "–"
    }
}

/// Steuer-Orientierung vom 1. Januar bis zum Ende der Spanne, in Euro. Orientierung, kein Steuerbescheid (Doc 22).
struct BerichtSteuer: View {
    let bericht: Zeitraumbericht
    let kontext: BerichtKontext
    @Environment(\.thema) private var thema

    var body: some View {
        BerichtAbschnitt(titel: "Steuer-Orientierung", untertitel: untertitel) {
            BerichtHinweis(String(localized: "Orientierung, kein Steuerbescheid. Ohne Steuersatz, Sparer-Pauschbetrag, Verlustvorträge und Teilfreistellung. Ergebnis je Trade = Kursergebnis + Kommission + Swap. Krypto-Haltefrist und Freigrenze stehen auf der Steuer-Seite der App."))
            if bericht.steuerBisEnde.isEmpty {
                BerichtHinweis(String(localized: "Keine Verkäufe im Jahr bis zum Ende des Berichtszeitraums."))
            }
            ForEach(bericht.steuerBisEnde, id: \.topf) { summe in
                BerichtZeile(titel: summe.topf.berichtTitel, wert: wert(summe), farbe: summe.ohneEuro == summe.anzahl ? nil : thema.vorzeichen(summe.saldo))
                BerichtHinweis(zusatz(summe))
            }
            BerichtHinweis(ezbText)
            if let abzug = abzugText {
                BerichtHinweis(abzug)
            }
        }
    }

    private var untertitel: String {
        // Steuerjahr ist das Jahr des letzten Tags; eine Woche über den Jahreswechsel zählt zum neuen Jahr.
        let bis = BerichtKontext.datum(kontext.letzter)
        return String(localized: "1. Januar \(String(bericht.steuerjahr)) bis \(bis), Beträge in Euro, Verkaufsjahr nach deutscher Zeit")
    }

    private func wert(_ summe: Topfsumme) -> String {
        summe.ohneEuro == summe.anzahl ? "–" : String(localized: "Saldo \(Format.geld(summe.saldo, "EUR"))")
    }

    private func zusatz(_ summe: Topfsumme) -> String {
        var teile = [String(localized: "\(summe.anzahl) Trades"),
                     String(localized: "Gewinne \(Format.geld(summe.gewinne, "EUR"))"),
                     String(localized: "Verluste \(Format.geld(summe.verluste, "EUR"))")]
        if summe.topf == .allgemein, summe.davonCFD != 0 {
            teile.append(String(localized: "davon CFDs \(Format.geld(summe.davonCFD, "EUR"))"))
        }
        if summe.ohneEuro > 0 {
            teile.append(String(localized: "\(summe.ohneEuro) Trades ohne Euro-Wert nicht enthalten"))
        }
        return teile.joined(separator: " · ")
    }

    /// Fremdwährung zum EZB-Referenzkurs am Schlusstag (Näherung, Doc 32); ohne Kurse bleiben solche Trades Lücke.
    private var ezbText: String {
        guard let tag = kontext.ezbBis else {
            return String(localized: "EZB-Referenzkurse noch nicht geladen; Trades in Fremdwährung fehlen in den Euro-Summen.")
        }
        let bis = BerichtKontext.datum(tag)
        return String(localized: "Fremdwährung zum EZB-Referenzkurs am Schlusstag umgerechnet (Näherung, USDT wie USD), Kurse bis \(bis).")
    }

    private var abzugText: String? {
        switch kontext.brokerFuehrtSteuerAb {
        case true?: String(localized: "Der Broker führt die Steuer selbst ab; maßgeblich ist seine Steuerbescheinigung.")
        case false?: String(localized: "Der Broker führt keine Steuer ab; Gewinne gehören in die Steuererklärung.")
        case nil: nil
        }
    }
}

/// Was im Bericht fehlt oder anders gezählt ist.
struct BerichtDatenhinweise: View {
    let bericht: Zeitraumbericht
    let kontext: BerichtKontext

    var body: some View {
        BerichtAbschnitt(titel: "Hinweise zu den Daten") {
            if let fremd = fremdwaehrungText {
                BerichtHinweis(fremd)
            }
            if bericht.tradesOhneUhrzeit > 0 {
                BerichtHinweis(String(localized: "\(bericht.tradesOhneUhrzeit) Trades ohne Uhrzeit: Trade Republic und Scalable Capital liefern im Export nur das Datum. Für diese Trades fehlen Stunde, Haltedauer und die Reihenfolge am Tag; in Netto, Trefferquote und Steuer zählen sie mit."))
            }
            if bericht.auswertung.geloeschteOrders > 0 {
                BerichtHinweis(String(localized: "Gelöschte Pending Orders: \(bericht.auswertung.geloeschteOrders), Stornoquote \(Format.prozent(bericht.auswertung.stornoquote))."))
            }
            BerichtHinweis(String(localized: "Grundlage sind alle Trades des Kontos, unabhängig vom Filter in der App. Tagesnotizen und verpasste Trades gelten für alle Konten."))
        }
    }

    /// Trades in fremder Währung (Doc 40, W2): Summen rechnen sie zum EZB-Kurs des Schlusstags um,
    /// ohne Kurs fehlen sie. `nil`, wenn alle Trades in Kontowährung lauten.
    private var fremdwaehrungText: String? {
        guard bericht.umgerechnet > 0 || bericht.ohneKurs > 0 else { return nil }
        let waehrungen = bericht.fremdwaehrungen.joined(separator: ", ")
        if bericht.ohneKurs == 0 {
            return String(localized: "\(bericht.umgerechnet) Trades in \(waehrungen) zum EZB-Kurs des Schlusstags in \(kontext.waehrung) umgerechnet (Näherung). Einzelbeträge und Summen lauten auf \(kontext.waehrung).")
        }
        return String(localized: "\(bericht.umgerechnet) Trades in \(waehrungen) zum EZB-Kurs des Schlusstags in \(kontext.waehrung) umgerechnet (Näherung), \(bericht.ohneKurs) ohne Kurs in Kennzahlen und Summen nicht enthalten.")
    }
}
