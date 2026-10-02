import Foundation
import GRDB
import TradingCore

// Speicherung der CSV-Importe (Trade Republic, Scalable; Kryptobörsen Kraken, Binance, Coinbase, Bitpanda):
// Ausführungen, Geldbewegungen, Kapitalmaßnahmen, verworfene Orders und Importhinweise (Migration v3).

struct AusfuehrungZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ausfuehrung"
    var kontoId: Int64
    var importlaufId: Int64
    var vorgangId: String
    var zeit: Date
    var nurDatum: Bool
    var kennung: String
    var name: String
    var seite: String
    var menge: Decimal
    var preis: Decimal
    var betrag: Decimal
    var gebuehr: Decimal
    var steuer: Decimal
    var waehrung: String
    var sparplan: Bool
    var rohzeile: [String]
    var produktart: String

    init(kontoId: Int64, importlaufId: Int64, _ a: Ausfuehrung) {
        self.kontoId = kontoId
        self.importlaufId = importlaufId
        vorgangId = a.id
        zeit = a.zeit
        nurDatum = a.nurDatum
        kennung = a.kennung
        name = a.name
        seite = a.seite.rawValue
        menge = a.menge
        preis = a.preis
        betrag = a.betrag
        gebuehr = a.gebuehr
        steuer = a.steuer
        waehrung = a.waehrung
        sparplan = a.sparplan
        rohzeile = a.rohzeile
        produktart = a.produktart.rawValue
    }

    func modell() throws -> Ausfuehrung {
        guard let s = Side(rawValue: seite) else { throw SpeicherFehler.unbekannterWert(seite) }
        return Ausfuehrung(id: vorgangId, zeit: zeit, nurDatum: nurDatum, kennung: kennung, name: name, seite: s,
                           menge: menge, preis: preis, betrag: betrag, gebuehr: gebuehr, steuer: steuer,
                           waehrung: waehrung, sparplan: sparplan, produktart: try art(produktart),
                           rohzeile: rohzeile)
    }
}

struct GeldbewegungZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "geldbewegung"
    var kontoId: Int64
    var importlaufId: Int64
    var vorgangId: String
    var zeit: Date
    var nurDatum: Bool
    var art: String
    var betrag: Decimal
    var gebuehr: Decimal
    var steuer: Decimal
    var waehrung: String
    var kennung: String?
    var rohzeile: [String]

    init(kontoId: Int64, importlaufId: Int64, _ g: Geldbewegung) {
        self.kontoId = kontoId
        self.importlaufId = importlaufId
        vorgangId = g.id
        zeit = g.zeit
        nurDatum = g.nurDatum
        art = g.art.rawValue
        betrag = g.betrag
        gebuehr = g.gebuehr
        steuer = g.steuer
        waehrung = g.waehrung
        kennung = g.kennung
        rohzeile = g.rohzeile
    }

    func modell() throws -> Geldbewegung {
        guard let a = Geldbewegung.Art(rawValue: art) else { throw SpeicherFehler.unbekannterWert(art) }
        return Geldbewegung(id: vorgangId, zeit: zeit, nurDatum: nurDatum, art: a, betrag: betrag,
                            gebuehr: gebuehr, steuer: steuer, waehrung: waehrung, kennung: kennung,
                            rohzeile: rohzeile)
    }
}

struct KapitalmassnahmeZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kapitalmassnahme"
    var kontoId: Int64
    var importlaufId: Int64
    var vorgangId: String
    var zeit: Date
    var art: String
    var vorgang: String
    var kennung: String
    var menge: Decimal
    var rohzeile: [String]

    init(kontoId: Int64, importlaufId: Int64, _ k: Kapitalmassnahme) {
        self.kontoId = kontoId
        self.importlaufId = importlaufId
        vorgangId = k.id
        zeit = k.zeit
        art = k.art.rawValue
        vorgang = k.vorgang
        kennung = k.kennung
        menge = k.menge
        rohzeile = k.rohzeile
    }

    func modell() throws -> Kapitalmassnahme {
        guard let a = Kapitalmassnahme.Art(rawValue: art) else { throw SpeicherFehler.unbekannterWert(art) }
        return Kapitalmassnahme(id: vorgangId, zeit: zeit, art: a, vorgang: vorgang, kennung: kennung,
                                menge: menge, rohzeile: rohzeile)
    }
}

struct VerworfenZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "verworfenerVorgang"
    var kontoId: Int64
    var importlaufId: Int64
    var vorgangId: String
}

struct HinweisZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "importhinweis"
    var importlaufId: Int64
    var zeile: Int
    var vorgang: String
    var folge: String

    func modell() throws -> Importhinweis {
        guard let f = Importhinweis.Folge(rawValue: folge) else { throw SpeicherFehler.unbekannterWert(folge) }
        return Importhinweis(zeile: zeile, vorgang: vorgang, folge: f)
    }
}

/// GRDB speichert Zeiten auf die Millisekunde; feinere Unterschiede gelten beim Vergleich als gleich.
func gleicheZeit(_ gespeichert: Date, _ neu: Date) -> Date {
    abs(gespeichert.timeIntervalSince(neu)) < 0.001 ? neu : gespeichert
}

extension ImportErgebnis {
    /// Neue und schon bekannte Datensätze eines CSV-Imports (bei XTB nur Geldbewegungen und Hinweise).
    public struct CSVZaehler: Sendable, Equatable {
        public var ausfuehrungenNeu = 0
        public var ausfuehrungenBekannt = 0
        public var geldbewegungenNeu = 0
        public var geldbewegungenBekannt = 0
        public var kapitalmassnahmenNeu = 0
        public var kapitalmassnahmenBekannt = 0
        public var verworfen = 0
        public var hinweise = 0
    }
}

extension Journal {
    /// Namen in `Importlauf.importer` für die CSV-Importer.
    public static let tradeRepublicImporter = "TradeRepublic-CSV"
    public static let scalableImporter = "Scalable-CSV"
    public static let krakenImporter = "Kraken-CSV"
    public static let binanceImporter = "Binance-CSV"
    public static let coinbaseImporter = "Coinbase-CSV"
    public static let bitpandaImporter = "Bitpanda-CSV"

    /// Liest einen CSV-Export von Trade Republic, Scalable, Kraken, Binance, Coinbase oder Bitpanda und
    /// speichert ihn.
    /// Das Format wird am Spaltenkopf erkannt, nicht am Dateinamen.
    ///
    /// Doppelte wie beim MT4-Import auf zwei Ebenen: dieselbe Datei (SHA-256) wird übersprungen,
    /// ein schon bekannter Vorgang (Konto + Vorgangs-ID) nicht neu angelegt. Verglichen werden dabei
    /// alle Werte außer der Rohzeile, weil derselbe Vorgang in zwei Exportvarianten (Komma oder
    /// Semikolon) verschieden aussieht. Weicht ein Wert ab, bricht der ganze Import ab.
    /// - Parameters:
    ///   - kontonummer: steht nicht in der Datei; die App fragt sie ab oder nimmt eine feste Bezeichnung.
    ///   - kontowaehrung: Vorgabe EUR (Entscheidung 16).
    ///   - zeitzone: nur für Scalable (deutsche Ortszeit); Trade Republic und die Kryptobörsen schreiben UTC
    ///     oder Zeiten mit Versatz.
    ///   - produktartVorgabe: Art für Ausführungen, bei denen der Importer keine erkennt (`.unbekannt`, etwa
    ///     Scalable), z. B. aus der Nachfrage im Import-Blatt. Gilt für neue Ausführungen und für gespeicherte,
    ///     die noch `.unbekannt` sind; eine schon bekannte Art bleibt.
    @discardableResult
    public func importiereCSV(datei: Data, dateiname: String, kontonummer: String,
                              kontoname: String? = nil, kontowaehrung: String = "EUR",
                              zeitzone: TimeZone = TimeZone(identifier: "Europe/Berlin")!,
                              produktartVorgabe: Produktart? = nil,
                              jetzt: Date = Date()) throws -> ImportErgebnis {
        let hash = Self.fingerabdruck(datei)
        if let bekannt = try lies({ try Importlauf.filter(Column("dateiHash") == hash).fetchOne($0) }) {
            return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
        }
        guard let text = String(data: datei, encoding: .utf8) else { throw SpeicherFehler.keinText }

        let broker: String, importer: String, quellzeit: TimeZone, bewegungen: Kontobewegungen
        if TradeRepublicCSV.erkennt(text) {
            broker = "Trade Republic"
            importer = Self.tradeRepublicImporter
            quellzeit = TimeZone(secondsFromGMT: 0)!
            bewegungen = try TradeRepublicCSV.lies(text)
        } else if ScalableCSV.erkennt(text) {
            broker = "Scalable Capital"
            importer = Self.scalableImporter
            quellzeit = zeitzone
            bewegungen = try ScalableCSV.lies(text, zeitzone: zeitzone)
        } else if KrakenCSV.erkennt(text) {
            broker = "Kraken"
            importer = Self.krakenImporter
            quellzeit = TimeZone(secondsFromGMT: 0)!
            bewegungen = try KrakenCSV.lies(text)
        } else if BinanceCSV.erkennt(text) {
            broker = "Binance"
            importer = Self.binanceImporter
            quellzeit = TimeZone(secondsFromGMT: 0)!
            bewegungen = try BinanceCSV.lies(text)
        } else if CoinbaseCSV.erkennt(text) {
            broker = "Coinbase"
            importer = Self.coinbaseImporter
            quellzeit = TimeZone(secondsFromGMT: 0)!
            bewegungen = try CoinbaseCSV.lies(text)
        } else if BitpandaCSV.erkennt(text) {
            broker = "Bitpanda"
            importer = Self.bitpandaImporter
            quellzeit = TimeZone(secondsFromGMT: 0)!
            bewegungen = try BitpandaCSV.lies(text)
        } else {
            throw CSVImportFehler.unbekanntesFormat(kopf: CSVTabelle(text: text).kopf)
        }

        let alleIds = bewegungen.ausfuehrungen.map(\.id) + bewegungen.geldbewegungen.map(\.id)
            + bewegungen.kapitalmassnahmen.map(\.id) + bewegungen.verworfen
        if alleIds.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw SpeicherFehler.ungueltigerWert("Vorgang ohne Kennung (transaction_id oder reference) in \(dateiname)")
        }
        let zeiten = bewegungen.ausfuehrungen.map(\.zeit) + bewegungen.geldbewegungen.map(\.zeit)
            + bewegungen.kapitalmassnahmen.map(\.zeit)

        return try schreibe { db in
            if let bekannt = try Importlauf.filter(Column("dateiHash") == hash).fetchOne(db) {
                return ImportErgebnis(status: .dateiBereitsImportiert, importlaufId: bekannt.id!)
            }
            let konto = try Self.konto(db, broker: broker, nummer: kontonummer,
                                       name: kontoname ?? kontonummer, waehrung: kontowaehrung)
            let kontoId = konto.id!
            var lauf = Importlauf(id: nil, kontoId: kontoId, importer: importer,
                                  importerVersion: TradingCore.version, dateiname: dateiname,
                                  dateiHash: hash, datei: datei, art: "transaktionen",
                                  stichtag: zeiten.max() ?? jetzt, serverZeitzone: quellzeit.identifier,
                                  importiertAm: jetzt)
            try lauf.insert(db)
            let laufId = lauf.id!
            var zaehler = ImportErgebnis.CSVZaehler()
            var abweichend: [String] = []

            func bekannt<Z: FetchableRecord & TableRecord>(_: Z.Type, _ id: String) throws -> Z? {
                try Z.filter(Column("kontoId") == kontoId && Column("vorgangId") == id).fetchOne(db)
            }

            for var a in bewegungen.ausfuehrungen {
                let alt = try bekannt(AusfuehrungZeile.self, a.id)
                a.produktart = vorgegeben(a.produktart, gespeichert: alt?.produktart, produktartVorgabe)
                if let alt {
                    var vergleich = try alt.modell()
                    let produktart = vereinteProduktart(vergleich.produktart, a.produktart)
                    vergleich.rohzeile = a.rohzeile
                    vergleich.zeit = gleicheZeit(vergleich.zeit, a.zeit)
                    vergleich.produktart = a.produktart
                    if vergleich == a {
                        zaehler.ausfuehrungenBekannt += 1
                        if produktart.rawValue != alt.produktart {
                            try AusfuehrungZeile.filter(Column("kontoId") == kontoId && Column("vorgangId") == a.id)
                                .updateAll(db, Column("produktart").set(to: produktart.rawValue))
                        }
                    } else {
                        abweichend.append(a.id)
                    }
                } else {
                    try AusfuehrungZeile(kontoId: kontoId, importlaufId: laufId, a).insert(db)
                    zaehler.ausfuehrungenNeu += 1
                }
            }
            for g in bewegungen.geldbewegungen {
                if let alt = try bekannt(GeldbewegungZeile.self, g.id) {
                    var vergleich = try alt.modell()
                    vergleich.rohzeile = g.rohzeile
                    vergleich.zeit = gleicheZeit(vergleich.zeit, g.zeit)
                    if vergleich == g { zaehler.geldbewegungenBekannt += 1 } else { abweichend.append(g.id) }
                } else {
                    try GeldbewegungZeile(kontoId: kontoId, importlaufId: laufId, g).insert(db)
                    zaehler.geldbewegungenNeu += 1
                }
            }
            for k in bewegungen.kapitalmassnahmen {
                if let alt = try bekannt(KapitalmassnahmeZeile.self, k.id) {
                    var vergleich = try alt.modell()
                    vergleich.rohzeile = k.rohzeile
                    vergleich.zeit = gleicheZeit(vergleich.zeit, k.zeit)
                    if vergleich == k { zaehler.kapitalmassnahmenBekannt += 1 } else { abweichend.append(k.id) }
                } else {
                    try KapitalmassnahmeZeile(kontoId: kontoId, importlaufId: laufId, k).insert(db)
                    zaehler.kapitalmassnahmenNeu += 1
                }
            }
            for id in bewegungen.verworfen {
                guard try bekannt(VerworfenZeile.self, id) == nil else { continue }
                try VerworfenZeile(kontoId: kontoId, importlaufId: laufId, vorgangId: id).insert(db)
                zaehler.verworfen += 1
            }
            for h in bewegungen.hinweise {
                try HinweisZeile(importlaufId: laufId, zeile: h.zeile, vorgang: h.vorgang,
                                 folge: h.folge.rawValue).insert(db)
                zaehler.hinweise += 1
            }

            // Ein Fehler in der Transaktion macht alle Schreibvorgänge oben rückgängig.
            guard abweichend.isEmpty else { throw SpeicherFehler.abweichenderDatensatz(tickets: abweichend) }
            var ergebnis = ImportErgebnis(status: .gespeichert, importlaufId: laufId)
            ergebnis.csv = zaehler
            return ergebnis
        }
    }

    /// Alles, was für ein Konto aus CSV-Importen gespeichert ist, je Vorgang einmal, nach Zeit sortiert.
    /// Hinweise aus allen Importen des Kontos. Eingabe für `Positionsbildung.bilde`.
    public func kontobewegungen(konto: Konto) throws -> Kontobewegungen {
        try lies { db in
            let kontoId = konto.id!
            var ergebnis = Kontobewegungen()
            ergebnis.ausfuehrungen = try AusfuehrungZeile.filter(Column("kontoId") == kontoId)
                .order(Column("zeit"), Column("vorgangId")).fetchAll(db).map { try $0.modell() }
            ergebnis.geldbewegungen = try GeldbewegungZeile.filter(Column("kontoId") == kontoId)
                .order(Column("zeit"), Column("vorgangId")).fetchAll(db).map { try $0.modell() }
            ergebnis.kapitalmassnahmen = try KapitalmassnahmeZeile.filter(Column("kontoId") == kontoId)
                .order(Column("zeit"), Column("vorgangId")).fetchAll(db).map { try $0.modell() }
            ergebnis.verworfen = try VerworfenZeile.filter(Column("kontoId") == kontoId)
                .order(Column("vorgangId")).fetchAll(db).map(\.vorgangId)
            let laeufe = try Importlauf.filter(Column("kontoId") == kontoId).fetchAll(db).compactMap(\.id)
            ergebnis.hinweise = try HinweisZeile.filter(laeufe.contains(Column("importlaufId")))
                .order(Column("importlaufId"), Column("zeile")).fetchAll(db).map { try $0.modell() }
            return ergebnis
        }
    }

    /// Hinweise aus einem einzelnen Import (Zeilennummern beziehen sich auf dessen Datei).
    public func importhinweise(importlauf: Importlauf) throws -> [Importhinweis] {
        try lies { db in
            try HinweisZeile.filter(Column("importlaufId") == importlauf.id!)
                .order(Column("zeile")).fetchAll(db).map { try $0.modell() }
        }
    }
}
