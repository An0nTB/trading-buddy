import Foundation
import TradingCore

// Baut die Exportdatei für den Connector aus MetaTrader-4-Auszügen, ohne App.
// Zum Testen des Connectors, solange die App die Datei noch nicht schreibt.
// Aufruf: tb-export --ziel <Ordner> [--waehrung EUR] [--serverzeit 3] [--trades-je-tag 3] Auszug.html …
// `--trades-je-tag` setzt eine eigene Handelsregel für alle Konten, damit CI den Regelabschnitt prüft.
// `--beispielkurse SYMBOL` legt erfundene Tageskerzen (Montag bis Freitag, 400 Tage bis 06.06.2025) für SYMBOL an,
// damit CI `hole_kursanalyse` mit Kursen prüft; die Kurse sind gerechnet, keine Marktdaten.
// Trades aus Tages- und Monatsauszügen zählen einmal (Konto plus Ticket, wie im Journal).

/// Gerechnete Kerzen: Welle um 100 mit leichtem Anstieg, Spanne 1 um den Schluss, nur Werktage.
func beispielreihe(_ symbol: String) -> JournalExport.Kursreihe {
    let utc = TimeZone(secondsFromGMT: 0)!
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = utc
    let ende = kalender.date(from: DateComponents(year: 2025, month: 6, day: 6))!
    var kerzen: [Kerze] = []
    var vorher: Decimal = 100
    for i in 0..<400 {
        let tag = kalender.date(byAdding: .day, value: i - 399, to: ende)!
        guard !kalender.isDateInWeekend(tag) else { continue }
        let schluss = Decimal(100 + 10 * sin(Double(i) / 20) + Double(i) * 0.05).gerundet(2)
        kerzen.append(Kerze(tag: Journaltag(tag, zeitzone: utc), open: vorher, high: max(vorher, schluss) + 1,
                            low: min(vorher, schluss) - 1, close: schluss))
        vorher = schluss
    }
    return .init(symbol: symbol, quelle: "beispiel", waehrung: "USD", stand: ende.addingTimeInterval(86_400),
                 kerzen: kerzen)
}

var zielOrdner: String?
var waehrung = "EUR"
var serverzeit = 3
var tradesJeTag: Int?
var beispielkurse: String?
var dateien: [String] = []
var argumente = CommandLine.arguments.dropFirst().makeIterator()
while let arg = argumente.next() {
    switch arg {
    case "--ziel": zielOrdner = argumente.next()
    case "--waehrung": waehrung = argumente.next() ?? waehrung
    case "--serverzeit": serverzeit = argumente.next().flatMap { Int($0) } ?? serverzeit
    case "--trades-je-tag": tradesJeTag = argumente.next().flatMap { Int($0) }
    case "--beispielkurse": beispielkurse = argumente.next()
    default: dateien.append(arg)
    }
}
guard let ziel = zielOrdner, !dateien.isEmpty, let zone = TimeZone(secondsFromGMT: serverzeit * 3600) else {
    print("Aufruf: tb-export --ziel <Ordner> [--waehrung EUR] [--serverzeit 3] Auszug.html …")
    exit(2)
}

struct Sammlung {
    var trades: [String: Trade] = [:]
    var geloescht: [String: Date] = [:]
}
var konten: [String: (broker: String, nummer: String, daten: Sammlung)] = [:]
do {
    for datei in dateien {
        let auszug = try MT4Statement.parse(html: String(contentsOfFile: datei, encoding: .utf8), serverZeitzone: zone)
        let schluessel = "\(auszug.broker)|\(auszug.accountNumber)"
        var eintrag = konten[schluessel] ?? (broker: auszug.broker, nummer: auszug.accountNumber, daten: Sammlung())
        for p in auszug.closedPositions { eintrag.daten.trades[p.ticket] = Trade(p) }
        for o in auszug.cancelledOrders { eintrag.daten.geloescht[o.ticket] = o.cancelledAt }
        konten[schluessel] = eintrag
    }
    let export = JournalExport(
        konten: konten.keys.sorted().map { schluessel -> JournalExport.Kontodaten in
            let k = konten[schluessel]!
            return .init(broker: k.broker, kontonummer: k.nummer, waehrung: waehrung,
                         trades: k.daten.trades.values.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) },
                         geloeschteOrders: k.daten.geloescht.values.sorted(),
                         regeln: Handelsregeln(maxTradesJeTag: tradesJeTag))
        },
        zeitzone: .current, kursverlauf: beispielkurse.map { [beispielreihe($0)] } ?? [])
    let pfad = URL(filePath: ziel, directoryHint: .isDirectory).appending(path: JournalExport.dateiname)
    try export.json().write(to: pfad, options: .atomic)
    for k in export.konten {
        print("\(export.kurzname(k)): \(k.trades.count) Trades, \(k.geloeschteOrders.count) gelöschte Orders")
    }
    print("Geschrieben: \(pfad.path)")
} catch {
    print("Fehler: \(error)")
    exit(1)
}
