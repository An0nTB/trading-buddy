import Foundation

/// Verlusttopf nach Rechtsstand 2026 (Doc 22). Orientierung, keine Steuerberechnung.
/// Seit dem Jahressteuergesetz 2024 gibt es keinen eigenen Topf für Termingeschäfte mehr; sie laufen
/// im allgemeinen Topf mit (EY 2025 zum BMF-Schreiben 14.05.2025). Aktienverluste sind nur mit
/// Aktiengewinnen verrechenbar (§ 20 Abs. 6 S. 4 EStG, BVerfG 2 BvL 3/21 anhängig, Stand 2026).
/// Krypto im Privatvermögen ist privates Veräußerungsgeschäft (§ 23 EStG) mit Haltefrist.
public enum Verlusttopf: String, Sendable, Equatable, Hashable, CaseIterable {
    case aktien
    case allgemein
    case krypto
    /// Produktart unbekannt oder sonstiges: die App fragt den Nutzer.
    case nichtZugeordnet

    public init(_ art: Produktart) {
        switch art {
        case .aktie: self = .aktien
        case .fonds, .anleihe, .derivat, .cfd: self = .allgemein
        case .krypto: self = .krypto
        case .sonstiges, .unbekannt: self = .nichtZugeordnet
        }
    }
}

/// Summen eines Topfs in einem Kalenderjahr, in Euro.
public struct Topfsumme: Sendable, Equatable {
    public var topf: Verlusttopf
    public var jahr: Int
    /// Summe der Trades mit positivem Ergebnis.
    public var gewinne: Decimal
    /// Summe der Trades mit negativem Ergebnis (negativ).
    public var verluste: Decimal
    /// Teilsumme aus CFDs (Termingeschäfte), nur zur Information.
    public var davonCFD: Decimal
    public var anzahl: Int
    /// Trades in einem Konto mit anderer Währung als Euro; nicht in den Summen.
    public var ohneEuro: Int

    public var saldo: Decimal { gewinne + verluste }

    public init(topf: Verlusttopf, jahr: Int, gewinne: Decimal = 0, verluste: Decimal = 0, davonCFD: Decimal = 0,
                anzahl: Int = 0, ohneEuro: Int = 0) {
        self.topf = topf
        self.jahr = jahr
        self.gewinne = gewinne
        self.verluste = verluste
        self.davonCFD = davonCFD
        self.anzahl = anzahl
        self.ohneEuro = ohneEuro
    }
}

public enum Steuerorientierung {
    /// Zeitzone für die Jahreszuordnung (Einschätzung: deutscher Kalendertag zählt).
    public static let deutscheZeit = TimeZone(identifier: "Europe/Berlin")!

    static func kalender(in zeitzone: TimeZone) -> Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        return kalender
    }

    /// Ergebnis für die Töpfe: Kursergebnis plus Kommission und Swap, ohne bereits abgeführte Steuern.
    public static func ergebnis(_ t: Trade) -> Decimal { t.profit + t.commission + t.swap }

    /// Summen je Topf für die Trades eines Kontos, nach Verkaufsjahr. Krypto-Trades zählen hier nur
    /// mit; Haltefrist und Freigrenze rechnet `KryptoHaltefrist`, weil ein Trade Lose mischen kann.
    /// Reihenfolge der Töpfe wie in `Verlusttopf.allCases`; leere Töpfe fehlen.
    public static func toepfe(_ trades: [Trade], kontowaehrung: String, jahr: Int,
                              zeitzone: TimeZone = Steuerorientierung.deutscheZeit) -> [Topfsumme] {
        let jahre = kalender(in: zeitzone)
        let imJahr = trades.filter { jahre.component(.year, from: $0.closeTime) == jahr }
        let euro = kontowaehrung.uppercased() == "EUR"
        var summen: [Verlusttopf: Topfsumme] = [:]
        for t in imJahr {
            let topf = Verlusttopf(t.produktart)
            var s = summen[topf] ?? Topfsumme(topf: topf, jahr: jahr)
            s.anzahl += 1
            if euro {
                let e = ergebnis(t)
                if e > 0 { s.gewinne += e } else { s.verluste += e }
                if t.produktart == .cfd { s.davonCFD += e }
            } else {
                s.ohneEuro += 1
            }
            summen[topf] = s
        }
        return Verlusttopf.allCases.compactMap { summen[$0] }
    }
}
