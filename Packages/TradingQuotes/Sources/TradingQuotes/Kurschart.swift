import Foundation

/// Zeitraum des Kurscharts, gezählt in Kalendertagen ab heute.
public enum Chartzeitraum: String, CaseIterable, Sendable, Identifiable {
    case monat, quartal, halbjahr, jahr

    public var id: String { rawValue }

    public var tage: Int {
        switch self {
        case .monat: 30
        case .quartal: 91
        case .halbjahr: 182
        case .jahr: 365
        }
    }
}

/// Ein- oder Ausstieg eines eigenen Trades im Chart. Die App bildet sie aus `Trade` (TradingCore).
public struct Chartmarke: Sendable, Equatable, Identifiable {
    public enum Art: String, Sendable { case einstieg, ausstieg }

    public var tradeID: String
    public var art: Art
    public var zeit: Date
    public var preis: Decimal
    /// Kauf (long) oder Verkauf (short).
    public var kauf: Bool
    /// Netto-Ergebnis des Trades, nur beim Ausstieg.
    public var ergebnis: Decimal?

    public var id: String { tradeID + "|" + art.rawValue }

    public init(tradeID: String, art: Art, zeit: Date, preis: Decimal, kauf: Bool, ergebnis: Decimal? = nil) {
        self.tradeID = tradeID
        self.art = art
        self.zeit = zeit
        self.preis = preis
        self.kauf = kauf
        self.ergebnis = ergebnis
    }
}

/// Eine Meldung auf der Zeitachse. Die App bildet sie aus `Meldung` (TradingNews).
public struct Chartmeldung: Sendable, Equatable, Identifiable {
    public var id: String
    public var zeit: Date
    public var titel: String
    public var quelle: String
    public var link: URL

    public init(id: String, zeit: Date, titel: String, quelle: String, link: URL) {
        self.id = id
        self.zeit = zeit
        self.titel = titel
        self.quelle = quelle
        self.link = link
    }
}

/// Meldungen, die in die Zeit einer Kerze fallen (am Wochenende bei Aktien: die Kerze davor).
public struct Nachrichtentag: Sendable, Equatable, Identifiable {
    /// `Tageskerze.zeit` der Kerze, an der die Meldungen stehen.
    public var tag: Date
    /// Neueste zuerst.
    public var meldungen: [Chartmeldung]

    public var id: Date { tag }
}

/// Alles, was der Kurschart zeigt: nur Kursdaten, eigene Trades und Meldungen, keine Signale (Doc 18).
public struct Kurschart: Sendable, Equatable {
    public var kerzen: [Tageskerze]
    /// Marken innerhalb des Zeitraums, deren Preis zum Kursbereich passt; älteste zuerst.
    public var marken: [Chartmarke]
    /// Marken im Zeitraum, deren Preis weit außerhalb der Kerzen liegt, etwa ein CFD-Kurs des Brokers in anderer
    /// Währung. Die App nennt nur die Anzahl, damit die Achse lesbar bleibt.
    public var ausserhalb: Int
    public var nachrichtentage: [Nachrichtentag]
    /// Bereich der Preisachse über Kerzen und Marken.
    public var tief: Decimal
    public var hoch: Decimal

    /// Die letzte Kerze ist der laufende Tag; ihr Schluss ist nur der letzte Stand.
    public var laufend: Bool { kerzen.last?.abgeschlossen == false }

    /// Weiter als ein Fünftel unter dem Tief oder über dem Hoch der Kerzen gilt eine Marke als unpassend.
    static let toleranz = Decimal(string: "0.2")!

    /// `nil`, wenn im Zeitraum keine Kerze liegt.
    public static func baue(_ verlauf: Kursverlauf, zeitraum: Chartzeitraum, marken: [Chartmarke],
                            meldungen: [Chartmeldung], jetzt: Date) -> Kurschart? {
        let von = jetzt.addingTimeInterval(-Double(zeitraum.tage) * 86_400)
        let kerzen = verlauf.kerzen.filter { $0.zeit >= von && $0.zeit <= jetzt }.sorted { $0.zeit < $1.zeit }
        guard let erste = kerzen.first,
              let tief = kerzen.map(\.tief).min(), let hoch = kerzen.map(\.hoch).max() else { return nil }
        let untergrenze = tief * (1 - toleranz)
        let obergrenze = hoch * (1 + toleranz)
        let imZeitraum = marken.filter { $0.zeit >= erste.zeit && $0.zeit <= jetzt }
        let passend = imZeitraum.filter { $0.preis >= untergrenze && $0.preis <= obergrenze }
            .sorted { ($0.zeit, $0.art == .einstieg ? 0 : 1) < ($1.zeit, $1.art == .einstieg ? 0 : 1) }
        var jeTag: [Date: [Chartmeldung]] = [:]
        for meldung in meldungen where meldung.zeit >= erste.zeit && meldung.zeit <= jetzt {
            guard let kerze = kerzen.last(where: { $0.zeit <= meldung.zeit }) else { continue }
            jeTag[kerze.zeit, default: []].append(meldung)
        }
        let tage = jeTag.map { Nachrichtentag(tag: $0.key, meldungen: $0.value.sorted { $0.zeit > $1.zeit }) }
            .sorted { $0.tag < $1.tag }
        let preise = passend.map(\.preis)
        return Kurschart(kerzen: kerzen, marken: passend, ausserhalb: imZeitraum.count - passend.count,
                         nachrichtentage: tage, tief: min(tief, preise.min() ?? tief),
                         hoch: max(hoch, preise.max() ?? hoch))
    }
}
