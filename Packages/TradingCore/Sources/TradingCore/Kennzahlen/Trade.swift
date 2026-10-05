import Foundation

/// Abgeschlossener Trade, unabhängig vom Broker. Grundlage aller Kennzahlen.
/// Beträge in `waehrung`, ohne Angabe in Kontowährung; Zeiten in UTC.
public struct Trade: Sendable, Equatable, Identifiable {
    public var id: String
    public var symbol: String
    public var side: Side
    public var lots: Decimal
    public var openTime: Date
    public var closeTime: Date
    public var openPrice: Decimal
    public var closePrice: Decimal
    /// Stop laut Export. Bei MetaTrader der letzte Stand, nicht zwingend der beim Einstieg.
    public var stopLoss: Decimal?
    /// Geplantes Risiko (1 R) in Kontowährung, positiv, für Trades ohne brauchbaren Stop (Scalable,
    /// Trade Republic). Ohne Angabe `nil`, kein init-Parameter; setzen per Kopie oder `mitGeplantemRisiko(_:)`.
    public var geplantesRisiko: Decimal?
    public var takeProfit: Decimal?
    public var commission: Decimal
    public var swap: Decimal
    /// Kursergebnis ohne Kosten.
    public var profit: Decimal
    /// Abgeführte oder erstattete Steuern (Trade Republic, Scalable); bei MetaTrader 0.
    public var taxes: Decimal
    public var produktart: Produktart
    /// Kauf oder Verkauf nur mit Datum gebucht (Trade Republic, Scalable): Uhrzeit und Haltedauer sind
    /// dann nicht bekannt; Stunden- und Haltedauer-Auswertungen lassen solche Trades aus.
    public var nurDatum: Bool
    /// Währung der Beträge, wenn sie von der Kontowährung abweichen kann (Positionsbildung aus Ausführungen,
    /// z. B. BTC/USD auf einem Euro-Konto). `nil` heißt Kontowährung (MetaTrader, XTB).
    public var waehrung: String?
    /// Basiswert eines Hebelprodukts („Nasdaq 100“), erkannt am Namen (`Hebelprodukt`). `symbol` bleibt der
    /// volle Name des Scheins; `nil` bei allem anderen.
    public var basiswert: String?
    /// Markterwartung eines Hebelprodukts: `.sell` bei Short und Put. `side` bleibt `.buy`, weil der Schein
    /// gekauft wird und das Ergebnis so stimmt. `nil` bei allem anderen.
    public var markterwartung: Side?

    public init(id: String, symbol: String, side: Side, lots: Decimal, openTime: Date, closeTime: Date,
                openPrice: Decimal, closePrice: Decimal, stopLoss: Decimal? = nil, takeProfit: Decimal? = nil,
                commission: Decimal = 0, swap: Decimal = 0, profit: Decimal, taxes: Decimal = 0,
                produktart: Produktart = .unbekannt, nurDatum: Bool = false, waehrung: String? = nil,
                basiswert: String? = nil, markterwartung: Side? = nil) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.lots = lots
        self.openTime = openTime
        self.closeTime = closeTime
        self.openPrice = openPrice
        self.closePrice = closePrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.commission = commission
        self.swap = swap
        self.profit = profit
        self.taxes = taxes
        self.produktart = produktart
        self.nurDatum = nurDatum
        self.waehrung = waehrung?.uppercased()
        self.basiswert = basiswert
        self.markterwartung = markterwartung
    }

    /// Währung der Beträge in Großbuchstaben, ohne eigene Angabe die Kontowährung.
    public func waehrung(kontowaehrung: String) -> String { waehrung ?? kontowaehrung.uppercased() }

    public init(_ p: ClosedPosition) {
        self.init(id: p.ticket, symbol: p.symbol, side: p.side, lots: p.lots, openTime: p.openTime,
                  closeTime: p.closeTime, openPrice: p.openPrice, closePrice: p.closePrice,
                  stopLoss: p.stopLoss, takeProfit: p.takeProfit, commission: p.commission,
                  swap: p.swap, profit: p.profit, produktart: p.produktart)
    }

    /// Kosten (Kommission, Swap und Steuern), meist negativ.
    public var costs: Decimal { commission + swap + taxes }
    /// Ergebnis nach Kosten. Alle Kennzahlen rechnen damit.
    public var netProfit: Decimal { profit + costs }
    public var holdingTime: TimeInterval { closeTime.timeIntervalSince(openTime) }

    public enum Outcome: Sendable, Equatable {
        case win, loss, breakeven
    }

    public var outcome: Outcome {
        netProfit > 0 ? .win : (netProfit < 0 ? .loss : .breakeven)
    }

    /// Gleiche Eröffnung (Symbol, Richtung, Eröffnungszeit): Teilverkäufe einer Position ergeben mehrere
    /// Trades mit diesem Schlüssel und zählen für „Trades je Tag“ als einer. Ohne Uhrzeit fallen zwei
    /// getrennte Käufe desselben Werts am selben Tag zusammen (Näherung).
    var positionsschluessel: String {
        "\(symbol)|\(side)|\(openTime.timeIntervalSinceReferenceDate)"
    }

    /// Risiko (1 R) aus dem Stop in Kontowährung: Abstand Einstieg bis Stop mal Wert je Kurspunkt.
    /// Der Wert je Kurspunkt kommt aus dem Trade selbst (Kursergebnis ÷ Kursbewegung),
    /// so braucht es keine Kontraktgrößen je Instrument.
    /// `nil` ohne Stop, bei Stop auf der Gewinnseite (nachgezogen) oder ohne Kursbewegung.
    /// Kennzahlen rechnen mit `risk`, das ohne solchen Wert auf `geplantesRisiko` zurückfällt.
    public var stopRisiko: Decimal? {
        guard let stop = stopLoss else { return nil }
        let abstand = side == .buy ? openPrice - stop : stop - openPrice
        let bewegung = side == .buy ? closePrice - openPrice : openPrice - closePrice
        guard abstand > 0, bewegung != 0 else { return nil }
        let wertJePunkt = profit / bewegung
        guard wertJePunkt > 0 else { return nil }
        return abstand * wertJePunkt
    }

    /// Ergebnis nach Kosten in Vielfachen des Risikos. `nil`, wenn das Risiko unbekannt ist.
    public var rMultiple: Decimal? {
        guard let risk else { return nil }
        return netProfit / risk
    }

    /// Wurde `self` sicher geschlossen, bevor `t` eröffnet wurde? Ohne Uhrzeit (`nurDatum`) auf einer
    /// der beiden Seiten zählt nur ein früherer Kalendertag, weil die Reihenfolge am selben Tag unbekannt ist.
    func sicherGeschlossen(vor t: Trade, kalender: Calendar) -> Bool {
        guard id != t.id, closeTime <= t.openTime else { return false }
        guard nurDatum || t.nurDatum else { return true }
        return schlusstag(kalender) < t.eroeffnungstag(kalender)
    }

    /// Beginn des Eröffnungstags im Kalender des Nutzers; siehe `tagesbeginn`.
    public func eroeffnungstag(_ kalender: Calendar) -> Date {
        Self.tagesbeginn(openTime, nurDatum: nurDatum, kalender: kalender)
    }

    /// Beginn des Schlusstags im Kalender des Nutzers; siehe `tagesbeginn`.
    public func schlusstag(_ kalender: Calendar) -> Date {
        Self.tagesbeginn(closeTime, nurDatum: nurDatum, kalender: kalender)
    }

    /// Tagesbeginn eines Zeitpunkts. Buchungen nur mit Datum (Trade Republic, Scalable) stehen auf 00:00 UTC;
    /// westlich von UTC fielen sie damit auf den Vortag. Ein solcher Zeitpunkt zählt deshalb mit seinem
    /// UTC-Datum. Zeitpunkte mit Uhrzeit bleiben beim Kalendertag des Nutzers (Zweiter Gegencheck, Doc 40).
    public static func tagesbeginn(_ zeit: Date, nurDatum: Bool, kalender: Calendar) -> Date {
        guard nurDatum, zeit.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0 else {
            return kalender.startOfDay(for: zeit)
        }
        let tag = Journaltag(zeit, zeitzone: TimeZone(secondsFromGMT: 0)!)
        // Mittag statt Mitternacht: In Zeitzonen mit Umstellung um 0 Uhr gibt es Mitternacht nicht an jedem Tag.
        let mittag = kalender.date(from: DateComponents(year: tag.jahr, month: tag.monat, day: tag.tag, hour: 12))!
        return kalender.startOfDay(for: mittag)
    }
}

extension Decimal {
    /// Kaufmännisch gerundet auf `stellen` Nachkommastellen.
    public func gerundet(_ stellen: Int) -> Decimal {
        var wert = self
        var ergebnis = Decimal()
        NSDecimalRound(&ergebnis, &wert, stellen, .plain)
        return ergebnis
    }
}
