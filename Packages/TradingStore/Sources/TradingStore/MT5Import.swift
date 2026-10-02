import Foundation
import GRDB
import TradingCore

// Speicherung der MetaTrader-5-Handelsberichte (HTML aus dem Terminal, Doc 48): geschlossene Positionen wie
// bei MT4 und XTB in `geschlossenePosition`, Kassenzeilen aus „Deals“ in `geldbewegung` (Tabellen aus v1 und v3).

extension Journal {
    /// Name in `Importlauf.importer` für den MT5-Importer.
    public static let mt5Importer = "MT5-HTML"
    /// Broker, wenn der Bericht keine „Company:“ nennt.
    public static let mt5BrokerVorgabe = "MetaTrader 5"

    /// Liest einen MetaTrader-5-Handelsbericht (HTML, UTF-16 oder UTF-8) und speichert ihn.
    ///
    /// Doppelte wie bei MT4 und XTB: Dieselbe Datei (SHA-256) wird übersprungen, eine bekannte Position
    /// (Konto + Positionsnummer) oder Kassenzeile (Konto + Deal) nicht neu angelegt. Verglichen werden alle
    /// Werte außer der Rohzeile; weicht einer ab, bricht der ganze Import ab.
    ///
    /// Vorher prüft der Import die Summenzeile unter „Positions“ gegen die gelesenen Positionen. Passt sie
    /// nicht, wird nichts gespeichert. Fehlt sie, entfällt die Prüfung.
    /// - Parameters:
    ///   - kontonummer: nur nötig, wenn der Bericht keine enthält; sonst muss sie zum Bericht passen.
    ///   - kontowaehrung: nur nötig, wenn der Bericht keine nennt; sonst wie oben.
    ///   - serverZeitzone: Zeitzone des Handelsservers; steht nicht im Bericht, die App fragt sie ab.
    ///   - produktartVorgabe: Art für Positionen, bei denen der Importer keine erkennt; wie bei `importiereCSV`.
    /// - Returns: Zähler für Positionen in `geschlosseneNeu`/`geschlosseneBekannt`, für Kassenzeilen und
    ///   Hinweise in `csv`.
    @discardableResult
    public func importiereMT5(datei: Data, dateiname: String, kontonummer: String? = nil,
                              kontoname: String? = nil, kontowaehrung: String? = nil,
                              serverZeitzone: TimeZone, produktartVorgabe: Produktart? = nil,
                              jetzt: Date = Date()) throws -> ImportErgebnis {
        let hash = Self.fingerabdruck(datei)
        if let bekannt = try lies({ try Importlauf.filter(Column("dateiHash") == hash).fetchOne($0) }) {
            return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
        }
        guard let text = MT5Bericht.text(datei) else { throw SpeicherFehler.keinText }

        let bericht = try MT5Bericht.lies(text, serverZeitzone: serverZeitzone)
        let abweichungen = Self.summenpruefung(bericht)
        guard abweichungen.isEmpty else { throw SpeicherFehler.auszugWidersprichtSeinenSummen(abweichungen) }
        let nummer = try Self.kontoangabe("Kontonummer", datei: bericht.konto, angegeben: kontonummer, vorgabe: nil)
        let waehrung = try Self.kontoangabe("Kontowährung", datei: bericht.waehrung, angegeben: kontowaehrung,
                                            vorgabe: nil)
        let broker = bericht.broker.flatMap { $0.isEmpty ? nil : $0 } ?? Self.mt5BrokerVorgabe
        if bericht.positionen.contains(where: { $0.ticket.trimmingCharacters(in: .whitespaces).isEmpty })
            || bericht.kasse.geldbewegungen.contains(where: { $0.id.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw SpeicherFehler.ungueltigerWert("Vorgang ohne Kennung (Position oder Deal) in \(dateiname)")
        }
        // Kassenzeilen ohne Währung laufen in der Kontowährung.
        let kasse = bericht.kasse.geldbewegungen.map { g in
            var g = g
            if g.waehrung.isEmpty { g.waehrung = waehrung }
            return g
        }
        let zeiten = bericht.positionen.map(\.closeTime) + kasse.map(\.zeit)

        return try schreibe { db in
            if let bekannt = try Importlauf.filter(Column("dateiHash") == hash).fetchOne(db) {
                return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
            }
            let konto = try Self.konto(db, broker: broker, nummer: nummer, name: kontoname ?? nummer,
                                       waehrung: waehrung)
            let kontoId = konto.id!
            var lauf = Importlauf(id: nil, kontoId: kontoId, importer: Self.mt5Importer,
                                  importerVersion: TradingCore.version, dateiname: dateiname,
                                  dateiHash: hash, datei: datei, art: "kontoauszug",
                                  stichtag: zeiten.max() ?? jetzt, serverZeitzone: serverZeitzone.identifier,
                                  importiertAm: jetzt)
            try lauf.insert(db)
            let laufId = lauf.id!
            var ergebnis = ImportErgebnis(status: .gespeichert, importlaufId: laufId)
            var abweichend: [String] = []

            for var p in bericht.positionen {
                let alt = try GeschlossenZeile
                    .filter(Column("kontoId") == kontoId && Column("ticket") == p.ticket).fetchOne(db)
                p.produktart = vorgegeben(p.produktart, gespeichert: alt?.produktart, produktartVorgabe)
                if let alt {
                    var vergleich = try alt.modell()
                    let produktart = vereinteProduktart(vergleich.produktart, p.produktart)
                    vergleich.rohzeile = p.rohzeile
                    vergleich.openTime = gleicheZeit(vergleich.openTime, p.openTime)
                    vergleich.closeTime = gleicheZeit(vergleich.closeTime, p.closeTime)
                    vergleich.produktart = p.produktart
                    if vergleich == p {
                        ergebnis.geschlosseneBekannt += 1
                        try Self.ergaenzeProduktart(db, alt, produktart)
                    } else {
                        abweichend.append(p.ticket)
                    }
                } else {
                    try GeschlossenZeile(kontoId: kontoId, importlaufId: laufId, p).insert(db)
                    ergebnis.geschlosseneNeu += 1
                }
            }
            for g in kasse {
                if let alt = try GeldbewegungZeile
                    .filter(Column("kontoId") == kontoId && Column("vorgangId") == g.id).fetchOne(db) {
                    var vergleich = try alt.modell()
                    vergleich.rohzeile = g.rohzeile
                    vergleich.zeit = gleicheZeit(vergleich.zeit, g.zeit)
                    if vergleich == g { ergebnis.csv.geldbewegungenBekannt += 1 } else { abweichend.append(g.id) }
                } else {
                    try GeldbewegungZeile(kontoId: kontoId, importlaufId: laufId, g).insert(db)
                    ergebnis.csv.geldbewegungenNeu += 1
                }
            }
            for h in bericht.hinweise {
                try HinweisZeile(importlaufId: laufId, zeile: h.zeile, vorgang: h.vorgang,
                                 folge: h.folge.rawValue).insert(db)
                ergebnis.csv.hinweise += 1
            }

            // Ein Fehler in der Transaktion macht alle Schreibvorgänge oben rückgängig.
            guard abweichend.isEmpty else { throw SpeicherFehler.abweichenderDatensatz(tickets: abweichend) }
            return ergebnis
        }
    }

    /// Summenzeile unter „Positions“ gegen die gelesenen Positionen. Leer, wenn alles passt oder sie fehlt.
    static func summenpruefung(_ bericht: MT5Bericht) -> [String] {
        guard let summe = bericht.positionenLautSumme else { return [] }
        let p = bericht.positionen
        // Einzeln und mit Typ, sonst braucht der Swift-Compiler zu lange für die Typprüfung.
        let kommission: Decimal = p.reduce(0) { $0 + $1.commission }
        let swap: Decimal = p.reduce(0) { $0 + $1.swap }
        let ergebnis: Decimal = p.reduce(0) { $0 + $1.profit }
        let werte: [(String, Decimal, Decimal)] = [("Kommission", summe.commission, kommission),
                                                   ("Swap", summe.swap, swap),
                                                   ("Ergebnis", summe.profit, ergebnis)]
        return werte.filter { $0.1 != $0.2 }.map { "Positionen \($0.0): Summe \($0.1), Zeilen \($0.2)" }
    }
}
