import Foundation

/// Kontoauszug von XTB: Excel-Export aus xStation 5 („Account history“, Sprache Englisch).
/// Aufbau nach dem Open-Source-Parser xtb-xlsx-cleaner (Dezember 2025) und dem öffentlichen Beispielexport
/// von Export-To-Ghostfolio (2026): Blätter „CLOSED POSITION HISTORY“ und „CASH OPERATION HISTORY“,
/// Kontoangaben über der Tabelle, Spalte A leer, Summenzeile „Total“.
/// Die Zeitzone der Zeiten ist nicht belegt; Vorgabe ist deutsche Ortszeit (Annahme).
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public struct XTBAuszug: Sendable, Equatable {
    /// Kontonummer aus dem Kopf, `nil`, wenn sie fehlt. Den Namen des Inhabers liest der Importer nicht.
    public var konto: String?
    /// Kontowährung aus dem Kopf; fehlt sie, fragt die App wie bei MetaTrader.
    public var waehrung: String?
    /// Geschlossene Positionen. Swap enthält auch „Rollover“, Profit ist „Gross P/L“.
    public var positionen: [ClosedPosition]
    /// Kassenoperationen ohne Handel: Ein- und Auszahlungen, Dividenden, Steuern, Zinsen, Gebühren.
    public var kasse: Kontobewegungen
    /// Summe der Kassenzeilen, die zu Positionen gehören (Ergebnis, Swap, Kauf und Verkauf von Aktien).
    /// Gleich der Summe der Positionen nur, wenn alle im Zeitraum eröffnet und geschlossen wurden.
    public var handelLautKasse: Decimal
    /// Summenzeilen „Total“, wie in der Datei gedruckt; `nil`, wenn sie fehlen.
    public var positionenLautSumme: Totals?
    public var kasseLautSumme: Decimal?
    /// Zeilen beider Blätter, die der Importer nicht sicher zuordnen kann.
    public var hinweise: [Importhinweis]

    public var trades: [Trade] { positionen.map(Trade.init) }
    /// Alle Kassenzeilen zusammen; gleich `kasseLautSumme`, wenn nichts verloren ging.
    public var kassenwirkung: Decimal { handelLautKasse + kasse.kassenwirkung }
}

extension XTBAuszug {
    static let positionsspalten = ["position", "symbol", "type", "volume", "open time", "open price",
                                   "close time", "close price", "gross p/l"]
    static let kassenspalten = ["id", "type", "time", "amount"]

    public static func erkennt(_ daten: Data) -> Bool {
        (try? XLSXMappe(daten: daten).blatt(mit: ["closed", "position"])) != nil
    }

    public static func lies(_ daten: Data, zeitzone: TimeZone = TimeZone(identifier: "Europe/Berlin")!) throws
        -> XTBAuszug {
        let mappe = try XLSXMappe(daten: daten)
        let positionsblatt = try mappe.blatt(mit: ["closed", "position"])
        let kassenblatt = try? mappe.blatt(mit: ["cash", "operation"])
        var auszug = XTBAuszug(konto: nil, waehrung: nil, positionen: [], kasse: Kontobewegungen(),
                               handelLautKasse: 0, positionenLautSumme: nil, kasseLautSumme: nil, hinweise: [])

        let zeilen = positionsblatt.zeilen
        guard let kopf = XTBWerte.kopfzeile(zeilen, mit: ["position", "symbol", "type"])
        else { throw CSVImportFehler.fehlendeSpalte("position") }
        for blatt in [positionsblatt] + (kassenblatt.map { [$0] } ?? []) {
            let ende = XTBWerte.kopfzeile(blatt.zeilen, mit: ["type"]) ?? blatt.zeilen.count
            auszug.konto = auszug.konto ?? XTBWerte.kopfwert(blatt.zeilen, bis: ende, beschriftung: "account") {
                !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber }
            }
            auszug.waehrung = auszug.waehrung ?? XTBWerte.kopfwert(blatt.zeilen, bis: ende, beschriftung: "currency") {
                $0.count == 3 && $0.allSatisfy { $0.isASCII && $0.isUppercase }
            }
        }

        let spalten = try Self.spalten(zeilen[kopf], pflicht: positionsspalten)
        for r in (kopf + 1)..<max(kopf + 1, zeilen.count) {
            let z = zeilen[r], nr = r + 1
            let feld = Self.feld(z, spalten)
            func zahl(_ name: String) throws -> Decimal { try XTBWerte.zahl(feld(name), zeile: nr) }
            func zeit(_ name: String) throws -> Date { try XTBWerte.zeit(feld(name), zeitzone: zeitzone, zeile: nr) }
            // SL und TP stehen als 0, wenn keine gesetzt waren (wie bei MetaTrader).
            func grenze(_ name: String) throws -> Decimal? {
                let wert = try zahl(name)
                return wert == 0 ? nil : wert
            }
            if feld("type").isEmpty {
                if Self.istSumme(z) {
                    auszug.positionenLautSumme = Totals(commission: try zahl("commission"),
                                                        swap: try zahl("swap") + zahl("rollover"),
                                                        profit: try zahl("gross p/l"))
                }
                continue
            }
            guard let seite = Side(rawValue: feld("type").lowercased()), !feld("close time").isEmpty else {
                auszug.hinweise.append(Importhinweis(zeile: nr, vorgang: "Position \(feld("position")) \(feld("type"))",
                                                     folge: .nichtVerbucht))
                continue
            }
            auszug.positionen.append(ClosedPosition(
                ticket: feld("position"), rohzeile: z, side: seite, lots: try zahl("volume"), symbol: feld("symbol"),
                openTime: try zeit("open time"), openPrice: try zahl("open price"),
                stopLoss: try grenze("sl"), takeProfit: try grenze("tp"),
                closeTime: try zeit("close time"), closePrice: try zahl("close price"),
                commission: try zahl("commission"), swap: try zahl("swap") + zahl("rollover"),
                profit: try zahl("gross p/l")))
        }

        if let kassenblatt { try lies(kassenblatt.zeilen, in: &auszug, zeitzone: zeitzone) }
        return auszug
    }

    /// Kassenoperationen: Handel nur summieren, alles andere als Geldbewegung.
    static func lies(_ zeilen: [[String]], in auszug: inout XTBAuszug, zeitzone: TimeZone) throws {
        guard let kopf = XTBWerte.kopfzeile(zeilen, mit: ["type", "time", "amount"]) else { return }
        let spalten = try Self.spalten(zeilen[kopf], pflicht: kassenspalten)
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        for r in (kopf + 1)..<max(kopf + 1, zeilen.count) {
            let z = zeilen[r], nr = r + 1
            let feld = Self.feld(z, spalten)
            let typ = feld("type")
            if typ.isEmpty {
                if Self.istSumme(z) { auszug.kasseLautSumme = try XTBWerte.zahl(feld("amount"), zeile: nr) }
                continue
            }
            let betrag = try XTBWerte.zahl(feld("amount"), zeile: nr)
            let art: Geldbewegung.Art
            switch XTBWerte.kassenart(typ, betrag: betrag) {
            case .handel:
                auszug.handelLautKasse += betrag
                continue
            case .geld(let a):
                art = a
            case .unbekannt:
                art = .sonstiges
                auszug.hinweise.append(Importhinweis(zeile: nr, vorgang: typ, folge: .alsSonstiges))
            }
            let zeit = try XTBWerte.zeit(feld("time"), zeitzone: zeitzone, zeile: nr)
            let uhr = kalender.dateComponents([.hour, .minute, .second], from: zeit)
            let symbol = feld("symbol")
            auszug.kasse.geldbewegungen.append(Geldbewegung(
                id: feld("id").isEmpty ? "zeile-\(nr)" : feld("id"), zeit: zeit,
                nurDatum: uhr.hour == 0 && uhr.minute == 0 && uhr.second == 0, art: art, betrag: betrag,
                waehrung: auszug.waehrung ?? "", kennung: symbol.isEmpty ? nil : symbol, rohzeile: z))
        }
    }

    /// Spaltenindex je Name (klein geschrieben); Pflichtspalten müssen da sein (Regel 2).
    static func spalten(_ kopf: [String], pflicht: [String]) throws -> [String: Int] {
        var index: [String: Int] = [:]
        for (i, name) in kopf.enumerated() {
            let schluessel = name.trimmingCharacters(in: .whitespaces).lowercased()
            if !schluessel.isEmpty, index[schluessel] == nil { index[schluessel] = i }
        }
        for name in pflicht where index[name] == nil { throw CSVImportFehler.fehlendeSpalte(name) }
        return index
    }

    static func feld(_ zeile: [String], _ spalten: [String: Int]) -> (String) -> String {
        { name in
            guard let i = spalten[name], i < zeile.count else { return "" }
            return zeile[i].trimmingCharacters(in: .whitespaces)
        }
    }

    /// Summenzeile: eine Zelle „Total“, aber keine Vorgangsart.
    static func istSumme(_ zeile: [String]) -> Bool {
        zeile.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "total" }
    }
}
