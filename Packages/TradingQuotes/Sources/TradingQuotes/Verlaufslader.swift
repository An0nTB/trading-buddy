import Foundation

/// Stand der geladenen Kursverläufe, je Journal-Symbol. Die App hält ihn im Speicher und in einer Datei.
public struct Verlaufsstand: Sendable, Equatable, Codable {
    public var verlaeufe: [String: Kursverlauf]
    /// Fehler je Journal-Symbol als Text; ein älterer Verlauf bleibt dann in `verlaeufe` stehen.
    public var fehler: [String: String]
    /// Zeitpunkt des letzten vollständigen Ladens, `nil` vor dem ersten.
    public var geladen: Date?
    /// Zeitpunkt des letzten Teilabrufs nach Fehlern (Gegencheck P1 Nr. 3); `nil`, solange es keinen gab.
    public var letzterVersuch: Date?

    public static let leer = Verlaufsstand(verlaeufe: [:], fehler: [:], geladen: nil)

    public init(verlaeufe: [String: Kursverlauf], fehler: [String: String], geladen: Date?, letzterVersuch: Date? = nil) {
        self.verlaeufe = verlaeufe
        self.fehler = fehler
        self.geladen = geladen
        self.letzterVersuch = letzterVersuch
    }

    /// Einmal am Tag reicht: aktuell, wenn vor weniger als 20 Stunden geladen und jedes Symbol dabei war.
    /// Nach einem Fehler gibt es nach einer Stunde einen neuen Versuch (Gegencheck Q3).
    public func istAktuell(fuer symbole: [String], jetzt: Date) -> Bool {
        zuErneuern(symbole, jetzt: jetzt).isEmpty
    }

    /// Symbole, die ein Abruf jetzt holen muss: nach 20 Stunden alle, sonst nur neue und, eine Stunde nach dem
    /// letzten Versuch, die mit Fehler. So löst ein dauerhafter Fehler (etwa ohne Alpaca-Schlüssel) nicht jede
    /// Stunde einen Abruf aller Symbole aus (Gegencheck P1 Nr. 3).
    public func zuErneuern(_ symbole: [String], jetzt: Date) -> [String] {
        guard let geladen, jetzt.timeIntervalSince(geladen) < 20 * 3600 else { return symbole }
        let wiederholen = jetzt.timeIntervalSince(letzterVersuch ?? geladen) >= 3600
        return symbole.filter { symbol in
            if verlaeufe[symbol] == nil && fehler[symbol] == nil { return true }
            return wiederholen && fehler[symbol] != nil
        }
    }

    /// Arbeitet einen Abruf für `symbole` ein. War der Stand abgelaufen (siehe `zuErneuern`), ersetzt `neu` ihn
    /// ganz; sonst gelten nur diese Symbole neu, `geladen` bleibt und `letzterVersuch` wird `jetzt`.
    public func ergaenzt(um neu: Verlaufsstand, symbole: [String], jetzt: Date) -> Verlaufsstand {
        guard let geladen, jetzt.timeIntervalSince(geladen) < 20 * 3600 else { return neu }
        var stand = self
        for symbol in symbole {
            stand.verlaeufe[symbol] = neu.verlaeufe[symbol]
            stand.fehler[symbol] = neu.fehler[symbol]
        }
        stand.letzterVersuch = jetzt
        return stand
    }
}

/// Lädt Tageskerzen für eine Liste von Kurszuordnungen, nacheinander und mit Pause, damit die freien
/// Abrufgrenzen halten (Alpaca gratis 200 Abrufe je Minute laut alpaca.markets/data, 02.10.2026; Kraken
/// zählt öffentliche Abrufe je Adresse). Mehrere Journal-Symbole auf dasselbe Quellsymbol teilen sich einen Abruf.
public struct Verlaufslader: Sendable {
    public let quellen: [String: any Verlaufsquelle]
    let warte: @Sendable (Duration) async -> Void

    /// `warte` nur für Tests; ohne Angabe wartet der Lader wirklich.
    public init(quellen: [any Verlaufsquelle], warte: (@Sendable (Duration) async -> Void)? = nil) {
        var nachID: [String: any Verlaufsquelle] = [:]
        for quelle in quellen { nachID[quelle.id] = quelle }
        self.quellen = nachID
        self.warte = warte ?? Kursquellen.schlafe
    }

    /// Lädt die letzten `monate` Monate (je 31 Tage). 13 als Vorgabe: Die Kursanalyse in TradingCore rechnet über
    /// 365 Kalendertage und braucht für ATR 14 weitere Kerzen davor (Hauptthread, 02.10.2026).
    /// Scheitert ein Abruf, bleibt der Verlauf aus `bisher` stehen.
    public func lade(_ zuordnungen: [Kurszuordnung], monate: Int = 13, bisher: Verlaufsstand = .leer,
                     jetzt: Date) async -> Verlaufsstand {
        let seit = jetzt.addingTimeInterval(-Double(monate) * 31 * 86_400)
        var stand = Verlaufsstand(verlaeufe: [:], fehler: [:], geladen: jetzt)
        var geholt: [String: Result<[Tageskerze], Verlaufsfehler>] = [:]
        var erster = true
        for z in zuordnungen {
            guard let quelle = quellen[z.quelle] else {
                stand.fehler[z.journalSymbol] = "Für \(z.quelle) gibt es keinen Kursverlauf."
                continue
            }
            let schluessel = z.quelle + "|" + z.quellSymbol
            if geholt[schluessel] == nil {
                if !erster { await warte(.seconds(1)) }
                erster = false
                geholt[schluessel] = await Self.hole(quelle, z.quellSymbol, seit: seit, jetzt: jetzt)
            }
            guard let ergebnis = geholt[schluessel] else { continue }
            switch ergebnis {
            case .success(let kerzen) where !kerzen.isEmpty:
                stand.verlaeufe[z.journalSymbol] = Kursverlauf(journalSymbol: z.journalSymbol, quelle: z.quelle,
                                                               quellSymbol: z.quellSymbol, naeherung: z.naeherung,
                                                               kerzen: kerzen, geladen: jetzt)
            case .success, .failure:
                // Eine leere Antwort ersetzt keinen gespeicherten Verlauf (Gegencheck Q3).
                if case .failure(let fehler) = ergebnis {
                    stand.fehler[z.journalSymbol] = fehler.description
                } else {
                    stand.fehler[z.journalSymbol] = "Keine Kerzen geliefert"
                }
                if let alt = bisher.verlaeufe[z.journalSymbol] { stand.verlaeufe[z.journalSymbol] = alt }
            }
        }
        return stand
    }

    private static func hole(_ quelle: any Verlaufsquelle, _ symbol: String, seit: Date,
                             jetzt: Date) async -> Result<[Tageskerze], Verlaufsfehler> {
        do {
            return .success(try await quelle.tageskerzen(symbol, seit: seit, jetzt: jetzt))
        } catch let fehler as Verlaufsfehler {
            return .failure(fehler)
        } catch {
            return .failure(.anbieter(String(describing: error)))
        }
    }
}

/// Zwischenspeicher als JSON-Datei, damit die Analyse ohne Netz und ohne erneuten Abruf am selben Tag läuft.
public struct Verlaufsspeicher: Sendable {
    public let datei: URL

    public init(datei: URL) {
        self.datei = datei
    }

    /// `Application Support/Trading Buddy/kursverlaeufe.json`, neben der Datenbank und den EZB-Kursen.
    public static func standardDatei() -> URL {
        let ordner = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ordner.appendingPathComponent("Trading Buddy", isDirectory: true)
            .appendingPathComponent("kursverlaeufe.json")
    }

    private struct Datei: Codable {
        var format: Int
        var stand: Verlaufsstand
    }

    /// `nil`, wenn die Datei fehlt, unlesbar ist oder ein anderes Format hat.
    public func lies() -> Verlaufsstand? {
        guard let daten = try? Data(contentsOf: datei),
              let inhalt = try? Self.decoder.decode(Datei.self, from: daten), inhalt.format == 1 else { return nil }
        return inhalt.stand
    }

    public func schreibe(_ stand: Verlaufsstand) throws {
        let daten = try Self.encoder.encode(Datei(format: 1, stand: stand))
        try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
        try daten.write(to: datei, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
