import SwiftUI
import TradingCore
import TradingStore
import UniformTypeIdentifiers

/// Import (Doc 10, Abschnitt 7): Liste der bisherigen Importe, „Datei wählen“ öffnet das Blatt mit Prüfung.
struct ImportView: View {
    @AppStorage(Ton.schluessel) private var ton = Ton.henry
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var dateiWaehlen = false
    @State private var vorschau: ImportVorschau?
    @State private var lesefehler: String?

    /// Dateitypen im Öffnen-Dialog: HTML (MetaTrader 4 und 5), CSV (Trade Republic, Scalable, IBKR, Kryptobörsen), XLSX (XTB).
    private var dateitypen: [UTType] {
        [.html, .plainText, .commaSeparatedText, .spreadsheet]
            + [UTType("org.openxmlformats.spreadsheetml.sheet"), UTType(filenameExtension: "xlsx")].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Kopfzeile("Import", untertitel: String(localized: "\(modell.importe.count) Dateien")) {
                #if os(macOS)
                Button("Datei wählen") { dateiWaehlen = true }
                    .buttonStyle(.borderedProminent)
                #endif
            }
            #if os(iOS)
            Label("Der Import läuft am Mac. Hier siehst du, was dort schon eingelesen wurde.", systemImage: "macbook")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            #endif
            if modell.importe.contains(where: { Importer.istUngeprueft($0.lauf.importer) }) {
                Label("„ungeprüft“: Dieser Importer lief noch gegen keine echte Datei, nur gegen öffentliche Beispiele. Prüfe Stückzahlen und Beträge gegen die App deines Brokers.",
                      systemImage: "info.circle")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            #if os(macOS)
            ImportordnerKarte() // Rückfragen und stille Importe aus dem Import-Ordner (Doc 45)
            #endif
            if modell.importe.isEmpty {
                ContentUnavailableView(ton.text("Noch kein Import", henry: "Ein Auszug, bitte."), systemImage: "square.and.arrow.down",
                                       description: Text("Wähle einen Kontoauszug: MetaTrader 4 (HTML-Auszug aus der Broker-Mail, nicht der Bericht aus dem Terminal), MetaTrader 5 (Handelsbericht), den Transaktionsexport von Trade Republic oder Scalable Capital (CSV), das Activity Statement von Interactive Brokers (CSV), den Trade- oder Transaktionsexport von Kraken, Binance, Coinbase oder Bitpanda (CSV) oder die Kontohistorie von XTB (Excel aus xStation 5)."))
            } else {
                List(modell.importe) { eintrag in
                    ImportZeile(eintrag: eintrag)
                        .listRowBackground(thema.flaeche)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(Abstand.seitenrand)
        #if os(macOS)
        .fileImporter(isPresented: $dateiWaehlen, allowedContentTypes: dateitypen) { ergebnis in
            switch ergebnis {
            case .success(let url): lies(url)
            case .failure(let fehler): lesefehler = fehler.localizedDescription
            }
        }
        .sheet(item: $vorschau) { vorschau in
            ImportBlatt(vorschau: vorschau)
        }
        .alert("Datei nicht lesbar", isPresented: lesefehlerSichtbar) {
            Button("OK") { lesefehler = nil }
        } message: {
            Text(verbatim: lesefehler ?? "")
        }
        #endif
    }

    private var lesefehlerSichtbar: Binding<Bool> {
        Binding(get: { lesefehler != nil }, set: { if !$0 { lesefehler = nil } })
    }

    #if os(macOS)
    /// Liest die gewählte Datei in der Sandbox (vom Nutzer gewählt, daher mit Security-Scope).
    private func lies(_ url: URL) {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        do {
            vorschau = ImportVorschau(daten: try Data(contentsOf: url), dateiname: url.lastPathComponent)
        } catch {
            lesefehler = error.localizedDescription
        }
    }
    #endif
}

/// Eine importierte Datei in der Liste: Kennzeichnung „ungeprüft“ und aufklappbare Hinweise des Importers.
private struct ImportZeile: View {
    let eintrag: ImportEintrag
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            HStack {
                VStack(alignment: .leading, spacing: Abstand.raster) {
                    HStack(spacing: Abstand.raster * 2) {
                        Text(verbatim: eintrag.lauf.dateiname)
                            .foregroundStyle(thema.text)
                        if Importer.istUngeprueft(eintrag.lauf.importer) {
                            Kapsel(text: String(localized: "ungeprüft"))
                        }
                    }
                    Text(verbatim: "\(eintrag.konto.broker) · \(eintrag.konto.kontoname) · \(Importart.name(eintrag.lauf.art)) · \(String(localized: "Stichtag")) \(Format.datum(eintrag.lauf.stichtag))")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                Spacer()
                Text(verbatim: Format.datum(eintrag.lauf.importiertAm))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            if !eintrag.hinweise.isEmpty {
                DisclosureGroup {
                    HinweisListe(hinweise: eintrag.hinweise)
                } label: {
                    Text(verbatim: HinweisListe.anzahlText(eintrag.hinweise.count))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }
    }
}

/// Zeilen, die der Importer nicht sicher zuordnen konnte: Zeile in der Datei, Vorgangsart laut Broker, Folge.
struct HinweisListe: View {
    let hinweise: [Importhinweis]
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            ForEach(Array(hinweise.enumerated()), id: \.offset) { _, hinweis in
                Text(verbatim: Self.text(hinweis))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.text)
            }
        }
    }

    static func text(_ hinweis: Importhinweis) -> String {
        let folge: String = switch hinweis.folge {
        case .alsSonstiges: String(localized: "Betrag als „sonstiges“ verbucht")
        case .nichtVerbucht: String(localized: "nicht verbucht")
        }
        return String(localized: "Zeile \(hinweis.zeile): \(hinweis.vorgang) · \(folge)")
    }

    static func anzahlText(_ anzahl: Int) -> String {
        anzahl == 1 ? String(localized: "1 Hinweis") : String(localized: "\(anzahl) Hinweise")
    }
}

/// Art eines Auszugs, wie `Importlauf.art` sie speichert.
enum Importart {
    static func name(_ art: String) -> String {
        switch art {
        case "daily": String(localized: "Tagesauszug")
        case "monthly": String(localized: "Monatsauszug")
        case "transaktionen": String(localized: "Transaktionen")
        case "kontoauszug": String(localized: "Kontoauszug")
        default: art
        }
    }
}

/// Import A, ein Blatt mit Prüfung (Doc 10, Abschnitt 7): Erkennung, vier Zahlen, Konto und Zeit,
/// Prüfung gegen den Auszug, Hinweise. Der Knopf ist nur aktiv, wenn die Prüfung stimmt.
struct ImportBlatt: View {
    let vorschau: ImportVorschau
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var dismiss
    @State private var serverzeit = Serverzeit.vorgabe
    /// Zeitzone der XTB-Zeiten: nicht belegt, Vorgabe deutsche Ortszeit (Stand-Doc 16).
    @State private var xtbZeit = Serverzeit.mitteleuropa
    /// Kontonummer für einen XTB-Auszug ohne Kontokopf.
    @State private var xtbKontonummer = ""
    /// Zeitzone einmal vom letzten Import dieses Kontos übernommen (Doc 52 H5); danach gilt die Wahl im Blatt.
    @State private var zeitVorbelegt = false
    /// Kontonummer für einen MetaTrader-5-Bericht ohne Kontozeile.
    @State private var mt5Kontonummer = ""
    @State private var waehrung = "EUR"
    @State private var erkannt: ErkannteDatei?
    @State private var kontowahl: Kontowahl?
    @State private var neuerKontoname = ""
    @State private var lesefehler: String?
    @State private var ergebnis: ImportErgebnis?
    @State private var speicherfehler: String?
    /// Produktart für Zeilen, deren Art die Datei nicht nennt (Scalable, XTB); `nil` heißt später je Symbol.
    @State private var produktartVorgabe: Produktart?

    private static let waehrungen = ["EUR", "USD", "GBP", "CHF"]

    /// Konto für einen Export ohne Kontonummer: ein bestehendes des Brokers oder ein neues mit Bezeichnung.
    private enum Kontowahl: Hashable {
        case bestehend(Int64)
        case neu
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text(verbatim: vorschau.dateiname)
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    switch erkannt {
                    case .mt4(let auszug)?:
                        inhaltMT4(auszug)
                    case .csv(let broker, let bewegungen)?:
                        inhaltCSV(broker, bewegungen)
                    case .xtb(let auszug)?:
                        inhaltXTB(auszug)
                    case .mt5(let bericht)?:
                        inhaltMT5(bericht)
                    case nil:
                        if let lesefehler {
                            Label(lesefehler, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(thema.verlust)
                            if ProbeKarte.moeglich(vorschau.daten) {
                                Text("Eine anonymisierte Probe hilft, den Importer für diese Datei zu erweitern.")
                                    .font(Schrift.beschriftung)
                                    .foregroundStyle(thema.textSchwach)
                                ProbeKarte(daten: vorschau.daten)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            HStack(spacing: Abstand.kachelAbstand) {
                if let ergebnis {
                    Text(verbatim: ergebnisText(ergebnis))
                        .font(Schrift.fliesstext)
                        .foregroundStyle(thema.text)
                } else if let speicherfehler {
                    Text(verbatim: speicherfehler)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.verlust)
                }
                Spacer()
                if ergebnis == nil {
                    Button("Abbrechen") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    if erkannt != nil, !importierbar {
                        // Doc 55 J5: sagen, warum der Knopf grau ist.
                        Text(Self.gesperrtGrund)
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(knopfText) { speichere() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!importierbar)
                        .help(importierbar ? Text("") : Text(Self.gesperrtGrund))
                } else {
                    Button("Schließen") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Abstand.seitenrand)
        .frame(minWidth: 640, idealWidth: 700, minHeight: 540)
        .onChange(of: serverzeit, initial: true) { lies() }
        .onChange(of: xtbZeit) { lies() }
    }

    // MARK: MetaTrader 4

    @ViewBuilder
    private func inhaltMT4(_ auszug: MT4Statement) -> some View {
        let konto = modell.bekanntesKonto(broker: auszug.broker, kontonummer: auszug.accountNumber)
        let bekannt = modell.bekannteTickets(broker: auszug.broker, kontonummer: auszug.accountNumber)
        let dubletten = auszug.closedPositions.filter { bekannt.contains($0.ticket) }.count
        let ohneStop = auszug.closedPositions.filter { $0.stopLoss == nil }.count
        let abweichungen = auszug.pruefe()
        let anzeigeWaehrung = konto?.waehrung ?? waehrung

        Text(verbatim: Importlesung.erkennung(auszug))
            .font(Schrift.fliesstext)
            .foregroundStyle(thema.textSchwach)

        HStack(spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Trades", wert: "\(auszug.closedPositions.count)")
            Kachel(titel: "Gelöschte Orders (nie ausgelöst)", wert: "\(auszug.cancelledOrders.count)")
            Kachel(titel: "Ein-/Auszahlungen", wert: Format.betrag(auszug.summary.depositWithdrawal, anzeigeWaehrung))
            Kachel(titel: "Schon bekannt", wert: "\(dubletten)")
        }

        Text("Konto und Zeit")
            .font(.headline)
            .foregroundStyle(thema.text)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                Text("Konto").foregroundStyle(thema.textSchwach)
                if let konto {
                    Text(verbatim: "\(konto.broker) · \(konto.kontoname) (\(String(localized: "bestehend")), \(konto.waehrung))")
                        .foregroundStyle(thema.text)
                } else {
                    HStack {
                        Text(verbatim: "\(auszug.broker) · \(auszug.accountName) (\(String(localized: "neu")))")
                            .foregroundStyle(thema.text)
                        Picker("Kontowährung", selection: $waehrung) {
                            ForEach(Self.waehrungen, id: \.self) { Text(verbatim: $0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            GridRow {
                Text("Serverzeit der Datei").foregroundStyle(thema.textSchwach)
                Picker("Serverzeit", selection: $serverzeit) {
                    ForEach(Serverzeit.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .help(Self.serverzeitHilfe) // Doc 55 J13
            }
            GridRow {
                Text("Kosten").foregroundStyle(thema.textSchwach)
                Text("Kommission und Swap aus dem Export, nichts geschätzt").foregroundStyle(thema.text)
            }
        }

        Text("Prüfung gegen den Auszug")
            .font(.headline)
            .foregroundStyle(thema.text)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Wert")
                Text("laut Auszug").gridColumnAlignment(.trailing)
                Text("berechnet").gridColumnAlignment(.trailing)
                Text("")
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            ForEach(Importlesung.pruefungen(auszug)) { pruefung in
                GridRow {
                    Text(verbatim: pruefung.id).foregroundStyle(thema.text)
                    Text(verbatim: Format.zahl(pruefung.lautAuszug)).font(Schrift.tabelle)
                    Text(verbatim: Format.zahl(pruefung.berechnet)).font(Schrift.tabelle)
                    if pruefung.stimmt {
                        Text("stimmt").foregroundStyle(thema.gewinn)
                    } else {
                        Text("weicht ab").foregroundStyle(thema.verlust)
                    }
                }
            }
        }
        if !abweichungen.isEmpty {
            Text(verbatim: abweichungen.map(\.description).joined(separator: "\n"))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.verlust)
        }

        if ohneStop > 0 {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text("\(ohneStop) Trades ohne Stop im Export")
                    .font(.headline)
                    .foregroundStyle(thema.text)
                Text("Im Export steht nur der letzte Stop-Loss. Ohne Stop kein R; der Trade wird markiert. Stop nachtragen: Trade anklicken, rechts beim Stop eintragen.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            .padding(Abstand.kachelInnen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
        }

        claudeSatz
    }

    // MARK: Trade Republic, Scalable und Kryptobörsen (CSV)

    @ViewBuilder
    private func inhaltCSV(_ broker: CSVBroker, _ bewegungen: Kontobewegungen) -> some View {
        let bildung = Positionsbildung.bilde(bewegungen.ausfuehrungen, kapitalmassnahmen: bewegungen.kapitalmassnahmen)
        let konten = modell.konten(broker: broker.name)
        let gewaehlt = gewaehltesKonto(konten)
        let bekannt = gewaehlt.map { modell.bekannteVorgaenge(broker: broker.name, kontonummer: $0.kontonummer) } ?? []
        let vorgangsIds = bewegungen.ausfuehrungen.map(\.id) + bewegungen.geldbewegungen.map(\.id)
            + bewegungen.kapitalmassnahmen.map(\.id)
        let dubletten = vorgangsIds.filter { bekannt.contains($0) }.count
        let anzeigeWaehrung = gewaehlt?.waehrung ?? waehrung
        let kaeufe = bewegungen.ausfuehrungen.filter { $0.seite == .buy }.count
        let verkaeufe = bewegungen.ausfuehrungen.count - kaeufe
        // Gegencheck A4: Summen je Währung, USD und USDT nicht als Kontowährung addieren.
        let geldPosten: [(String, Decimal)] = bewegungen.geldbewegungen
            .map { ($0.waehrung, $0.betrag + $0.gebuehr + $0.steuer) }
        let handelPosten: [(String, Decimal)] = bewegungen.ausfuehrungen
            .map { ($0.waehrung, $0.betrag + $0.gebuehr + $0.steuer) }
        let einAusPosten: [(String, Decimal)] = bewegungen.geldbewegungen
            .filter { $0.art == .einzahlung || $0.art == .auszahlung }
            .map { ($0.waehrung, $0.betrag + $0.gebuehr + $0.steuer) }
        let einAus = Waehrungssummen(einAusPosten, kontowaehrung: anzeigeWaehrung)
        let kasse = Waehrungssummen(handelPosten + geldPosten, kontowaehrung: anzeigeWaehrung)
        let tradeWaehrungen = Set(bildung.trades.map { $0.waehrung(kontowaehrung: anzeigeWaehrung) }).sorted()
        let tradeListe = tradeWaehrungen.joined(separator: ", ")

        HStack(spacing: Abstand.raster * 2) {
            Text(verbatim: Importlesung.erkennung(broker, bewegungen))
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.textSchwach)
            Kapsel(text: String(localized: "ungeprüft"), betont: true)
        }
        // Ein Block, damit der ViewBuilder unter zehn Kindern bleibt.
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text("Dieser Importer lief noch gegen keine echte Datei, nur gegen öffentliche Beispiele. Prüfe nach dem Import Stückzahlen und Beträge gegen die App deines Brokers.")
            if broker.istKrypto {
                Text("Krypto: Käufe und Verkäufe gegen Euro, Dollar, Franken, Pfund oder Stablecoin (USDT, USDC, EURC) werden Trades mit Produktart Krypto. Krypto gegen Krypto, Margin, Staking-Umbuchungen und Krypto-Ein- und -Auszahlungen stehen als Hinweise und werden nicht verbucht. Die Steuer-Seite rechnet die Haltefrist von einem Jahr; Trades in Dollar oder Stablecoin brauchen dort noch den Tageskurs.")
            }
        }
        .font(Schrift.beschriftung)
        .foregroundStyle(thema.textSchwach)

        HStack(spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Ausführungen", wert: "\(bewegungen.ausfuehrungen.count)",
                   zusatz: String(localized: "\(kaeufe) Käufe, \(verkaeufe) Verkäufe"))
            Kachel(titel: "Trades", wert: "\(bildung.trades.count)",
                   zusatz: !tradeWaehrungen.isEmpty && tradeWaehrungen != [anzeigeWaehrung.uppercased()]
                       ? String(localized: "nach FIFO, nur diese Datei · in \(tradeListe)")
                       : String(localized: "nach FIFO, nur diese Datei"))
            Kachel(titel: "Ein-/Auszahlungen", wert: einAus.kontowaehrungText,
                   zusatz: einAus.zusatz(String(localized: "\(bewegungen.geldbewegungen.count) Geldbewegungen gesamt")))
            Kachel(titel: "Schon bekannt", wert: "\(dubletten)",
                   zusatz: String(localized: "von \(vorgangsIds.count) Vorgängen"))
        }

        Text("Konto und Zeit")
            .font(.headline)
            .foregroundStyle(thema.text)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                Text("Konto").foregroundStyle(thema.textSchwach)
                HStack {
                    Picker("Konto", selection: kontowahlBinding) {
                        ForEach(konten, id: \.id) { konto in
                            Text(verbatim: "\(konto.kontoname) (\(konto.waehrung))").tag(Kontowahl.bestehend(konto.id ?? 0))
                        }
                        Text("Neues Konto").tag(Kontowahl.neu)
                    }
                    .labelsHidden()
                    .fixedSize()
                    if kontowahl == .neu {
                        TextField("Bezeichnung", text: $neuerKontoname)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Picker("Kontowährung", selection: $waehrung) {
                            ForEach(Self.waehrungen, id: \.self) { Text(verbatim: $0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            GridRow {
                Text("Zeit in der Datei").foregroundStyle(thema.textSchwach)
                Text(broker.zeitzoneText).foregroundStyle(thema.text)
            }
            GridRow {
                Text("Kosten").foregroundStyle(thema.textSchwach)
                Text(broker.kostenText).foregroundStyle(thema.text)
            }
            if broker == .scalable {
                produktartZeile
            }
        }
        Text(verbatim: broker.istKrypto
             ? String(localized: "Die Datei nennt kein Konto. Wähle bei jedem Export dieser Börse dasselbe Konto, sonst zählt die App Vorgänge doppelt.")
             : String(localized: "Die Datei nennt kein Konto. Wähle bei jedem Export dieses Depots dasselbe Konto, sonst zählt die App Vorgänge doppelt."))
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)

        Text("Prüfung")
            .font(.headline)
            .foregroundStyle(thema.text)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Kassenwirkung der Datei").foregroundStyle(thema.text)
                Text(verbatim: kasse.alleText)
                    .font(Schrift.tabelle)
                    .gridColumnAlignment(.trailing)
                Text(verbatim: kasse.fremde.isEmpty
                     ? String(localized: "Summe aller Zeilen; der Export nennt keinen Saldo zum Gegenprüfen")
                     : String(localized: "Summe aller Zeilen je Währung, ohne Umrechnung; der Export nennt keinen Saldo zum Gegenprüfen"))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            GridRow {
                Text("Verworfene Orders").foregroundStyle(thema.text)
                Text(verbatim: "\(bewegungen.verworfen.count)").font(Schrift.tabelle)
                Text("storniert oder abgelehnt, zählen nie als Trade")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            if !bildung.ohneBestand.isEmpty {
                GridRow {
                    Text("Verkäufe ohne Kauf").foregroundStyle(thema.text)
                    Text(verbatim: "\(bildung.ohneBestand.count)").font(Schrift.tabelle)
                    Text("Der Kauf liegt vor dem Exportzeitraum; ohne Einstand kein Trade. Ein längerer Export hilft.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            if !bildung.offen.isEmpty {
                GridRow {
                    Text("Offene Käufe").foregroundStyle(thema.text)
                    Text(verbatim: "\(bildung.offen.count)").font(Schrift.tabelle)
                    Text("noch im Depot; werden beim Verkauf zu Trades")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }

        if !bewegungen.hinweise.isEmpty {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: HinweisListe.anzahlText(bewegungen.hinweise.count) + ": " + String(localized: "Zeilen, die der Importer nicht sicher zuordnen kann"))
                    .font(.headline)
                    .foregroundStyle(thema.text)
                HinweisListe(hinweise: bewegungen.hinweise)
            }
            .padding(Abstand.kachelInnen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
        }

        claudeSatz
    }

    // MARK: XTB (Excel)

    @ViewBuilder
    private func inhaltXTB(_ auszug: XTBAuszug) -> some View {
        let nummer = xtbNummer(auszug)
        let konto = nummer.isEmpty ? nil : modell.bekanntesKonto(broker: Importer.xtbBroker, kontonummer: nummer)
        let bekannt = nummer.isEmpty ? [] : modell.bekannteTickets(broker: Importer.xtbBroker, kontonummer: nummer)
        let dubletten = auszug.positionen.filter { bekannt.contains($0.ticket) }.count
        let ohneStop = auszug.positionen.filter { $0.stopLoss == nil }.count
        let anzeigeWaehrung = auszug.waehrung ?? konto?.waehrung ?? waehrung
        let einAus = auszug.kasse.geldbewegungen.filter { $0.art == .einzahlung || $0.art == .auszahlung }
            .map { $0.betrag + $0.gebuehr + $0.steuer }.reduce(Decimal(0), +)
        let summenpruefung = Importlesung.pruefungen(auszug)

        HStack(spacing: Abstand.raster * 2) {
            Text(verbatim: Importlesung.erkennung(auszug))
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.textSchwach)
            Kapsel(text: String(localized: "ungeprüft"), betont: true)
        }
        Text("Dieser Importer lief noch gegen keine echte Datei, nur gegen öffentliche Beispiele. Prüfe nach dem Import Stückzahlen und Beträge gegen xStation.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)

        HStack(spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Trades", wert: "\(auszug.positionen.count)",
                   zusatz: String(localized: "geschlossene Positionen"))
            Kachel(titel: "Kassenoperationen", wert: "\(auszug.kasse.geldbewegungen.count)",
                   zusatz: String(localized: "ohne Handel"))
            Kachel(titel: "Ein-/Auszahlungen", wert: Format.betrag(einAus, anzeigeWaehrung))
            Kachel(titel: "Schon bekannt", wert: "\(dubletten)")
        }

        Text("Konto und Zeit")
            .font(.headline)
            .foregroundStyle(thema.text)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                Text("Konto").foregroundStyle(thema.textSchwach)
                HStack {
                    if let konto {
                        Text(verbatim: "\(konto.broker) · \(konto.kontoname) (\(String(localized: "bestehend")), \(konto.waehrung))")
                            .foregroundStyle(thema.text)
                    } else if auszug.konto != nil {
                        Text(verbatim: "\(Importer.xtbBroker) · \(String(localized: "Konto")) \(Importlesung.maskiert(nummer)) (\(String(localized: "neu")))")
                            .foregroundStyle(thema.text)
                    } else {
                        Text(verbatim: Importer.xtbBroker).foregroundStyle(thema.text)
                        TextField("Kontonummer", text: $xtbKontonummer)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                    if konto == nil {
                        if let waehrung = auszug.waehrung {
                            Text(verbatim: waehrung).foregroundStyle(thema.textSchwach)
                        } else {
                            Picker("Kontowährung", selection: $waehrung) {
                                ForEach(Self.waehrungen, id: \.self) { Text(verbatim: $0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
            GridRow {
                Text("Zeit in der Datei").foregroundStyle(thema.textSchwach)
                Picker("Zeitzone", selection: $xtbZeit) {
                    ForEach(Serverzeit.allCases) { Text($0.kurzname).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Kosten").foregroundStyle(thema.textSchwach)
                Text("Kommission, Swap und Rollover aus dem Export; Kassenzeilen zu Positionen zählen nicht doppelt").foregroundStyle(thema.text)
            }
            produktartZeile
        }
        if auszug.konto == nil {
            Text("Die Datei nennt keine Kontonummer. Gib dieselbe Nummer wie bei früheren Auszügen dieses Kontos an, sonst zählt die App Positionen doppelt.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        Text("XTB schreibt keine Zeitzone in die Datei; deutsche Ortszeit ist eine Annahme. Eine andere Wahl verschiebt alle Zeiten, und ein späterer Auszug mit anderer Wahl bricht als abweichend ab.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)

        Text("Prüfung gegen den Auszug")
            .font(.headline)
            .foregroundStyle(thema.text)
        if summenpruefung.isEmpty {
            Text("Die Datei hat keine Summenzeilen „Total“; nichts zu vergleichen.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        } else {
            Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
                GridRow {
                    Text("Wert")
                    Text("laut Auszug").gridColumnAlignment(.trailing)
                    Text("berechnet").gridColumnAlignment(.trailing)
                    Text("")
                }
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                ForEach(summenpruefung) { pruefung in
                    GridRow {
                        Text(verbatim: pruefung.id).foregroundStyle(thema.text)
                        Text(verbatim: Format.zahl(pruefung.lautAuszug)).font(Schrift.tabelle)
                        Text(verbatim: Format.zahl(pruefung.berechnet)).font(Schrift.tabelle)
                        if pruefung.stimmt {
                            Text("stimmt").foregroundStyle(thema.gewinn)
                        } else {
                            Text("weicht ab").foregroundStyle(thema.verlust)
                        }
                    }
                }
            }
        }

        if !auszug.hinweise.isEmpty {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: HinweisListe.anzahlText(auszug.hinweise.count) + ": " + String(localized: "Zeilen, die der Importer nicht sicher zuordnen kann"))
                    .font(.headline)
                    .foregroundStyle(thema.text)
                HinweisListe(hinweise: auszug.hinweise)
            }
            .padding(Abstand.kachelInnen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
        }

        if ohneStop > 0 {
            Text("\(ohneStop) Trades ohne Stop im Export: ohne Stop kein R; Stop nachtragen geht im Inspektor.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }

        claudeSatz
    }

    // MARK: MetaTrader 5 (HTML, Doc 48)

    @ViewBuilder
    private func inhaltMT5(_ bericht: MT5Bericht) -> some View {
        let nummer = mt5Nummer(bericht)
        let broker = Importlesung.broker(bericht)
        let konto = nummer.isEmpty ? nil : modell.bekanntesKonto(broker: broker, kontonummer: nummer)
        let bekannt = nummer.isEmpty ? [] : modell.bekannteTickets(broker: broker, kontonummer: nummer)
        let dubletten = bericht.positionen.filter { bekannt.contains($0.ticket) }.count
        let ohneStop = bericht.positionen.filter { $0.stopLoss == nil }.count
        let anzeigeWaehrung = bericht.waehrung ?? konto?.waehrung ?? waehrung
        let einAus = bericht.kasse.geldbewegungen.filter { $0.art == .einzahlung || $0.art == .auszahlung }
            .map { $0.betrag + $0.gebuehr + $0.steuer }.reduce(Decimal(0), +)

        HStack(spacing: Abstand.raster * 2) {
            Text(verbatim: Importlesung.erkennung(bericht))
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.textSchwach)
            Kapsel(text: String(localized: "ungeprüft"), betont: true)
        }
        Text("Dieser Importer lief noch gegen keine echte Datei, nur gegen nachgebaute Beispiele. Prüfe nach dem Import Lots und Beträge gegen den Bericht im Terminal.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)

        HStack(spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Trades", wert: "\(bericht.positionen.count)",
                   zusatz: String(localized: "geschlossene Positionen"))
            Kachel(titel: "Kassenoperationen", wert: "\(bericht.kasse.geldbewegungen.count)",
                   zusatz: String(localized: "ohne Handel"))
            Kachel(titel: "Ein-/Auszahlungen", wert: Format.betrag(einAus, anzeigeWaehrung))
            Kachel(titel: "Schon bekannt", wert: "\(dubletten)")
        }

        Text("Konto und Zeit")
            .font(.headline)
            .foregroundStyle(thema.text)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                Text("Konto").foregroundStyle(thema.textSchwach)
                HStack {
                    if let konto {
                        Text(verbatim: "\(konto.broker) · \(konto.kontoname) (\(String(localized: "bestehend")), \(konto.waehrung))")
                            .foregroundStyle(thema.text)
                    } else if bericht.konto != nil {
                        Text(verbatim: "\(broker) · \(String(localized: "Konto")) \(Importlesung.maskiert(nummer)) (\(String(localized: "neu")))")
                            .foregroundStyle(thema.text)
                    } else {
                        Text(verbatim: broker).foregroundStyle(thema.text)
                        TextField("Kontonummer", text: $mt5Kontonummer)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                    if konto == nil {
                        if let waehrung = bericht.waehrung {
                            Text(verbatim: waehrung).foregroundStyle(thema.textSchwach)
                        } else {
                            Picker("Kontowährung", selection: $waehrung) {
                                ForEach(Self.waehrungen, id: \.self) { Text(verbatim: $0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
            GridRow {
                Text("Serverzeit der Datei").foregroundStyle(thema.textSchwach)
                Picker("Serverzeit", selection: $serverzeit) {
                    ForEach(Serverzeit.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .help(Self.serverzeitHilfe) // Doc 55 J13
            }
            GridRow {
                Text("Kosten").foregroundStyle(thema.textSchwach)
                Text("Kommission und Swap aus dem Bericht, nichts geschätzt").foregroundStyle(thema.text)
            }
        }
        if bericht.konto == nil {
            Text("Die Datei nennt keine Kontonummer. Gib dieselbe Nummer wie bei früheren Berichten dieses Kontos an, sonst zählt die App Positionen doppelt.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }

        Text("Prüfung gegen den Auszug")
            .font(.headline)
            .foregroundStyle(thema.text)
        pruefRaster(Importlesung.pruefungen(bericht))

        if !bericht.hinweise.isEmpty {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: HinweisListe.anzahlText(bericht.hinweise.count) + ": " + String(localized: "Zeilen, die der Importer nicht sicher zuordnen kann"))
                    .font(.headline)
                    .foregroundStyle(thema.text)
                HinweisListe(hinweise: bericht.hinweise)
            }
            .padding(Abstand.kachelInnen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
        }

        if ohneStop > 0 {
            Text("\(ohneStop) Trades ohne Stop im Export: ohne Stop kein R; Stop nachtragen geht im Inspektor.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }

        claudeSatz
    }

    /// Summenprüfung als Raster; leer mit Hinweis statt Tabelle.
    @ViewBuilder
    private func pruefRaster(_ liste: [Importlesung.Pruefung]) -> some View {
        if liste.isEmpty {
            Text("Die Datei hat keine Summenzeile; nichts zu vergleichen.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        } else {
            Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
                GridRow {
                    Text("Wert")
                    Text("laut Auszug").gridColumnAlignment(.trailing)
                    Text("berechnet").gridColumnAlignment(.trailing)
                    Text("")
                }
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                ForEach(liste) { pruefung in
                    GridRow {
                        Text(verbatim: pruefung.id).foregroundStyle(thema.text)
                        Text(verbatim: Format.zahl(pruefung.lautAuszug)).font(Schrift.tabelle)
                        Text(verbatim: Format.zahl(pruefung.berechnet)).font(Schrift.tabelle)
                        if pruefung.stimmt {
                            Text("stimmt").foregroundStyle(thema.gewinn)
                        } else {
                            Text("weicht ab").foregroundStyle(thema.verlust)
                        }
                    }
                }
            }
        }
    }

    /// Kontonummer aus dem Bericht, sonst die eingegebene.
    private func mt5Nummer(_ bericht: MT5Bericht) -> String {
        bericht.konto ?? mt5Kontonummer.trimmingCharacters(in: .whitespaces)
    }

    /// Kontonummer aus dem Kopf der Datei, sonst die eingegebene.
    private func xtbNummer(_ auszug: XTBAuszug) -> String {
        auszug.konto ?? xtbKontonummer.trimmingCharacters(in: .whitespaces)
    }

    private var claudeSatz: some View {
        Text("Später an Claude gehen: Zeiten, Instrument, Richtung, Lots, Kurse, Kosten, Ergebnis, Journal. Nicht: Kontonummer, Name, Saldo.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    // MARK: Zustand

    private var knopfText: String { Importlesung.knopfText(erkannt) }

    private var importierbar: Bool {
        var nummer = ""
        var mt5 = ""
        if case .xtb(let auszug)? = erkannt { nummer = xtbNummer(auszug) }
        if case .mt5(let bericht)? = erkannt { mt5 = mt5Nummer(bericht) }
        return Importlesung.importierbar(erkannt, kontoGueltig: kontoGueltig, xtbNummer: nummer, mt5Nummer: mt5)
    }

    private var kontoGueltig: Bool {
        switch kontowahl {
        case .bestehend?: true
        case .neu?: !neuerKontoname.trimmingCharacters(in: .whitespaces).isEmpty
        case nil: false
        }
    }

    private var kontowahlBinding: Binding<Kontowahl> {
        Binding(get: { kontowahl ?? .neu }, set: { kontowahl = $0 })
    }

    private func gewaehltesKonto(_ konten: [Konto]) -> Konto? {
        if case .bestehend(let id)? = kontowahl { return konten.first { $0.id == id } }
        return nil
    }

    /// Zeile „Produktart“ für Dateien ohne Art (Scalable, XTB; TradingStore #96): gilt nur für Zeilen, deren Art der
    /// Importer nicht kennt; „später je Symbol“ lässt sie offen, die Steuer-Seite fragt dann je Wertpapier nach.
    private var produktartZeile: some View {
        GridRow {
            Text("Produktart").foregroundStyle(thema.textSchwach)
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Picker("Produktart", selection: $produktartVorgabe) {
                    Text("Später je Wertpapier (Steuer-Seite)").tag(Produktart?.none)
                    ForEach(Produktartformat.waehlbar, id: \.self) { art in
                        Text(verbatim: Produktartformat.titel(art)).tag(Produktart?.some(art))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Text("Die Datei nennt keine Produktart. Eine Vorgabe gilt für alle Zeilen dieser Datei ohne Art; gemischte Depots besser später je Wertpapier zuordnen.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    private static let gesperrtGrund: LocalizedStringKey = "Importieren geht erst, wenn jede Prüfzeile „stimmt“ zeigt und das Konto feststeht. Wähl zuerst eine andere Serverzeit; hilft das nicht, Hilfe › Problem melden."
    private static let serverzeitHilfe: LocalizedStringKey = "Die Zeitzone, in der dein MetaTrader die Zeiten zeigt. Unsicher: Vorgabe lassen. Wichtig: bei jedem Import dieselbe."

    /// Liest die Datei über `Importlesung` (testbar ohne Ansicht, Doc 44) und setzt die Kontovorgabe.
    private func lies() {
        erkannt = nil
        lesefehler = nil
        switch Importlesung.lies(vorschau.daten, dateiname: vorschau.dateiname,
                                 serverzeit: serverzeit.zeitzone, xtbZeit: xtbZeit.zeitzone) {
        case .erkannt(let datei): erkannt = datei
        case .fehler(let text, let kategorie):
            lesefehler = text
            Fehlerprotokoll.merke("Lesen: \(kategorie)") // Hilfe › Problem melden, nur die Fehlerart
        }
        if !zeitVorbelegt, let datei = erkannt {
            zeitVorbelegt = true
            // Bekanntes Konto: Zeitzone wie beim letzten Import, sonst stimmen die Tickets nicht überein (Doc 52 H5).
            // Die Änderung liest die Datei über onChange noch einmal mit dieser Zone.
            if let zone = letzteZone(datei) {
                if case .xtb = datei {
                    if zone != xtbZeit { xtbZeit = zone }
                } else if zone != serverzeit {
                    serverzeit = zone
                }
            }
        }
        if case .csv(let broker, _)? = erkannt, kontowahl == nil {
            // Vorgabe: das erste Konto dieses Brokers, sonst ein neues namens „Depot“ (Börsen: „Spot“).
            // IBKR nennt die Kontonummer: dann das Konto mit dieser Nummer, sonst ein neues mit ihr als Name.
            let konten = modell.konten(broker: broker.name)
            if broker == .ibkr, let text = Importtext.lies(vorschau.daten) {
                let kopf = IBKRCSV.konto(text)
                if let nummer = kopf.nummer {
                    kontowahl = konten.first { $0.kontonummer == nummer }.flatMap(\.id).map(Kontowahl.bestehend) ?? .neu
                    if neuerKontoname.isEmpty { neuerKontoname = nummer }
                }
                if let w = kopf.waehrung { waehrung = w }
            }
            if kontowahl == nil {
                kontowahl = konten.first.flatMap(\.id).map(Kontowahl.bestehend) ?? .neu
            }
            if neuerKontoname.isEmpty { neuerKontoname = broker.kontoVorgabe }
        }
    }

    /// Zeitzone des jüngsten Imports, wenn die Datei ein bekanntes MetaTrader- oder XTB-Konto nennt.
    private func letzteZone(_ datei: ErkannteDatei) -> Serverzeit? {
        let konto: Konto?
        switch datei {
        case .mt4(let auszug):
            konto = modell.bekanntesKonto(broker: auszug.broker, kontonummer: auszug.accountNumber)
        case .mt5(let bericht):
            konto = bericht.konto.flatMap { modell.bekanntesKonto(broker: Importlesung.broker(bericht), kontonummer: $0) }
        case .xtb(let auszug):
            konto = auszug.konto.flatMap { modell.bekanntesKonto(broker: Importer.xtbBroker, kontonummer: $0) }
        case .csv:
            konto = nil
        }
        guard let konto else { return nil }
        let letzter = modell.importe.filter { $0.konto.id == konto.id }
            .max { $0.lauf.importiertAm < $1.lauf.importiertAm }
        guard let kennung = letzter?.lauf.serverZeitzone else { return nil }
        return Serverzeit.allCases.first { $0.rawValue == kennung || $0.zeitzone.identifier == kennung }
    }

    private func speichere() {
        do {
            switch erkannt {
            case .mt4(let auszug)?:
                let kontowaehrung = modell.bekanntesKonto(broker: auszug.broker, kontonummer: auszug.accountNumber)?.waehrung
                    ?? waehrung
                ergebnis = try modell.importiereMT4(daten: vorschau.daten, dateiname: vorschau.dateiname,
                                                    serverZeitzone: serverzeit.zeitzone, waehrung: kontowaehrung)
            case .csv(let broker, _)?:
                let konto = gewaehltesKonto(modell.konten(broker: broker.name))
                let name = neuerKontoname.trimmingCharacters(in: .whitespaces)
                ergebnis = try modell.importiereCSV(daten: vorschau.daten, dateiname: vorschau.dateiname,
                                                    kontonummer: konto?.kontonummer ?? name,
                                                    kontoname: konto?.kontoname ?? name,
                                                    waehrung: konto?.waehrung ?? waehrung, zeitzone: broker.zeitzone,
                                                    produktartVorgabe: broker == .scalable ? produktartVorgabe : nil)
            case .xtb(let auszug)?:
                // Nummer und Währung nur mitgeben, wenn die Datei sie nicht nennt; sonst prüft die
                // Speicherung Datei gegen Angabe und bricht bei Widerspruch ab.
                let nummer = xtbNummer(auszug)
                let bestehend = modell.bekanntesKonto(broker: Importer.xtbBroker, kontonummer: nummer)
                ergebnis = try modell.importiereXTB(daten: vorschau.daten, dateiname: vorschau.dateiname,
                                                    kontonummer: auszug.konto == nil ? nummer : nil,
                                                    kontoname: bestehend?.kontoname ?? String(localized: "Konto \(Importlesung.maskiert(nummer))"),
                                                    waehrung: auszug.waehrung == nil ? (bestehend?.waehrung ?? waehrung) : nil,
                                                    zeitzone: xtbZeit.zeitzone, produktartVorgabe: produktartVorgabe)
            case .mt5(let bericht)?:
                // Wie XTB: Nummer und Währung nur, wenn der Bericht sie nicht nennt.
                let nummer = mt5Nummer(bericht)
                let bestehend = modell.bekanntesKonto(broker: Importlesung.broker(bericht), kontonummer: nummer)
                ergebnis = try modell.importiereMT5(daten: vorschau.daten, dateiname: vorschau.dateiname,
                                                    kontonummer: bericht.konto == nil ? nummer : nil,
                                                    kontoname: bestehend?.kontoname ?? String(localized: "Konto \(Importlesung.maskiert(nummer))"),
                                                    waehrung: bericht.waehrung == nil ? (bestehend?.waehrung ?? waehrung) : nil,
                                                    serverZeitzone: serverzeit.zeitzone)
            case nil:
                return
            }
            speicherfehler = nil
        } catch {
            speicherfehler = Importlesung.fehlertext(error)
            Fehlerprotokoll.merke("Speichern: \(Importlesung.kategorie(error))") // nur die Fehlerart
        }
    }

    private func ergebnisText(_ ergebnis: ImportErgebnis) -> String {
        switch ergebnis.status {
        case .dateiBereitsImportiert:
            return Ton.aktuell.text("Genau diese Datei war schon importiert. Nichts geändert.",
                                    henry: "Diese Datei lag bereits vor. Nichts geändert.")
        case .gespeichert:
            let gespeichert = Ton.aktuell.text("Gespeichert:", henry: "Verbucht:")
            if case .csv(_, _)? = erkannt {
                let z = ergebnis.csv
                return String(localized: "\(gespeichert) \(z.ausfuehrungenNeu) neue Ausführungen (\(z.ausfuehrungenBekannt) bekannt), \(z.geldbewegungenNeu) Geldbewegungen, \(z.kapitalmassnahmenNeu) Kapitalmaßnahmen, \(z.verworfen) verworfen, \(z.hinweise) Hinweise.")
            }
            if case .xtb? = erkannt {
                let z = ergebnis.csv
                return String(localized: "\(gespeichert) \(ergebnis.geschlosseneNeu) neue Trades, \(ergebnis.geschlosseneBekannt) schon bekannt, \(z.geldbewegungenNeu) Kassenoperationen (\(z.geldbewegungenBekannt) bekannt), \(z.hinweise) Hinweise.")
            }
            if case .mt5? = erkannt {
                let z = ergebnis.csv
                return String(localized: "\(gespeichert) \(ergebnis.geschlosseneNeu) neue Trades, \(ergebnis.geschlosseneBekannt) schon bekannt, \(z.geldbewegungenNeu) Kassenoperationen (\(z.geldbewegungenBekannt) bekannt), \(z.hinweise) Hinweise.")
            }
            return String(localized: "\(gespeichert) \(ergebnis.geschlosseneNeu) neue Trades, \(ergebnis.geschlosseneBekannt) schon bekannt, \(ergebnis.geloeschteNeu) gelöschte Orders.")
        }
    }
}
