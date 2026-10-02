import SwiftUI
import TradingCore

/// Kennzahlen (Doc 10, Reihe 4): Stichprobenhinweis, acht Kacheln, Aufschlüsselung mit Umschalter,
/// Reihenfolge-Effekte und Playbook-Auswertung (Karten in KennzahlenAufschluesselung.swift).
struct KennzahlenView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let kennzahlen = modell.kennzahlen
        let verlauf = modell.kapitalverlauf
        let waehrung = modell.waehrung
        let muster = modell.musterJeTrade
        let mitRegelbruch = modell.trades.filter { muster[$0.id] != nil }
        let ohneRegelbruch = modell.trades.filter { muster[$0.id] == nil }
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Kennzahlen") {
                    Filterleiste()
                    FragBradKnopf(.monat) // Frag Brad (Doc 31)
                }
                if modell.trades.isEmpty {
                    KeineTrades()
                } else {
                    HStack(spacing: Abstand.raster * 2) {
                        Kapsel(text: String(localized: "\(kennzahlen.anzahl) Trades"), betont: true)
                        StichprobenHinweis(anzahl: kennzahlen.anzahl)
                    }
                    LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
                        Kachel(titel: "Netto",
                               wert: Format.geld(kennzahlen.netto, waehrung),
                               zusatz: String(localized: "Brutto \(Format.geld(kennzahlen.brutto, waehrung)) · Kosten \(Format.betrag(kennzahlen.kosten, waehrung)) (\(Format.prozent(kennzahlen.kostenquote)))"),
                               farbe: thema.vorzeichen(kennzahlen.netto))
                        Kachel(titel: "Trefferquote",
                               wert: Format.prozent(kennzahlen.trefferquote),
                               zusatz: String(localized: "\(kennzahlen.gewinner) Gewinner, \(kennzahlen.verlierer) Verlierer, \(kennzahlen.breakeven) null"))
                        Kachel(titel: "Profitfaktor",
                               wert: Format.zahl(kennzahlen.profitfaktor),
                               zusatz: String(localized: "Payoff \(Format.zahl(kennzahlen.payoff)) · Ø \(Format.geld(kennzahlen.durchschnittGewinn ?? 0, waehrung)) / \(Format.geld(kennzahlen.durchschnittVerlust ?? 0, waehrung))"))
                        Kachel(titel: "Erwartung je Trade",
                               wert: Format.geld(kennzahlen.erwartungswert ?? 0, waehrung),
                               zusatz: String(localized: "\(Format.r(kennzahlen.erwartungswertR)) · bei \(kennzahlen.anzahlMitR) Trades mit Stop"),
                               farbe: thema.vorzeichen(kennzahlen.erwartungswert ?? 0))
                        Kachel(titel: "Max. Drawdown",
                               wert: Format.geld(-verlauf.maxDrawdown, waehrung),
                               zusatz: drawdownZusatz(verlauf),
                               farbe: verlauf.maxDrawdown > 0 ? thema.verlust : nil)
                        Kachel(titel: "Längste Verlustserie",
                               wert: "\(verlauf.laengsteVerlustserie)",
                               zusatz: String(localized: "Gewinnserie \(verlauf.laengsteGewinnserie)"))
                        Kachel(titel: "Ohne Regelbrüche",
                               wert: Format.geld(netto(ohneRegelbruch), waehrung),
                               zusatz: String(localized: "\(mitRegelbruch.count) Trades mit Regelbruch: \(Format.geld(netto(mitRegelbruch), waehrung))"),
                               farbe: thema.vorzeichen(netto(ohneRegelbruch)))
                        Kachel(titel: "Stop fehlt",
                               wert: "\(modell.ohneStop)",
                               zusatz: String(localized: "ohne Stop kein R"))
                    }
                    AufschluesselungKarte()
                    ReihenfolgeKarte()
                    if !modell.playbook.isEmpty {
                        PlaybookAuswertungKarte()
                    }
                }
                Pflichthinweis()
            }
            .padding(Abstand.seitenrand)
        }
    }

    private func netto(_ trades: [Trade]) -> Decimal {
        trades.reduce(Decimal(0)) { $0 + $1.netProfit }
    }

    private func drawdownZusatz(_ verlauf: Kapitalverlauf) -> String {
        if let prozent = verlauf.maxDrawdownProzent {
            return Format.prozent(prozent)
        }
        return String(localized: "vom Hoch der Kurve; ohne Startkapital kein Prozentwert")
    }
}
