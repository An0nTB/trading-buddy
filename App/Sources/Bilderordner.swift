import Foundation
import TradingCore

/// Bilderordner der App: `Application Support/Trading Buddy/Bilder`, in der Sandbox im Container.
/// Screenshots werden hierher kopiert; Speicher und Export kennen nur den relativen Pfad
/// (`Bildverweis`, Doc 24). Unterordner je Monat, Dateiname zufällig, damit nichts überschrieben wird.
enum Bilderordner {
    static func ordner() throws -> URL {
        let ordner = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Trading Buddy", isDirectory: true)
            .appendingPathComponent("Bilder", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner
    }

    /// Volle Adresse eines Verweises; `nil`, wenn der Pfad ungültig ist oder aus dem Ordner führt.
    static func url(fuer datei: String) -> URL? {
        guard Bildverweis.istGueltig(datei), let ordner = try? ordner() else { return nil }
        let ziel = ordner.appendingPathComponent(datei).standardizedFileURL
        let basis = ordner.standardizedFileURL.path + "/"
        return ziel.path.hasPrefix(basis) ? ziel : nil
    }

    /// Kopiert ein Bild in den Ordner und gibt den relativen Pfad zurück, z. B. „2026-10/3F2A….png“.
    /// Die Quelle bleibt unverändert; Bilder aus „Datei wählen“ brauchen den Zugriff auf die Quelle.
    static func uebernimm(_ quelle: URL, jetzt: Date = Date(), zeitzone: TimeZone = .current) throws -> String {
        let endung = quelle.pathExtension.lowercased()
        guard Bildverweis.endungen.contains(endung) else { throw Bildfehler.keinBild(quelle.lastPathComponent) }
        let zugriff = quelle.startAccessingSecurityScopedResource()
        defer { if zugriff { quelle.stopAccessingSecurityScopedResource() } }

        let datei = relativerPfad(endung: endung, jetzt: jetzt, zeitzone: zeitzone)
        guard let ziel = url(fuer: datei) else { throw Bildfehler.ungueltigerPfad }
        do {
            try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: quelle, to: ziel)
        } catch {
            throw Bildfehler.kopieren(quelle.lastPathComponent)
        }
        return datei
    }

    /// Wie `uebernimm(_:)` für beide Herkünfte; Daten (Fotoauswahl am iPhone) schreibt sie neu.
    static func uebernimm(_ quelle: Bildquelle, jetzt: Date = Date(), zeitzone: TimeZone = .current) throws -> String {
        switch quelle {
        case .datei(let url):
            return try uebernimm(url, jetzt: jetzt, zeitzone: zeitzone)
        case .daten(let daten, let endung, let name):
            let endung = endung.lowercased()
            guard Bildverweis.endungen.contains(endung) else { throw Bildfehler.keinBild(name) }
            let datei = relativerPfad(endung: endung, jetzt: jetzt, zeitzone: zeitzone)
            guard let ziel = url(fuer: datei) else { throw Bildfehler.ungueltigerPfad }
            do {
                try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try daten.write(to: ziel, options: .withoutOverwriting)
            } catch {
                throw Bildfehler.kopieren(name)
            }
            return datei
        }
    }

    /// Legt die Bilder ab und speichert je einen Verweis; scheitert der Verweis, fliegt die Kopie wieder
    /// heraus. Nicht unterstützte Dateien überspringt sie. Gibt die erste Fehlermeldung zurück.
    static func lege(_ quellen: [Bildquelle], bezug: Bildverweis.Bezug, jetzt: Date = Date(),
                     zeitzone: TimeZone = .current, speichern: (Bildverweis) throws -> Void) -> String? {
        var ersterFehler: String?
        for quelle in quellen {
            do {
                let datei = try uebernimm(quelle, jetzt: jetzt, zeitzone: zeitzone)
                do {
                    try speichern(Bildverweis(datei: datei, bezug: bezug, erstellt: jetzt))
                } catch {
                    loesche(datei)
                    throw error
                }
            } catch {
                if ersterFehler == nil { ersterFehler = error.localizedDescription }
            }
        }
        return ersterFehler
    }

    /// Zeitpunkt der letzten Wiederherstellung als Sekunden seit 1970; 0 = nie. Bilder, die bis dahin schon da
    /// waren, räumt `raeumeAuf` nicht weg: die zurückgespielte Datenbank kennt sie nicht, der beiseitegelegte
    /// Stand „Vor Wiederherstellung“ schon (dritter Gegencheck G16).
    static let schluesselGeschuetztBis = "bilder.geschuetztBis"

    /// Schützt alle jetzt vorhandenen Bilder vor dem Aufräumen; nach jedem Wiederherstellen aufrufen.
    static func schuetzeBestand(jetzt: Date = .now, ablage: UserDefaults = .standard) {
        ablage.set(jetzt.timeIntervalSince1970, forKey: schluesselGeschuetztBis)
    }

    static func schutzzeitpunkt(ablage: UserDefaults = .standard) -> Date? {
        let sekunden = ablage.double(forKey: schluesselGeschuetztBis)
        return sekunden > 0 ? Date(timeIntervalSince1970: sekunden) : nil
    }

    /// Löscht Bilddateien in den Monatsordnern, auf die kein Verweis zeigt (gelöschte Einträge, abgebrochenes
    /// Ablegen). Ohne einen einzigen Verweis tut sie nichts: dann ist eher die Datenbank leer oder neu als
    /// der Ordner voller Waisen. Dateien, die bis `geschuetztBis` entstanden sind, bleiben (G16); ohne lesbares
    /// Erstelldatum bleibt die Datei ebenfalls. Läuft auf dem Hauptthread, damit kein gleichzeitiges Ablegen
    /// dazwischenkommt. `basis` nur für Tests (App/Tests): ein Ordner im temporären Verzeichnis statt des echten.
    @MainActor
    static func raeumeAuf(behalten: Set<String>, geschuetztBis: Date? = schutzzeitpunkt(), in basis: URL? = nil) -> Int {
        guard !behalten.isEmpty, let ordner = basis ?? (try? Self.ordner()) else { return 0 }
        let dateisystem = FileManager.default
        guard let monate = try? dateisystem.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil) else {
            return 0
        }
        var geloescht = 0
        for monat in monate {
            let schluessel: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey]
            let dateien = (try? dateisystem.contentsOfDirectory(at: monat, includingPropertiesForKeys: Array(schluessel))) ?? []
            for url in dateien {
                let datei = "\(monat.lastPathComponent)/\(url.lastPathComponent)"
                guard Bildverweis.istGueltig(datei), !behalten.contains(datei),
                      let werte = try? url.resourceValues(forKeys: schluessel), werte.isRegularFile == true
                else { continue }
                if let geschuetztBis {
                    guard let erstellt = werte.creationDate, erstellt > geschuetztBis else { continue }
                }
                if (try? dateisystem.removeItem(at: url)) != nil { geloescht += 1 }
            }
        }
        return geloescht
    }

    /// Entfernt die Datei; fehlt sie schon, ist das kein Fehler.
    static func loesche(_ datei: String) {
        guard let url = url(fuer: datei) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func relativerPfad(endung: String, jetzt: Date, zeitzone: TimeZone) -> String {
        let tag = Journaltag(jetzt, zeitzone: zeitzone).description
        return "\(tag.prefix(7))/\(UUID().uuidString).\(endung)"
    }
}

/// Herkunft eines neuen Bildes: Datei (Ziehen, Dateiauswahl) oder Daten (Fotoauswahl am iPhone).
enum Bildquelle {
    case datei(URL)
    case daten(Data, endung: String, name: String)
}

enum Bildfehler: LocalizedError {
    case keinBild(String)
    case kopieren(String)
    case ungueltigerPfad

    var errorDescription: String? {
        switch self {
        case .keinBild(let name):
            String(localized: "„\(name)“ ist kein unterstütztes Bild. Möglich sind PNG, JPEG und HEIC.")
        case .kopieren(let name):
            String(localized: "„\(name)“ ließ sich nicht in den Bilderordner kopieren.")
        case .ungueltigerPfad:
            String(localized: "Der Bildpfad zeigt aus dem Bilderordner heraus und wird nicht gespeichert.")
        }
    }
}
