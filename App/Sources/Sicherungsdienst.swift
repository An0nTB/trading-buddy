#if os(macOS)
import Foundation
import TradingCore
import TradingStore

/// Tägliche Sicherung der Datenbank in einen Ordner nach Wahl, Wiederherstellen mit Prüfung (Frage 5, Tim
/// 02.10.2026 18:23 UTC). Der Store kopiert, prüft und spielt zurück (AP9, Doc 46); hier liegen Ordnerwahl,
/// Zeitplan, Aufbewahrung und der Spiegel der Screenshots. Der Ordner wird wie beim Export als
/// Security-scoped Bookmark gemerkt. Schlüssel aus dem Schlüsselbund gehören nicht in die Sicherung.
enum Sicherungsdienst {
    static let schluesselOrdner = "datensicherung.ordner"
    static let schluesselAktiv = "datensicherung.aktiv"
    static let schluesselBehalten = "datensicherung.behalten"
    /// Zeitpunkt der letzten Sicherung als Sekunden seit 1970; 0 = noch keine.
    static let schluesselLetzte = "datensicherung.letzte"
    /// Ergebnis des letzten Laufs als Text, auch des automatischen; die Einstellungen zeigen es.
    static let schluesselStand = "datensicherung.stand"
    static let standardBehalten = 14
    static let behaltenBereich = 1...60
    /// Abstand zwischen zwei automatischen Sicherungen.
    static let abstand: TimeInterval = 24 * 60 * 60

    static let endung = "sqlite"
    static let bilderUnterordner = "Bilder"

    // MARK: Ordner

    static func merke(_ url: URL) throws {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        let daten = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                         relativeTo: nil)
        UserDefaults.standard.set(daten, forKey: schluesselOrdner)
    }

    static func gemerkterOrdner() -> URL? {
        guard let daten = UserDefaults.standard.data(forKey: schluesselOrdner) else { return nil }
        var veraltet = false
        guard let url = try? URL(resolvingBookmarkData: daten, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &veraltet)
        else { return nil }
        if veraltet { try? merke(url) }
        return url
    }

    // MARK: Einstellungen

    static var aktiv: Bool { UserDefaults.standard.bool(forKey: schluesselAktiv) }

    static var behalten: Int {
        let wert = UserDefaults.standard.integer(forKey: schluesselBehalten)
        return behaltenBereich.contains(wert) ? wert : standardBehalten
    }

    static var letzte: Date? {
        let sekunden = UserDefaults.standard.double(forKey: schluesselLetzte)
        return sekunden > 0 ? Date(timeIntervalSince1970: sekunden) : nil
    }

    /// Fällig, wenn eingeschaltet, ein Ordner gemerkt ist und die letzte Sicherung einen Tag zurückliegt.
    /// `ablage` nur für Tests (App/Tests) austauschbar, damit ein Testlauf am Mac die Einstellungen des Nutzers nicht anfasst.
    static func istFaellig(jetzt: Date = .now, ablage: UserDefaults = .standard) -> Bool {
        guard ablage.bool(forKey: schluesselAktiv), ablage.data(forKey: schluesselOrdner) != nil else { return false }
        let sekunden = ablage.double(forKey: schluesselLetzte)
        guard sekunden > 0 else { return true }
        return jetzt.timeIntervalSince(Date(timeIntervalSince1970: sekunden)) >= abstand
    }

    // MARK: Sichern

    /// Schreibt eine Sicherung in den gemerkten Ordner (Store: `sichereInOrdner`, prüft und behält die
    /// neuesten `behalten`), spiegelt die Screenshots in den Unterordner „Bilder“ und merkt Zeit und Stand.
    /// Die Arbeit läuft abseits des Hauptthreads; wirft nicht, der Stand steht als Text in den Einstellungen.
    @discardableResult @MainActor
    static func sichere(_ journal: Journal?, jetzt: Date = .now) async -> String {
        let stand: String
        if let journal {
            let behalte = behalten
            let ergebnis = await Task.detached(priority: .utility) {
                schreibeSicherung(journal, jetzt: jetzt, behalte: behalte)
            }.value
            if ergebnis.erfolgreich { UserDefaults.standard.set(jetzt.timeIntervalSince1970, forKey: schluesselLetzte) }
            stand = ergebnis.text
        } else {
            stand = String(localized: "Sicherung: Journal nicht geöffnet")
        }
        UserDefaults.standard.set(stand, forKey: schluesselStand)
        return stand
    }

    private static func schreibeSicherung(_ journal: Journal, jetzt: Date,
                                          behalte: Int) -> (erfolgreich: Bool, text: String) {
        guard let ordner = gemerkterOrdner() else {
            return (false, String(localized: "Sicherung: noch kein Ordner gewählt oder Ordner nicht erreichbar"))
        }
        guard ordner.startAccessingSecurityScopedResource() else {
            return (false, String(localized: "Sicherung: kein Zugriff auf \(ordner.path)"))
        }
        defer { ordner.stopAccessingSecurityScopedResource() }
        do {
            let ziel = try journal.sichereInOrdner(ordner, jetzt: jetzt, behalte: behalte)
            let bilder = spiegleBilder(nach: ordner.appending(path: bilderUnterordner, directoryHint: .isDirectory))
            return (true, String(localized: "Sicherung: \(ziel.lastPathComponent), \(bilder) neue Bilder"))
        } catch {
            return (false, String(localized: "Sicherung: Fehler \(error.localizedDescription)"))
        }
    }

    /// Sichert, sobald fällig, und schaut danach stündlich nach; läuft, solange die App läuft.
    @MainActor
    static func laufe(journal: @escaping @MainActor () -> Journal?) async {
        while !Task.isCancelled {
            if istFaellig() { await sichere(journal()) }
            try? await Task.sleep(for: .seconds(60 * 60))
        }
    }

    /// Kopiert Screenshots, die im Ziel fehlen; löscht dort nichts, ältere Sicherungen zeigen darauf.
    /// Gibt die Zahl neuer Dateien zurück.
    @discardableResult
    static func spiegleBilder(nach ziel: URL) -> Int {
        guard let quelle = try? Bilderordner.ordner() else { return 0 }
        return kopiereFehlende(von: quelle, nach: ziel)
    }

    /// Kopiert Dateien aus den Monatsordnern von `quelle`, die in `ziel` fehlen, und nur gültige Bildpfade.
    static func kopiereFehlende(von quelle: URL, nach ziel: URL) -> Int {
        let dateisystem = FileManager.default
        let monate = (try? dateisystem.contentsOfDirectory(at: quelle, includingPropertiesForKeys: nil)) ?? []
        var neu = 0
        for monat in monate {
            let dateien = (try? dateisystem.contentsOfDirectory(at: monat, includingPropertiesForKeys: nil)) ?? []
            for datei in dateien {
                let relativ = "\(monat.lastPathComponent)/\(datei.lastPathComponent)"
                guard Bildverweis.istGueltig(relativ) else { continue }
                let nach = ziel.appending(path: relativ)
                guard !dateisystem.fileExists(atPath: nach.path) else { continue }
                do {
                    try dateisystem.createDirectory(at: nach.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
                    try dateisystem.copyItem(at: datei, to: nach)
                    neu += 1
                } catch {
                    continue
                }
            }
        }
        return neu
    }

    // MARK: Wiederherstellen

    /// Prüft eine gewählte Sicherung, ohne sie zu ändern (abseits des Hauptthreads).
    static func pruefe(_ datei: URL) async -> Sicherungspruefung {
        await Task.detached(priority: .userInitiated) {
            let zugriff = datei.startAccessingSecurityScopedResource()
            defer { if zugriff { datei.stopAccessingSecurityScopedResource() } }
            return Journal.pruefeSicherung(datei)
        }.value
    }

    /// Sichert zuerst den aktuellen Stand in `Application Support/Trading Buddy/Vor Wiederherstellung`, spielt
    /// dann die Sicherung ein und holt fehlende Screenshots aus dem Bilder-Spiegel neben der Datei zurück.
    /// Den Spiegel darf die Sandbox nur lesen, wenn er im gemerkten Sicherungsordner liegt; die gewählte Datei
    /// allein öffnet ihren Nachbarordner nicht (dritter Gegencheck G17). Danach sind alle vorhandenen Bilder vor
    /// dem Aufräumen geschützt, auch die, die nur der beiseitegelegte Stand kennt (G16).
    static func stelleWiederHer(_ datei: URL, journal: Journal, jetzt: Date = .now) async throws -> String {
        let ordner = gemerkterOrdner()
        return try await Task.detached(priority: .userInitiated) {
            let vorher = try journal.sichereInOrdner(vorWiederherstellungOrdner(), jetzt: jetzt, behalte: 5)
            let zugriff = datei.startAccessingSecurityScopedResource()
            let ordnerZugriff = ordner?.startAccessingSecurityScopedResource() ?? false
            defer {
                if zugriff { datei.stopAccessingSecurityScopedResource() }
                if ordnerZugriff { ordner?.stopAccessingSecurityScopedResource() }
            }
            try journal.stelleWiederHer(aus: datei)
            let spiegel = datei.deletingLastPathComponent()
                .appending(path: bilderUnterordner, directoryHint: .isDirectory)
            let lesbar = (try? FileManager.default.contentsOfDirectory(at: spiegel, includingPropertiesForKeys: nil)) != nil
            let bilder = (try? Bilderordner.ordner()).map { kopiereFehlende(von: spiegel, nach: $0) } ?? 0
            Bilderordner.schuetzeBestand()
            let ergebnis = String(localized: "Wiederhergestellt aus \(datei.lastPathComponent), \(bilder) Bilder zurückgeholt. Der vorherige Stand liegt in \(vorher.path).")
            // Fehlt der Ordner nur, weil es nie Bilder gab: kein Hinweis. Außerhalb des gemerkten Ordners ist er
            // in der Sandbox sicher gesperrt.
            let imOrdner = ordner.map { datei.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/") } ?? false
            guard !lesbar, !imOrdner else { return ergebnis }
            return ergebnis + " " + String(localized: "Der Ordner „Bilder“ neben der Sicherung war nicht lesbar. Liegt die Sicherung nicht im gewählten Sicherungsordner, diesen Ordner zuerst wählen und die Sicherung erneut einspielen, dann kommen die Screenshots mit.")
        }.value
    }

    private static func vorWiederherstellungOrdner() throws -> URL {
        let ordner = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Trading Buddy/Vor Wiederherstellung", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner
    }
}
#endif
