import SwiftUI
import TradingCore

/// Trade-Liste, erster Entwurf: Liste mit zwei Zeilen je Trade (Doc 10, Reihe 6).
/// Die Tabelle mit Inspektor für den Mac (Reihe 4) kommt im nächsten Pull Request.
struct TradesView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var suche = ""
    @State private var nurMitMuster = false
    @State private var nurOhneStop = false

    private var gefiltert: [Trade] {
        let muster = modell.musterJeTrade
        return modell.tradesNeuesteZuerst.filter { trade in
            if nurMitMuster, muster[trade.id] == nil { return false }
            if nurOhneStop, trade.stopLoss != nil { return false }
            if !suche.isEmpty, !trade.symbol.localizedCaseInsensitiveContains(suche), !trade.id.contains(suche) {
                return false
            }
            return true
        }
    }

    var body: some View {
        let liste = gefiltert
        let muster = modell.musterJeTrade
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Kopfzeile("Trades", untertitel: String(localized: "\(liste.count) von \(modell.trades.count)")) {
                Toggle("Nur mit Muster", isOn: $nurMitMuster)
                Toggle("Stop fehlt (\(modell.ohneStop))", isOn: $nurOhneStop)
            }
            .toggleStyle(.button)
            .padding(.horizontal, Abstand.seitenrand)
            if liste.isEmpty {
                KeineTrades()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(liste) { trade in
                    TradeZeile(trade: trade, muster: muster[trade.id] ?? [], waehrung: modell.waehrung)
                        .listRowBackground(thema.flaeche)
                }
                .scrollContentBackground(.hidden)
                Summenzeile(trades: liste, waehrung: modell.waehrung)
                    .padding(.horizontal, Abstand.seitenrand)
                    .padding(.bottom, Abstand.kachelAbstand)
            }
        }
        .padding(.top, Abstand.seitenrand)
        .searchable(text: $suche, prompt: "Instrument oder Ticket")
    }
}

/// Eine Zeile der Trade-Liste: Instrument und Richtung, darunter Zeit, Lots und Haltedauer; rechts Netto und R.
struct TradeZeile: View {
    let trade: Trade
    let muster: [Fehlermuster]
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: "\(trade.symbol) · \(Format.richtung(trade.side))")
                    .font(Schrift.fliesstext.weight(.semibold))
                    .foregroundStyle(thema.text)
                Text(verbatim: "\(Format.zeit(trade.closeTime)) · \(Format.lots(trade.lots)) Lots · \(Format.dauer(trade.holdingTime))")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                if !muster.isEmpty {
                    HStack(spacing: Abstand.raster) {
                        ForEach(muster, id: \.self) { MusterChip(muster: $0) }
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Abstand.raster) {
                Text(verbatim: Format.geld(trade.netProfit, waehrung))
                    .font(Schrift.tabelle.weight(.semibold))
                    .foregroundStyle(thema.vorzeichen(trade.netProfit))
                if trade.rMultiple == nil {
                    Text("kein Stop")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    Text(verbatim: Format.r(trade.rMultiple))
                        .font(Schrift.beschriftung)
                        .monospacedDigit()
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }
        .padding(.vertical, Abstand.raster)
    }
}

/// Summenzeile unter der Liste: Anzahl, Ø R, Netto, Trades ohne Stop.
struct Summenzeile: View {
    let trades: [Trade]
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        let kennzahlen = Kennzahlen(trades: trades)
        let ohneStop = trades.filter { $0.stopLoss == nil }.count
        HStack(spacing: Abstand.kachelAbstand) {
            Text("Summe")
                .foregroundStyle(thema.textSchwach)
            Text("\(kennzahlen.anzahl) Trades")
                .foregroundStyle(thema.textSchwach)
            Spacer()
            Text(verbatim: "Ø \(Format.r(kennzahlen.erwartungswertR))")
                .font(Schrift.tabelle)
                .foregroundStyle(thema.textSchwach)
            Text(verbatim: Format.geld(kennzahlen.netto, waehrung))
                .font(Schrift.tabelle.weight(.semibold))
                .foregroundStyle(thema.vorzeichen(kennzahlen.netto))
            Text("\(ohneStop) ohne Stop")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        .font(Schrift.fliesstext)
    }
}
