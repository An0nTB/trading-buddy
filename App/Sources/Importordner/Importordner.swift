#if os(macOS)
import AppKit
import Foundation
import TradingCore
import TradingStore
import UserNotifications

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
    /// JSON `[Signatur: Erledigt]`; der alte Schlüssel „importOrdnerErledigt“ (nur Zeitstempel) entfällt (G20).
    static let schluesselErledigt = "importOrdnerErledigt2"
    /// Mitteilung nach stillem Import (Paket A4); Standard an, in den Einstellungen abschaltbar.
    static let schluesselMitteilung = "importOrdnerMitteilung"
    /// Größere Dateien sind kein Kontoauszug; die App liest sie nicht ein.
    nonisolated static let hoechstgroesse = 50 * 1024 * 1024
    /// So lange nach der letzten Änderung wartet die App, damit eine Datei fertig geschrieben ist.
    static let ruhezeit: TimeInterval = 3

    /// Eine Datei, zu der die App nachfragt.
    struct Rueckfrage: Identifiable, Equatable, Sendable {
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
    private(set) var mitteilung: Bool

    @ObservationIgnored private let speicher: UserDefaults
    @ObservationIgnored private weak var modell: AppModell?
    @ObservationIgnored private var ordner: URL?
    @ObservationIgnored private var quelle: DispatchSourceFileSystemObject?
    @ObservationIgnored private var nachlauf: Task<Void, Never>?
    @ObservationIgnored private var vordergrund: NSObjectProtocol?
    /// Nur nach `verbinde` (die laufende App) gehen Mitteilungen raus, in Tests nicht.
    @ObservationIgnored private var mitteilen = false
    /// Läuft gerade eine Prüfung; ein weiterer Anstoß setzt `nochmal`.
    @ObservationIgnored private var laeuft = false
    @ObservationIgnored private var nochmal = false
    /// Rückfragen dieser Sitzung je Signatur, gültig für den Journalstand `rueckfragenStand` (Import-IDs).
    @ObservationIgnored private var rueckfragenSpeicher: [String: Rueckfrage] = [:]
    @ObservationIgnored private var rueckfragenStand: Set<Int64> = []

    init(speicher: UserDefaults = .standard) {
        self.speicher = speicher
        aktiv = speicher.bool(forKey: Self.schluesselAktiv)
        mitteilung = speicher.object(forKey: Self.schluesselMitteilung) as? Bool ?? true
        speicher.removeObject(forKey: "importOrdnerErledigt")
    }

    /// Beim Start der App (AppModell, nur mit Nebenwirkungen): beobachtet, falls eingeschaltet.
    func verbinde(_ modell: AppModell) {
        self.modell = modell
        mitteilen = true
        if vordergrund == nil {
            vordergrund = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.pruefe() }
            }
        }
        starte()
    }

    func setzeAktiv(_ an: Bool) {
        aktiv = an
        speicher.set(an, forKey: Self.schluesselAktiv)
        if an && mitteilung { Self.erbitteMitteilungen() }
        starte()
    }

    func setzeMitteilung(_ an: Bool) {
        mitteilung = an
        speicher.set(an, forKey: Self.schluesselMitteilung)
        if an { Self.erbitteMitteilungen() }
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
        merkeIgnoriert(rueckfrage.id)
        rueckfragenSpeicher[rueckfrage.id] = nil
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
        Task { await pruefe() }
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
            await self?.pruefe()
        }
    }

    // MARK: Prüfung

    /// Eine Datei des Ordners, die gelesen werden muss (noch nicht erledigt, nicht schon als Rückfrage bekannt).
    struct Kandidat: Sendable {
        let url: URL
        let name: String
        let signatur: String
        let groesse: Int
    }

    /// Ergebnis für eine Datei aus dem Hintergrundlauf.
    enum Ausgang: Sendable {
        /// Gespeichert oder schon im Journal; `meldung` nur, wenn die Speicherung selbst lief.
        case erledigt(signatur: String, name: String, hash: String, meldung: String?, gespeichert: Bool)
        case rueckfrage(Rueckfrage)
    }

    /// Geht alle Dateien des Ordners durch, die noch nicht erledigt sind. Lesen, Prüfsumme, Erkennung und
    /// Speichern laufen im Hintergrund (Gegencheck G19); Rückfragen zu unveränderten Dateien liest die App erst
    /// wieder, wenn sich das Journal geändert hat. Kommt während eines Laufs ein weiterer Anstoß, folgt ein Lauf.
    func pruefe(jetzt: Date = .now) async {
        guard !laeuft else {
            nochmal = true
            return
        }
        laeuft = true
        repeat {
            nochmal = false
            await lauf(jetzt: jetzt)
        } while nochmal
        laeuft = false
    }

    private func lauf(jetzt: Date) async {
        guard aktiv, let ordner, let modell, let journal = modell.journal else { return }
        let schluessel: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let dateien = (try? FileManager.default.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: schluessel,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        // Gemerkten Signaturen nur trauen, solange ihr Hash im Journal steht (G20: nach einem Wiederherstellen
        // oder Löschen eines Imports prüft die App die Datei neu).
        let bekannteHashes = Set(modell.importe.map(\.lauf.dateiHash))
        let stand = Set(modell.importe.map(\.id))
        if stand != rueckfragenStand {
            rueckfragenSpeicher = [:]
            rueckfragenStand = stand
        }
        let gemerkt = erledigteDateien()
        var offen: [Rueckfrage] = []
        var kandidaten: [Kandidat] = []
        var unfertig = false
        for url in dateien.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard Importordnerregel.kommtInFrage(name),
                  let werte = try? url.resourceValues(forKeys: Set(schluessel)),
                  werte.isRegularFile == true, let groesse = werte.fileSize, groesse > 0,
                  let geaendert = werte.contentModificationDate
            else { continue }
            let signatur = "\(name)|\(groesse)|\(Int(geaendert.timeIntervalSince1970))"
            if let eintrag = gemerkt[signatur], eintrag.hash.map({ bekannteHashes.contains($0) }) ?? true { continue }
            if let bekannt = rueckfragenSpeicher[signatur] {
                offen.append(bekannt)
                continue
            }
            guard jetzt.timeIntervalSince(geaendert) >= Self.ruhezeit else {
                unfertig = true
                continue
            }
            kandidaten.append(Kandidat(url: url, name: name, signatur: signatur, groesse: groesse))
        }
        var importiert = false
        var gespeichert: [Meldung] = []
        var erledigt = gemerkt
        if !kandidaten.isEmpty {
            let konten = modell.konten
            var zonen: [Int64: TimeZone] = [:]
            for konto in konten {
                if let id = konto.id, let zone = Self.letzteZeitzone(konto, importe: modell.importe) { zonen[id] = zone }
            }
            let liste = kandidaten
            let zeitzonen = zonen
            let ausgaenge = await Task.detached(priority: .utility) {
                Importordner.verarbeite(liste, journal: journal, konten: konten, zonen: zeitzonen,
                                        bekannteHashes: bekannteHashes)
            }.value
            // Neu lesen: „Ignorieren“ während des Laufs soll nicht verloren gehen.
            erledigt = erledigteDateien()
            for ausgang in ausgaenge {
                switch ausgang {
                case .erledigt(let signatur, let name, let hash, let meldung, let neu):
                    erledigt[signatur] = Erledigt(zeit: jetzt.timeIntervalSince1970, hash: hash)
                    importiert = importiert || neu
                    if let meldung {
                        melde(name, meldung, jetzt: jetzt)
                        if neu, let eintrag = zuletzt.first { gespeichert.append(eintrag) }
                    }
                case .rueckfrage(let rueckfrage):
                    rueckfragenSpeicher[rueckfrage.id] = rueckfrage
                    offen.append(rueckfrage)
                }
            }
        }
        speichere(erledigt)
        rueckfragen = offen.sorted { $0.dateiname < $1.dateiname }
        if importiert {
            modell.laden()
            modell.exportiere()
            // Das Journal hat sich geändert: Rückfragen beim nächsten Lauf neu bewerten.
            rueckfragenStand = []
        }
        if mitteilen, mitteilung, let inhalt = Self.mitteilungstext(gespeichert, offen: offen.count) {
            Self.teileMit(titel: inhalt.titel, text: inhalt.text)
        }
        if unfertig { pruefeSpaeter() }
    }

    /// Liest, prüft und speichert die Kandidaten, abseits des Hauptthreads.
    nonisolated static func verarbeite(_ kandidaten: [Kandidat], journal: Journal, konten: [Konto],
                                       zonen: [Int64: TimeZone], bekannteHashes: Set<String>) -> [Ausgang] {
        var ergebnis: [Ausgang] = []
        var hashes = bekannteHashes
        for k in kandidaten {
            func frage(_ grund: String) {
                ergebnis.append(.rueckfrage(Rueckfrage(id: k.signatur, dateiname: k.name, url: k.url, grund: grund)))
            }
            guard k.groesse <= hoechstgroesse else {
                frage(String(localized: "Datei zu groß für einen Kontoauszug."))
                continue
            }
            guard let daten = try? Data(contentsOf: k.url) else {
                frage(String(localized: "Datei nicht lesbar."))
                continue
            }
            // Schon gespeichert, etwa über „Prüfen“ im Blatt: erledigt, auch wenn das Konto mehrdeutig ist.
            let hash = Journal.fingerabdruck(daten)
            if hashes.contains(hash) {
                ergebnis.append(.erledigt(signatur: k.signatur, name: k.name, hash: hash, meldung: nil, gespeichert: false))
                continue
            }
            let entscheidung = Importordnerregel.entscheide(daten: daten, dateiname: k.name, konten: konten,
                                                            zeitzone: { $0.id.flatMap { zonen[$0] } })
            do {
                guard let gespeichert = try importiere(entscheidung, daten: daten, dateiname: k.name, journal: journal)
                else {
                    if case .rueckfrage(let grund) = entscheidung { frage(grund) }
                    continue
                }
                hashes.insert(hash)
                ergebnis.append(.erledigt(signatur: k.signatur, name: k.name, hash: hash, meldung: text(gespeichert),
                                          gespeichert: gespeichert.status == .gespeichert))
            } catch {
                // Widerspruch zu den Summen, andere Kontowährung, abweichender Datensatz: das Blatt zeigt Einzelheiten.
                frage(String(localized: "Import abgebrochen: bitte im Blatt prüfen."))
            }
        }
        return ergebnis
    }

    /// Speichert still; `nil` bei einer Rückfrage.
    nonisolated static func importiere(_ entscheidung: Importordnerregel.Entscheidung, daten: Data, dateiname: String,
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

    nonisolated private static func text(_ ergebnis: ImportErgebnis) -> String {
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

    // MARK: Mitteilung

    /// Titel und Text der Mitteilung nach einem Lauf; `nil`, wenn nichts still gespeichert wurde.
    /// Wartende Dateien nennt der Text nur mit, eine eigene Mitteilung bekommen sie nicht.
    static func mitteilungstext(_ gespeichert: [Meldung], offen: Int) -> (titel: String, text: String)? {
        guard let erste = gespeichert.first, let letzte = gespeichert.last else { return nil }
        var text = gespeichert.count == 1
            ? "\(erste.dateiname): \(erste.text)"
            : String(localized: "\(gespeichert.count) Dateien importiert, zuletzt \(letzte.dateiname)")
        if offen > 0 {
            text += " · " + String(localized: "\(offen) Dateien warten auf dich")
        }
        return (String(localized: "Aus dem Import-Ordner importiert"), text)
    }

    /// Fragt einmal nach der Erlaubnis für Mitteilungen; danach merkt sich macOS die Antwort.
    private static func erbitteMitteilungen() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func teileMit(titel: String, text: String) {
        let inhalt = UNMutableNotificationContent()
        inhalt.title = titel
        inhalt.body = text
        let anfrage = UNNotificationRequest(identifier: "importordner-\(UUID().uuidString)", content: inhalt, trigger: nil)
        UNUserNotificationCenter.current().add(anfrage) { _ in }
    }

    private func melde(_ dateiname: String, _ text: String, jetzt: Date) {
        zuletzt.insert(Meldung(dateiname: dateiname, text: text, zeit: jetzt), at: 0)
        zuletzt = Array(zuletzt.prefix(5))
    }

    // MARK: Erledigte Dateien

    /// Eine erledigte Datei: Hash bei Import oder „schon im Journal“, `nil` bei „Ignorieren“ (gilt, bis sich die
    /// Datei ändert). Ein Hash, der nicht mehr im Journal steht, macht den Eintrag ungültig (G20).
    struct Erledigt: Codable, Equatable {
        var zeit: Double
        var hash: String?
    }

    private func erledigteDateien() -> [String: Erledigt] {
        guard let daten = speicher.data(forKey: Self.schluesselErledigt) else { return [:] }
        return (try? JSONDecoder().decode([String: Erledigt].self, from: daten)) ?? [:]
    }

    /// Hebt höchstens 1000 Einträge auf, die jüngsten.
    private func speichere(_ erledigt: [String: Erledigt]) {
        let behalten = erledigt.count > 1000
            ? Dictionary(uniqueKeysWithValues: erledigt.sorted { $0.value.zeit > $1.value.zeit }.prefix(1000).map { ($0.key, $0.value) })
            : erledigt
        if let daten = try? JSONEncoder().encode(behalten) { speicher.set(daten, forKey: Self.schluesselErledigt) }
    }

    private func merkeIgnoriert(_ signatur: String) {
        var erledigt = erledigteDateien()
        erledigt[signatur] = Erledigt(zeit: Date.now.timeIntervalSince1970, hash: nil)
        speichere(erledigt)
    }
}

extension Importordner {
    /// Nur für Tests: beobachtet `url` ohne Bookmark und ohne Dispatch-Quelle.
    func pruefeTestweise(_ url: URL, modell: AppModell, jetzt: Date) async {
        self.modell = modell
        ordner = url
        aktiv = true
        await pruefe(jetzt: jetzt)
    }
}
#endif
