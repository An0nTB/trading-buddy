import Foundation

/// Tageskerze eines Werts in der Kurswährung seiner Reihe (Doc 38, Paket A2).
/// Codable mit Kursen als Text („101.25“), damit sie exakt als `Decimal` zurückkommen (wie `Trade`).
public struct Kerze: Sendable, Equatable, Codable {
    public var tag: Journaltag
    public var open: Decimal
    public var high: Decimal
    public var low: Decimal
    public var close: Decimal
    /// Fehlt bei Quellen ohne Volumen.
    public var volumen: Decimal?
    /// Der laufende Handelstag; `close` ist dann der letzte Kurs, nicht der Schluss. Im Export nur, wenn wahr.
    public var laufend: Bool

    public init(tag: Journaltag, open: Decimal, high: Decimal, low: Decimal, close: Decimal, volumen: Decimal? = nil,
                laufend: Bool = false) {
        self.tag = tag
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volumen = volumen
        self.laufend = laufend
    }

    private enum CodingKeys: String, CodingKey {
        case tag, open, high, low, close, volumen, laufend
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func kurs(_ key: CodingKeys) throws -> Decimal {
            let text = try c.decode(String.self, forKey: key)
            guard let wert = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Kein Kurs: \(text)")
            }
            return wert
        }
        self.init(tag: try c.decode(Journaltag.self, forKey: .tag), open: try kurs(.open), high: try kurs(.high),
                  low: try kurs(.low), close: try kurs(.close),
                  volumen: try c.decodeIfPresent(String.self, forKey: .volumen) == nil ? nil : kurs(.volumen),
                  laufend: try c.decodeIfPresent(Bool.self, forKey: .laufend) ?? false)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tag, forKey: .tag)
        try c.encode(open.description, forKey: .open)
        try c.encode(high.description, forKey: .high)
        try c.encode(low.description, forKey: .low)
        try c.encode(close.description, forKey: .close)
        try c.encodeIfPresent(volumen?.description, forKey: .volumen)
        if laufend { try c.encode(true, forKey: .laufend) }
    }
}

/// Beschreibende Kennzahlen aus Tageskerzen für „Frag Henry“ (Doc 38): keine Prognose, kein Signal.
/// Anteile wie `Kennzahlen.trefferquote` (0,05 heißt 5 %). Gerechnet wird nur mit abgeschlossenen Kerzen;
/// eine laufende Kerze erscheint nur als `aktuellerKurs`.
public struct Kursanalyse: Sendable, Equatable {
    /// Rückblick in Kalendertagen ab dem letzten Schluss.
    public enum Spanne: Int, Sendable, CaseIterable {
        case woche = 7, monat = 30, quartal = 91, jahr = 365
    }

    public var letzterTag: Journaltag
    public var letzterSchluss: Decimal
    /// Schluss gegen den letzten Schluss am oder vor dem Zieltag. Fehlt, wenn die Reihe später beginnt
    /// oder davor mehr als 7 Tage ohne Kerze liegen (Lücke in den Daten).
    public var veraenderung: [Spanne: Decimal]
    /// Standardabweichung der Tagesrenditen (Stichprobe) mal Wurzel aus `handelstageJeJahr`, auf 4 Stellen;
    /// über die ganze übergebene Reihe, ab 3 Kerzen.
    public var schwankungJahr: Decimal?
    public var handelstageJeJahr: Int
    /// Einfacher Durchschnitt der letzten 14 True Ranges in Kurswährung, ab 15 Kerzen.
    public var atr14: Decimal?
    public var atr14Anteil: Decimal?
    /// Schluss ÷ höchstes Hoch der letzten 365 Kalendertage − 1, also höchstens 0.
    public var abstandHoch52W: Decimal?
    /// Schluss ÷ tiefstes Tief der letzten 365 Kalendertage − 1, also mindestens 0.
    public var abstandTief52W: Decimal?
    /// Größter Rückgang der Schlusskurse vom bisherigen Hoch, positiv; über die ganze Reihe, ab 2 Kerzen.
    public var groessterRueckgang: Decimal?
    public var anzahlKerzen: Int
    /// Letzter Kurs des laufenden Tages, wenn die Reihe eine laufende Kerze nach dem letzten Schluss hat.
    public var aktuellerKurs: Decimal?

    /// `nil` ohne abgeschlossene Kerze oder ohne positiven letzten Schluss.
    /// Sortiert selbst; je Tag zählt die zuletzt übergebene Kerze.
    /// - Parameters:
    ///   - bis: nur Kerzen bis einschließlich dieses Tages.
    ///   - handelstageJeJahr: Hochrechnung der Schwankung; ohne Angabe 365, sobald eine Kerze auf ein Wochenende
    ///     fällt (Krypto), sonst 252 (Börse).
    public init?(kerzen: [Kerze], bis: Journaltag? = nil, handelstageJeJahr: Int? = nil) {
        var jeTag: [Journaltag: Kerze] = [:]
        for k in kerzen where bis.map({ k.tag <= $0 }) ?? true { jeTag[k.tag] = k }
        let alle = jeTag.values.sorted { $0.tag < $1.tag }
        let reihe = alle.filter { !$0.laufend }
        guard let letzte = reihe.last, letzte.close > 0 else { return nil }
        aktuellerKurs = alle.last.flatMap { $0.laufend && $0.tag > letzte.tag ? $0.close : nil }
        letzterTag = letzte.tag
        letzterSchluss = letzte.close
        anzahlKerzen = reihe.count

        veraenderung = [:]
        for spanne in Spanne.allCases {
            let ziel = letzte.tag.minus(tage: spanne.rawValue)
            guard let basis = reihe.last(where: { $0.tag <= ziel }), basis.tag > ziel.minus(tage: 7),
                  basis.close > 0 else { continue }
            veraenderung[spanne] = letzte.close / basis.close - 1
        }

        let tage = handelstageJeJahr ?? (reihe.contains { $0.tag.istWochenende } ? 365 : 252)
        self.handelstageJeJahr = tage
        let schluesse = reihe.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let renditen = zip(schluesse, schluesse.dropFirst()).compactMap { $0 > 0 ? $1 / $0 - 1 : nil }
        if renditen.count >= 2 {
            let mittel = renditen.reduce(0, +) / Double(renditen.count)
            let varianz = renditen.map { ($0 - mittel) * ($0 - mittel) }.reduce(0, +) / Double(renditen.count - 1)
            schwankungJahr = Decimal(varianz.squareRoot() * Double(tage).squareRoot()).gerundet(4)
        } else {
            schwankungJahr = nil
        }

        if reihe.count >= 15 {
            let letzte15 = Array(reihe.suffix(15))
            let spannen = zip(letzte15, letzte15.dropFirst()).map { (vorher: Kerze, k: Kerze) -> Decimal in
                max(k.high - k.low, abs(k.high - vorher.close), abs(k.low - vorher.close))
            }
            let atr = spannen.reduce(0, +) / 14
            atr14 = atr
            atr14Anteil = atr / letzte.close
        } else {
            atr14 = nil
            atr14Anteil = nil
        }

        let jahr = reihe.filter { $0.tag > letzte.tag.minus(tage: 365) }
        let hoch = jahr.map(\.high).max()
        let tief = jahr.map(\.low).min()
        abstandHoch52W = hoch.flatMap { $0 > 0 ? letzte.close / $0 - 1 : nil }
        abstandTief52W = tief.flatMap { $0 > 0 ? letzte.close / $0 - 1 : nil }

        if reihe.count >= 2 {
            var spitze = reihe[0].close
            var rueckgang: Decimal = 0
            for k in reihe {
                spitze = max(spitze, k.close)
                if spitze > 0 { rueckgang = max(rueckgang, 1 - k.close / spitze) }
            }
            groessterRueckgang = rueckgang
        } else {
            groessterRueckgang = nil
        }
    }
}

extension Journaltag {
    /// Kalendertag `tage` Tage vorher.
    fileprivate func minus(tage: Int) -> Journaltag {
        let utc = TimeZone(secondsFromGMT: 0)!
        let datum = Self.gregorianisch(utc).date(byAdding: .day, value: -tage, to: beginn(in: utc))!
        return Journaltag(datum, zeitzone: utc)
    }

    fileprivate var istWochenende: Bool {
        let utc = TimeZone(secondsFromGMT: 0)!
        let wochentag = Self.gregorianisch(utc).component(.weekday, from: beginn(in: utc))
        return wochentag == 1 || wochentag == 7
    }
}
