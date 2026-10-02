import Foundation
import GRDB
import TradingCore

// Speicherung von Tagesnotizen, verpassten Trades und Bildverweisen (Migration v8, Doc 18 F4).
// Tagesnotizen und verpasste Trades gelten für alle Konten; Bilder zu Trades gehören zu einem Konto.

struct TagesnotizZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tagesnotiz"
    var tag: String
    var plan: String
    var planErstellt: Date?
    var rueckblick: String
    var verfassung: Int?
    var erstellt: Date
    var geaendert: Date

    init(_ n: Tagesnotiz) {
        tag = n.tag.description
        plan = n.plan
        planErstellt = n.planErstellt
        rueckblick = n.rueckblick
        verfassung = n.verfassung
        erstellt = n.erstellt
        geaendert = n.geaendert
    }

    func modell() throws -> Tagesnotiz {
        guard let t = Journaltag(tag) else { throw SpeicherFehler.unbekannterWert(tag) }
        return Tagesnotiz(tag: t, plan: plan, planErstellt: planErstellt, rueckblick: rueckblick,
                          verfassung: verfassung, erstellt: erstellt, geaendert: geaendert)
    }
}

struct VerpasstZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "verpassterTrade"
    var id: String
    var zeit: Date
    var symbol: String
    var seite: String
    var setup: String?
    var grund: String
    var notiz: String
    var ergebnisR: Decimal?

    init(_ v: VerpassterTrade) {
        id = v.id
        zeit = v.zeit
        symbol = v.symbol
        seite = v.seite.rawValue
        setup = v.setup
        grund = v.grund.rawValue
        notiz = v.notiz
        ergebnisR = v.ergebnisR
    }

    func modell() throws -> VerpassterTrade {
        guard let s = Side(rawValue: seite) else { throw SpeicherFehler.unbekannterWert(seite) }
        guard let g = VerpassterTrade.Grund(rawValue: grund) else { throw SpeicherFehler.unbekannterWert(grund) }
        return VerpassterTrade(id: id, zeit: zeit, symbol: symbol, seite: s, setup: setup, grund: g, notiz: notiz,
                               ergebnisR: ergebnisR)
    }
}

struct BildZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bild"
    var datei: String
    var art: String
    var kontoId: Int64?
    var ticket: String?
    var tag: String?
    var verpassterTradeId: String?
    var beschriftung: String
    var erstellt: Date

    init(_ b: Bildverweis, kontoId: Int64?) {
        datei = b.datei
        switch b.bezug {
        case .trade(let t):
            art = "trade"
            self.kontoId = kontoId
            ticket = t
        case .tag(let t):
            art = "tag"
            tag = t.description
        case .verpassterTrade(let id):
            art = "verpasst"
            verpassterTradeId = id
        }
        beschriftung = b.beschriftung
        erstellt = b.erstellt
    }

    func modell() throws -> Bildverweis {
        let bezug: Bildverweis.Bezug
        switch art {
        case "trade":
            guard let ticket else { throw SpeicherFehler.unbekannterWert("Bild \(datei) ohne Ticket") }
            bezug = .trade(ticket)
        case "tag":
            guard let tag, let t = Journaltag(tag) else { throw SpeicherFehler.unbekannterWert(tag ?? "leer") }
            bezug = .tag(t)
        case "verpasst":
            guard let id = verpassterTradeId else {
                throw SpeicherFehler.unbekannterWert("Bild \(datei) ohne verpassten Trade")
            }
            bezug = .verpassterTrade(id)
        default:
            throw SpeicherFehler.unbekannterWert(art)
        }
        return Bildverweis(datei: datei, bezug: bezug, beschriftung: beschriftung, erstellt: erstellt)
    }
}

extension Journal {
    // MARK: Tagesnotizen

    /// Notiz zum Tag oder `nil`, wenn es keine gibt.
    public func tagesnotiz(_ tag: Journaltag) throws -> Tagesnotiz? {
        try lies { db in try TagesnotizZeile.fetchOne(db, key: tag.description)?.modell() }
    }

    /// Notizen von `von` bis einschließlich `bis`, nach Tag sortiert. Passt als `notizen` in `Planwirkung`.
    public func tagesnotizen(von: Journaltag, bis: Journaltag) throws -> [Tagesnotiz] {
        try lies { db in
            try TagesnotizZeile.filter(Column("tag") >= von.description && Column("tag") <= bis.description)
                .order(Column("tag")).fetchAll(db).map { try $0.modell() }
        }
    }

    /// Speichert die Notiz des Tages und gibt sie so zurück, wie sie gespeichert ist; `nil`, wenn sie leer
    /// war (ohne Plan, Rückblick und Verfassung) und deshalb entfernt wurde.
    ///
    /// Der Zeitpunkt des Plans ist der erste: Hat der gespeicherte Tag schon einen Plan, bleibt dessen
    /// `planErstellt`, auch wenn der Plan später geändert wird. Sonst gilt `planErstellt` der Notiz oder
    /// `jetzt`. Ohne Plan ist `planErstellt` leer. `erstellt` bleibt beim ersten Speichern, `geaendert`
    /// wird `jetzt`. Abgelehnt wird eine Verfassung außerhalb von 1 bis 5.
    @discardableResult
    public func speichereTagesnotiz(_ notiz: Tagesnotiz, jetzt: Date = Date()) throws -> Tagesnotiz? {
        if let v = notiz.verfassung, !(1...5).contains(v) {
            throw SpeicherFehler.ungueltigerWert("Verfassung \(v) liegt nicht zwischen 1 und 5")
        }
        let hatPlan = !Self.leer(notiz.plan)
        return try schreibe { db in
            let alt = try TagesnotizZeile.fetchOne(db, key: notiz.tag.description)
            if !hatPlan, Self.leer(notiz.rueckblick), notiz.verfassung == nil {
                _ = try TagesnotizZeile.deleteOne(db, key: notiz.tag.description)
                return nil
            }
            var n = notiz
            if !hatPlan {
                n.planErstellt = nil
            } else if let alt, !Self.leer(alt.plan), let frueher = alt.planErstellt {
                n.planErstellt = frueher
            } else {
                n.planErstellt = notiz.planErstellt ?? jetzt
            }
            n.erstellt = alt?.erstellt ?? notiz.erstellt
            n.geaendert = jetzt
            try TagesnotizZeile(n).save(db)
            // Neu gelesen, damit Zeiten genau so zurückkommen wie gespeichert (auf die Millisekunde).
            return try TagesnotizZeile.fetchOne(db, key: notiz.tag.description)?.modell()
        }
    }

    // MARK: Verpasste Trades

    /// Verpasste Trades mit `von <= zeit < bis`, nach Zeit sortiert. Passt in `VerpassteAuswertung`.
    public func verpassteTrades(von: Date, bis: Date) throws -> [VerpassterTrade] {
        try lies { db in
            try VerpasstZeile.filter(Column("zeit") >= von && Column("zeit") < bis)
                .order(Column("zeit"), Column("id")).fetchAll(db).map { try $0.modell() }
        }
    }

    /// Legt den verpassten Trade an oder ersetzt den mit derselben `id`. Ein leeres Setup wird `nil`.
    /// Abgelehnt werden eine leere `id` und ein leeres Symbol.
    public func speichereVerpasstenTrade(_ trade: VerpassterTrade) throws {
        guard !Self.leer(trade.id) else { throw SpeicherFehler.ungueltigerWert("Verpasster Trade ohne ID") }
        guard !Self.leer(trade.symbol) else {
            throw SpeicherFehler.ungueltigerWert("Verpasster Trade ohne Symbol")
        }
        var v = trade
        if let s = v.setup, Self.leer(s) { v.setup = nil }
        let zeile = VerpasstZeile(v)
        try schreibe { db in try zeile.save(db) }
    }

    /// Entfernt den verpassten Trade und die Verweise auf seine Bilder. Die Bilddateien löscht die App.
    public func loescheVerpasstenTrade(id: String) throws {
        try schreibe { db in _ = try VerpasstZeile.deleteOne(db, key: id) }
    }

    // MARK: Bilder

    /// Bilder zu einem Trade des Kontos, nach Zeit sortiert.
    public func bilder(trade ticket: String, konto: Konto) throws -> [Bildverweis] {
        try bilder(BildZeile.filter(Column("art") == "trade" && Column("kontoId") == konto.id!
                                        && Column("ticket") == ticket))
    }

    /// Bilder zu einem Tag, nach Zeit sortiert.
    public func bilder(tag: Journaltag) throws -> [Bildverweis] {
        try bilder(BildZeile.filter(Column("art") == "tag" && Column("tag") == tag.description))
    }

    /// Bilder zu einem verpassten Trade, nach Zeit sortiert.
    public func bilder(verpassterTrade id: String) throws -> [Bildverweis] {
        try bilder(BildZeile.filter(Column("art") == "verpasst" && Column("verpassterTradeId") == id))
    }

    /// Alle Dateien, auf die ein Verweis zeigt. Damit findet die App Bilder im Ordner ohne Verweis.
    public func bilddateien() throws -> Set<String> {
        try lies { db in Set(try String.fetchAll(db, sql: "SELECT datei FROM bild")) }
    }

    /// Legt den Verweis an oder ersetzt den auf dieselbe Datei. Bei Bezug `.trade` gehört das Konto dazu.
    ///
    /// Abgelehnt werden: ein Pfad, den `Bildverweis.istGueltig` nicht zulässt, ein Trade-Bild ohne oder mit
    /// unbekanntem Konto, ein Bild zu einem verpassten Trade, den es nicht gibt.
    public func speichereBild(_ bild: Bildverweis, konto: Konto? = nil) throws {
        guard Bildverweis.istGueltig(bild.datei) else {
            throw SpeicherFehler.ungueltigerWert("Kein gültiger Bildpfad: \(bild.datei)")
        }
        try schreibe { db in
            switch bild.bezug {
            case .trade(let ticket):
                guard let kontoId = konto?.id else {
                    throw SpeicherFehler.ungueltigerWert("Bild zum Trade \(ticket) ohne Konto")
                }
                guard try Konto.exists(db, key: kontoId) else {
                    throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
                }
                try BildZeile(bild, kontoId: kontoId).save(db)
            case .verpassterTrade(let id):
                guard try VerpasstZeile.exists(db, key: id) else {
                    throw SpeicherFehler.ungueltigerWert("Verpassten Trade \(id) gibt es nicht")
                }
                try BildZeile(bild, kontoId: nil).save(db)
            case .tag:
                try BildZeile(bild, kontoId: nil).save(db)
            }
        }
    }

    /// Entfernt den Verweis. Die Datei selbst löscht die App.
    public func loescheBild(datei: String) throws {
        try schreibe { db in _ = try BildZeile.deleteOne(db, key: datei) }
    }

    private func bilder(_ anfrage: QueryInterfaceRequest<BildZeile>) throws -> [Bildverweis] {
        try lies { db in
            try anfrage.order(Column("erstellt"), Column("datei")).fetchAll(db).map { try $0.modell() }
        }
    }

    private static func leer(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
