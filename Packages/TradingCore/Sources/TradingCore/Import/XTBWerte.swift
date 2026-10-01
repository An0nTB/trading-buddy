import Foundation

/// Zahlen, Zeiten und Kopfangaben aus XTB-Excel-Dateien.
enum XTBWerte {
    /// Zellwert als Zahl. Excel speichert Zahlen mit Punkt und schreibt Gleitkomma-Reste
    /// („23.050000000000001“), deshalb auf zehn Stellen gerundet. Leer zählt als 0.
    static func zahl(_ text: String, zeile: Int) throws -> Decimal {
        var roh = text.trimmingCharacters(in: .whitespaces)
        if roh.isEmpty { return 0 }
        // Der öffentliche Beispielexport enthält „-0.“ (Export-To-Ghostfolio 2026).
        if roh.hasSuffix(".") { roh.removeLast() }
        let erlaubt = roh.allSatisfy { $0.isASCII && ($0.isNumber || "+-.eE".contains($0)) }
        guard erlaubt, roh.contains(where: \.isNumber),
              let wert = Decimal(string: roh, locale: Locale(identifier: "en_US_POSIX"))
        else { throw CSVImportFehler.ungueltigeZahl(zeile: zeile, text: text) }
        return wert.gerundet(10)
    }

    /// Zeit als Text („02/03/2026 09:10:00“, „12.04.2024 13:01:45“, „2026-03-02 09:10:00“)
    /// oder als Excel-Seriennummer (Tage seit 30.12.1899, Bruchteil = Uhrzeit), jeweils Ortszeit.
    static func zeit(_ text: String, zeitzone: TimeZone, zeile: Int) throws -> Date {
        let roh = text.trimmingCharacters(in: .whitespaces)
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        if let serie = Double(roh), roh.allSatisfy({ $0.isNumber || $0 == "." }) {
            // Seriennummer als UTC-Wanduhr lesen und die Uhrzeit dann in der Ortszeit ansetzen.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let basis = utc.date(from: DateComponents(year: 1899, month: 12, day: 30))!
            let wanduhr = basis.addingTimeInterval((serie * 86_400).rounded())
            var teile = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wanduhr)
            teile.timeZone = nil
            if let zeit = kalender.date(from: teile) { return zeit }
        }
        let felder = roh.split(whereSeparator: { " T".contains($0) })
        let datum = felder.first.map { $0.split(whereSeparator: { "/.-".contains($0) }).map { Int($0) } } ?? []
        let uhr = (felder.count > 1 ? felder[1] : "00:00:00").split(separator: ":").map { Int($0) }
        guard datum.count == 3, !datum.contains(nil), (2...3).contains(uhr.count), !uhr.contains(nil)
        else { throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: text) }
        let jahrVorn = roh.prefix(4).allSatisfy(\.isNumber)
        let (jahr, monat, tag) = jahrVorn ? (datum[0]!, datum[1]!, datum[2]!) : (datum[2]!, datum[1]!, datum[0]!)
        let teile = DateComponents(year: jahr, month: monat, day: tag,
                                   hour: uhr[0], minute: uhr[1], second: uhr.count > 2 ? uhr[2] : 0)
        // Gegenprobe: Ein 31.02. würde sonst still zum 03.03.
        guard let zeit = kalender.date(from: teile),
              case let probe = kalender.dateComponents([.year, .month, .day], from: zeit),
              probe.year == jahr, probe.month == monat, probe.day == tag
        else { throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: text) }
        return zeit
    }

    /// Wert zu einer Beschriftung über der Tabelle („Account“, „Currency“). XTB schreibt den Wert
    /// unter die Beschriftung, andere Nachbauten daneben; genommen wird der erste passende.
    static func kopfwert(_ zeilen: [[String]], bis ende: Int, beschriftung: String,
                         passt: (String) -> Bool) -> String? {
        func zelle(_ r: Int, _ s: Int) -> String {
            r < zeilen.count && s < zeilen[r].count ? zeilen[r][s].trimmingCharacters(in: .whitespaces) : ""
        }
        for r in 0..<min(ende, zeilen.count) {
            for s in zeilen[r].indices where zelle(r, s).lowercased() == beschriftung {
                if let wert = [zelle(r, s + 1), zelle(r + 1, s)].first(where: passt) { return wert }
            }
        }
        return nil
    }

    /// Index der Kopfzeile: die erste Zeile, die alle Namen als Zelle enthält.
    static func kopfzeile(_ zeilen: [[String]], mit namen: [String]) -> Int? {
        zeilen.firstIndex { zeile in
            let zellen = Set(zeile.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
            return namen.allSatisfy(zellen.contains)
        }
    }

    enum Kassenart: Equatable {
        /// Ergebnis, Swap oder Kauf und Verkauf von Aktien: gehört zu einer Position.
        case handel
        case geld(Geldbewegung.Art)
        case unbekannt
    }

    /// Bedeutung der Spalte `Type` in „CASH OPERATION HISTORY“. Belegt im öffentlichen Beispiel
    /// (Export-To-Ghostfolio 2026): Deposit, Withdrawal, Transfer, Stocks/ETF purchase und sale,
    /// Profit/Loss (FX/CFD), Swap, Dividend, Withholding tax, Free funds interests (tax), Spin off.
    /// „close trade“ und „DIVIDENT“ aus älteren Exporten (xtb-xlsx-cleaner 2025).
    static func kassenart(_ typ: String, betrag: Decimal) -> Kassenart {
        let t = typ.trimmingCharacters(in: .whitespaces).lowercased()
        let handel = ["close trade", "open trade", "swap", "rollover", "commission",
                      "stocks/etf purchase", "stocks/etf sale", "stock purchase", "stock sale"]
        if handel.contains(t) || t.hasPrefix("profit/loss") { return .handel }
        if t.contains("tax") { return .geld(.steuer) }
        if t.contains("deposit") { return .geld(.einzahlung) }
        if t.contains("withdraw") { return .geld(.auszahlung) }
        if t.contains("transfer") { return .geld(betrag < 0 ? .auszahlung : .einzahlung) }
        if t.contains("divident") || t.contains("dividend") { return .geld(.dividende) }
        if t.contains("interest") { return .geld(.zinsen) }
        if t.contains("fee") { return .geld(.gebuehr) }
        return .unbekannt
    }
}
