import Foundation

/// Kerze mit Uhrzeit (Minute, Stunde) für die Ausstiegsanalyse (Doc 39, F7). Kurse in der Kurswährung
/// des Trades; bei MetaTrader der Geldkurs (Bid) des Brokers. Codable mit Kursen als Text wie `Kerze`.
public struct Zeitkerze: Sendable, Equatable, Codable {
    public var beginn: Date
    /// Länge der Kerze in Sekunden, 60 bei Minutenkerzen.
    public var dauer: Int
    public var open: Decimal
    public var high: Decimal
    public var low: Decimal
    public var close: Decimal

    public init(beginn: Date, dauer: Int, open: Decimal, high: Decimal, low: Decimal, close: Decimal) {
        self.beginn = beginn
        self.dauer = dauer
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }

    public var ende: Date { beginn.addingTimeInterval(TimeInterval(dauer)) }

    private enum CodingKeys: String, CodingKey {
        case beginn, dauer, open, high, low, close
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
        self.init(beginn: try c.decode(Date.self, forKey: .beginn), dauer: try c.decode(Int.self, forKey: .dauer),
                  open: try kurs(.open), high: try kurs(.high), low: try kurs(.low), close: try kurs(.close))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(beginn, forKey: .beginn)
        try c.encode(dauer, forKey: .dauer)
        try c.encode(open.description, forKey: .open)
        try c.encode(high.description, forKey: .high)
        try c.encode(low.description, forKey: .low)
        try c.encode(close.description, forKey: .close)
    }
}

/// Wie weit lief ein Trade gegen und für den Händler (MAE und MFE), und was geschah nach dem Ausstieg.
/// Nur beschreibend: Rückblick auf vergangene Kurse, keine Aussage über künftige.
/// Abstände in Kurspunkten, immer positiv; `…Anteil` bezogen auf den Einstiegskurs, `…R` auf den Stop-Abstand.
public struct Ausstiegsanalyse: Sendable, Equatable {
    public var tradeID: String
    public var ergebnis: Trade.Outcome
    /// Länge der kürzesten genutzten Kerze in Sekunden.
    public var kerzenDauer: Int
    public var anzahlKerzen: Int
    /// Anteil der Haltedauer, den Kerzen abdecken, auf 2 Stellen; unter 1 bei Lücken (Wochenende, Datenlücke).
    public var abdeckung: Decimal
    /// Erste oder letzte Kerze reicht mehr als eine Minute über Ein- oder Ausstieg hinaus (Stunden-, Tageskerzen).
    /// Hoch und Tief können dann von Kursen vor dem Einstieg oder nach dem Ausstieg stammen:
    /// MAE und MFE sind eher zu groß. Bei Minutenkerzen ist die Minute die Auflösung.
    public var unscharf: Bool

    /// Größter Abstand gegen den Trade (Maximum Adverse Excursion), mindestens der Verlust beim Ausstieg.
    public var mae: Decimal
    /// Größter Abstand für den Trade (Maximum Favorable Excursion), mindestens der Gewinn beim Ausstieg.
    public var mfe: Decimal
    /// Kursbewegung bis zum Ausstieg in Richtung des Trades, negativ bei Verlust.
    public var erzielt: Decimal
    public var maeAnteil: Decimal
    public var mfeAnteil: Decimal
    /// Nur mit Stop auf der Verlustseite. Bei MetaTrader ist der Stop der letzte Stand, nicht zwingend der erste.
    public var maeR: Decimal?
    public var mfeR: Decimal?
    /// Erzielt ÷ MFE: 1 heißt am besten Kurs ausgestiegen, negativ heißt trotz Plus im Verlauf mit Verlust.
    /// `nil`, wenn der Trade nie im Plus war.
    public var effizienz: Decimal?
    /// (MFE − erzielt) × Wert je Kurspunkt in der Währung des Trades, vor Kosten.
    /// `nil` ohne Kursbewegung, weil der Wert je Kurspunkt dann unbekannt ist (wie bei `Trade.stopRisiko`).
    public var liegengelassen: Decimal?
    /// Beginn der Kerze mit dem schlechtesten bzw. besten Kurs; `nil`, wenn es der Ausstieg selbst war.
    public var zeitMAE: Date?
    public var zeitMFE: Date?
    /// Weitere Bewegung in Richtung des Trades bzw. dagegen innerhalb von `nachlauf` nach dem Ausstieg,
    /// gemessen vom Ausstiegskurs. `nil` ohne Kerzen nach dem Ausstieg.
    public var nachAusstiegFuer: Decimal?
    public var nachAusstiegGegen: Decimal?

    /// `nil` bei Trades ohne Uhrzeit (`nurDatum`), ohne Einstiegskurs oder ohne Kerze in der Haltedauer.
    /// - Parameters:
    ///   - kerzen: beliebig sortiert; doppelte Kerzen (gleicher Beginn) zählen einmal, die letzte gilt.
    ///   - nachlauf: Sekunden nach dem Ausstieg für `nachAusstieg…`.
    public init?(trade: Trade, kerzen: [Zeitkerze], nachlauf: TimeInterval = 3_600) {
        guard !trade.nurDatum, trade.openPrice > 0, trade.closeTime >= trade.openTime else { return nil }
        var jeBeginn: [Date: Zeitkerze] = [:]
        for k in kerzen where k.dauer > 0 { jeBeginn[k.beginn] = k }
        let sortiert = jeBeginn.values.sorted { $0.beginn < $1.beginn }
        let imTrade = sortiert.filter {
            $0.ende > trade.openTime && ($0.beginn < trade.closeTime || $0.beginn == trade.openTime)
        }
        guard let erste = imTrade.first, let letzte = imTrade.last else { return nil }

        let kauf = trade.side == .buy
        /// Bewegung von `kurs` aus Sicht des Trades, gemessen ab `basis`.
        func fuer(_ kurs: Decimal, ab basis: Decimal) -> Decimal { kauf ? kurs - basis : basis - kurs }
        func bestes(_ k: Zeitkerze) -> Decimal { kauf ? k.high : k.low }
        func schlechtestes(_ k: Zeitkerze) -> Decimal { kauf ? k.low : k.high }

        tradeID = trade.id
        ergebnis = trade.outcome
        kerzenDauer = imTrade.map(\.dauer).min() ?? erste.dauer
        anzahlKerzen = imTrade.count
        unscharf = trade.openTime.timeIntervalSince(erste.beginn) > 60
            || letzte.ende.timeIntervalSince(trade.closeTime) > 60

        let halten = trade.holdingTime
        if halten > 0 {
            let gedeckt = imTrade.reduce(0.0) { summe, k in
                summe + max(0, min(k.ende, trade.closeTime).timeIntervalSince(max(k.beginn, trade.openTime)))
            }
            abdeckung = Decimal(min(1, gedeckt / halten)).gerundet(2)
        } else {
            abdeckung = 1
        }

        let erzielt = fuer(trade.closePrice, ab: trade.openPrice)
        self.erzielt = erzielt
        var mfe = max(0, erzielt)
        var mae = max(0, -erzielt)
        var zeitMFE: Date?
        var zeitMAE: Date?
        for k in imTrade {
            let plus = fuer(bestes(k), ab: trade.openPrice)
            let minus = -fuer(schlechtestes(k), ab: trade.openPrice)
            if plus > mfe { mfe = plus; zeitMFE = k.beginn }
            if minus > mae { mae = minus; zeitMAE = k.beginn }
        }
        self.mfe = mfe
        self.mae = mae
        self.zeitMFE = zeitMFE
        self.zeitMAE = zeitMAE
        maeAnteil = mae / trade.openPrice
        mfeAnteil = mfe / trade.openPrice

        let stopAbstand = trade.stopLoss.map { fuer(trade.openPrice, ab: $0) }
        if let stopAbstand, stopAbstand > 0 {
            maeR = mae / stopAbstand
            mfeR = mfe / stopAbstand
        } else {
            maeR = nil
            mfeR = nil
        }
        effizienz = mfe > 0 ? erzielt / mfe : nil
        let wertJePunkt = erzielt != 0 ? trade.profit / erzielt : 0
        liegengelassen = wertJePunkt > 0 ? (mfe - erzielt) * wertJePunkt : nil

        let danach = sortiert.filter {
            $0.beginn >= trade.closeTime && $0.beginn < trade.closeTime.addingTimeInterval(nachlauf)
        }
        if danach.isEmpty {
            nachAusstiegFuer = nil
            nachAusstiegGegen = nil
        } else {
            nachAusstiegFuer = max(0, danach.map { fuer(bestes($0), ab: trade.closePrice) }.max()!)
            nachAusstiegGegen = max(0, danach.map { -fuer(schlechtestes($0), ab: trade.closePrice) }.max()!)
        }
    }
}

/// Zusammenfassung mehrerer Ausstiegsanalysen, nur beschreibend. Mediane statt Mittelwerte,
/// weil einzelne Ausreißer (Nachrichten, Kurslücken) sonst das Bild bestimmen.
public struct Ausstiegsauswertung: Sendable, Equatable {
    public var anzahl: Int
    public var anzahlUnscharf: Int
    public var medianEffizienz: Decimal?
    /// Wie weit liefen Gewinner zwischendurch gegen den Händler, in R: Hinweis auf den nötigen Stop-Abstand.
    public var medianMaeRGewinner: Decimal?
    public var medianMfeR: Decimal?
    /// Verlierer, die zwischendurch mindestens 1 R im Plus lagen.
    public var verliererMitEinemRPlus: Int
    /// Verlierer mit bekanntem R, Grundmenge für `verliererMitEinemRPlus`.
    public var verliererMitR: Int
    /// Summe `liegengelassen`, nur zulässig bei einer gemeinsamen Währung; sonst `nil`.
    public var summeLiegengelassen: Decimal?

    /// - Parameter gleicheWaehrung: Die Trades lauten alle auf eine Währung; nur dann gibt es eine Summe.
    public init(_ analysen: [Ausstiegsanalyse], gleicheWaehrung: Bool) {
        anzahl = analysen.count
        anzahlUnscharf = analysen.filter(\.unscharf).count
        medianEffizienz = Self.median(analysen.compactMap(\.effizienz))
        medianMaeRGewinner = Self.median(analysen.filter { $0.ergebnis == .win }.compactMap(\.maeR))
        medianMfeR = Self.median(analysen.compactMap(\.mfeR))
        let verlierer = analysen.filter { $0.ergebnis == .loss && $0.mfeR != nil }
        verliererMitR = verlierer.count
        verliererMitEinemRPlus = verlierer.filter { $0.mfeR! >= 1 }.count
        let betraege = analysen.compactMap(\.liegengelassen)
        summeLiegengelassen = gleicheWaehrung && !betraege.isEmpty ? betraege.reduce(0, +) : nil
    }

    static func median(_ werte: [Decimal]) -> Decimal? { Fehlermuster.median(werte) }
}
