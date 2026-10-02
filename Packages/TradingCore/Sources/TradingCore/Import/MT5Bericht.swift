import Foundation

/// Handelsbericht aus dem MetaTrader-5-Terminal: „Werkzeugkasten → Historie → Rechtsklick → Bericht → HTML“
/// („Trade History Report“, Datei `ReportHistory-<Konto>.html`, meist UTF-16 mit BOM).
/// Aufbau nach der MetaTrader-5-Hilfe und veröffentlichten Beispielberichten: eine große Tabelle mit
/// Kontokopf in `<th>`-Zellen, danach Abschnitte „Positions“, „Orders“, „Deals“ und Zusammenfassung.
/// Gelesen werden geschlossene Positionen und die Kassenzeilen aus „Deals“ (Typ `balance`, `credit` …);
/// Orders und offene Positionen nicht. Spalten werden über den Kopf gelesen; „Time“ und „Price“ stehen
/// zweimal (Eröffnung, dann Schluss). Zeiten sind Serverzeit wie bei MetaTrader 4.
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist (Tim hat kein MT5-Konto, Stand 02.10.2026).
public struct MT5Bericht: Sendable, Equatable {
    /// Kontonummer aus „Account:“, `nil`, wenn sie fehlt. Den Namen des Inhabers liest der Importer nicht.
    public var konto: String?
    /// Kontowährung aus „Account: 12345678 (USD, Server, real, Hedge)“.
    public var waehrung: String?
    /// Broker aus „Company:“.
    public var broker: String?
    public var positionen: [ClosedPosition]
    /// Kassenzeilen aus „Deals“ ohne Handel: Ein- und Auszahlungen, Gutschriften, Gebühren.
    public var kasse: Kontobewegungen
    /// Summenzeile unter „Positions“ (Kommission, Swap, Gewinn), wie gedruckt; `nil`, wenn sie fehlt.
    public var positionenLautSumme: Totals?
    public var hinweise: [Importhinweis]

    public var trades: [Trade] { positionen.map(Trade.init) }
}

extension MT5Bericht {
    static let positionsspalten = ["time", "position", "symbol", "type", "volume", "price", "commission", "swap",
                                   "profit"]
    static let dealspalten = ["time", "deal", "type", "profit"]

    /// Text eines Berichts: MetaTrader 5 speichert UTF-16 (Little Endian, mit BOM), ältere Builds auch UTF-8.
    public static func text(_ daten: Data) -> String? {
        let bytes = [UInt8](daten.prefix(2))
        if bytes == [0xFF, 0xFE] { return String(data: daten.dropFirst(2), encoding: .utf16LittleEndian) }
        if bytes == [0xFE, 0xFF] { return String(data: daten.dropFirst(2), encoding: .utf16BigEndian) }
        // Ohne BOM: Ist mindestens jedes zweite Byte an ungerader Stelle null, ist es UTF-16 Little Endian.
        let probe = [UInt8](daten.prefix(200))
        let nullen = stride(from: 1, to: probe.count, by: 2).filter { probe[$0] == 0 }.count
        if probe.count >= 20, nullen >= probe.count / 4 {
            return String(data: daten, encoding: .utf16LittleEndian)
        }
        return String(data: daten, encoding: .utf8)
    }

    public static func erkennt(_ text: String) -> Bool {
        text.range(of: "Trade History Report", options: .caseInsensitive) != nil
            && HTMLTabelle.zeilen(text, kopfzellen: true).contains { $0.count == 1 && abschnitt($0[0]) == .positionen }
    }

    enum Abschnitt: Equatable { case kopf, positionen, orders, deals, offen, andere }

    /// Abschnittstitel: eine Zeile mit genau einer Zelle.
    static func abschnitt(_ titel: String) -> Abschnitt? {
        switch titel.lowercased() {
        case "positions": .positionen
        case "orders": .orders
        case "deals": .deals
        case "open positions": .offen
        case "working orders", "summary", "results", "report": .andere
        default: nil
        }
    }

    /// Liest einen Bericht.
    /// - Parameter serverZeitzone: Zeitzone des Handelsservers; steht nicht im Bericht, die App fragt sie ab.
    public static func lies(_ text: String, serverZeitzone: TimeZone) throws -> MT5Bericht {
        guard erkennt(text) else { throw MT4ImportFehler.keinMT4Auszug }
        var bericht = MT5Bericht(konto: nil, waehrung: nil, broker: nil, positionen: [], kasse: Kontobewegungen(),
                                 positionenLautSumme: nil, hinweise: [])
        var abschnitt = Abschnitt.kopf
        var kopf: [String]?
        for (n, zeile) in HTMLTabelle.zeilen(text, kopfzellen: true, ohneVersteckte: true).enumerated() {
            let nr = n + 1
            if zeile.count == 1, let neu = Self.abschnitt(zeile[0]) {
                abschnitt = neu
                kopf = nil
                continue
            }
            if zeile.allSatisfy(\.isEmpty) { continue }
            switch abschnitt {
            case .kopf:
                kopfangabe(zeile, in: &bericht)
            case .positionen:
                if kopf == nil {
                    kopf = try spaltenkopf(zeile, pflicht: positionsspalten, abschnitt: "Positions")
                    continue
                }
                try position(zeile, kopf: kopf!, nr: nr, zeitzone: serverZeitzone, in: &bericht)
            case .deals:
                if kopf == nil {
                    kopf = try spaltenkopf(zeile, pflicht: dealspalten, abschnitt: "Deals")
                    continue
                }
                try deal(zeile, kopf: kopf!, nr: nr, zeitzone: serverZeitzone, in: &bericht)
            case .orders, .offen, .andere:
                continue
            }
        }
        return bericht
    }

    /// „Account:“, „Company:“ im Kopf; der Name des Inhabers bleibt ungelesen.
    static func kopfangabe(_ zeile: [String], in bericht: inout MT5Bericht) {
        guard zeile.count >= 2 else { return }
        let wert = zeile[1]
        switch zeile[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": ")) {
        case "account":
            let nummer = wert.prefix { $0.isNumber }
            if !nummer.isEmpty { bericht.konto = String(nummer) }
            if let auf = wert.firstIndex(of: "(") {
                let erste = wert[wert.index(after: auf)...].prefix { $0 != "," && $0 != ")" }
                    .trimmingCharacters(in: .whitespaces)
                if erste.count == 3, erste.allSatisfy({ $0.isASCII && $0.isUppercase }) { bericht.waehrung = erste }
            }
        case "company":
            bericht.broker = wert.isEmpty ? nil : wert
        default:
            break
        }
    }

    /// Spaltennamen klein und ohne Leerraum („S / L“ wird „s/l“); doppelte Namen bekommen „#2“.
    static func spaltenkopf(_ zeile: [String], pflicht: [String], abschnitt: String) throws -> [String] {
        var gesehen: [String: Int] = [:]
        let namen = zeile.map { zelle -> String in
            let name = zelle.lowercased().filter { !$0.isWhitespace }
            gesehen[name, default: 0] += 1
            return gesehen[name]! > 1 ? "\(name)#\(gesehen[name]!)" : name
        }
        guard pflicht.allSatisfy(namen.contains) else {
            throw MT4ImportFehler.unerwarteteSpalten(abschnitt: abschnitt, gefunden: zeile)
        }
        return namen
    }

    static func position(_ zeile: [String], kopf: [String], nr: Int, zeitzone: TimeZone,
                         in bericht: inout MT5Bericht) throws {
        // Summenzeile: kürzer als der Kopf, die letzten drei Zellen Kommission, Swap, Gewinn.
        if zeile.count < kopf.count {
            let zahlen = zeile.filter { !$0.isEmpty }
            if zahlen.count == 3, let summe = try? zahlen.map(MT4Werte.zahl) {
                bericht.positionenLautSumme = Totals(commission: summe[0], swap: summe[1], profit: summe[2])
                return
            }
            throw MT4ImportFehler.unerwarteteSpalten(abschnitt: "Positions", gefunden: zeile)
        }
        guard zeile.count == kopf.count else {
            throw MT4ImportFehler.unerwarteteSpalten(abschnitt: "Positions", gefunden: zeile)
        }
        func feld(_ name: String) -> String { kopf.firstIndex(of: name).map { zeile[$0] } ?? "" }
        func grenze(_ name: String) throws -> Decimal? {
            let text = feld(name)
            return text.isEmpty ? nil : try MT4Werte.optionaleZahl(text)
        }
        guard let seite = Side(rawValue: feld("type").lowercased()) else {
            bericht.hinweise.append(Importhinweis(zeile: nr, vorgang: "Position \(feld("position")) \(feld("type"))",
                                                  folge: .nichtVerbucht))
            return
        }
        // Teilschlüsse stehen als „0.05 / 0.1“ (geschlossen / eröffnet); gezählt wird die geschlossene Menge.
        let menge = feld("volume").split(separator: "/").first.map(String.init) ?? ""
        bericht.positionen.append(ClosedPosition(
            ticket: feld("position"), rohzeile: zeile, side: seite, lots: try MT4Werte.zahl(menge),
            symbol: feld("symbol"),
            openTime: try MT4Werte.zeit(feld("time"), zeitzone: zeitzone), openPrice: try MT4Werte.zahl(feld("price")),
            stopLoss: try grenze("s/l"), takeProfit: try grenze("t/p"),
            closeTime: try MT4Werte.zeit(feld("time#2"), zeitzone: zeitzone),
            closePrice: try MT4Werte.zahl(feld("price#2")),
            commission: try MT4Werte.zahl(feld("commission")), swap: try MT4Werte.zahl(feld("swap")),
            profit: try MT4Werte.zahl(feld("profit"))))
    }

    /// Deals: Handel steckt schon in den Positionen; nur Kassenzeilen werden Geldbewegungen.
    static func deal(_ zeile: [String], kopf: [String], nr: Int, zeitzone: TimeZone,
                     in bericht: inout MT5Bericht) throws {
        guard zeile.count == kopf.count else { return }  // Summenzeile am Ende
        func feld(_ name: String) -> String { kopf.firstIndex(of: name).map { zeile[$0] } ?? "" }
        let typ = feld("type").lowercased()
        if typ == "buy" || typ == "sell" { return }
        let betrag = try MT4Werte.zahl(feld("profit"))
        let art: Geldbewegung.Art
        switch typ {
        case "balance": art = betrag < 0 ? .auszahlung : .einzahlung
        case "commission", "charge", "agent": art = .gebuehr
        case "interest": art = .zinsen
        case "dividend", "dividend franked": art = .dividende
        case "tax": art = .steuer
        default:
            art = .sonstiges
            bericht.hinweise.append(Importhinweis(zeile: nr, vorgang: "Deal \(feld("deal")) \(feld("type"))",
                                                  folge: .alsSonstiges))
        }
        let kommentar = feld("comment")
        bericht.kasse.geldbewegungen.append(Geldbewegung(
            id: feld("deal"), zeit: try MT4Werte.zeit(feld("time"), zeitzone: zeitzone), art: art, betrag: betrag,
            waehrung: bericht.waehrung ?? "", kennung: kommentar.isEmpty ? nil : kommentar, rohzeile: zeile))
    }
}
