import Foundation
import TradingCore

/// Ein Symbol im Kerzenspeicher, für die Liste „Kursdaten“ auf der Seite „Ausstieg“.
struct Kerzenbestand: Sendable, Equatable, Codable, Identifiable {
    var symbol: String
    var anzahl: Int
    var von: Date
    var bis: Date
    /// Kürzeste gespeicherte Kerzenlänge in Sekunden, 60 bei Minutenkursen.
    var kerzenDauer: Int
    /// Herkunft der Kerzen, z. B. „MT4“, „Alpaca“, „Binance“; mehrere bei gemischtem Bestand.
    var quellen: [String]
    var id: String { symbol }
}

/// Zeitkerzen (Minute, Stunde) je Symbol für die Ausstiegsanalyse (Doc 39, Paket B3) als Dateien unter
/// `Application Support/Trading Buddy/zeitkerzen/`, nicht in der Datenbank. Ein Ordner je Symbol, eine Datei
/// je Kalendermonat in UTC (`2026-10.json`), damit eine Analyse nur die Monate ihrer Trades liest;
/// Minutenkurse eines Monats sind rund 30.000 bis 45.000 Kerzen. Dazu `bestand.json` als Übersicht.
///
/// Dateiformat 1 (Festlegung B3, 02.10.2026):
/// `{"format":1,"symbol":"EURUSD","monat":"2026-10","quellen":["MT4"],"kerzen":[Zeitkerze…]}`, Kerzen aufsteigend,
/// Zeiten ISO 8601 in UTC, Kurse als Text wie in `Zeitkerze` (nie als JSON-Zahl). Symbole sind die Symbole
/// des Journals (`Trade.symbol`); Zeichen außer Buchstaben, Ziffern, Punkt, Minus und Unterstrich stehen im
/// Ordnernamen als `~` mit zwei Hex-Ziffern je Byte (`BTC/EUR` → `BTC~2FEUR`), damit kein Name doppelt vorkommt.
struct Zeitkerzenspeicher: Sendable {
    let ordner: URL

    init(ordner: URL = Zeitkerzenspeicher.standardOrdner()) {
        self.ordner = ordner
    }

    /// `Application Support/Trading Buddy/zeitkerzen`, neben Datenbank, Kursverläufen und EZB-Kursen.
    static func standardOrdner() -> URL {
        let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return basis.appendingPathComponent("Trading Buddy", isDirectory: true)
            .appendingPathComponent("zeitkerzen", isDirectory: true)
    }

    static let format = 1

    private struct Monatsdatei: Codable {
        var format: Int
        var symbol: String
        var monat: String
        var quellen: [String]
        var kerzen: [Zeitkerze]
    }

    private struct Bestandsdatei: Codable {
        var format: Int
        var symbole: [Kerzenbestand]
    }

    // MARK: Lesen

    /// Übersicht aller Symbole, nach Symbol sortiert; leer ohne Datei.
    func bestand() -> [Kerzenbestand] {
        guard let daten = try? Data(contentsOf: bestandsdatei),
              let inhalt = try? Self.decoder.decode(Bestandsdatei.self, from: daten),
              inhalt.format == Self.format else { return [] }
        return inhalt.symbole.sorted { $0.symbol < $1.symbol }
    }

    /// Kerzen eines Symbols, die das Zeitfenster berühren, aufsteigend. Fehlende Monate sind keine Fehler.
    func kerzen(symbol: String, von: Date, bis: Date) -> [Zeitkerze] {
        guard bis >= von else { return [] }
        var ergebnis: [Zeitkerze] = []
        for monat in Self.monate(von: von, bis: bis) {
            guard let datei = lies(symbol: symbol, monat: monat) else { continue }
            ergebnis += datei.kerzen.filter { $0.ende > von && $0.beginn <= bis }
        }
        return ergebnis
    }

    /// Alle Kerzen eines UTC-Monats („2026-10“), aufsteigend; leer ohne Datei.
    func kerzen(symbol: String, monat: String) -> [Zeitkerze] {
        lies(symbol: symbol, monat: monat)?.kerzen ?? []
    }

    private func lies(symbol: String, monat: String) -> Monatsdatei? {
        guard let daten = try? Data(contentsOf: monatsdatei(symbol: symbol, monat: monat)),
              let inhalt = try? Self.decoder.decode(Monatsdatei.self, from: daten),
              inhalt.format == Self.format, inhalt.symbol == symbol else { return nil }
        return inhalt
    }

    // MARK: Schreiben

    /// Übernimmt Kerzen eines Symbols. Gespeicherte Kerzen, die in `fenster` beginnen (Ende ausgeschlossen), werden durch die neuen
    /// ersetzt (ein erneuter Abruf oder Import desselben Zeitraums ersetzt den alten, auch wenn er weniger Kerzen
    /// liefert); außerhalb bleibt alles stehen. Ohne `fenster` gilt die Spanne der neuen Kerzen.
    /// Bei gleichem Beginn gilt die neue Kerze. Feinere gespeicherte Kerzen bleiben stehen: Ein Stundenexport
    /// über Monate mit Minutenkursen ersetzt diese nicht, seine Kerzen fallen dort weg, wo Minutenkerzen liegen.
    /// - Returns: der neue Stand des Symbols, `nil`, wenn danach keine Kerze mehr gespeichert ist.
    @discardableResult
    func speichere(_ neue: [Zeitkerze], symbol: String, quelle: String, fenster: DateInterval? = nil) throws -> Kerzenbestand? {
        let gueltig = neue.filter { $0.dauer > 0 }
        let spanne: DateInterval
        if let fenster {
            spanne = fenster
        } else if let erste = gueltig.map(\.beginn).min(), let letzte = gueltig.map(\.beginn).max() {
            spanne = DateInterval(start: erste, end: letzte.addingTimeInterval(1))
        } else {
            return bestand().first { $0.symbol == symbol }
        }
        let neueDauer = gueltig.map(\.dauer).min() ?? 0
        var jeMonat: [String: [Zeitkerze]] = [:]
        for kerze in gueltig { jeMonat[Self.monat(kerze.beginn), default: []].append(kerze) }
        let betroffen = Set(Self.monate(von: spanne.start, bis: spanne.end)).union(jeMonat.keys)

        try FileManager.default.createDirectory(at: symbolordner(symbol), withIntermediateDirectories: true)
        for monat in betroffen.sorted() {
            let alt = lies(symbol: symbol, monat: monat)
            var jeBeginn: [Date: Zeitkerze] = [:]
            var feiner: [Zeitkerze] = []
            for kerze in alt?.kerzen ?? [] {
                let imFenster = kerze.beginn >= spanne.start && kerze.beginn < spanne.end
                if !imFenster {
                    jeBeginn[kerze.beginn] = kerze
                } else if kerze.dauer < neueDauer {
                    jeBeginn[kerze.beginn] = kerze
                    feiner.append(kerze)
                }
            }
            let dazu = (jeMonat[monat] ?? []).filter { !Self.ueberdeckt($0, von: feiner) }
            for kerze in dazu { jeBeginn[kerze.beginn] = kerze }
            let datei = monatsdatei(symbol: symbol, monat: monat)
            guard !jeBeginn.isEmpty else {
                try? FileManager.default.removeItem(at: datei)
                continue
            }
            var quellen = alt?.quellen ?? []
            if !dazu.isEmpty, !quellen.contains(quelle) { quellen.append(quelle) }
            let inhalt = Monatsdatei(format: Self.format, symbol: symbol, monat: monat, quellen: quellen,
                                     kerzen: jeBeginn.values.sorted { $0.beginn < $1.beginn })
            try Self.encoder.encode(inhalt).write(to: datei, options: .atomic)
        }
        return try aktualisiereBestand(symbol: symbol)
    }

    /// Ob eine Kerze eine der feineren (aufsteigend sortierten) Kerzen zeitlich berührt.
    static func ueberdeckt(_ kerze: Zeitkerze, von feiner: [Zeitkerze]) -> Bool {
        var unten = 0
        var oben = feiner.count
        while unten < oben {
            let mitte = (unten + oben) / 2
            if feiner[mitte].ende <= kerze.beginn { unten = mitte + 1 } else { oben = mitte }
        }
        return unten < feiner.count && feiner[unten].beginn < kerze.ende
    }

    /// Löscht alle Kerzen eines Symbols.
    func loesche(symbol: String) throws {
        let ordner = symbolordner(symbol)
        if FileManager.default.fileExists(atPath: ordner.path) {
            try FileManager.default.removeItem(at: ordner)
        }
        _ = try aktualisiereBestand(symbol: symbol)
    }

    /// Zählt die Monatsdateien eines Symbols neu aus und schreibt `bestand.json`.
    private func aktualisiereBestand(symbol: String) throws -> Kerzenbestand? {
        var symbole = bestand().filter { $0.symbol != symbol }
        let dateien = ((try? FileManager.default.contentsOfDirectory(at: symbolordner(symbol),
                                                                      includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        var neu: Kerzenbestand?
        for monat in dateien {
            guard let datei = lies(symbol: symbol, monat: monat),
                  let erste = datei.kerzen.first, let letzte = datei.kerzen.last else { continue }
            let dauer = datei.kerzen.map(\.dauer).min() ?? erste.dauer
            if var stand = neu {
                stand.anzahl += datei.kerzen.count
                stand.von = min(stand.von, erste.beginn)
                stand.bis = max(stand.bis, letzte.ende)
                stand.kerzenDauer = min(stand.kerzenDauer, dauer)
                for q in datei.quellen where !stand.quellen.contains(q) { stand.quellen.append(q) }
                neu = stand
            } else {
                neu = Kerzenbestand(symbol: symbol, anzahl: datei.kerzen.count, von: erste.beginn, bis: letzte.ende,
                                    kerzenDauer: dauer, quellen: datei.quellen)
            }
        }
        if let neu { symbole.append(neu) }
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let inhalt = Bestandsdatei(format: Self.format, symbole: symbole.sorted { $0.symbol < $1.symbol })
        try Self.encoder.encode(inhalt).write(to: bestandsdatei, options: .atomic)
        return neu
    }

    // MARK: Pfade

    private var bestandsdatei: URL { ordner.appendingPathComponent("bestand.json") }

    private func symbolordner(_ symbol: String) -> URL {
        ordner.appendingPathComponent(Self.ordnername(symbol), isDirectory: true)
    }

    private func monatsdatei(symbol: String, monat: String) -> URL {
        symbolordner(symbol).appendingPathComponent(monat + ".json")
    }

    /// Umkehrbarer Ordnername: erlaubte Zeichen bleiben, alle anderen Bytes werden zu `~XX`.
    static func ordnername(_ symbol: String) -> String {
        var name = ""
        for byte in symbol.utf8 {
            let zeichen = Character(UnicodeScalar(byte))
            if byte < 0x80, zeichen.isLetter || zeichen.isNumber || zeichen == "." || zeichen == "-" || zeichen == "_" {
                name.append(zeichen)
            } else {
                name += String(format: "~%02X", byte)
            }
        }
        return name.isEmpty || name.hasPrefix(".") ? "~" + name : name
    }

    // MARK: Monate in UTC

    private static var utc: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return kalender
    }

    /// „2026-10“ für den UTC-Monat des Zeitpunkts.
    static func monat(_ datum: Date) -> String {
        let teile = utc.dateComponents([.year, .month], from: datum)
        return String(format: "%04d-%02d", teile.year ?? 0, teile.month ?? 0)
    }

    /// Alle UTC-Monate von `von` bis `bis`, beide eingeschlossen.
    static func monate(von: Date, bis: Date) -> [String] {
        let kalender = utc
        guard bis >= von, var tag = kalender.dateInterval(of: .month, for: von)?.start else { return [] }
        var ergebnis: [String] = []
        while tag <= bis, ergebnis.count < 1_200 {
            ergebnis.append(monat(tag))
            guard let weiter = kalender.date(byAdding: .month, value: 1, to: tag) else { break }
            tag = weiter
        }
        return ergebnis
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
