import SwiftUI
import TradingCore
import UniformTypeIdentifiers

/// Eine gewählte Kursdatei aus dem MetaTrader-Verlaufszentrum, noch nicht gespeichert.
struct MT4Kursdatei: Identifiable {
    let id = UUID()
    let dateiname: String
    let text: String

    static let dateitypen: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]

    /// Liest die Datei als Text. MetaTrader 5 schreibt den Export als UTF-16 mit Byte-Order-Mark,
    /// MetaTrader 4 als ASCII (Einschätzung, an Tims Datei zu prüfen).
    static func lies(_ url: URL) throws -> MT4Kursdatei {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        let daten = try Data(contentsOf: url)
        let text: String?
        if daten.starts(with: [0xFF, 0xFE]) {
            text = String(data: daten, encoding: .utf16LittleEndian)
        } else if daten.starts(with: [0xFE, 0xFF]) {
            text = String(data: daten, encoding: .utf16BigEndian)
        } else {
            text = String(data: daten, encoding: .utf8) ?? String(data: daten, encoding: .isoLatin1)
        }
        guard let text else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return MT4Kursdatei(dateiname: url.lastPathComponent, text: text)
    }

    /// Symbol aus dem Dateinamen: MT4 `EURUSD1.csv` (Symbol plus Minuten), MT5 `EURUSD_M1_202501020000_….csv`.
    /// Passt ein Journal-Symbol genau oder ohne Endung des Brokers, gilt dieses.
    static func vermutetesSymbol(_ dateiname: String, journal: [String]) -> String? {
        let stamm = (dateiname as NSString).deletingPathExtension
        var kern = String(stamm.split(separator: "_").first ?? Substring(stamm))
        if journal.contains(kern) { return kern }
        while let letztes = kern.last, letztes.isNumber { kern.removeLast() }
        if journal.contains(kern) { return kern }
        let gross = kern.uppercased()
        return journal.first { $0.uppercased() == gross }
            ?? journal.first { !gross.isEmpty && $0.uppercased().hasPrefix(gross) }
            ?? (kern.isEmpty ? nil : kern)
    }
}

/// Blatt zum Import von Minutenkursen aus dem MetaTrader-Verlaufszentrum (Doc 39, Paket B3): Symbol zuordnen,
/// Serverzeit wählen wie beim Kontoauszug, Vorschau prüfen, übernehmen. Format nach Doku, noch nicht an einer
/// echten Datei geprüft.
struct MT4KursimportBlatt: View {
    let datei: MT4Kursdatei
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var dismiss
    /// Zuletzt gewählte Serverzeit; MT4-Auszug und Verlauf laufen in derselben Serverzeit.
    @AppStorage("ausstieg.serverzeit") private var serverzeitWert = Serverzeit.vorgabe.rawValue
    @State private var symbol = ""
    @State private var vorschau: Result<[Zeitkerze], MT4Kursimportfehler>?
    @State private var speichert = false
    @State private var speicherfehler: String?

    private var serverzeit: Binding<Serverzeit> {
        Binding(get: { Serverzeit(rawValue: serverzeitWert) ?? .vorgabe }, set: { serverzeitWert = $0.rawValue })
    }

    private var journalSymbole: [String] {
        Array(Set(modell.alleTrades.filter { !$0.nurDatum }.map(\.symbol))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text("Kurse für die Ausstiegsanalyse")
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
            HStack(spacing: Abstand.raster * 2) {
                Text(verbatim: datei.dateiname)
                    .foregroundStyle(thema.textSchwach)
                Kapsel(text: String(localized: "ungeprüft"))
            }
            einstellungen
            vorschauText
            Text("Die Kurse bleiben auf diesem Gerät unter Application Support. Ein erneuter Import desselben Zeitraums ersetzt die gespeicherten Kerzen.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            Spacer(minLength: 0)
            knoepfe
        }
        .padding(Abstand.seitenrand)
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 380)
        #endif
        .onAppear {
            if symbol.isEmpty {
                symbol = MT4Kursdatei.vermutetesSymbol(datei.dateiname, journal: journalSymbole) ?? ""
            }
        }
        .task(id: serverzeitWert) { await lies() }
    }

    private var einstellungen: some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                Text("Symbol im Journal").foregroundStyle(thema.textSchwach)
                HStack {
                    TextField("Symbol", text: $symbol)
                        .textFieldStyle(.roundedBorder)
                    if !journalSymbole.isEmpty {
                        Menu("Aus dem Journal") {
                            ForEach(journalSymbole, id: \.self) { s in
                                Button(s) { symbol = s }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
            GridRow {
                Text("Serverzeit der Datei").foregroundStyle(thema.textSchwach)
                Picker("Serverzeit", selection: serverzeit) {
                    ForEach(Serverzeit.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var vorschauText: some View {
        switch vorschau {
        case .success(let kerzen):
            if let erste = kerzen.first, let letzte = kerzen.last {
                VStack(alignment: .leading, spacing: Abstand.raster) {
                    Text("\(kerzen.count) Kerzen zu \(Ausstiegsformat.kerzenlaenge(erste.dauer)), \(Format.zeit(erste.beginn)) bis \(Format.zeit(letzte.ende)) in deiner Zeitzone")
                        .foregroundStyle(thema.text)
                    let trades = passendeTrades(von: erste.beginn, bis: letzte.ende)
                    Text("\(trades) Trades mit Uhrzeit zu diesem Symbol liegen in diesem Zeitraum.")
                        .foregroundStyle(trades > 0 ? thema.text : thema.textSchwach)
                }
            } else {
                Text("Die Datei enthält keine Kerzen.").foregroundStyle(thema.verlust)
            }
        case .failure(let fehler):
            Text(verbatim: fehler.text).foregroundStyle(thema.verlust)
        case nil:
            ProgressView()
        }
        if let speicherfehler {
            Text(verbatim: speicherfehler).foregroundStyle(thema.verlust)
        }
    }

    private var knoepfe: some View {
        HStack {
            Spacer()
            Button("Abbrechen") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Übernehmen") { Task { await uebernimm() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!bereit || speichert)
        }
    }

    private var bereit: Bool {
        guard case .success(let kerzen) = vorschau else { return false }
        return !kerzen.isEmpty && !symbol.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func passendeTrades(von: Date, bis: Date) -> Int {
        let s = symbol.trimmingCharacters(in: .whitespaces)
        return modell.alleTrades.filter { $0.symbol == s && !$0.nurDatum && $0.openTime < bis && $0.closeTime > von }.count
    }

    /// Liest die Datei abseits der Oberfläche; ein Monat Minutenkurse sind Zehntausende Zeilen.
    private func lies() async {
        vorschau = nil
        let zeitzone = (Serverzeit(rawValue: serverzeitWert) ?? .vorgabe).zeitzone
        let text = datei.text
        let ergebnis = await Task.detached { () -> Result<[Zeitkerze], MT4Kursimportfehler> in
            do {
                return .success(try MT4Verlauf.parse(text: text, serverZeitzone: zeitzone))
            } catch let fehler as MT4ImportFehler {
                return .failure(MT4Kursimportfehler(fehler))
            } catch {
                return .failure(MT4Kursimportfehler(text: error.localizedDescription))
            }
        }.value
        guard !Task.isCancelled else { return }
        vorschau = ergebnis
    }

    private func uebernimm() async {
        guard case .success(let kerzen) = vorschau else { return }
        speichert = true
        defer { speichert = false }
        do {
            try await Ausstiegsdienst.geteilt.uebernimm(kerzen, symbol: symbol.trimmingCharacters(in: .whitespaces),
                                                        quelle: "MT4")
            dismiss()
        } catch {
            speicherfehler = String(localized: "Speichern fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}

/// Lesefehler der Kursdatei als sachlicher Satz.
struct MT4Kursimportfehler: Error, Equatable, Sendable {
    let text: String

    init(text: String) {
        self.text = text
    }

    init(_ fehler: MT4ImportFehler) {
        switch fehler {
        case .unerwarteteSpalten(_, let gefunden):
            text = String(localized: "Unerwarteter Aufbau: Erwartet sind Datum, Uhrzeit, Eröffnung, Hoch, Tief, Schluss. Gefunden: \(gefunden.joined(separator: ", "))")
        case .ungueltigeZahl(let wert):
            text = String(localized: "Kein lesbarer Kurs: \(wert)")
        case .ungueltigeZeit(let wert):
            text = String(localized: "Keine lesbare Zeit: \(wert)")
        default:
            text = String(localized: "Die Datei ist kein Kursexport aus dem MetaTrader-Verlaufszentrum.")
        }
    }
}
