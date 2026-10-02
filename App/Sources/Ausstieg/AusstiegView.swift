import SwiftUI
import TradingCore
import TradingRates

/// Seite „Ausstieg“ (Doc 39, Paket B3): Auswertung der Ausstiege über alle Trades mit Kursen (Mediane aus dem
/// Kern), die einzelnen Trades und die gespeicherten Kursdaten mit Import. Nur beschreibend: Rückblick auf
/// vergangene Kurse, keine Empfehlung, wann man aussteigen soll.
struct AusstiegView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var dienst = Ausstiegsdienst.geteilt
    @State private var ergebnis: Ergebnis?
    #if os(macOS)
    @State private var dateiWaehlen = false
    @State private var kursdatei: MT4Kursdatei?
    @State private var fehler: String?
    #endif

    /// Höchstens so viele Trades in der Liste, jüngste zuerst; die Auswertung zählt alle.
    private static let listengrenze = 200

    struct Ergebnis {
        var auswertung: Ausstiegsauswertung
        /// Summe `liegengelassen` in Kontowährung nach Währungsangleich; `nil` ohne Beträge.
        var summe: Decimal?
        var umgerechnet: Int
        var ohneKurs: Int
        var zeilen: [Ausstiegszeile]
        var mitUhrzeit: Int
    }

    private struct Schluessel: Equatable {
        var trades: [Trade]
        var stand: Int
        var waehrung: String
        var kurseBis: Journaltag?
        var kurseAbgerufen: Date?
    }

    var body: some View {
        let trades = modell.trades
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Ausstieg", untertitel: untertitel) {
                    #if os(macOS)
                    Button("Kurse importieren …") { dateiWaehlen = true }
                    #endif
                }
                Text("Wie weit liefen Trades gegen und für dich, und wie viel der besten Bewegung blieb beim Ausstieg übrig. Rückblick auf vergangene Kurse, keine Aussage über künftige.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                inhalt
                KursdatenKarte(dienst: dienst)
            }
            .padding(Abstand.seitenrand)
        }
        .task(id: Schluessel(trades: trades, stand: dienst.stand, waehrung: modell.waehrung,
                             kurseBis: modell.ezb.letzterTag, kurseAbgerufen: modell.ezb.abgerufen)) {
            await dienst.ladeBestand()
            let neu = await rechne(trades)
            guard !Task.isCancelled else { return }
            ergebnis = neu
        }
        #if os(macOS)
        .fileImporter(isPresented: $dateiWaehlen, allowedContentTypes: MT4Kursdatei.dateitypen) { auswahl in
            switch auswahl {
            case .success(let url):
                do { kursdatei = try MT4Kursdatei.lies(url) } catch { fehler = error.localizedDescription }
            case .failure(let f):
                fehler = f.localizedDescription
            }
        }
        .sheet(item: $kursdatei) { MT4KursimportBlatt(datei: $0) }
        .alert("Datei nicht lesbar", isPresented: Binding(get: { fehler != nil }, set: { if !$0 { fehler = nil } })) {
            Button("OK") { fehler = nil }
        } message: {
            Text(verbatim: fehler ?? "")
        }
        #endif
    }

    private var untertitel: String? {
        guard let ergebnis else { return nil }
        return String(localized: "\(ergebnis.auswertung.anzahl) von \(ergebnis.mitUhrzeit) Trades mit Kursen")
    }

    @ViewBuilder
    private var inhalt: some View {
        if let ergebnis, ergebnis.auswertung.anzahl > 0 {
            AuswertungKarte(ergebnis: ergebnis, waehrung: modell.waehrung)
            TradeListeKarte(zeilen: Array(ergebnis.zeilen.prefix(Self.listengrenze)), gesamt: ergebnis.zeilen.count,
                            kontowaehrung: modell.waehrung)
        } else if ergebnis != nil {
            Karte("Auswertung") {
                Group {
                    if dienst.bestand.isEmpty {
                        Text("Noch keine Kurse gespeichert. Am Mac: MetaTrader, Extras, Verlaufszentrum, Symbol und M1 wählen, Exportieren; die CSV-Datei hier importieren.")
                    } else {
                        Text("Für die Trades im gewählten Zeitraum liegen keine passenden Kurse vor. Trades ohne Uhrzeit im Auszug (Trade Republic, Scalable) bleiben außen vor.")
                    }
                }
                .foregroundStyle(thema.textSchwach)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func rechne(_ trades: [Trade]) async -> Ergebnis {
        let angleich = Waehrungsangleich(trades, kontowaehrung: modell.waehrung, kurse: modell.ezb.kurse)
        let analysen = await dienst.analysen(trades, angeglichen: angleich.trades)
        let liste = trades.compactMap { t in analysen.original[t.id].map { Ausstiegszeile(trade: t, analyse: $0) } }
            .sorted { $0.trade.closeTime > $1.trade.closeTime }
        let auswertung = Ausstiegsauswertung(liste.map(\.analyse), gleicheWaehrung: false)
        let summe = Ausstiegsauswertung(Array(analysen.angeglichen.values), gleicheWaehrung: true).summeLiegengelassen
        let ids = Set(liste.map(\.trade.id))
        return Ergebnis(auswertung: auswertung, summe: summe,
                        umgerechnet: angleich.umgerechnet.intersection(ids).count,
                        ohneKurs: angleich.ohneKurs.filter { ids.contains($0.id) }.count,
                        zeilen: liste, mitUhrzeit: trades.filter { !$0.nurDatum }.count)
    }
}

/// Ein analysierter Trade in der Liste.
struct Ausstiegszeile: Identifiable {
    var trade: Trade
    var analyse: Ausstiegsanalyse
    var id: String { trade.id }
}

/// Mediane über alle analysierten Trades (`Ausstiegsauswertung`).
private struct AuswertungKarte: View {
    let ergebnis: AusstiegView.Ergebnis
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        let a = ergebnis.auswertung
        Karte("Auswertung") {
            Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
                zeile("Trades mit Kursen", "\(a.anzahl)")
                zeile("Anteil der MFE erzielt, Median", Ausstiegsformat.effizienz(a.medianEffizienz))
                zeile("MAE der Gewinner, Median", Ausstiegsformat.rWert(a.medianMaeRGewinner))
                zeile("MFE, Median", Ausstiegsformat.rWert(a.medianMfeR))
                zeile("Verlierer, die 1 R im Plus lagen",
                      a.verliererMitR > 0 ? String(localized: "\(a.verliererMitEinemRPlus) von \(a.verliererMitR)") : "–")
                zeile("Bis zur MFE offen, Summe vor Kosten", ergebnis.summe.map { Format.betrag($0, waehrung) } ?? "–")
            }
            VStack(alignment: .leading, spacing: Abstand.raster) {
                StichprobenHinweis(anzahl: a.anzahl)
                Text("R nur bei Trades mit Stop auf der Verlustseite. Median statt Mittelwert, damit einzelne Ausreißer das Bild nicht bestimmen.")
                if a.anzahlUnscharf > 0 {
                    Text("\(a.anzahlUnscharf) Trades mit Kerzen über Ein- oder Ausstieg hinaus (Stunden- oder Tageskerzen): MAE und MFE dort eher zu groß.")
                }
                if ergebnis.umgerechnet > 0 {
                    Text("\(ergebnis.umgerechnet) Trades für die Summe zum EZB-Referenzkurs in \(waehrung) umgerechnet (Näherung).")
                }
                if ergebnis.ohneKurs > 0 {
                    Text("\(ergebnis.ohneKurs) Trades in fremder Währung ohne EZB-Kurs fehlen in der Summe.")
                }
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        }
    }

    private func zeile(_ titel: LocalizedStringKey, _ wert: String) -> some View {
        GridRow {
            Text(titel)
                .foregroundStyle(thema.textSchwach)
                .gridColumnAlignment(.leading)
            Text(verbatim: wert)
                .font(Schrift.tabelle)
                .foregroundStyle(thema.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
    }
}

/// Die analysierten Trades, jüngste zuerst. Beträge in der Währung des Trades (W1).
private struct TradeListeKarte: View {
    let zeilen: [Ausstiegszeile]
    let gesamt: Int
    let kontowaehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Trades") {
            Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
                GridRow {
                    Text("Trade")
                    Text("MAE").gridColumnAlignment(.trailing)
                    Text("MFE").gridColumnAlignment(.trailing)
                    Text("Erzielt").gridColumnAlignment(.trailing)
                    Text("Offen").gridColumnAlignment(.trailing)
                }
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                ForEach(zeilen) { zeile in
                    GridRow {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "\(zeile.trade.symbol) · \(Format.richtung(zeile.trade.side))")
                                .foregroundStyle(thema.text)
                            Text(verbatim: Format.zeit(zeile.trade.closeTime) + (zeile.analyse.unscharf ? " · ≈" : ""))
                                .font(Schrift.beschriftung)
                                .foregroundStyle(thema.textSchwach)
                        }
                        wert(zeile.analyse.maeR.map { Ausstiegsformat.rWert($0) } ?? Format.kurs(zeile.analyse.mae))
                        wert(zeile.analyse.mfeR.map { Ausstiegsformat.rWert($0) } ?? Format.kurs(zeile.analyse.mfe))
                        wert(Ausstiegsformat.effizienz(zeile.analyse.effizienz))
                        wert(zeile.analyse.liegengelassen.map {
                            Format.betrag($0, zeile.trade.waehrung(kontowaehrung: kontowaehrung))
                        } ?? "–")
                    }
                }
            }
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text("MAE und MFE in R, ohne Stop in Kurspunkten. Erzielt: Anteil der MFE. Offen: bis zur MFE, vor Kosten. ≈: Kerzen reichen über Ein- oder Ausstieg hinaus.")
                if gesamt > zeilen.count {
                    Text("Gezeigt sind die jüngsten \(zeilen.count) von \(gesamt) Trades.")
                }
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        }
    }

    private func wert(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Schrift.tabelle)
            .foregroundStyle(thema.text)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Gespeicherte Kurse je Symbol mit Zeitraum und Herkunft; am Mac mit Löschen.
private struct KursdatenKarte: View {
    let dienst: Ausstiegsdienst
    @Environment(\.thema) private var thema
    @State private var fehler: String?

    var body: some View {
        Karte("Kursdaten") {
            if dienst.bestand.isEmpty {
                Text("Keine Kurse gespeichert.")
                    .foregroundStyle(thema.textSchwach)
            }
            ForEach(dienst.bestand) { b in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: b.symbol)
                            .foregroundStyle(thema.text)
                        Text(verbatim: "\(Format.datum(b.von)) – \(Format.datum(b.bis)) · \(b.anzahl.formatted()) × \(Ausstiegsformat.kerzenlaenge(b.kerzenDauer)) · \(b.quellen.joined(separator: ", "))")
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                    Spacer()
                    #if os(macOS)
                    Button("Löschen", role: .destructive) { loesche(b.symbol) }
                        .buttonStyle(.borderless)
                    #endif
                }
            }
            if let fehler {
                Text(verbatim: fehler)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.verlust)
            }
            Text("MetaTrader-Kurse sind die des eigenen Brokers und passen zu den Fills; der Chart zeigt den Geldkurs (Bid). Das Verlaufszentrum exportiert nur, was MetaTrader zwischengespeichert hat; Minutenkurse reichen am wenigsten weit zurück.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func loesche(_ symbol: String) {
        Task {
            do { try await dienst.loesche(symbol: symbol) } catch {
                fehler = String(localized: "Löschen fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }
}
