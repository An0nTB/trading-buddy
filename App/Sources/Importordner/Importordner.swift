#if os(macOS)
import AppKit
import Foundation
import TradingCore
import TradingStore

/// Import-Ordner beobachten (Frage 6, Tim 02.10.2026, Doc 45): Neue Broker-Auszüge in einem gewählten Ordner
/// importiert die App selbst, wenn nichts zu wählen bleibt (`Importordnerregel`); sonst landet die Datei in der
/// Liste „Wartet auf dich“ der Import-Seite. Standard aus. Dateien bleiben liegen; die App merkt sich nur,
/// welche sie erledigt hat (Name, Größe, Änderungszeit). Beobachtet wird mit einer Dispatch-Quelle auf dem
/// Ordner, ohne Abfrage im Takt; zusätzlich beim Einschalten, nach der Ordnerwahl und wenn die App nach vorn kommt.
@Observable @MainActor
final class Importordner {
    /// Die eine Beobachtung der App; `AppModell` verbindet sie beim Start (Patch Importordner_einhaengen).
    static let geteilt = Importordner()

    static let schluesselAktiv = "importOrdnerAktiv"
    static let schluesselLesezeichen = "importOrdnerLesezeichen"
    static let schluesselErledigt = "importOrdnerErledigt"
    /// Größere Dateien sind kein Kontoauszug; die App liest sie nicht ein.
    static let hoechstgroesse = 50 * 1024 * 1024
    /// So lange nach der letzten Änderung wartet die App, damit eine Datei fertig geschrieben ist.
    static let ruhezeit: TimeInterval = 3

    /// Eine Datei, zu der die App nachfragt.
    struct Rueckfrage: Identifiable, Equatable {
        /// Signatur aus Name, Größe und Änderungszeit.
        let id: String
        let dateiname: String
        let url: URL
        let grund: String
    }

    /// Ein stiller Import in dieser Sitzung, für die Zeile „Zuletzt“ auf der Import-Seite.
    struct Meldung: Identifiable, Equatable {
        let id = UUID()
        let dateiname: String
        let text: String
        let zeit: Date
    }

    private(set) var rueckfragen: [Rueckfrage] = []
    private(set) var zuletzt: [Meldung] = []
    /// Zustand für die Einstellungen, etwa „Ordner nicht erreichbar“.
    private(set) var stand = ""
    private(set) var aktiv: Bool

    @ObservationIgnored private let speicher: UserDefaults
    @ObservationIgnored private weak var modell: AppModell?
    @ObservationIgnored private var ordner: URL?
    @ObservationIgnored private var quelle: DispatchSourceFileSystemObject?
    @ObservationIgnored private var nachlauf: Task<Void, Never>?
    @ObservationIgnored private var vordergrund: NSObjectProtocol?

    init(speicher: UserDefaults = .standard) {
        self.speicher = speicher
        aktiv = speicher.bool(forKey: Self.schluesselAktiv)
    }

    /// Beim Start der App (AppModell, nur mit Nebenwirkungen): beobachtet, falls eingeschaltet.
    func verbinde(_ modell: AppModell) {
        self.modell = modell
        if vordergrund == nil {
            vordergrund = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.pruefe() }
            }
        }
        starte()
    }

    func setzeAktiv(_ an: Bool) {
        aktiv = an
        speicher.set(an, forKey: Self.schluesselAktiv)
        starte()
    }

    /// Merkt sich den Ordner aus dem Auswahldialog als Security-scoped Bookmark und beobachtet ihn.
    func waehle(_ url: URL) throws {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        let daten = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        speicher.set(daten, forKey: Self.schluesselLesezeichen)
        starte()
    }

    /// Pfad des gewählten Ordners für die Einstellungen.
    var ordnerPfad: String? { gemerkterOrdner()?.path }

    /// Die Datei soll nicht importiert werden: erledigt, bis sie sich ändert.
    func ignoriere(_ rueckfrage: Rueckfrage) {
        merkeErledigt(rueckfrage.id)
        rueckfragen.removeAll { $0.id == rueckfrage.id }
    }

    /// Inhalt für das Import-Blatt. Nach dem Blatt prüft die App den Ordner neu: War die Datei gespeichert,
    /// meldet die Speicherung sie als schon importiert und sie verschwindet aus der Liste.
    func vorschau(_ rueckfrage: Rueckfrage) -> ImportVorschau? {
        guard let daten = try? Data(contentsOf: rueckfrage.url) else { return nil }
        return ImportVorschau(daten: daten, dateiname: rueckfrage.dateiname)
    }

    // MARK: Beobachtung

    private func gemerkterOrdner() -> URL? {
        guard let daten = speicher.data(forKey: Self.schluesselLesezeichen) else { return nil }
        var veraltet = false
        guard let url = try? URL(resolvingBookmarkData: daten, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &veraltet)
        else { return nil }
        if veraltet { try? waehleOhneStart(url) }
        return url
    }

    private func waehleOhneStart(_ url: URL) throws {
        let daten = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        speicher.set(daten, forKey: Self.schluesselLesezeichen)
    }

    /// Hält die laufende Beobachtung an und startet sie neu, wenn eingeschaltet und ein Ordner gewählt ist.
    private func starte() {
        halteAn()
        guard aktiv else {
            stand = ""
            rueckfragen = []
            return
        }
        guard let url = gemerkterOrdner() else {
            stand = speicher.data(forKey: Self.schluesselLesezeichen) == nil
                ? String(localized: "Noch kein Ordner gewählt.")
                : String(localized: "Ordner nicht erreichbar, bitte neu wählen.")
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            stand = String(localized: "Kein Zugriff auf den Ordner, bitte neu wählen.")
            return
        }
        ordner = url
        let deskriptor = open(url.path, O_EVTONLY)
        if deskriptor >= 0 {
            let neu = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: deskriptor, eventMask: [.write, .rename, .delete], queue: .main)
            neu.setEventHandler { [weak self] in
                Task { @MainActor in self?.geaendert() }
            }
            neu.setCancelHandler { close(deskriptor) }
            neu.resume()
            quelle = neu
        }
        stand = String(localized: "Beobachtet \(url.path)")
        pruefe()
    }

    private func halteAn() {
        quelle?.cancel()
        quelle = nil
        nachlauf?.cancel()
        nachlauf = nil
        ordner?.stopAccessingSecurityScopedResource()
        ordner = nil
    }

    /// Ordnerinhalt hat sich geändert. Kurz warten, weil Browser und Finder in mehreren Schritten schreiben.
    private func geaendert() {
        if let ordner, !FileManager.default.fileExists(atPath: ordner.path) {
            halteAn()
            stand = String(localized: "Ordner nicht erreichbar, bitte neu wählen.")
            return
        }
        pruefeSpaeter()
    }

    private func pruefeSpaeter() {
        nachlauf?.cancel()
        nachlauf = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.ruhezeit))
            guard !Task.isCancelled else { return }
            self?.pruefe()
        }
    }

    // MARK: Prüfung

    /// Geht alle Dateien des Ordners durch, die noch nicht erledigt sind.
    func pruefe(jetzt: Date = .now) {
        guard aktiv, let ordner, let modell, let journal = modell.journal else { return }
        let schluessel: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let dateien = (try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: schluessel,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        var erledigt = erledigteSignaturen()
        let bekannteHashes = Set(modell.importe.map(\.lauf.dateiHash))
        var offen: [Rueckfrage] = []
        var importiert = false
        var unfertig = false
        for url in dateien.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard Importordnerregel.kommtInFrage(name),
                  let werte = try? url.resourceValues(forKeys: Set(schluessel)),
                  werte.isRegularFile == true, let groesse = werte.fileSize, groesse > 0,
                  let geaendert = werte.contentModificationDate
            else { continue }
            let signatur = "\(name)|\(groesse)|\(Int(geaendert.timeIntervalSince1970))"
            guard erledigt[signatur] == nil else { continue }
            guard jetzt.timeIntervalSince(geaendert) >= Self.ruhezeit else {
                unfertig = true
                continue
            }
            func frage(_ grund: String) {
                offen.append(Rueckfrage(id: signatur, dateiname: name, url: url, grund: grund))
            }
            guard groesse <= Self.hoechstgroesse else {
                frage(String(localized: "Datei zu groß für einen Kontoauszug."))
                continue
            }
            guard let daten = try? Data(contentsOf: url) else {
                frage(String(localized: "Datei nicht lesbar."))
                continue
            }
            // Schon gespeichert, etwa über „Prüfen“ im Blatt: erledigt, auch wenn das Konto mehrdeutig ist.
            if bekannteHashes.contains(Journal.fingerabdruck(daten)) {
                erledigt[signatur] = jetzt.timeIntervalSince1970
                continue
            }
            let entscheidung = Importordnerregel.entscheide(daten: daten, dateiname: name, konten: modell.konten,
                                                            zeitzone: { Self.letzteZeitzone($0, importe: modell.importe) })
            do {
                guard let ergebnis = try Self.importiere(entscheidung, daten: daten, dateiname: name, journal: journal)
                else {
                    if case .rueckfrage(let grund) = entscheidung { frage(grund) }
                    continue
                }
                erledigt[signatur] = jetzt.timeIntervalSince1970
                importiert = importiert || ergebnis.status == .gespeichert
                melde(name, Self.text(ergebnis), jetzt: jetzt)
            } catch {
                // Widerspruch zu den Summen, andere Kontowährung, abweichender Datensatz: das Blatt zeigt Einzelheiten.
                frage(String(localized: "Import abgebrochen: bitte im Blatt prüfen."))
            }
        }
        speichere(erledigt)
        rueckfragen = offen
        if importiert {
            modell.laden()
            modell.exportiere()
        }
        if unfertig { pruefeSpaeter() }
    }

    /// Speichert still; `nil` bei einer Rückfrage.
    static func importiere(_ entscheidung: Importordnerregel.Entscheidung, daten: Data, dateiname: String,
                           journal: Journal) throws -> ImportErgebnis? {
        switch entscheidung {
        case .mt4(let konto, let zone):
            return try journal.importiereMT4(datei: daten, dateiname: dateiname, serverZeitzone: zone,
                                             kontowaehrung: konto.waehrung)
        case .csv(let broker, let konto):
            return try journal.importiereCSV(datei: daten, dateiname: dateiname, kontonummer: konto.kontonummer,
                                             kontoname: konto.kontoname, kontowaehrung: konto.waehrung,
                                             zeitzone: broker.zeitzone)
        case .xtb(_, let zone):
            // Kontonummer und Währung stehen in der Datei; die Speicherung prüft sie gegen das Konto.
            return try journal.importiereXTB(datei: daten, dateiname: dateiname, zeitzone: zone)
        case .rueckfrage:
            return nil
        }
    }

    /// Zeitzone des jüngsten Imports dieses Kontos.
    static func letzteZeitzone(_ konto: Konto, importe: [ImportEintrag]) -> TimeZone? {
        importe.filter { $0.konto.id == konto.id }
            .max { $0.lauf.importiertAm < $1.lauf.importiertAm }
            .flatMap { TimeZone(identifier: $0.lauf.serverZeitzone) }
    }

    private static func text(_ ergebnis: ImportErgebnis) -> String {
        switch ergebnis.status {
        case .dateiBereitsImportiert:
            return String(localized: "schon importiert, nichts geändert")
        case .gespeichert:
            if ergebnis.csv.ausfuehrungenNeu + ergebnis.csv.ausfuehrungenBekannt > 0 {
                return String(localized: "\(ergebnis.csv.ausfuehrungenNeu) neue Ausführungen")
            }
            return String(localized: "\(ergebnis.geschlosseneNeu) neue Trades")
        }
    }

    private func melde(_ dateiname: String, _ text: String, jetzt: Date) {
        zuletzt.insert(Meldung(dateiname: dateiname, text: text, zeit: jetzt), at: 0)
        zuletzt = Array(zuletzt.prefix(5))
    }

    // MARK: Erledigte Dateien

    private func erledigteSignaturen() -> [String: Double] {
        speicher.dictionary(forKey: Self.schluesselErledigt) as? [String: Double] ?? [:]
    }

    /// Hebt höchstens 1000 Einträge auf, die jüngsten.
    private func speichere(_ erledigt: [String: Double]) {
        let behalten = erledigt.count > 1000
            ? Dictionary(uniqueKeysWithValues: erledigt.sorted { $0.value > $1.value }.prefix(1000).map { ($0.key, $0.value) })
            : erledigt
        speicher.set(behalten, forKey: Self.schluesselErledigt)
    }

    private func merkeErledigt(_ signatur: String) {
        var erledigt = erledigteSignaturen()
        erledigt[signatur] = Date.now.timeIntervalSince1970
        speichere(erledigt)
    }
}

extension Importordner {
    /// Nur für Tests: beobachtet `url` ohne Bookmark und ohne Dispatch-Quelle.
    func pruefeTestweise(_ url: URL, modell: AppModell, jetzt: Date) {
        self.modell = modell
        ordner = url
        aktiv = true
        pruefe(jetzt: jetzt)
    }
}
#endif
