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
