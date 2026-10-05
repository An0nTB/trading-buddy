import Foundation

/// Hebelprodukt (Turbo, Knock-out, Mini-Future, Optionsschein), erkannt am Produktnamen des Brokers.
/// Scalable und Trade Republic nennen Basiswert, Richtung und Schwelle nur im Namen,
/// etwa „Nasdaq 100 Long 29.209,64 Turbo Open End HSBC“ oder „Iren Long 23,39 $ Turbo Open End HSBC“.
/// Erkannt wird nur das Muster `<Basiswert> (Long|Short|Call|Put) <Zahl> [$|€] …` zusammen mit einem
/// Produktwort; alles Unsichere ergibt `nil`, damit keine Aktie als Hebelprodukt durchgeht.
public struct Hebelprodukt: Sendable, Equatable {
    public enum Art: String, Sendable, Equatable {
        /// Turbo, Knock-out, Mini-Future: Schein verfällt an der Schwelle.
        case knockout
        case optionsschein
        /// Faktor-Zertifikat mit festem Hebel.
        case faktor
    }

    /// Basiswert wie im Namen, etwa „Nasdaq 100“, „Advanced Micro Devices“, „DAX“.
    public var basiswert: String
    /// Markterwartung des Scheins: Long und Call `.buy`, Short und Put `.sell`.
    /// Der Schein selbst wird immer gekauft; das hier ist die Richtung auf den Basiswert.
    public var markterwartung: Side
    public var art: Art
    /// Basispreis oder Knock-out-Schwelle aus dem Namen, `nil` wenn sie fehlt.
    public var schwelle: Decimal?
    /// Währung der Schwelle: „$“ ergibt "USD", „€“ ergibt "EUR"; ohne Zeichen `nil`.
    public var schwellenwaehrung: String?

    public init(basiswert: String, markterwartung: Side, art: Art, schwelle: Decimal? = nil,
                schwellenwaehrung: String? = nil) {
        self.basiswert = basiswert
        self.markterwartung = markterwartung
        self.art = art
        self.schwelle = schwelle
        self.schwellenwaehrung = schwellenwaehrung
    }

    /// Richtungswörter im Namen und die Markterwartung dazu.
    static let richtungen: [String: Side] = ["long": .buy, "short": .sell, "call": .buy, "put": .sell]

    /// Währungszeichen hinter der Schwelle.
    static let waehrungen: [String: String] = ["$": "USD", "€": "EUR", "usd": "USD", "eur": "EUR"]

    /// nil, wenn der Name kein erkennbares Hebelprodukt ist.
    public static func erkenne(_ name: String) -> Hebelprodukt? {
        let woerter = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let klein = name.lowercased()
        let kleineWoerter = woerter.map { $0.lowercased() }
        let knockout = klein.contains("turbo") || klein.contains("knock-out") || klein.contains("knockout")
            || klein.contains("mini future") || klein.contains("mini-future") || kleineWoerter.contains("ko")
        let faktor = klein.contains("faktor")
        let optionsschein = klein.contains("optionsschein")

        // Erstes Richtungswort mit Zahl dahinter; davor muss ein Basiswert stehen.
        guard let stelle = woerter.indices.dropFirst().first(where: { i in
            Self.richtungen[kleineWoerter[i]] != nil && i + 1 < woerter.count && Self.zahl(woerter[i + 1]) != nil
        }) else { return nil }
        let richtung = kleineWoerter[stelle]
        let art: Art
        if knockout {
            art = .knockout
        } else if faktor {
            art = .faktor
        } else if optionsschein || richtung == "call" || richtung == "put" {
            art = .optionsschein
        } else {
            // Long oder Short mit Zahl, aber ohne Produktwort: zu unsicher.
            return nil
        }

        let basiswert = woerter[..<stelle].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !basiswert.isEmpty, let schwelle = zahl(woerter[stelle + 1]) else { return nil }
        var waehrung = schwelle.waehrung
        if waehrung == nil, stelle + 2 < woerter.count {
            waehrung = waehrungen[kleineWoerter[stelle + 2]]
        }
        return Hebelprodukt(basiswert: basiswert, markterwartung: richtungen[richtung]!, art: art,
                            schwelle: schwelle.wert, schwellenwaehrung: waehrung)
    }

    /// Zahl im deutschen Format („29.209,64“, „23,39“, „8000“), auf Wunsch mit angehängtem „$“ oder „€“.
    /// Punkte nur als Tausendertrenner vor genau drei Ziffern, höchstens ein Komma.
    static func zahl(_ wort: String) -> (wert: Decimal, waehrung: String?)? {
        var text = wort
        var waehrung: String?
        if let letztes = text.last, let w = waehrungen[String(letztes)] {
            waehrung = w
            text.removeLast()
        }
        let teile = text.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(teile.count), let ganz = teile.first else { return nil }
        let nachkomma = teile.count == 2 ? String(teile[1]) : ""
        guard teile.count == 1 || !nachkomma.isEmpty, nachkomma.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        let gruppen = ganz.split(separator: ".", omittingEmptySubsequences: false)
        guard let erste = gruppen.first, !erste.isEmpty, erste.count <= (gruppen.count > 1 ? 3 : 20) else { return nil }
        for (n, gruppe) in gruppen.enumerated() {
            guard gruppe.allSatisfy({ $0.isASCII && $0.isNumber }), n == 0 || gruppe.count == 3 else { return nil }
        }
        let normal = gruppen.joined() + (nachkomma.isEmpty ? "" : "." + nachkomma)
        guard let wert = Decimal(string: normal, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return (wert: wert, waehrung: waehrung)
    }
}
