import SwiftUI
import TradingCore

/// Fehlermuster im gewählten Zeitraum: je Regel eine Karte mit Treffern, Kosten und Regel im Klartext.
/// Die Seite ist noch nicht gezeichnet (Doc 10, Abschnitt 10); Schwellen bearbeiten kommt später.
struct FehlermusterView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let befunde = modell.befunde.sorted { $0.netto < $1.netto }
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Fehlermuster", untertitel: String(localized: "\(befunde.count) Regeln mit Treffern")) {
                    Filterleiste()
                }
                if modell.trades.isEmpty {
                    KeineTrades()
                } else if befunde.isEmpty {
                    Text("Keine Regel hat im gewählten Zeitraum angeschlagen.")
                        .font(Schrift.fliesstext)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    ForEach(befunde, id: \.muster) { befund in
                        Karte(verbatim: befund.muster.titel) {
                            Text(verbatim: befund.muster.regel)
                                .font(Schrift.fliesstext)
                                .foregroundStyle(thema.textSchwach)
                            HStack(spacing: Abstand.kachelAbstand) {
                                Text(verbatim: BefundText.kurz(befund, waehrung: modell.waehrung))
                                    .font(Schrift.tabelle)
                                    .foregroundStyle(thema.text)
                                Spacer()
                                Text("Stichprobe \(befund.stichprobe)")
                                    .font(Schrift.beschriftung)
                                    .foregroundStyle(thema.textSchwach)
                                if !befund.genugDaten {
                                    Text("unter 30: nur beschreiben")
                                        .font(Schrift.beschriftung)
                                        .foregroundStyle(thema.textSchwach)
                                }
                            }
                            if !befund.trades.isEmpty {
                                BefundTrades(befund: befund)
                            }
                        }
                    }
                    Text("Schwellen sind Vorschläge aus der Recherche (R5) und noch nicht am echten Datensatz kalibriert.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            .padding(Abstand.seitenrand)
        }
    }
}

/// Aufklappbare Liste der Trades eines Befunds (Tims Wunsch 01.10.2026): Klick auf einen Trade öffnet ihn
/// in der Trade-Tabelle, gefiltert auf dieses Muster; „Alle in Trades öffnen“ zeigt die ganze Gruppe.
struct BefundTrades: View {
    let befund: Befund
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var offen = false

    var body: some View {
        DisclosureGroup(isExpanded: $offen) {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                ForEach(modell.trades(zu: befund)) { trade in
                    Button {
                        modell.zeigeTrade(trade.id, muster: befund.muster)
                    } label: {
                        HStack(spacing: Abstand.kachelAbstand) {
                            Text(verbatim: Format.zeit(trade.closeTime))
                                .font(Schrift.tabelle)
                                .foregroundStyle(thema.textSchwach)
                                .frame(width: 100, alignment: .leading)
                            Text(verbatim: "\(trade.symbol) · \(Format.richtung(trade.side)) · \(Format.lots(trade.lots)) Lots")
                                .foregroundStyle(thema.text)
                            Spacer()
                            if trade.rMultiple != nil {
                                Text(verbatim: Format.r(trade.rMultiple))
                                    .font(Schrift.tabelle)
                                    .foregroundStyle(thema.textSchwach)
                            }
                            Text(verbatim: Format.geld(trade.netProfit, modell.waehrung))
                                .font(Schrift.tabelle)
                                .foregroundStyle(thema.vorzeichen(trade.netProfit))
                                .frame(width: 90, alignment: .trailing)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(thema.textSchwach)
                        }
                        .padding(.vertical, Abstand.raster / 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Im Journal öffnen")
                }
                Button("Alle \(befund.trades.count) in Trades öffnen") {
                    modell.zeigeTrades(mit: befund.muster)
                }
                .buttonStyle(.plain)
                .foregroundStyle(thema.akzent)
                .padding(.top, Abstand.raster)
            }
            .padding(.top, Abstand.raster)
        } label: {
            Text("\(befund.trades.count) betroffene Trades")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        .tint(thema.textSchwach)
    }
}

/// Kurztext zu einem Befund: Treffer und Kosten in R oder Geld, bei Zeitraum-Regeln der Messwert.
enum BefundText {
    static func kurz(_ befund: Befund, waehrung: String) -> String {
        if befund.trades.isEmpty, let wert = befund.wert {
            return String(localized: "Messwert \(Format.zahl(wert))")
        }
        var teile = [String(localized: "\(befund.trades.count) Trades")]
        if let r = befund.summeR {
            teile.append(Format.r(r))
        }
        teile.append(Format.geld(befund.netto, waehrung))
        return teile.joined(separator: " · ")
    }
}
