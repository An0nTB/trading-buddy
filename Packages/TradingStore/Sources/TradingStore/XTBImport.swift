import Foundation
import GRDB
import TradingCore

// Speicherung der XTB-Kontoauszüge (Excel aus xStation 5): geschlossene Positionen wie bei MT4 in
// `geschlossenePosition`, Kassenoperationen ohne Handel in `geldbewegung` (Tabellen aus v1 und v3).

extension Journal {
    /// Name in `Importlauf.importer` für den XTB-Importer.
    public static let xtbImporter = "XTB-Excel"

    /// Liest einen XTB-Kontoauszug (Excel, „Account history“) und speichert ihn.
    ///
    /// Doppelte wie bei MT4 und CSV: Dieselbe Datei (SHA-256) wird übersprungen, eine bekannte Position
    /// (Konto + Positionsnummer) oder Kassenoperation (Konto + ID) nicht neu angelegt. Verglichen werden
    /// alle Werte außer der Rohzeile, weil Exporte verschiedener Zeiträume Spalten und Zeitformat anders
    /// schreiben können. Weicht ein Wert ab, bricht der ganze Import ab.
    ///
    /// Vorher prüft der Import die Summenzeilen „Total“ der Datei gegen die gelesenen Zeilen. Passt eine
    /// nicht, wird nichts gespeichert (gleiche Linie wie `MT4Statement.pruefe()`).
    /// - Parameters:
    ///   - kontonummer: nur nötig, wenn die Datei keine enthält; sonst muss sie zur Datei passen.
    ///   - kontowaehrung: nur nötig, wenn die Datei keine nennt (dann Vorgabe EUR); sonst wie oben.
    ///   - zeitzone: Zeitzone der Zeiten in der Datei; nicht belegt, Vorgabe deutsche Ortszeit.
    /// - Returns: Zähler für Positionen in `geschlosseneNeu`/`geschlosseneBekannt`, für Kassenoperationen
    ///   und Hinweise in `csv`.
    @discardableResult
    public func importiereXTB(datei: Data, dateiname: String, kontonummer: String? = nil,
                              kontoname: String? = nil, kontowaehrung: String? = nil,
                              zeitzone: TimeZone = TimeZone(identifier: "Europe/Berlin")!,
                              jetzt: Date = Date()) throws -> ImportErgebnis {
        let hash = Self.fingerabdruck(datei)
        if let bekannt = try lies({ try Importlauf.filter(Column("dateiHash") == hash).fetchOne($0) }) {
            return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
        }

        let auszug = try XTBAuszug.lies(datei, zeitzone: zeitzone)
        let abweichungen = Self.summenpruefung(auszug)
        guard abweichungen.isEmpty else { throw SpeicherFehler.auszugWidersprichtSeinenSummen(abweichungen) }
        let nummer = try Self.kontoangabe("Kontonummer", datei: auszug.konto, angegeben: kontonummer, vorgabe: nil)
        let waehrung = try Self.kontoangabe("Kontowährung", datei: auszug.waehrung, angegeben: kontowaehrung,
                                            vorgabe: "EUR")
        // Ohne ID-Zelle vergibt XTBAuszug „zeile-N“; die Zeilennummer ist in jeder Datei eine andere
        // und taugt deshalb nicht als Schlüssel für Doppelte.
        if auszug.positionen.contains(where: { $0.ticket.isEmpty })
            || auszug.kasse.geldbewegungen.contains(where: { $0.id.isEmpty || $0.id.hasPrefix("zeile-") }) {
            throw SpeicherFehler.ungueltigerWert("Vorgang ohne Kennung (Position oder ID) in \(dateiname)")
        }
        // Fehlt die Währung im Kopf, steht sie leer an jeder Kassenoperation; es ist die Kontowährung.
        let kasse = auszug.kasse.geldbewegungen.map { g in
            var g = g
            if g.waehrung.isEmpty { g.waehrung = waehrung }
            return g
        }
        let zeiten = auszug.positionen.map(\.closeTime) + kasse.map(\.zeit)

        return try schreibe { db in
            if let bekannt = try Importlauf.filter(Column("dateiHash") == hash).fetchOne(db) {
                return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
            }
            let konto = try Self.konto(db, broker: "XTB", nummer: nummer, name: kontoname ?? nummer,
                                       waehrung: waehrung)
            let kontoId = konto.id!
            var lauf = Importlauf(id: nil, kontoId: kontoId, importer: Self.xtbImporter,
                                  importerVersion: TradingCore.version, dateiname: dateiname,
                                  dateiHash: hash, datei: datei, art: "kontoauszug",
                                  stichtag: zeiten.max() ?? jetzt, serverZeitzone: zeitzone.identifier,
                                  importiertAm: jetzt)
            try lauf.insert(db)
            let laufId = lauf.id!
            var ergebnis = ImportErgebnis(status: .gespeichert, importlaufId: laufId)
            var abweichend: [String] = []

            for p in auszug.positionen {
                if let alt = try GeschlossenZeile
                    .filter(Column("kontoId") == kontoId && Column("ticket") == p.ticket).fetchOne(db) {
                    var vergleich = try alt.modell()
                    vergleich.rohzeile = p.rohzeile
                    vergleich.openTime = gleicheZeit(vergleich.openTime, p.openTime)
                    vergleich.closeTime = gleicheZeit(vergleich.closeTime, p.closeTime)
                    if vergleich == p { ergebnis.geschlosseneBekannt += 1 } else { abweichend.append(p.ticket) }
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
            for h in auszug.hinweise {
                try HinweisZeile(importlaufId: laufId, zeile: h.zeile, vorgang: h.vorgang,
                                 folge: h.folge.rawValue).insert(db)
                ergebnis.csv.hinweise += 1
            }

            // Ein Fehler in der Transaktion macht alle Schreibvorgänge oben rückgängig.
            guard abweichend.isEmpty else { throw SpeicherFehler.abweichenderDatensatz(tickets: abweichend) }
            return ergebnis
        }
    }

    /// Summenzeilen der Datei gegen die gelesenen Zeilen. Leer, wenn alles passt oder die Datei keine hat.
    static func summenpruefung(_ auszug: XTBAuszug) -> [String] {
        var abweichungen: [String] = []
        if let summe = auszug.positionenLautSumme {
            let p = auszug.positionen
            // Einzeln und mit Typ, sonst braucht der Swift-Compiler zu lange für die Typprüfung.
            let kommission: Decimal = p.reduce(0) { $0 + $1.commission }
            let swap: Decimal = p.reduce(0) { $0 + $1.swap }
            let ergebnis: Decimal = p.reduce(0) { $0 + $1.profit }
            let werte: [(String, Decimal, Decimal)] = [("Kommission", summe.commission, kommission),
                                                       ("Swap", summe.swap, swap),
                                                       ("Ergebnis", summe.profit, ergebnis)]
            for (name, soll, ist) in werte where soll != ist {
                abweichungen.append("Positionen \(name): Summe \(soll), Zeilen \(ist)")
            }
        }
        if let summe = auszug.kasseLautSumme, summe != auszug.kassenwirkung {
            abweichungen.append("Kasse: Summe \(summe), Zeilen \(auszug.kassenwirkung)")
        }
        return abweichungen
    }

    /// Angabe aus der Datei, sonst die der App, sonst die Vorgabe. Widersprechen sich Datei und App,
    /// bricht der Import ab, statt still eine Fassung zu wählen.
    static func kontoangabe(_ name: String, datei: String?, angegeben: String?, vorgabe: String?) throws -> String {
        if let datei, let angegeben, datei != angegeben {
            throw SpeicherFehler.ungueltigerWert("\(name) laut Datei \(datei), angegeben \(angegeben)")
        }
        guard let wert = datei ?? angegeben ?? vorgabe else {
            throw SpeicherFehler.ungueltigerWert("\(name) fehlt in der Datei und wurde nicht angegeben")
        }
        return wert
    }
}
