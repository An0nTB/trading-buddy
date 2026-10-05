import Foundation

extension Terminkalender {
    /// Währungen, für die Termine geführt werden.
    public static let gefuehrteWaehrungen: Set<String> = ["USD", "EUR", "GBP", "JPY", "CHF",
                                                          "AUD", "CAD", "NZD", "NOK", "SEK", "CNY", "HKD"]

    /// Währungen, die früher allein über ihr Kürzel irgendwo im Symbol erkannt wurden („XAUUSD“ → USD).
    /// Die übrigen zählen nur als Teil eines Devisenpaars am Anfang des Symbols, damit Aktien wie „NOK“
    /// (Nokia) keine Norwegen-Termine bekommen.
    static let kuerzelUeberall: Set<String> = ["USD", "EUR", "GBP", "JPY", "CHF"]

    /// Offshore-Kürzel und ihre Währung für Termine („USDCNH“ → CNY).
    static let ersatzkuerzel: [String: String] = ["CNH": "CNY"]

    /// Gängige Index-CFD-Namen und ihre Währung (Einschätzung nach üblichen Broker-Symbolen).
    static let indizes: [(name: String, waehrung: String)] = [
        ("US30", "USD"), ("US100", "USD"), ("US500", "USD"), ("NAS100", "USD"), ("SPX500", "USD"),
        ("USTEC", "USD"), ("DJ30", "USD"), ("US2000", "USD"),
        ("GER40", "EUR"), ("GER30", "EUR"), ("DE40", "EUR"), ("DE30", "EUR"), ("EU50", "EUR"),
        ("EUSTX50", "EUR"), ("FRA40", "EUR"), ("F40", "EUR"),
        ("UK100", "GBP"), ("JP225", "JPY"), ("JPN225", "JPY"), ("SWI20", "CHF"), ("CH20", "CHF"),
        ("AUS200", "AUD"), ("HK50", "HKD"), ("HKG33", "HKD"), ("CN50", "CNY"), ("CHINA50", "CNY")
    ]

    /// Betroffene Währungen eines Symbols: Devisenpaar am Anfang („AUDNZD“ → AUD, NZD), die fünf Hauptwährungen
    /// irgendwo im Namen („EURUSD.m“, „BTCUSDT“ → USD) oder ein bekannter Index („GER40“ → EUR).
    /// Leer, wenn nichts passt; dann gilt kein Termin als betroffen.
    public static func waehrungen(symbol: String) -> Set<String> {
        let roh = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        var ergebnis = Set(kuerzelUeberall.filter { roh.contains($0) })
        if roh.count >= 6 {
            let zeichen = Array(roh)
            let basis = waehrung(String(zeichen[0..<3]))
            let gegen = waehrung(String(zeichen[3..<6]))
            if let basis, let gegen {
                ergebnis.insert(basis)
                ergebnis.insert(gegen)
            }
        }
        for index in indizes where roh.hasPrefix(index.name) {
            ergebnis.insert(index.waehrung)
        }
        return ergebnis
    }

    private static func waehrung(_ kuerzel: String) -> String? {
        let kuerzel = ersatzkuerzel[kuerzel] ?? kuerzel
        return gefuehrteWaehrungen.contains(kuerzel) ? kuerzel : nil
    }

    /// Regionen der Termine in fester Reihenfolge für Filter: Kürzel und deutscher Name.
    public static let regionen: [(kuerzel: String, name: String)] = [
        ("us", "USA"), ("eu", "Euroraum"), ("de", "Deutschland"), ("uk", "Großbritannien"), ("ch", "Schweiz"),
        ("jp", "Japan"), ("cn", "China"), ("hk", "Hongkong"), ("in", "Indien"), ("au", "Australien"),
        ("nz", "Neuseeland"), ("ca", "Kanada"), ("no", "Norwegen"), ("se", "Schweden"), ("fr", "Frankreich"),
        ("kr", "Südkorea"), ("tw", "Taiwan"), ("sg", "Singapur"), ("br", "Brasilien"), ("welt", "Welt")
    ]

    static let regionJeWaehrung: [String: String] = [
        "USD": "us", "EUR": "eu", "GBP": "uk", "JPY": "jp", "CHF": "ch", "AUD": "au", "CAD": "ca", "NZD": "nz",
        "NOK": "no", "SEK": "se", "CNY": "cn", "HKD": "hk", "INR": "in", "KRW": "kr", "TWD": "tw", "SGD": "sg",
        "BRL": "br"
    ]

    /// Region aus den Währungen eines Termins, wenn die Datei keine nennt: genau eine Währung → ihre Region, sonst „welt“.
    public static func region(waehrungen: Set<String>) -> String {
        guard waehrungen.count == 1, let waehrung = waehrungen.first else { return "welt" }
        return regionJeWaehrung[waehrung] ?? "welt"
    }

    /// Währung und Region je Börse der Börsenuhr (Kennungen aus TradingClock); Forex und Krypto fehlen absichtlich,
    /// sie kennen keine Feiertage.
    public static let boersen: [String: (waehrung: String, region: String)] = [
        "xetra": ("EUR", "de"), "xpar": ("EUR", "fr"), "lse": ("GBP", "uk"), "xswx": ("CHF", "ch"),
        "nyse": ("USD", "us"), "nasdaq": ("USD", "us"), "xtse": ("CAD", "ca"), "bvmf": ("BRL", "br"),
        "xtks": ("JPY", "jp"), "xhkg": ("HKD", "hk"), "xshg": ("CNY", "cn"), "xbom": ("INR", "in"),
        "xkrx": ("KRW", "kr"), "xtai": ("TWD", "tw"), "xses": ("SGD", "sg"), "xasx": ("AUD", "au")
    ]

    /// Börsenfeiertag als ganztägiger Termin in der Zeitzone der Börse, ID „boerse-xetra-2026-12-24“.
    /// Die App übergibt die Feiertage aus TradingClock, damit sie nur an einer Stelle gepflegt werden, und den
    /// fertigen Titel in der Sprache der Oberfläche („Xetra geschlossen: Heiligabend“).
    /// `nil` bei ungültigem Datum; Börsen ohne Eintrag in `boersen` bekommen keine Währung und Region „welt“.
    public static func boersenfeiertag(boerse: String, titel: String,
                                       jahr: Int, monat: Int, tag: Int, zeitzone: TimeZone) -> Termin? {
        let zuordnung = boersen[boerse]
        func zweistellig(_ zahl: Int) -> String { zahl < 10 ? "0\(zahl)" : "\(zahl)" }
        let id = "boerse-\(boerse)-\(jahr)-\(zweistellig(monat))-\(zweistellig(tag))"
        return Termin.ganztaegig(id: id, art: .boersenfeiertag, institution: boerse, titel: titel,
                                 jahr: jahr, monat: monat, tag: tag, zeitzone: zeitzone,
                                 waehrungen: zuordnung.map { [$0.waehrung] } ?? [],
                                 wichtigkeit: .mittel, region: zuordnung?.region ?? "welt")
    }
}
