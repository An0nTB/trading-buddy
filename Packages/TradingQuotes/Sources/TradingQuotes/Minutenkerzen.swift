import Foundation
import TradingCore

/// Liefert Minutenkerzen für ein Zeitfenster, für die Ausstiegsanalyse (Doc 39, Paket B2). Nur Abruf, keine Ablage:
/// Den Zwischenspeicher je Trade führt die App (App/Sources/Ausstieg/).
public protocol Minutenquelle: Sendable {
    /// Gleich der `Kursquelle.id` derselben Plattform, etwa "alpaca" oder "binance".
    var id: String { get }
    /// Kerzen mit Beginn in `von ..< bis`, älteste zuerst, Länge 60 Sekunden.
    func minutenkerzen(_ quellSymbol: String, von: Date, bis: Date) async throws -> [Zeitkerze]
}

/// Holt Minutenkerzen für ein Journal-Symbol: wählt die Quelle (US-Aktien Alpaca, Krypto Binance), prüft das
/// Zeitfenster und lässt nur abgeschlossene Kerzen durch.
public struct Minutenlader: Sendable {
    public let quellen: [String: any Minutenquelle]
    /// Längstes Zeitfenster je Abruf. 31 Tage sind rund 45.000 Kerzen bei Krypto (45 Abrufe bei Binance);
    /// längere Trades braucht die Ausstiegsanalyse nicht minutengenau (Festlegung B2, Standardwert).
    public static let hoechstdauer: TimeInterval = 31 * 86_400

    public init(quellen: [any Minutenquelle]) {
        var nachID: [String: any Minutenquelle] = [:]
        for quelle in quellen { nachID[quelle.id] = quelle }
        self.quellen = nachID
    }

    /// Fenster um einen Trade: eine Minute vor dem Einstieg bis `nachlauf` nach dem Ausstieg, auf volle Minuten.
    /// `nachlauf` wie `Ausstiegsanalyse(trade:kerzen:nachlauf:)`. `nil` für Trades ohne Uhrzeit (`nurDatum`).
    public static func fenster(_ trade: Trade, nachlauf: TimeInterval = 3_600) -> (von: Date, bis: Date)? {
        guard !trade.nurDatum, trade.closeTime >= trade.openTime else { return nil }
        let von = minute(trade.openTime.addingTimeInterval(-60))
        let bis = minute(trade.closeTime.addingTimeInterval(nachlauf + 59))
        return (von, bis)
    }

    static func minute(_ zeit: Date) -> Date {
        Date(timeIntervalSince1970: (zeit.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    /// Kerzen für `zuordnung` (aus `Minutenlader.zuordnung`) mit Beginn in `von ..< bis`.
    /// Kerzen, die bei `jetzt` noch laufen, fehlen: Ihr Hoch und Tief steht noch nicht fest.
    public func lade(_ zuordnung: Kurszuordnung, von: Date, bis: Date, jetzt: Date = Date()) async throws -> [Zeitkerze] {
        guard let quelle = quellen[zuordnung.quelle] else {
            throw Verlaufsfehler.anbieter("Für \(zuordnung.quelle) gibt es keine Minutenkerzen.")
        }
        guard bis > von else { return [] }
        guard bis.timeIntervalSince(von) <= Self.hoechstdauer else {
            throw Verlaufsfehler.anbieter("Zeitfenster länger als 31 Tage")
        }
        let ende = min(bis, jetzt)
        guard ende > von else { return [] }
        let roh = try await quelle.minutenkerzen(zuordnung.quellSymbol, von: von, bis: ende)
        var jeBeginn: [Date: Zeitkerze] = [:]
        for k in roh where k.beginn >= von && k.beginn < bis && k.ende <= jetzt { jeBeginn[k.beginn] = k }
        return jeBeginn.values.sorted { $0.beginn < $1.beginn }
    }

    /// Quelle für Minutenkerzen zu einem Journal-Symbol, oder `nil` ohne freie Quelle (CFD, Devisen, ISIN).
    /// Ausgangspunkt ist der Vorschlag für Echtzeitkurse; eine eigene Zuordnung des Nutzers geht über
    /// `zuordnung(aus:)`.
    public static func zuordnung(fuer journalSymbol: String) -> Kurszuordnung? {
        guard case .zuordnung(let z) = Kurszuordner.vorschlag(fuer: journalSymbol) else { return nil }
        return zuordnung(aus: z)
    }

    /// Alpaca bleibt Alpaca. Krypto-Paare (Kraken, Coinbase, Binance) gehen an Binance, weil Kraken nur die
    /// letzten 720 Minuten liefert (Doc 39). Binance führt kein USD: USD wird USDT, mit Hinweis.
    public static func zuordnung(aus z: Kurszuordnung) -> Kurszuordnung? {
        switch z.quelle {
        case "alpaca":
            return z
        case "kraken", "coinbase", "binance":
            guard let paar = Kurszuordner.kryptoPaar(z.quellSymbol.uppercased()) else { return nil }
            let gegen = paar.gegen == "USD" ? "USDT" : paar.gegen
            var hinweise: [String] = []
            if let naeherung = z.naeherung { hinweise.append(naeherung.replacingOccurrences(of: "Kraken", with: "Binance")) }
            if paar.gegen == "USD" { hinweise.append("Kurs in USDT statt USD (Binance führt kein USD).") }
            return Kurszuordnung(journalSymbol: z.journalSymbol, quelle: "binance", quellSymbol: paar.basis + gegen,
                                 naeherung: hinweise.isEmpty ? nil : hinweise.joined(separator: " "))
        default:
            return nil
        }
    }
}

public enum Minutenkerzen {
    /// Lader mit Alpaca (US-Aktien, Schlüssel aus dem Schlüsselbund) und Binance (Krypto, ohne Schlüssel).
    public static func lader(schluessel: any AlpacaSchluesselquelle,
                             abruf: @escaping Abruf = Kursverlaeufe.urlSession) -> Minutenlader {
        Minutenlader(quellen: [AlpacaMinuten(schluessel: schluessel, abruf: abruf), BinanceMinuten(abruf: abruf)])
    }
}
