import Foundation
import TradingCore

/// Zwischenspeicher der EZB-Kurse als JSON-Datei, damit die Steuer-Seite auch ohne Netz rechnet.
/// Kurse stehen als Text in der Datei („1.1708“), nicht als JSON-Zahl: Decimal verliert sonst Stellen.
public struct Kursspeicher: Sendable {
    public let datei: URL

    public init(datei: URL) {
        self.datei = datei
    }

    /// `Application Support/Trading Buddy/ezb-referenzkurse.json`, in der Sandbox im Container der App.
    /// Gleicher Ordner wie die Datenbank (AppModell.datenbankpfad).
    public static func standardDatei() -> URL {
        let ordner = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ordner.appendingPathComponent("Trading Buddy", isDirectory: true)
            .appendingPathComponent("ezb-referenzkurse.json")
    }

    public struct Inhalt: Sendable, Equatable {
        public var kurse: [Journaltag: [String: Decimal]]
        /// Zeitpunkt des letzten erfolgreichen Abrufs.
        public var abgerufen: Date

        public init(kurse: [Journaltag: [String: Decimal]], abgerufen: Date) {
            self.kurse = kurse
            self.abgerufen = abgerufen
        }

        public var letzterTag: Journaltag? { kurse.keys.max() }
    }

    /// `nil`, wenn die Datei fehlt oder unlesbar ist.
    public func lies() -> Inhalt? {
        guard let daten = try? Data(contentsOf: datei),
              let datei = try? Self.decoder.decode(Datei.self, from: daten), datei.format == 1 else { return nil }
        var kurse: [Journaltag: [String: Decimal]] = [:]
        for (text, liste) in datei.tage {
            guard let tag = Journaltag(text) else { continue }
            var tageskurse: [String: Decimal] = [:]
            for (waehrung, kurs) in liste {
                if let wert = EZBKursdatei.zahl(kurs) { tageskurse[waehrung] = wert }
            }
            if !tageskurse.isEmpty { kurse[tag] = tageskurse }
        }
        return Inhalt(kurse: kurse, abgerufen: datei.abgerufen)
    }

    /// Schreibt die Datei vollständig neu; legt den Ordner bei Bedarf an.
    public func schreibe(_ inhalt: Inhalt) throws {
        var tage: [String: [String: String]] = [:]
        for (tag, liste) in inhalt.kurse {
            tage[tag.description] = liste.mapValues { "\($0)" }
        }
        let daten = try Self.encoder.encode(Datei(format: 1, abgerufen: inhalt.abgerufen, tage: tage))
        try FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
        try daten.write(to: datei, options: .atomic)
    }

    struct Datei: Codable {
        var format: Int
        var abgerufen: Date
        var tage: [String: [String: String]]
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
