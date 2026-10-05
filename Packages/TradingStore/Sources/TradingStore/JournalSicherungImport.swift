import Foundation
import GRDB
import TradingCore

// Import der Sicherung des Browser-Journals (`journal-sicherung-JJJJ-MM-TT.json`, Doc 02 Nr. 63):
// Positionen in `geschlossenePosition` (Migration v11 für Ausstiegszeit und Markterwartung), Setup, Regeltreue,
// Notiz und Risiko ins Journal, Setup-Namen ins Playbook.

extension Journal {
    /// Name in `Importlauf.importer` für die Journal-Sicherung.
    public static let journalSicherungImporter = "Journal-Sicherung"
    /// Broker des Kontos, wenn die App keinen anderen angibt: Die Sicherung nennt keinen.
    public static let journalSicherungBroker = "Trading Journal"

    /// Liest eine Sicherung des Browser-Journals und speichert sie in ein Euro-Konto.
    ///
    /// Doppelte wie bei den anderen Importen: Dieselbe Datei (SHA-256) wird übersprungen, eine bekannte Position
    /// (Konto + Ticket `js-<id>`) nicht neu angelegt. Verglichen werden alle Werte außer der Rohzeile, dazu
    /// Markterwartung und Schein; weicht einer ab (im Browser nachträglich geändert), bricht der ganze Import ab.
    ///
    /// Journaleinträge (Setup, Zeiteinheit, Regeltreue, Notiz als `grund`, Risiko als `risikoEinstieg`) nur für
    /// Tickets ohne Eintrag; was in Henry schon steht, bleibt. Setup-Namen ohne Karte bekommen eine neue Karte
    /// (Status „test“). Trades ohne Exit zählen in `ohneAusstieg`, unlesbare Zeilen als Importhinweis.
    /// - Parameters:
    ///   - kontonummer: Die Sicherung nennt kein Konto; die App fragt es ab. Das Konto muss in Euro geführt sein.
    ///   - zeitzone: Zeitzone, in der Datum und Uhrzeit im Journal stehen.
    @discardableResult
    public func importiereJournalSicherung(datei: Data, dateiname: String, kontonummer: String,
                                           kontoname: String? = nil, broker: String = journalSicherungBroker,
                                           zeitzone: TimeZone = TimeZone(identifier: "Europe/Berlin")!,
                                           jetzt: Date = Date()) throws -> ImportErgebnis {
        let hash = Self.fingerabdruck(datei)
        if let bekannt = try lies({ try Importlauf.filter(Column("dateiHash") == hash).fetchOne($0) }) {
            return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
        }
        let nummer = kontonummer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nummer.isEmpty else { throw SpeicherFehler.ungueltigerWert("Kontonummer fehlt") }
        let sicherung = try JournalSicherung.lies(datei, zeitzone: zeitzone)
        let setupnamen = Self.setupnamen(sicherung)

        return try schreibe { db in
            if let bekannt = try Importlauf.filter(Column("dateiHash") == hash).fetchOne(db) {
                return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
            }
            let konto = try Self.konto(db, broker: broker, nummer: nummer, name: kontoname ?? nummer,
                                       waehrung: "EUR")
            let kontoId = konto.id!
            var lauf = Importlauf(id: nil, kontoId: kontoId, importer: Self.journalSicherungImporter,
                                  importerVersion: TradingCore.version, dateiname: dateiname,
                                  dateiHash: hash, datei: datei, art: "journal-sicherung",
                                  stichtag: sicherung.positionen.map(\.closeTime).max() ?? jetzt,
                                  serverZeitzone: zeitzone.identifier, importiertAm: jetzt)
            try lauf.insert(db)
            let laufId = lauf.id!
            var ergebnis = ImportErgebnis(status: .gespeichert, importlaufId: laufId)
            ergebnis.ohneAusstieg = sicherung.offen
            var abweichend: [String] = []

            for (p, e) in zip(sicherung.positionen, sicherung.eintraege) {
                let neu = GeschlossenZeile(kontoId: kontoId, importlaufId: laufId, p,
                                           markterwartung: e.markterwartung, schein: e.schein)
                if let alt = try GeschlossenZeile
                    .filter(Column("kontoId") == kontoId && Column("ticket") == p.ticket).fetchOne(db) {
                    var vergleich = try alt.modell()
                    let produktart = vereinteProduktart(vergleich.produktart, p.produktart)
                    vergleich.rohzeile = p.rohzeile
                    vergleich.produktart = p.produktart
                    if vergleich == p, alt.markterwartung == neu.markterwartung, alt.schein == neu.schein {
                        ergebnis.geschlosseneBekannt += 1
                        try Self.ergaenzeProduktart(db, alt, produktart)
                    } else {
                        abweichend.append(p.ticket)
                    }
                } else {
                    try neu.insert(db)
                    ergebnis.geschlosseneNeu += 1
                }
                if try Self.legeEintragAn(db, e, kontoId: kontoId, jetzt: jetzt) { ergebnis.journaleintraegeNeu += 1 }
            }
            for name in setupnamen {
                guard try SetupZeile.filter(Column("name") == name).fetchCount(db) == 0 else { continue }
                var zeile = SetupZeile(Setup(name: name, statusSeit: jetzt))
                try zeile.insert(db)
                ergebnis.setupsNeu += 1
            }
            for h in sicherung.hinweise {
                try HinweisZeile(importlaufId: laufId, zeile: h.zeile, vorgang: h.vorgang,
                                 folge: h.folge.rawValue).insert(db)
                ergebnis.csv.hinweise += 1
            }

            // Ein Fehler in der Transaktion macht alle Schreibvorgänge oben rückgängig.
            guard abweichend.isEmpty else { throw SpeicherFehler.abweichenderDatensatz(tickets: abweichend) }
            return ergebnis
        }
    }

    /// Setup-Namen aus der Liste der Sicherung und aus den Trades, jeder einmal, in dieser Reihenfolge.
    static func setupnamen(_ sicherung: JournalSicherung) -> [String] {
        var gesehen = Set<String>()
        return (sicherung.setups + sicherung.eintraege.compactMap(\.setup))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && gesehen.insert($0).inserted }
    }

    /// Legt den Journaleintrag aus der Sicherung an, wenn das Ticket noch keinen hat und die Sicherung etwas
    /// mitbringt. `true`, wenn einer angelegt wurde.
    static func legeEintragAn(_ db: Database, _ e: JournalSicherung.Eintrag, kontoId: Int64,
                              jetzt: Date) throws -> Bool {
        guard e.setup != nil || e.regeltreue != nil || e.notiz != nil || e.risiko != nil || e.zeiteinheit != nil
        else { return false }
        guard try !Journaleintrag.exists(db, key: ["kontoId": kontoId, "ticket": e.ticket]) else { return false }
        let eintrag = Journaleintrag(kontoId: kontoId, ticket: e.ticket, setup: e.setup, regeltreue: e.regeltreue,
                                     grund: e.notiz, risikoEinstieg: e.risiko.map { abs($0) },
                                     zeiteinheit: e.zeiteinheit, geaendertAm: jetzt)
        try eintrag.insert(db)
        return true
    }
}
