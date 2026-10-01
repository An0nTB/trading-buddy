import Foundation

/// Geldbewegung ohne Wertpapier-Ausführung: Ein- und Auszahlung, Dividende, Zinsen, Steuer.
public struct Geldbewegung: Sendable, Equatable {
    public enum Art: String, Sendable, CaseIterable {
        case einzahlung, auszahlung, dividende, zinsen, steuer, gebuehr, sonstiges
    }

    public var id: String
    public var zeit: Date
    public var nurDatum: Bool
    public var art: Art
    /// Betrag ohne Gebühr und Steuer, als Kassenwirkung. Negativ bei einer Dividenden-Korrektur.
    public var betrag: Decimal
    /// Gebühr, etwa für eine Einzahlung per Karte.
    public var gebuehr: Decimal
    public var steuer: Decimal
    public var waehrung: String
    /// ISIN bei Dividenden; XTB nennt stattdessen das Symbol („SAP.DE“).
    public var kennung: String?
    public var rohzeile: [String]

    public init(id: String, zeit: Date, nurDatum: Bool = false, art: Art, betrag: Decimal, gebuehr: Decimal = 0,
                steuer: Decimal = 0, waehrung: String, kennung: String? = nil, rohzeile: [String] = []) {
        self.id = id
        self.zeit = zeit
        self.nurDatum = nurDatum
        self.art = art
        self.betrag = betrag
        self.gebuehr = gebuehr
        self.steuer = steuer
        self.waehrung = waehrung
        self.kennung = kennung
        self.rohzeile = rohzeile
    }
}

/// Bestandsänderung ohne Kauf oder Verkauf: Split, Fälligkeit einer Anleihe, Ausübung eines Optionsscheins.
public struct Kapitalmassnahme: Sendable, Equatable {
    public enum Art: String, Sendable, CaseIterable {
        /// Zusätzliche Stücke (oder weniger bei umgekehrtem Split), Einstand bleibt gleich.
        case split
        /// Stücke gehen aus dem Depot; den Erlös bucht der Broker in einer eigenen Zeile.
        case ausbuchung
        /// Bedeutung nicht belegt; die Positionsbildung kann abweichen.
        case unbekannt
    }

    public var id: String
    public var zeit: Date
    public var art: Art
    /// Vorgangsart laut Broker, etwa „SPLIT“ oder „WARRANT_EXERCISE“.
    public var vorgang: String
    public var kennung: String
    /// Stückänderung laut Broker: positiv bei Split, negativ bei Ausbuchung.
    public var menge: Decimal
    public var rohzeile: [String]

    public init(id: String, zeit: Date, art: Art, vorgang: String, kennung: String, menge: Decimal,
                rohzeile: [String] = []) {
        self.id = id
        self.zeit = zeit
        self.art = art
        self.vorgang = vorgang
        self.kennung = kennung
        self.menge = menge
        self.rohzeile = rohzeile
    }
}

/// Zeile, die der Importer nicht sicher zuordnen kann. Der Import läuft weiter, die App zeigt den Hinweis.
public struct Importhinweis: Sendable, Equatable {
    public enum Folge: String, Sendable {
        /// Betrag als Geldbewegung „sonstiges“ übernommen, die Kassenwirkung stimmt.
        case alsSonstiges
        /// Nicht verbucht, weil die Zeile keinen Betrag hat oder ein Wertpapier betrifft.
        case nichtVerbucht
    }

    /// Zeile in der Datei: bei CSV ist der Kopf Zeile 1, bei Excel die Zeilennummer im Blatt.
    public var zeile: Int
    /// Vorgangsart laut Broker.
    public var vorgang: String
    public var folge: Folge

    public init(zeile: Int, vorgang: String, folge: Folge) {
        self.zeile = zeile
        self.vorgang = vorgang
        self.folge = folge
    }
}

/// Ergebnis eines CSV-Imports; bei XTB die Kassenoperationen ohne Handel.
public struct Kontobewegungen: Sendable, Equatable {
    public var ausfuehrungen: [Ausfuehrung] = []
    public var geldbewegungen: [Geldbewegung] = []
    public var kapitalmassnahmen: [Kapitalmassnahme] = []
    /// Kennungen nicht ausgeführter Orders (storniert, abgelehnt); zählen nie als Trade.
    public var verworfen: [String] = []
    public var hinweise: [Importhinweis] = []

    public init() {}

    /// Kassenwirkung aller Zeilen: Beträge plus Gebühren plus Steuern.
    public var kassenwirkung: Decimal {
        let handel = ausfuehrungen.map { $0.betrag + $0.gebuehr + $0.steuer }
        let geld = geldbewegungen.map { $0.betrag + $0.gebuehr + $0.steuer }
        return (handel + geld).reduce(0, +)
    }
}
