import Foundation

/// Eintrag der Merkliste für Nachrichten (Doc 26, R6 Abschnitt 3): Symbol, ISIN, Firmenname oder Stichwort.
/// Die App fügt nichts still hinzu: Vorschläge aus dem Journal sind `vorgeschlagen`, bis Tim sie bestätigt.
public struct Merklisteneintrag: Sendable, Hashable, Codable, Identifiable {
    /// Wonach gesucht wird. Bestimmt die Zuordnung je Quelle (Alpaca nach US-Symbol, Marketaux nach Symbol
    /// oder Suchbegriff, RSS nach Textsuche).
    public enum Art: String, Sendable, Codable, CaseIterable {
        case symbol, isin, name, stichwort
    }

    public enum Herkunft: String, Sendable, Codable, CaseIterable {
        case offenePosition, letzteTage, vonHand
    }

    /// `abgelehnt` merkt sich verworfene Vorschläge, damit sie beim nächsten Vorschlag nicht wiederkommen.
    public enum Status: String, Sendable, Codable, CaseIterable {
        case vorgeschlagen, aktiv, abgelehnt
    }

    public var id: String
    /// Suchbegriff, z. B. „AAPL“, „SAP.DE“, „DE0007164600“, „Nvidia Zölle“.
    public var begriff: String
    public var art: Art
    public var anzeigename: String
    public var herkunft: Herkunft
    public var status: Status
    public var notiz: String
    public var erstellt: Date

    public init(id: String = UUID().uuidString, begriff: String, art: Art? = nil, anzeigename: String? = nil,
                herkunft: Herkunft = .vonHand, status: Status = .aktiv, notiz: String = "", erstellt: Date) {
        let sauber = Merkliste.bereinigt(begriff)
        self.id = id
        self.begriff = sauber
        self.art = art ?? Merkliste.art(fuer: sauber)
        self.anzeigename = anzeigename ?? sauber
        self.herkunft = herkunft
        self.status = status
        self.notiz = notiz
        self.erstellt = erstellt
    }

    /// Vergleichsschlüssel gegen Doppelte: ohne Groß- und Kleinschreibung und doppelte Leerzeichen.
    public var schluessel: String { begriff.lowercased() }
}

public enum Merkliste {
    /// Zeitraum für Vorschläge aus geschlossenen Trades (N-E3, Tim 02.10.2026).
    public static let vorschlagTage = 30
    /// Bis zu dieser Größe reicht Marketaux Free bei vier Läufen am Tag (R6: 20 × 4 = 80 von 100 Abrufen).
    public static let empfohleneHoechstzahl = 20

    /// Vorschläge aus offenen Positionen und Trades, die in den letzten `tage` Tagen geschlossen wurden.
    /// Offene Positionen zuerst (nach Begriff), dann nach letztem Schluss absteigend. Begriffe, die schon
    /// in `bestehend` stehen, auch abgelehnte, fehlen. Alle Vorschläge haben Status `vorgeschlagen`.
    public static func vorschlag(trades: [Trade], offeneSymbole: [String], bestehend: [Merklisteneintrag],
                                 jetzt: Date, tage: Int = vorschlagTage) -> [Merklisteneintrag] {
        var bekannt = Set(bestehend.map(\.schluessel))
        var ergebnis: [Merklisteneintrag] = []
        func aufnehmen(_ begriff: String, _ herkunft: Merklisteneintrag.Herkunft) {
            let eintrag = Merklisteneintrag(begriff: begriff, herkunft: herkunft, status: .vorgeschlagen,
                                            erstellt: jetzt)
            guard !eintrag.begriff.isEmpty, !bekannt.contains(eintrag.schluessel) else { return }
            bekannt.insert(eintrag.schluessel)
            ergebnis.append(eintrag)
        }
        for s in offeneSymbole.map({ bereinigt($0) }).sorted() { aufnehmen(s, .offenePosition) }
        let grenze = jetzt.addingTimeInterval(-Double(tage) * 86_400)
        var letzterSchluss: [String: Date] = [:]
        for t in trades where t.closeTime >= grenze && t.closeTime <= jetzt {
            let s = bereinigt(t.symbol)
            letzterSchluss[s] = max(letzterSchluss[s] ?? t.closeTime, t.closeTime)
        }
        let reihenfolge = letzterSchluss.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
        for (s, _) in reihenfolge { aufnehmen(s, .letzteTage) }
        return ergebnis
    }

    /// Ohne Leerzeichen am Rand, mehrere Leerzeichen zu einem.
    public static func bereinigt(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Schätzt die Art: gültige ISIN; Symbol, wenn ohne Leerzeichen und vor dem ersten Punkt ohne
    /// Kleinbuchstaben („SAP.DE“, „XAUUSD.r“, „BTC/EUR“); sonst Name („Apple Inc.“). Stichworte nur von Hand.
    public static func art(fuer begriff: String) -> Merklisteneintrag.Art {
        if istISIN(begriff) { return .isin }
        let zeichen = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-/:_"))
        let stamm = begriff.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let symbolhaft = !begriff.isEmpty && begriff.count <= 15
            && begriff.unicodeScalars.allSatisfy { zeichen.contains($0) }
            && !stamm.contains { $0.isLowercase }
        return symbolhaft ? .symbol : .name
    }

    /// ISIN nach ISO 6166: zwei Buchstaben, neun Zeichen, Prüfziffer (Luhn über die Ziffernfolge).
    public static func istISIN(_ text: String) -> Bool {
        let z = Array(text)
        guard z.count == 12, z[0].isASCII, z[1].isASCII, z[0].isUppercase, z[1].isUppercase,
              z[11].isASCII, z[11].isNumber else { return false }
        var ziffern: [Int] = []
        for c in z {
            guard c.isASCII, let wert = Int(String(c), radix: 36), c.isNumber || c.isUppercase else { return false }
            if wert >= 10 { ziffern.append(wert / 10) }
            ziffern.append(wert % 10)
        }
        var summe = 0
        for (i, d) in ziffern.reversed().enumerated() {
            let w = i % 2 == 1 ? d * 2 : d
            summe += w > 9 ? w - 9 : w
        }
        return summe % 10 == 0
    }
}
