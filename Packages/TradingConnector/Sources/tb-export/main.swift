import Foundation
import TradingCore

// Baut die Exportdatei für den Connector aus MetaTrader-4-Auszügen, ohne App.
// Zum Testen des Connectors, solange die App die Datei noch nicht schreibt.
// Aufruf: tb-export --ziel <Ordner> [--waehrung EUR] [--serverzeit 3] Auszug.html …
// Trades aus Tages- und Monatsauszügen zählen einmal (Konto plus Ticket, wie im Journal).

var zielOrdner: String?
var waehrung = "EUR"
var serverzeit = 3
var dateien: [String] = []
var argumente = CommandLine.arguments.dropFirst().makeIterator()
while let arg = argumente.next() {
    switch arg {
    case "--ziel": zielOrdner = argumente.next()
    case "--waehrung": waehrung = argumente.next() ?? waehrung
    case "--serverzeit": serverzeit = argumente.next().flatMap { Int($0) } ?? serverzeit
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
                         geloeschteOrders: k.daten.geloescht.values.sorted())
        },
        zeitzone: .current)
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
