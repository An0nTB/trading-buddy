import Foundation

extension Side: Codable {}

/// Beträge und Kurse stehen als Text („-0.07“), damit sie exakt als `Decimal` zurückkommen.
/// Eine JSON-Zahl ginge beim Lesen über `Double` und könnte Stellen verlieren.
extension Trade: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, symbol, side, lots, openTime, closeTime, openPrice, closePrice
        case stopLoss, takeProfit, commission, swap, profit, taxes, produktart
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  symbol: try c.decode(String.self, forKey: .symbol),
                  side: try c.decode(Side.self, forKey: .side),
                  lots: try c.betrag(.lots),
                  openTime: try c.decode(Date.self, forKey: .openTime),
                  closeTime: try c.decode(Date.self, forKey: .closeTime),
                  openPrice: try c.betrag(.openPrice),
                  closePrice: try c.betrag(.closePrice),
                  stopLoss: try c.optionalerBetrag(.stopLoss),
                  takeProfit: try c.optionalerBetrag(.takeProfit),
                  commission: try c.betrag(.commission),
                  swap: try c.betrag(.swap),
                  profit: try c.betrag(.profit),
                  taxes: try c.optionalerBetrag(.taxes) ?? 0,
                  produktart: try c.decodeIfPresent(Produktart.self, forKey: .produktart) ?? .unbekannt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(side, forKey: .side)
        try c.encode(lots.description, forKey: .lots)
        try c.encode(openTime, forKey: .openTime)
        try c.encode(closeTime, forKey: .closeTime)
        try c.encode(openPrice.description, forKey: .openPrice)
        try c.encode(closePrice.description, forKey: .closePrice)
        try c.encodeIfPresent(stopLoss?.description, forKey: .stopLoss)
        try c.encodeIfPresent(takeProfit?.description, forKey: .takeProfit)
        try c.encode(commission.description, forKey: .commission)
        try c.encode(swap.description, forKey: .swap)
        try c.encode(profit.description, forKey: .profit)
        // Nur wenn vorhanden: Exporte ohne Steuern bleiben für ältere Connector-Versionen gleich.
        if taxes != 0 { try c.encode(taxes.description, forKey: .taxes) }
        // Ebenso: `unbekannt` fehlt im Export; ältere Leser ignorieren das neue Feld.
        if produktart != .unbekannt { try c.encode(produktart, forKey: .produktart) }
    }
}

extension KeyedDecodingContainer {
    fileprivate func betrag(_ key: Key) throws -> Decimal {
        let text = try decode(String.self, forKey: key)
        guard let wert = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Kein Betrag: \(text)")
        }
        return wert
    }

    fileprivate func optionalerBetrag(_ key: Key) throws -> Decimal? {
        try decodeIfPresent(String.self, forKey: key) == nil ? nil : betrag(key)
    }
}
