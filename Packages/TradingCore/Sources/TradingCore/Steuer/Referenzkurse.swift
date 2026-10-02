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
        kurs(waehrung, am: am, zeitzone: zeitzone).map { betrag / $0 }
    }

    /// Betrag von einer Währung in eine andere über den Euro, beide Kurse wie bei `inEuro`.
    /// Gleiche Währung (auch USDT und USD) bleibt unverändert; `nil`, wenn ein Kurs fehlt.
    public func umrechnen(_ betrag: Decimal, von: String, nach: String, am: Date,
                          zeitzone: TimeZone = Steuerorientierung.deutscheZeit) -> Decimal? {
        let quelle = Self.code(von)
        let ziel = Self.code(nach)
        if quelle == ziel { return betrag }
        guard let vonKurs = kurs(quelle, am: am, zeitzone: zeitzone),
              let nachKurs = kurs(ziel, am: am, zeitzone: zeitzone) else { return nil }
        return betrag / vonKurs * nachKurs
    }

    /// Einheiten `waehrung` je 1 Euro am oder vor dem Kalendertag; Euro ist 1.
    private func kurs(_ waehrung: String, am: Date, zeitzone: TimeZone) -> Decimal? {
        let code = Self.code(waehrung)
        if code == "EUR" { return 1 }
        let k = Steuerorientierung.kalender(in: zeitzone)
        for zurueck in 0...Self.hoechstensTageZurueck {
            guard let zeit = k.date(byAdding: .day, value: -zurueck, to: am) else { return nil }
            if let kurs = kurse[Journaltag(zeit, zeitzone: zeitzone)]?[code] { return kurs }
        }
        return nil
    }

    private static func code(_ waehrung: String) -> String {
        let gross = waehrung.uppercased()
        return gleichgesetzt[gross] ?? gross
    }
}
