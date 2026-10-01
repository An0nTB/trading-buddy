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
}

/// Gelesene Datei vor dem Speichern: Grundlage des Import-Blatts.
struct ImportVorschau: Identifiable {
    let id = UUID()
    let daten: Data
    let dateiname: String
}

/// Import (Doc 10, Abschnitt 7): Liste der bisherigen Importe, „Datei wählen“ öffnet das Blatt mit Prüfung.
struct ImportView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var dateiWaehlen = false
    @State private var vorschau: ImportVorschau?
    @State private var lesefehler: String?

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
            if modell.importe.isEmpty {
                ContentUnavailableView("Noch kein Import", systemImage: "square.and.arrow.down",
                                       description: Text("Wähle einen Kontoauszug von GBE oder einem anderen MetaTrader-4-Broker (HTML, Daily Confirmation oder Monthly Statement)."))
            } else {
                List(modell.importe) { eintrag in
                    HStack {
                        VStack(alignment: .leading, spacing: Abstand.raster) {
                            Text(verbatim: eintrag.lauf.dateiname)
                                .foregroundStyle(thema.text)
                            Text(verbatim: "\(eintrag.konto.broker) · \(eintrag.konto.kontoname) · \(Importart.name(eintrag.lauf.art)) · \(String(localized: "Stichtag")) \(Format.datum(eintrag.lauf.stichtag))")
                                .font(Schrift.beschriftung)
                                .foregroundStyle(thema.textSchwach)
                        }
                        Spacer()
                        Text(verbatim: Format.datum(eintrag.lauf.importiertAm))
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                    .listRowBackground(thema.flaeche)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(Abstand.seitenrand)
        #if os(macOS)
        .fileImporter(isPresented: $dateiWaehlen, allowedContentTypes: [.html, .plainText]) { ergebnis in
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

/// Art eines Auszugs, wie `Importlauf.art` sie speichert.
enum Importart {
    static func name(_ art: String) -> String {
        switch art {
        case "daily": String(localized: "Tagesauszug")
        case "monthly": String(localized: "Monatsauszug")
        default: art
        }
    }
}

/// Import A, ein Blatt mit Prüfung (Doc 10, Abschnitt 7): Erkennung, vier Zahlen, Konto und Serverzeit,
/// Prüfung gegen den Auszug, Hinweis auf Trades ohne Stop. Der Knopf ist nur aktiv, wenn die Prüfung stimmt.
struct ImportBlatt: View {
    let vorschau: ImportVorschau
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var dismiss
    @State private var serverzeit = Serverzeit.vorgabe
    @State private var waehrung = "EUR"
    @State private var auszug: MT4Statement?
    @State private var lesefehler: String?
    @State private var ergebnis: ImportErgebnis?
    @State private var speicherfehler: String?

    private static let waehrungen = ["EUR", "USD", "GBP", "CHF"]

    private struct Pruefung: Identifiable {
        let id: String
        let lautAuszug: Decimal
        let berechnet: Decimal
        var stimmt: Bool { lautAuszug == berechnet }
    }

    var body: some View {
        let anzahl = auszug?.closedPositions.count ?? 0
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text(verbatim: vorschau.dateiname)
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
            if let auszug {
                inhalt(auszug)
            } else if let lesefehler {
                Label(lesefehler, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(thema.verlust)
            }
            Spacer(minLength: 0)
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
                    Button("\(anzahl) Trades importieren") { speichere() }
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
    }

    @ViewBuilder
    private func inhalt(_ auszug: MT4Statement) -> some View {
        let konto = modell.bekanntesKonto(broker: auszug.broker, kontonummer: auszug.accountNumber)
        let bekannt = modell.bekannteTickets(broker: auszug.broker, kontonummer: auszug.accountNumber)
        let dubletten = auszug.closedPositions.filter { bekannt.contains($0.ticket) }.count
        let ohneStop = auszug.closedPositions.filter { $0.stopLoss == nil }.count
        let abweichungen = auszug.pruefe()
        let anzeigeWaehrung = konto?.waehrung ?? waehrung

        Text(verbatim: erkennung(auszug))
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

        Text("Später an Claude gehen: Zeiten, Instrument, Richtung, Lots, Kurse, Kosten, Ergebnis, Journal. Nicht: Kontonummer, Name, Saldo.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private var importierbar: Bool {
        guard let auszug else { return false }
        return auszug.pruefe().isEmpty
    }

    private func erkennung(_ auszug: MT4Statement) -> String {
        let art = auszug.kind == .daily ? String(localized: "Tagesauszug") : String(localized: "Monatsauszug")
        let nummer = "••••" + String(auszug.accountNumber.suffix(4))
        return String(localized: "Erkannt: MetaTrader 4 \(art) · \(auszug.broker) · Konto \(nummer) · Stichtag \(Format.datum(auszug.reportTime))")
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

    private func lies() {
        guard let html = String(data: vorschau.daten, encoding: .utf8) else {
            auszug = nil
            lesefehler = String(localized: "Die Datei ist kein Text (UTF-8).")
            return
        }
        do {
            auszug = try MT4Statement.parse(html: html, serverZeitzone: serverzeit.zeitzone)
            lesefehler = nil
        } catch {
            auszug = nil
            lesefehler = fehlertext(error)
        }
    }

    private func speichere() {
        guard let auszug else { return }
        let kontowaehrung = modell.bekanntesKonto(broker: auszug.broker, kontonummer: auszug.accountNumber)?.waehrung ?? waehrung
        do {
            ergebnis = try modell.importiere(daten: vorschau.daten, dateiname: vorschau.dateiname,
                                             serverZeitzone: serverzeit.zeitzone, waehrung: kontowaehrung)
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
                return String(localized: "Tickets mit anderen Werten als beim früheren Import: \(tickets.joined(separator: ", "))")
            case .unbekannterWert(let wert):
                return String(localized: "Unbekannter Wert in der Datenbank: \(wert)")
            case .ungueltigerWert(let wert):
                return String(localized: "Eingabe außerhalb des erlaubten Bereichs: \(wert)")
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
