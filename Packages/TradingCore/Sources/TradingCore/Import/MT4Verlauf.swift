import Foundation

/// Kursverlauf aus dem MetaTrader-Verlaufszentrum (Doc 39, F7): die Kurse des eigenen Brokers,
/// passend zu den Trades im Auszug. Gelesen werden zwei Formen:
/// - MetaTrader 4, „Extras → Verlaufszentrum → Exportieren“: ohne Kopf, Komma,
///   `2026.05.06,10:41,197.851,197.873,197.836,197.840,41`
/// - MetaTrader 5, „Symbole → Balken → Exportieren“: Kopf `<DATE>	<TIME>	<OPEN>…`, Tabulator,
///   Zeit mit Sekunden.
/// Format nach Doku und Beispielen, noch nicht an einer echten Datei geprüft (Doc 39).
public enum MT4Verlauf {
    /// Kerzen in UTC, aufsteigend sortiert.
    /// - Parameters:
    ///   - serverZeitzone: dieselbe Zeitzone wie beim Auszug; Verlauf und Auszug laufen in Serverzeit.
    ///   - dauer: Länge einer Kerze in Sekunden. Ohne Angabe der kleinste Abstand zweier Kerzen, sonst 60.
    public static func parse(text: String, serverZeitzone: TimeZone, dauer: Int? = nil) throws -> [Zeitkerze] {
        var roh: [(beginn: Date, werte: [Decimal])] = []
        for zeile in text.split(whereSeparator: \.isNewline) {
            let inhalt = zeile.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{FEFF}", with: "")
            guard !inhalt.isEmpty, !inhalt.hasPrefix("<") else { continue }
            let zellen = inhalt.split(whereSeparator: { $0 == "," || $0 == "\t" || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard zellen.count >= 6 else {
                throw MT4ImportFehler.unerwarteteSpalten(abschnitt: "Verlauf", gefunden: zellen)
            }
            let uhrzeit = zellen[1].filter { $0 == ":" }.count == 1 ? zellen[1] + ":00" : zellen[1]
            let beginn = try MT4Werte.zeit(zellen[0] + " " + uhrzeit, zeitzone: serverZeitzone)
            let werte = try zellen[2...5].map { try MT4Werte.zahl($0) }
            guard werte[2] <= werte[1] else { throw MT4ImportFehler.ungueltigeZahl(inhalt) }
            roh.append((beginn, werte))
        }
        roh.sort { $0.beginn < $1.beginn }
        let abstaende = zip(roh, roh.dropFirst()).map { Int($1.beginn.timeIntervalSince($0.beginn)) }.filter { $0 > 0 }
        let laenge = dauer ?? abstaende.min() ?? 60
        return roh.map {
            Zeitkerze(beginn: $0.beginn, dauer: laenge, open: $0.werte[0], high: $0.werte[1], low: $0.werte[2],
                      close: $0.werte[3])
        }
    }
}
