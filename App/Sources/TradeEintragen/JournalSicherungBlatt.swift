import SwiftUI
import TradingCore
import TradingStore

/// Weiche im Import: Eine Sicherung des Browser-Journals (`journal-sicherung-*.json`) bekommt ihr eigenes Blatt,
/// alles andere das Import-Blatt. Erkannt wird am Inhalt, nicht am Dateinamen.
struct ImportWeiche: View {
    let vorschau: ImportVorschau

    var body: some View {
        if JournalSicherung.erkennt(vorschau.daten) {
            JournalSicherungBlatt(vorschau: vorschau)
        } else {
            ImportBlatt(vorschau: vorschau)
        }
    }
}

/// Vorschau einer Journal-Sicherung ohne Ansicht: Zahlen für das Blatt, prüfbar in den App-Tests.
struct JournalSicherungVorschau: Equatable {
    /// Zeitzone der Datums- und Uhrzeitfelder: Das Journal lief im Browser in deutscher Ortszeit (Annahme, fest).
    static let zeitzone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    /// Vorgabe für den Kontonamen.
    static var kontoVorgabe: String { String(localized: "Browser-Journal") }

    let sicherung: JournalSicherung

    static func lies(_ daten: Data) throws -> JournalSicherungVorschau {
        JournalSicherungVorschau(sicherung: try JournalSicherung.lies(daten, zeitzone: zeitzone))
    }

    var trades: Int { sicherung.positionen.count }
    var offen: Int { sicherung.offen }
    /// Ergebnis nach Gebühren in Euro; das Journal kennt keine Gebühren, also das Kursergebnis.
    var netto: Decimal { sicherung.positionen.reduce(Decimal(0)) { $0 + $1.profit + $1.commission + $1.swap } }
    var gewinner: Int { sicherung.positionen.filter { $0.profit + $0.commission + $0.swap > 0 }.count }
    var mitRisiko: Int { sicherung.eintraege.filter { $0.risiko != nil }.count }
    var scheine: Int { sicherung.eintraege.filter(\.schein).count }

    /// Setups der Datei, die im Playbook noch fehlen (Groß- und Kleinschreibung zählt nicht).
    func neueSetups(playbook: [String]) -> [String] {
        let bekannt = Set(playbook.map { $0.lowercased() })
        let ausTrades = sicherung.eintraege.compactMap(\.setup)
        var gesehen = Set<String>()
        return (sicherung.setups + ausTrades).filter { name in
            let schluessel = name.lowercased()
            guard !bekannt.contains(schluessel), !gesehen.contains(schluessel) else { return false }
            gesehen.insert(schluessel)
            return true
        }
    }

    /// Erster und letzter Handelstag, `nil` ohne Trades.
    var zeitraum: (von: Date, bis: Date)? {
        let zeiten = sicherung.positionen.map(\.openTime)
        guard let von = zeiten.min(), let bis = zeiten.max() else { return nil }
        return (von, bis)
    }

    var erkennung: String {
        var text = String(localized: "Erkannt: Sicherung des Browser-Journals (JSON)")
        if let zeitraum {
            text += " · " + String(localized: "\(Format.datum(zeitraum.von)) bis \(Format.datum(zeitraum.bis))")
        }
        return text
    }

    var knopfText: String { String(localized: "\(trades) Trades importieren") }
}

/// Blatt für die Journal-Sicherung: Erkennung, Zahlen, Konto, Hinweise; der Knopf speichert in ein Euro-Konto.
struct JournalSicherungBlatt: View {
    let vorschau: ImportVorschau
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var dismiss
    @State private var gelesen: JournalSicherungVorschau?
    @State private var lesefehler: String?
    @State private var kontoname = JournalSicherungVorschau.kontoVorgabe
    @State private var ergebnis: ImportErgebnis?
    @State private var speicherfehler: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text(verbatim: vorschau.dateiname)
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
            ScrollView {
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    if let gelesen {
                        inhalt(gelesen)
                    } else if let lesefehler {
                        Label(lesefehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(thema.verlust)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            fusszeile
        }
        .padding(Abstand.seitenrand)
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 480)
        #endif
        .onAppear(perform: lies)
    }

    @ViewBuilder
    private func inhalt(_ gelesen: JournalSicherungVorschau) -> some View {
        Text(verbatim: gelesen.erkennung)
            .font(Schrift.fliesstext)
            .foregroundStyle(thema.text)
        zahlen(gelesen)
        TextField("Name des Kontos", text: $kontoname)
            .textFieldStyle(.roundedBorder)
        Text("Neues Konto in Euro: Das Journal rechnet nur in Euro. Gleicher Name beim nächsten Import, dann kommen nur neue Trades dazu.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        Text("Das Journal kennt keine Ausstiegszeit und keine Gebühren: Die Trades zählen nur mit Datum, Uhrzeit- und Haltedauer-Auswertungen lassen sie aus.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        let neue = gelesen.neueSetups(playbook: modell.playbook.map(\.name))
        if !neue.isEmpty {
            Text(verbatim: String(localized: "Neue Setups im Playbook: \(neue.joined(separator: ", "))"))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.text)
        }
        if !gelesen.sicherung.hinweise.isEmpty {
            DisclosureGroup(HinweisListe.anzahlText(gelesen.sicherung.hinweise.count)) {
                HinweisListe(hinweise: gelesen.sicherung.hinweise)
            }
        }
    }

    private func zahlen(_ gelesen: JournalSicherungVorschau) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            zeile("Geschlossene Trades", "\(gelesen.trades)")
            zeile("Offen, nicht übernommen", "\(gelesen.offen)")
            zeile("Davon Gewinner", "\(gelesen.gewinner)")
            zeile("Mit Risiko (ergibt R)", "\(gelesen.mitRisiko)")
            zeile("Scheine", "\(gelesen.scheine)")
            zeile("Ergebnis", Format.geld(gelesen.netto, "EUR"))
        }
        .font(Schrift.fliesstext)
    }

    private func zeile(_ titel: LocalizedStringKey, _ wert: String) -> some View {
        GridRow {
            Text(titel)
                .foregroundStyle(thema.textSchwach)
            Text(verbatim: wert)
                .font(Schrift.tabelle)
                .foregroundStyle(thema.text)
        }
    }

    private var fusszeile: some View {
        HStack(spacing: Abstand.kachelAbstand) {
            if let ergebnis {
                Text(verbatim: Self.ergebnisText(ergebnis))
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
                Button(gelesen?.knopfText ?? String(localized: "Importieren")) { speichere() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!importierbar)
            } else {
                Button("Fertig") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var importierbar: Bool {
        guard let gelesen else { return false }
        return gelesen.trades > 0 && !kontoname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func ergebnisText(_ ergebnis: ImportErgebnis) -> String {
        switch ergebnis.status {
        case .dateiBereitsImportiert:
            return Ton.aktuell.text("Genau diese Datei war schon importiert. Nichts geändert.",
                                    henry: "Diese Datei lag bereits vor. Nichts geändert.")
        case .gespeichert:
            let gespeichert = Ton.aktuell.text("Gespeichert:", henry: "Verbucht:")
            return String(localized: "\(gespeichert) \(ergebnis.geschlosseneNeu) neue Trades, \(ergebnis.geschlosseneBekannt) schon bekannt, \(ergebnis.journaleintraegeNeu) Journaleinträge, \(ergebnis.setupsNeu) neue Setups, \(ergebnis.ohneAusstieg) offen nicht übernommen.")
        }
    }

    private func lies() {
        guard gelesen == nil, lesefehler == nil else { return }
        do {
            gelesen = try JournalSicherungVorschau.lies(vorschau.daten)
        } catch {
            lesefehler = Self.lesefehlerText(error)
        }
    }

    static func lesefehlerText(_ error: any Error) -> String {
        switch error as? JournalSicherungFehler {
        case .keinJSON?: String(localized: "Die Datei ist kein gültiges JSON.")
        case .keineTradesListe?: String(localized: "JSON ohne Liste „trades“: keine Sicherung des Browser-Journals.")
        case nil: Importlesung.fehlertext(error)
        }
    }

    private func speichere() {
        speicherfehler = nil
        do {
            ergebnis = try modell.importiereJournalSicherung(
                daten: vorschau.daten, dateiname: vorschau.dateiname,
                kontoname: kontoname.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            speicherfehler = Self.lesefehlerText(error)
        }
    }
}
