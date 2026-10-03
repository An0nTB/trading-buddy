import Foundation

/// Macht aus einer Importdatei eine Probe, die ein Nutzer weitergeben kann, wenn ein Import scheitert
/// oder das Format unbekannt ist. Aufbau, Spalten, Zahlen, Zeiten und Wertpapiere bleiben, damit der
/// Fehler nachvollziehbar bleibt; Namen, IBAN, Mailadressen, Konto- und Ticketnummern fallen weg.
///
/// Das ist eine Heuristik, keine Garantie: Freitext (etwa Verwendungszwecke) kann weitere Angaben
/// enthalten. Die App zeigt die Probe deshalb vor dem Speichern an.
public enum AnonymeProbe {
    public struct Ergebnis: Sendable, Equatable {
        public var text: String
        /// Wie viele Stellen ersetzt wurden, nach Art („Name“, „IBAN“, „Nummer“ …).
        public var ersetzt: [String: Int]
        /// Datenzeilen, die wegen `hoechstensZeilen` weggelassen wurden.
        public var weggelassen: Int
    }

    /// - Parameter hoechstensZeilen: Bei CSV höchstens so viele Zeilen nach den ersten 20 behalten
    ///   (`nil` = alle). HTML bleibt immer vollständig, sonst bricht die Tabelle.
    public static func erstelle(_ text: String, hoechstensZeilen: Int? = nil) -> Ergebnis {
        var probe = Probe()
        let html = text.range(of: "<table", options: .caseInsensitive) != nil
            || text.range(of: "<html", options: .caseInsensitive) != nil
        var ergebnis: String
        var weggelassen = 0
        // Dezimalzeichen: Im Komma-CSV und in MetaTrader-Berichten nur der Punkt, sonst auch das Komma.
        var dezimal = "."
        if html {
            ergebnis = probe.maskiereHTML(text)
        } else {
            if CSVTabelle.trenner(Substring(text)) != "," { dezimal = ".," }
            var zeilen = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
            if let grenze = hoechstensZeilen, zeilen.count > 20 + grenze {
                weggelassen = zeilen.count - 20 - grenze
                zeilen = Array(zeilen.prefix(20 + grenze))
            }
            ergebnis = probe.maskiereCSV(zeilen).joined(separator: "\n")
        }
        ergebnis = probe.maskiereMuster(ergebnis, dezimal: dezimal)
        return Ergebnis(text: ergebnis, ersetzt: probe.zaehler, weggelassen: weggelassen)
    }
}

private struct Probe {
    var zaehler: [String: Int] = [:]
    /// Gleiche Nummer, gleicher Ersatz: Deals bleiben ihren Positionen zugeordnet.
    var nummern: [String: String] = [:]

    mutating func zaehle(_ art: String) { zaehler[art, default: 0] += 1 }

    /// Ersatz gleicher Länge, beginnt mit 9, damit führende Nullen und Vorzeichen keine Rolle spielen.
    mutating func ersatz(fuer nummer: String) -> String {
        if let bekannt = nummern[nummer] { return bekannt }
        if nummern.values.contains(nummer) { return nummer }
        let lfd = String(nummern.count + 1)
        let laenge = max(nummer.count, lfd.count + 1)
        let neu = "9" + String(repeating: "0", count: laenge - 1 - lfd.count) + lfd
        nummern[nummer] = neu
        zaehle("Nummer")
        return neu
    }

    // MARK: CSV

    /// Spalten mit Angaben zu Personen (Trade Republic), unabhängig von Groß- und Kleinschreibung.
    static let personenspalten: Set<String> = ["counterparty_name", "counterparty_iban", "payment_reference"]
    /// Felder der IBKR-Kontoinformation, die bleiben dürfen; alle anderen werden ersetzt.
    static let ibkrOffen: Set<String> = ["Base Currency", "Account Type", "Customer Type", "Account Capabilities"]

    mutating func maskiereCSV(_ zeilen: [String]) -> [String] {
        guard let erste = zeilen.first(where: { !$0.isEmpty }) else { return zeilen }
        let trenner = CSVTabelle.trenner(Substring(erste))
        // Kopfzeile: die erste Zeile, ab der die Feldzahl über die nächsten Zeilen gleich bleibt.
        // Davor steht ein Vorspann (Bitpanda, Coinbase) mit Name und Nutzerkennung.
        let felder = zeilen.map { CSVZeile.zerlege($0, trenner: trenner) }
        let ibkr = felder.first?.prefix(2) == ["Statement", "Header"]
        let kopfIndex = ibkr ? 0 : Self.findeKopf(felder)
        var personen: Set<Int> = []
        var namensspalte: Int?
        var namen: Set<String> = []
        if let kopf = felder[safe: kopfIndex] {
            namensspalte = kopf.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased() == "counterparty_name" }
            for (i, name) in kopf.enumerated()
            where Self.personenspalten.contains(name.trimmingCharacters(in: .whitespaces).lowercased()) {
                personen.insert(i)
            }
        }
        var aus: [String] = []
        for (i, zeile) in zeilen.enumerated() {
            if i < kopfIndex {
                if !zeile.isEmpty { zaehle("Vorspann") }
                aus.append(zeile.isEmpty ? zeile : "Vorspann entfernt")
                continue
            }
            var f = felder[i]
            if ibkr, f.count >= 4, f[0] == "Account Information", f[1] == "Data", !Self.ibkrOffen.contains(f[2]) {
                if !f[3].isEmpty {
                    f[3] = f[2] == "Account" ? "U" + ersatz(fuer: f[3]) : "Anonym"
                    if f[2] != "Account" { zaehle("Name") }
                }
                aus.append(CSVZeile.verbinde(f, trenner: trenner))
                continue
            }
            if i > kopfIndex, !personen.isEmpty {
                var geaendert = false
                for p in personen where p < f.count && !f[p].isEmpty {
                    if p == namensspalte { namen.insert(f[p]) }
                    f[p] = "Anonym"
                    zaehle("Name")
                    geaendert = true
                }
                if geaendert { aus.append(CSVZeile.verbinde(f, trenner: trenner)); continue }
            }
            aus.append(zeile)
        }
        // Namen der Gegenpartei stehen oft auch im Verwendungszweck („Überweisung von …“).
        for name in namen where name.count >= 3 {
            aus = aus.map { $0.replacingOccurrences(of: name, with: "Anonym") }
        }
        return aus
    }

    static func findeKopf(_ felder: [[String]]) -> Int {
        for i in felder.indices.prefix(15) {
            let n = felder[i].count
            guard n >= 3 else { continue }
            let folgende = felder[(i + 1)...].prefix(5).filter { !$0.isEmpty }
            if !folgende.isEmpty, folgende.allSatisfy({ $0.count == n }) { return i }
        }
        return 0
    }

    // MARK: HTML

    /// MetaTrader 4 und 5: Wert hinter „Name:“ und „Account:“ (MT4 „A/C No:“), auch wenn Tags dazwischen
    /// stehen. Name und Kontonummer werden danach überall ersetzt, auch im Titel.
    mutating func maskiereHTML(_ text: String) -> String {
        var t = text
        let zwischen = #"((?:\s|&nbsp;|</?[A-Za-z][^>]*>)*)"#
        var namen: [String] = []
        t = ersetze(t, muster: #"(Name:)"# + zwischen + #"([^<:]*[^<:\s])(?=\s*<)"#) { teile, probe in
            namen.append(teile[3])
            probe.zaehle("Name")
            return teile[1] + teile[2] + "Anonym"
        }
        var konten: [String] = []
        t = ersetze(t, muster: #"((?:Account|A/C No):)"# + zwischen + #"([0-9]+)"#) { teile, probe in
            konten.append(teile[3])
            return teile[1] + teile[2] + probe.ersatz(fuer: teile[3])
        }
        // MetaTrader 5 schreibt „Kontonummer: Name - Trade History Report“ in den Titel.
        t = ersetze(t, muster: #"(<title>[^<:]*:\s*)([^<]*?)(\s+-\s+[^<]*</title>)"#) { teile, _ in
            teile[1] + "Anonym" + teile[3]
        }
        for name in Set(namen) where name != "Anonym" {
            t = t.replacingOccurrences(of: name, with: "Anonym")
        }
        for konto in Set(konten) {
            let neu = ersatz(fuer: konto)
            let muster = #"(?<![0-9.,])"# + NSRegularExpression.escapedPattern(for: konto) + #"(?![0-9]|[.,][0-9])"#
            t = ersetze(t, muster: muster) { _, _ in neu }
        }
        return t
    }

    // MARK: Muster für jedes Format

    mutating func maskiereMuster(_ text: String, dezimal: String) -> String {
        var t = text
        t = ersetze(t, muster: #"\b[A-Z]{2}[0-9]{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b"#) { teile, probe in
            probe.zaehle("IBAN")
            return String(teile[0].map { $0 == " " ? " " : ($0.isNumber ? "0" : "X") })
        }
        t = ersetze(t, muster: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#) { _, probe in
            probe.zaehle("Mail")
            return "anonym@example.org"
        }
        // Lange Zahlen ohne Dezimalteil und ohne Buchstaben davor (ISIN bleibt): Konto-, Order-, Ticketnummern.
        let d = "[" + dezimal + "]"
        let lang = #"(?<![A-Za-z0-9])(?<![0-9]"# + d + #")[0-9]{8,}(?![0-9]|"# + d + #"[0-9])"#
        t = ersetze(t, muster: lang) { teile, probe in
            probe.ersatz(fuer: teile[0])
        }
        return t
    }

    /// Ersetzt jeden Treffer; `teile[0]` ist der ganze Treffer, danach die Gruppen.
    mutating func ersetze(_ text: String, muster: String, _ neu: (_ teile: [String], _ probe: inout Probe) -> String)
        -> String {
        guard let regex = try? NSRegularExpression(pattern: muster) else { return text }
        let ns = NSString(string: text)
        var aus = ""
        var letzte = 0
        for treffer in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            aus += ns.substring(with: NSRange(location: letzte, length: treffer.range.location - letzte))
            let teile = (0..<treffer.numberOfRanges).map { i -> String in
                let r = treffer.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            aus += neu(teile, &self)
            letzte = treffer.range.location + treffer.range.length
        }
        aus += ns.substring(from: letzte)
        return aus
    }
}

/// Eine CSV-Zeile zerlegen und wieder zusammensetzen, für die Probe (eine Zeile, kein Umbruch im Feld).
enum CSVZeile {
    static func zerlege(_ zeile: String, trenner: Character) -> [String] {
        CSVTabelle.zerlege(Substring(zeile), trenner: trenner).first ?? []
    }

    static func verbinde(_ felder: [String], trenner: Character) -> String {
        felder.map { feld in
            feld.contains(trenner) || feld.contains("\"")
                ? "\"" + feld.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : feld
        }.joined(separator: String(trenner))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
