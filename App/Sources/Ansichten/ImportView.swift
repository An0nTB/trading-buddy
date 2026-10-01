import SwiftUI
import TradingCore
import TradingStore
import UniformTypeIdentifiers

/// Serverzeitzone eines MT4-Auszugs. Sie steht nicht in der Datei; die App fragt sie ab
/// (Entscheidung 14: Vorgabe UTC+3 im Sommer, UTC+2 im Winter).
enum Serverzeit: String, CaseIterable, Identifiable {
    case osteuropa = "Europe/Athens"
    case mitteleuropa = "Europe/Berlin"
    case london = "Europe/London"
    case utc = "UTC"
    case newYork = "America/New_York"

    static let vorgabe = Serverzeit.osteuropa

    var id: String { rawValue }
    var zeitzone: TimeZone { TimeZone(identifier: rawValue) ?? .gmt }

    var name: LocalizedStringKey {
        switch self {
        case .osteuropa: "UTC+2 Winter / UTC+3 Sommer (Vorgabe, viele MT4-Broker)"
        case .mitteleuropa: "UTC+1 / UTC+2 (Mitteleuropa)"
        case .london: "UTC+0 / UTC+1 (London)"
        case .utc: "UTC ohne Sommerzeit"
        case .newYork: "UTC−5 / UTC−4 (New York)"
        }
    }

    /// Ohne den MT4-Zusatz, für den XTB-Auszug (dort ist deutsche Ortszeit die Vorgabe, eine Annahme).
    var kurzname: LocalizedStringKey {
        switch self {
        case .osteuropa: "UTC+2 / UTC+3 (Osteuropa)"
        case .mitteleuropa: "UTC+1 / UTC+2 (Mitteleuropa, Vorgabe)"
        case .london: "UTC+0 / UTC+1 (London)"
        case .utc: "UTC ohne Sommerzeit"
        case .newYork: "UTC−5 / UTC−4 (New York)"
        }
    }
}

/// Gelesene Datei vor dem Speichern: Grundlage des Import-Blatts.
struct ImportVorschau: Identifiable {
    let id = UUID()
    let daten: Data
    let dateiname: String
}

/// Importer, die noch gegen keine echte Datei liefen, nur gegen öffentliche Beispiele (Stand-Doc 16,
/// Entscheidung 01.10.2026): Die App kennzeichnet sie als „ungeprüft“, bis eine echte Datei durchlief.
enum Importer {
    static let ungeprueft: Set<String> = [Journal.tradeRepublicImporter, Journal.scalableImporter, Journal.xtbImporter]
    /// Broker-Name der XTB-Konten, wie `Journal.importiereXTB` ihn speichert.
    static let xtbBroker = "XTB"

    static func istUngeprueft(_ name: String) -> Bool { ungeprueft.contains(name) }
}

/// Broker, deren Transaktionsexport (CSV) die App liest. Namen wie in `Konto.broker` der Speicherung.
enum CSVBroker {
    case tradeRepublic, scalable

    var name: String {
        switch self {
        case .tradeRepublic: "Trade Republic"
        case .scalable: "Scalable Capital"
        }
    }

    /// Zeitzone der Zeiten in der Datei (Stand-Doc 16): Trade Republic schreibt UTC, Scalable deutsche Ortszeit.
    var zeitzone: TimeZone {
        switch self {
        case .tradeRepublic: .gmt
        case .scalable: TimeZone(identifier: "Europe/Berlin") ?? .current
        }
    }

    var zeitzoneText: LocalizedStringKey {
        switch self {
        case .tradeRepublic: "UTC laut Datei; die App zeigt deine Zeitzone"
        case .scalable: "Deutsche Ortszeit laut Datei"
        }
    }
}

/// Was die App in der gewählten Datei erkannt hat. Erkannt wird am Inhalt, nicht am Dateinamen.
enum ErkannteDatei {
    case mt4(MT4Statement)
    case csv(CSVBroker, Kontobewegungen)
    case xtb(XTBAuszug)
}

/// Import (Doc 10, Abschnitt 7): Liste der bisherigen Importe, „Datei wählen“ öffnet das Blatt mit Prüfung.
struct ImportView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var dateiWaehlen = false
    @State private var vorschau: ImportVorschau?
    @State private var lesefehler: String?

    /// Dateitypen im Öffnen-Dialog: HTML (MetaTrader 4), CSV (Trade Republic, Scalable), XLSX (XTB).
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
            if modell.importe.isEmpty {
                ContentUnavailableView("Noch kein Import", systemImage: "square.and.arrow.down",
                                       description: Text("Wähle einen Kontoauszug: MetaTrader 4 (HTML, GBE und andere Broker), den Transaktionsexport von Trade Republic oder Scalable Capital (CSV) oder die Kontohistorie von XTB (Excel aus xStation 5)."))
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
    @State private var waehrung = "EUR"
    @State private var erkannt: ErkannteDatei?
    @State private var kontowahl: Kontowahl?
    @State private var neuerKontoname = ""
    @State private var lesefehler: String?
    @State private var ergebnis: ImportErgebnis?
    @State private var speicherfehler: String?

    private static let waehrungen = ["EUR", "USD", "GBP", "CHF"]

    /// Konto für einen Export ohne Kontonummer: ein bestehendes des Brokers oder ein neues mit Bezeichnung.
    private enum Kontowahl: Hashable {
        case bestehend(Int64)
        case neu
    }

    private struct Pruefung: Identifiable {
        let id: String
        let lautAuszug: Decimal
        let berechnet: Decimal
        var stimmt: Bool { lautAuszug == berechnet }
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
                    case nil:
                        if let lesefehler {
                            Label(lesefehler, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(thema.verlust)
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
                    Button(knopfText) { speichere() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!importierbar)
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

        Text(verbatim: erkennungMT4(auszug))
            .font(Schrift.fliesstext)
            .foregroundStyle(thema.textSchwach)

        HStack(spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Trades", wert: "\(auszug.closedPositions.count)")
            Kachel(titel: "Pending gelöscht", wert: "\(auszug.cancelledOrders.count)")
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
            ForEach(pruefungen(auszug)) { pruefung in
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
                Text("Im Export steht nur der letzte Stop-Loss. Ohne Stop kein R; der Trade wird markiert. Stop nachtragen kommt mit dem Journal-Paket.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            .padding(Abstand.kachelInnen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
        }

        claudeSatz
    }

    // MARK: Trade Republic und Scalable (CSV)

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
        let einAus = bewegungen.geldbewegungen.filter { $0.art == .einzahlung || $0.art == .auszahlung }
            .map { $0.betrag + $0.gebuehr + $0.steuer }.reduce(Decimal(0), +)

        HStack(spacing: Abstand.raster * 2) {
            Text(verbatim: erkennungCSV(broker, bewegungen))
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.textSchwach)
            Kapsel(text: String(localized: "ungeprüft"), betont: true)
        }
        Text("Dieser Importer lief noch gegen keine echte Datei, nur gegen öffentliche Beispiele. Prüfe nach dem Import Stückzahlen und Beträge gegen die App deines Brokers.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)

        HStack(spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Ausführungen", wert: "\(bewegungen.ausfuehrungen.count)",
                   zusatz: String(localized: "\(kaeufe) Käufe, \(verkaeufe) Verkäufe"))
            Kachel(titel: "Trades", wert: "\(bildung.trades.count)",
                   zusatz: String(localized: "nach FIFO, nur diese Datei"))
            Kachel(titel: "Ein-/Auszahlungen", wert: Format.betrag(einAus, anzeigeWaehrung),
                   zusatz: String(localized: "\(bewegungen.geldbewegungen.count) Geldbewegungen gesamt"))
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
                Text("Gebühr und Steuer je Vorgang aus dem Export; im Trade anteilig aus seinen Käufen").foregroundStyle(thema.text)
            }
        }
        Text("Die Datei nennt kein Konto. Wähle bei jedem Export dieses Depots dasselbe Konto, sonst zählt die App Vorgänge doppelt.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)

        Text("Prüfung")
            .font(.headline)
            .foregroundStyle(thema.text)
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Kassenwirkung der Datei").foregroundStyle(thema.text)
                Text(verbatim: Format.betrag(bewegungen.kassenwirkung, anzeigeWaehrung))
                    .font(Schrift.tabelle)
                    .gridColumnAlignment(.trailing)
                Text("Summe aller Zeilen; der Export nennt keinen Saldo zum Gegenprüfen")
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
        let summenpruefung = xtbPruefungen(auszug)

        HStack(spacing: Abstand.raster * 2) {
            Text(verbatim: erkennungXTB(auszug))
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
                        Text(verbatim: "\(Importer.xtbBroker) · \(String(localized: "Konto")) \(maskiert(nummer)) (\(String(localized: "neu")))")
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

    /// Kontonummer aus dem Kopf der Datei, sonst die eingegebene.
    private func xtbNummer(_ auszug: XTBAuszug) -> String {
        auszug.konto ?? xtbKontonummer.trimmingCharacters(in: .whitespaces)
    }

    private func maskiert(_ nummer: String) -> String {
        "••••" + String(nummer.suffix(4))
    }

    private func erkennungXTB(_ auszug: XTBAuszug) -> String {
        let zeiten = auszug.positionen.map(\.closeTime) + auszug.kasse.geldbewegungen.map(\.zeit)
        var text = String(localized: "Erkannt: XTB Kontohistorie (Excel)")
        if let konto = auszug.konto {
            text += " · " + String(localized: "Konto \(maskiert(konto))")
        }
        if let von = zeiten.min(), let bis = zeiten.max() {
            text += " · " + String(localized: "\(Format.datum(von)) bis \(Format.datum(bis))")
        }
        return text
    }

    /// Summenzeilen „Total“ der Datei gegen die gelesenen Zeilen, wie die Speicherung sie prüft.
    private func xtbPruefungen(_ auszug: XTBAuszug) -> [Pruefung] {
        var liste: [Pruefung] = []
        if let summe = auszug.positionenLautSumme {
            let p = auszug.positionen
            liste.append(Pruefung(id: String(localized: "Kommission gesamt"), lautAuszug: summe.commission,
                                  berechnet: p.reduce(Decimal(0)) { $0 + $1.commission }))
            liste.append(Pruefung(id: String(localized: "Swap gesamt"), lautAuszug: summe.swap,
                                  berechnet: p.reduce(Decimal(0)) { $0 + $1.swap }))
            liste.append(Pruefung(id: String(localized: "Ergebnis gesamt (Gross P/L)"), lautAuszug: summe.profit,
                                  berechnet: p.reduce(Decimal(0)) { $0 + $1.profit }))
        }
        if let kasse = auszug.kasseLautSumme {
            liste.append(Pruefung(id: String(localized: "Kasse gesamt"), lautAuszug: kasse, berechnet: auszug.kassenwirkung))
        }
        return liste
    }

    private var claudeSatz: some View {
        Text("Später an Claude gehen: Zeiten, Instrument, Richtung, Lots, Kurse, Kosten, Ergebnis, Journal. Nicht: Kontonummer, Name, Saldo.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    // MARK: Zustand

    private var knopfText: String {
        switch erkannt {
        case .mt4(let auszug)?: String(localized: "\(auszug.closedPositions.count) Trades importieren")
        case .csv(_, let bewegungen)?: String(localized: "\(bewegungen.ausfuehrungen.count) Ausführungen importieren")
        case .xtb(let auszug)?: String(localized: "\(auszug.positionen.count) Trades importieren")
        case nil: String(localized: "Importieren")
        }
    }

    private var importierbar: Bool {
        switch erkannt {
        case .mt4(let auszug)?:
            auszug.pruefe().isEmpty
        case .csv(_, let bewegungen)?:
            (bewegungen.ausfuehrungen.count + bewegungen.geldbewegungen.count + bewegungen.kapitalmassnahmen.count) > 0
                && kontoGueltig
        case .xtb(let auszug)?:
            (auszug.positionen.count + auszug.kasse.geldbewegungen.count) > 0
                && !xtbNummer(auszug).isEmpty && xtbPruefungen(auszug).allSatisfy(\.stimmt)
        case nil:
            false
        }
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

    private func erkennungMT4(_ auszug: MT4Statement) -> String {
        let art = auszug.kind == .daily ? String(localized: "Tagesauszug") : String(localized: "Monatsauszug")
        let nummer = "••••" + String(auszug.accountNumber.suffix(4))
        return String(localized: "Erkannt: MetaTrader 4 \(art) · \(auszug.broker) · Konto \(nummer) · Stichtag \(Format.datum(auszug.reportTime))")
    }

    private func erkennungCSV(_ broker: CSVBroker, _ bewegungen: Kontobewegungen) -> String {
        let zeiten = bewegungen.ausfuehrungen.map(\.zeit) + bewegungen.geldbewegungen.map(\.zeit)
            + bewegungen.kapitalmassnahmen.map(\.zeit)
        var text = String(localized: "Erkannt: \(broker.name) Transaktionsexport (CSV)")
        if let von = zeiten.min(), let bis = zeiten.max() {
            text += " · " + String(localized: "\(Format.datum(von)) bis \(Format.datum(bis))")
        }
        return text
    }

    private func pruefungen(_ auszug: MT4Statement) -> [Pruefung] {
        var liste = [
            Pruefung(id: String(localized: "Closed Trade P/L"),
                     lautAuszug: auszug.closedTradePL,
                     berechnet: auszug.closedPositions.reduce(Decimal(0)) { $0 + $1.netProfit }),
            Pruefung(id: String(localized: "Kommission gesamt"),
                     lautAuszug: auszug.closedTotals.commission,
                     berechnet: auszug.closedPositions.reduce(Decimal(0)) { $0 + $1.commission }),
        ]
        if let vortag = auszug.summary.previousBalance {
            liste.append(Pruefung(id: String(localized: "Kontostand"),
                                  lautAuszug: auszug.summary.balance,
                                  berechnet: vortag + auszug.summary.closedTradePL + auszug.summary.depositWithdrawal))
        }
        return liste
    }

    /// Erkennt das Format am Inhalt: erst XTB (Excel), dann die CSV-Köpfe von Trade Republic und Scalable,
    /// sonst MetaTrader 4 (HTML).
    private func lies() {
        erkannt = nil
        lesefehler = nil
        do {
            if XTBAuszug.erkennt(vorschau.daten) {
                let auszug = try XTBAuszug.lies(vorschau.daten, zeitzone: xtbZeit.zeitzone)
                erkannt = .xtb(auszug)
            } else if vorschau.dateiname.lowercased().hasSuffix(".xlsx") {
                lesefehler = String(localized: "Excel-Datei ohne Blatt „Closed Position History“: kein XTB-Kontoauszug aus xStation 5.")
            } else if let text = String(data: vorschau.daten, encoding: .utf8) {
                if TradeRepublicCSV.erkennt(text) {
                    let bewegungen = try TradeRepublicCSV.lies(text)
                    erkannt = .csv(.tradeRepublic, bewegungen)
                } else if ScalableCSV.erkennt(text) {
                    let bewegungen = try ScalableCSV.lies(text, zeitzone: CSVBroker.scalable.zeitzone)
                    erkannt = .csv(.scalable, bewegungen)
                } else {
                    let auszug = try MT4Statement.parse(html: text, serverZeitzone: serverzeit.zeitzone)
                    erkannt = .mt4(auszug)
                }
            } else {
                lesefehler = String(localized: "Die Datei ist weder Text (UTF-8) noch eine Excel-Datei.")
            }
        } catch MT4ImportFehler.keinMT4Auszug {
            lesefehler = String(localized: "Format nicht erkannt: kein MetaTrader-4-Auszug (HTML), kein Transaktionsexport von Trade Republic oder Scalable (CSV) und keine XTB-Kontohistorie (Excel).")
        } catch {
            lesefehler = fehlertext(error)
        }
        if case .csv(let broker, _)? = erkannt, kontowahl == nil {
            // Vorgabe: das erste Konto dieses Brokers, sonst ein neues namens „Depot“.
            kontowahl = modell.konten(broker: broker.name).first.flatMap(\.id).map(Kontowahl.bestehend) ?? .neu
            if neuerKontoname.isEmpty { neuerKontoname = String(localized: "Depot") }
        }
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
                                                    waehrung: konto?.waehrung ?? waehrung, zeitzone: broker.zeitzone)
            case .xtb(let auszug)?:
                // Nummer und Währung nur mitgeben, wenn die Datei sie nicht nennt; sonst prüft die
                // Speicherung Datei gegen Angabe und bricht bei Widerspruch ab.
                let nummer = xtbNummer(auszug)
                let bestehend = modell.bekanntesKonto(broker: Importer.xtbBroker, kontonummer: nummer)
                ergebnis = try modell.importiereXTB(daten: vorschau.daten, dateiname: vorschau.dateiname,
                                                    kontonummer: auszug.konto == nil ? nummer : nil,
                                                    kontoname: bestehend?.kontoname ?? String(localized: "Konto \(maskiert(nummer))"),
                                                    waehrung: auszug.waehrung == nil ? (bestehend?.waehrung ?? waehrung) : nil,
                                                    zeitzone: xtbZeit.zeitzone)
            case nil:
                return
            }
            speicherfehler = nil
        } catch {
            speicherfehler = fehlertext(error)
        }
    }

    private func ergebnisText(_ ergebnis: ImportErgebnis) -> String {
        switch ergebnis.status {
        case .dateiBereitsImportiert:
            return String(localized: "Genau diese Datei war schon importiert. Nichts geändert.")
        case .gespeichert:
            if case .csv(_, _)? = erkannt {
                let z = ergebnis.csv
                return String(localized: "Gespeichert: \(z.ausfuehrungenNeu) neue Ausführungen (\(z.ausfuehrungenBekannt) bekannt), \(z.geldbewegungenNeu) Geldbewegungen, \(z.kapitalmassnahmenNeu) Kapitalmaßnahmen, \(z.verworfen) verworfen, \(z.hinweise) Hinweise.")
            }
            if case .xtb? = erkannt {
                let z = ergebnis.csv
                return String(localized: "Gespeichert: \(ergebnis.geschlosseneNeu) neue Trades, \(ergebnis.geschlosseneBekannt) schon bekannt, \(z.geldbewegungenNeu) Kassenoperationen (\(z.geldbewegungenBekannt) bekannt), \(z.hinweise) Hinweise.")
            }
            return String(localized: "Gespeichert: \(ergebnis.geschlosseneNeu) neue Trades, \(ergebnis.geschlosseneBekannt) schon bekannt, \(ergebnis.geloeschteNeu) gelöschte Orders.")
        }
    }

    private func fehlertext(_ error: any Error) -> String {
        if let fehler = error as? SpeicherFehler {
            switch fehler {
            case .keinText:
                return String(localized: "Die Datei ist kein Text (UTF-8).")
            case .auszugWidersprichtSeinenSummen(let liste):
                return String(localized: "Der Auszug widerspricht seinen eigenen Summen: \(liste.joined(separator: ", "))")
            case .andereKontowaehrung(let gespeichert, let angegeben):
                return String(localized: "Das Konto ist mit \(gespeichert) angelegt, nicht mit \(angegeben).")
            case .abweichenderDatensatz(let tickets):
                return String(localized: "Vorgänge mit anderen Werten als beim früheren Import: \(tickets.joined(separator: ", "))")
            case .unbekannterWert(let wert):
                return String(localized: "Unbekannter Wert in der Datenbank: \(wert)")
            case .ungueltigerWert(let wert):
                return String(localized: "Eingabe außerhalb des erlaubten Bereichs: \(wert)")
            }
        }
        if let fehler = error as? CSVImportFehler {
            switch fehler {
            case .unbekanntesFormat(let kopf):
                return String(localized: "CSV-Format nicht erkannt. Spalten der Datei: \(kopf.prefix(6).joined(separator: ", "))")
            case .fehlendeSpalte(let name):
                return String(localized: "Spalte fehlt in der Datei: \(name)")
            case .ungueltigeZahl(let zeile, let text):
                return String(localized: "Ungültige Zahl in Zeile \(zeile): \(text)")
            case .ungueltigeZeit(let zeile, let text):
                return String(localized: "Ungültige Zeit in Zeile \(zeile): \(text)")
            }
        }
        if let fehler = error as? XLSXFehler {
            switch fehler {
            case .keineXLSX:
                return String(localized: "Die Datei ist kein Excel-Archiv (XLSX).")
            case .fehlenderTeil(let name):
                return String(localized: "Die Excel-Datei ist unvollständig, es fehlt: \(name)")
            case .fehlendesBlatt(let name):
                return String(localized: "Blatt fehlt in der Excel-Datei: \(name)")
            }
        }
        if let fehler = error as? MT4ImportFehler {
            switch fehler {
            case .keinMT4Auszug:
                return String(localized: "Kein MetaTrader-4-Auszug: weder „Daily Confirmation“ noch „Monthly Statement“ im Titel.")
            case .unbekannteZeile(let abschnitt, let ticket, _):
                return String(localized: "Unbekannte Zeile im Abschnitt \(abschnitt), Ticket \(ticket).")
            case .unerwarteteSpalten(let abschnitt, let gefunden):
                return String(localized: "Unerwartete Spalten im Abschnitt \(abschnitt): \(gefunden.joined(separator: ", "))")
            case .ungueltigeZahl(let text):
                return String(localized: "Ungültige Zahl: \(text)")
            case .ungueltigeZeit(let text):
                return String(localized: "Ungültige Zeit: \(text)")
            case .unbekannteAuftragsart(let text):
                return String(localized: "Unbekannte Auftragsart: \(text)")
            case .fehlenderWert(let name):
                return String(localized: "Fehlender Wert: \(name)")
            }
        }
        return error.localizedDescription
    }
}
