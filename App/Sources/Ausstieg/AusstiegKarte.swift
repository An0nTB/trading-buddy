import SwiftUI
import TradingCore

/// Anzeige der Ausstiegswerte, gemeinsam für Karte und Seite.
enum Ausstiegsformat {
    /// Abstand in Kurspunkten, dazu R oder, ohne Stop, der Anteil am Einstiegskurs.
    static func abstand(_ punkte: Decimal, r: Decimal?, anteil: Decimal) -> String {
        if let r { return "\(Format.kurs(punkte)) · \(rWert(r))" }
        return "\(Format.kurs(punkte)) · \(anteil.formatted(.percent.precision(.fractionLength(2))))"
    }

    /// R ohne Vorzeichen: MAE und MFE sind immer Abstände, nie Gewinn oder Verlust.
    static func rWert(_ r: Decimal?) -> String {
        guard let r else { return "–" }
        return r.formatted(.number.precision(.fractionLength(2))) + " R"
    }

    static func effizienz(_ wert: Decimal?) -> String {
        guard let wert else { return "–" }
        return wert.formatted(.percent.precision(.fractionLength(0)))
    }

    static func kerzenlaenge(_ sekunden: Int) -> String {
        switch sekunden {
        case 60: String(localized: "1 Minute")
        case 3_600: String(localized: "1 Stunde")
        case 86_400: String(localized: "1 Tag")
        default: Format.dauer(TimeInterval(sekunden))
        }
    }

    /// Hinweise zur Genauigkeit: Auflösung, Lücken, Kerzen über Ein- oder Ausstieg hinaus.
    static func hinweise(_ a: Ausstiegsanalyse) -> [String] {
        var ergebnis = [String(localized: "\(a.anzahlKerzen) Kerzen zu \(kerzenlaenge(a.kerzenDauer)), Kurse des Charts (bei MetaTrader der Geldkurs).")]
        if a.unscharf {
            ergebnis.append(String(localized: "Die Kerzen reichen über Ein- oder Ausstieg hinaus: MAE und MFE sind eher zu groß."))
        }
        if a.abdeckung < 1 {
            ergebnis.append(String(localized: "Kerzen decken \(a.abdeckung.formatted(.percent.precision(.fractionLength(0)))) der Haltedauer ab (Lücke, Wochenende)."))
        }
        return ergebnis
    }
}

/// Karte „Ausstieg“ im Trade-Inspektor (Doc 39, Paket B3): wie weit der Trade gegen und für einen lief und was
/// nach dem Ausstieg geschah. Nur beschreibend; keine Aussage, wie man hätte handeln sollen.
struct AusstiegKarte: View {
    let trade: Trade
    /// Währung des Trades (W1): Beträge nie mit dem Zeichen der Kontowährung, wenn der Trade anders lautet.
    let waehrung: String
    @Environment(\.thema) private var thema
    @State private var dienst = Ausstiegsdienst.geteilt
    @State private var analyse: Ausstiegsanalyse?
    @State private var gerechnet = false

    var body: some View {
        Karte("Ausstieg") {
            if trade.nurDatum {
                hinweis("Der Auszug nennt keine Uhrzeit; ohne Uhrzeit gibt es keine Ausstiegsanalyse.")
            } else if let analyse {
                werte(analyse)
            } else if gerechnet, dienst.hatKerzen(trade.symbol) {
                hinweis("Keine gespeicherten Kurse in der Haltedauer dieses Trades.")
            } else if gerechnet {
                hinweis("Für dieses Symbol sind keine Minutenkurse gespeichert. Abruf oder Import auf der Seite „Ausstieg“.")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: Schluessel(trade: trade.id, stop: trade.stopLoss, stand: dienst.stand)) {
            await dienst.ladeBestand()
            let neu = await dienst.analyse(trade)
            guard !Task.isCancelled else { return }
            analyse = neu
            gerechnet = true
        }
    }

    private struct Schluessel: Equatable {
        var trade: String
        var stop: Decimal?
        var stand: Int
    }

    @ViewBuilder
    private func werte(_ a: Ausstiegsanalyse) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            zeile("Größter Abstand dagegen (MAE)", Ausstiegsformat.abstand(a.mae, r: a.maeR, anteil: a.maeAnteil),
                  zeit: a.zeitMAE)
            zeile("Größter Abstand dafür (MFE)", Ausstiegsformat.abstand(a.mfe, r: a.mfeR, anteil: a.mfeAnteil),
                  zeit: a.zeitMFE)
            zeile("Anteil der MFE erzielt", Ausstiegsformat.effizienz(a.effizienz))
            zeile("Bis zur MFE offen, vor Kosten", a.liegengelassen.map { Format.betrag($0, waehrung) } ?? "–")
            zeile("Erste Stunde danach, dafür", a.nachAusstiegFuer.map(Format.kurs) ?? String(localized: "keine Kerzen"))
            zeile("Erste Stunde danach, dagegen", a.nachAusstiegGegen.map(Format.kurs) ?? String(localized: "keine Kerzen"))
        }
        VStack(alignment: .leading, spacing: Abstand.raster) {
            ForEach(Ausstiegsformat.hinweise(a), id: \.self) { Text(verbatim: $0) }
        }
        .font(Schrift.beschriftung)
        .foregroundStyle(thema.textSchwach)
    }

    private func zeile(_ titel: LocalizedStringKey, _ wert: String, zeit: Date? = nil) -> some View {
        GridRow {
            Text(titel)
                .foregroundStyle(thema.textSchwach)
                .gridColumnAlignment(.leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: wert)
                    .font(Schrift.tabelle)
                    .foregroundStyle(thema.text)
                if let zeit {
                    Text(verbatim: Format.zeit(zeit))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .gridColumnAlignment(.trailing)
        }
    }

    private func hinweis(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }
}
