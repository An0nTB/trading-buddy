import Foundation

/// Tageskurse zur Umrechnung in Euro, z. B. EZB-Referenzkurse (Doc 22, Lücke „Krypto in USD/USDT“).
/// Notation wie bei der EZB: Einheiten Fremdwährung je 1 Euro. Laden und Zwischenspeichern macht
/// TradingRates; der Kern rechnet nur um und kennt keine Quelle.
public struct Referenzkurse: Sendable, Equatable {
    /// Kurse je Kalendertag, Währung in Großbuchstaben.
    public var kurse: [Journaltag: [String: Decimal]]
    /// So viele Tage sucht `inEuro` höchstens zurück (Wochenenden, Feiertage ohne Kurs).
    public static let hoechstensTageZurueck = 7
    /// Währungen, die wie eine andere umgerechnet werden. USDT wie USD (Einschätzung, keine EZB-Notierung).
    public static let gleichgesetzt = ["USDT": "USD"]

    public init(kurse: [Journaltag: [String: Decimal]]) {
        var gross: [Journaltag: [String: Decimal]] = [:]
        for (tag, liste) in kurse {
            for (waehrung, kurs) in liste where kurs > 0 { gross[tag, default: [:]][waehrung.uppercased()] = kurs }
        }
        self.kurse = gross
    }

    /// Betrag in Euro mit dem letzten Kurs am oder vor dem Kalendertag von `am` in `zeitzone`.
    /// Euro bleibt unverändert; `nil`, wenn innerhalb von `hoechstensTageZurueck` Tagen kein Kurs vorliegt.
    public func inEuro(_ betrag: Decimal, waehrung: String, am: Date,
                       zeitzone: TimeZone = Steuerorientierung.deutscheZeit) -> Decimal? {
        let gross = waehrung.uppercased()
        if gross == "EUR" { return betrag }
        let code = Self.gleichgesetzt[gross] ?? gross
        let k = Steuerorientierung.kalender(in: zeitzone)
        for zurueck in 0...Self.hoechstensTageZurueck {
            guard let zeit = k.date(byAdding: .day, value: -zurueck, to: am) else { return nil }
            if let kurs = kurse[Journaltag(zeit, zeitzone: zeitzone)]?[code] { return betrag / kurs }
        }
        return nil
    }
}
