import Foundation
import GRDB
import TradingCore

/// Zeile der Tabelle `handelsregeln` (Migration v5), eine je Konto. Prop-Firm-Felder mit Präfix `pf`;
/// `pfName` gesetzt heißt Prop-Firm-Konto. Arten als Text, damit ein unbekanntes Wort als
/// `SpeicherFehler.unbekannterWert` ankommt statt als Absturz beim Lesen.
struct RegelZeile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "handelsregeln"
    var kontoId: Int64
    var maxTagesverlust: Decimal?
    var maxTradesJeTag: Int?
    var stoppNachVerlusten: Int?
    var maxRisikoJeTrade: Decimal?
    var pfName: String?
    var pfStartkapital: Decimal?
    var pfZeitzone: String?
    var pfTageswechselMinuten: Int?
    var pfMaxTagesverlust: Decimal?
    var pfMaxGesamtverlust: Decimal?
    var pfGesamtverlustart: String?
    var pfEinfrierenBeiSaldo: Decimal?
    var pfGewinnziel: Decimal?
    var pfMindestHandelstage: Int?
    var pfHandelstagzaehlung: String?
    var pfMindestTagesgewinn: Decimal?
    var pfKonsistenzMaxAnteil: Decimal?
    var pfKonsistenzbezug: String?
    var pfKeinHaltenUeberTageswechsel: Bool?
    var pfKeinHaltenUeberWochenende: Bool?
    var pfMaxLotsJeTrade: Decimal?
    var pfStopPflicht: Bool?
    var maxTagesverlustProzent: Decimal?
    var maxRisikoJeTradeProzent: Decimal?
    var maxMonatsverlust: Decimal?
    var maxMonatsverlustProzent: Decimal?
    var maxOffenePositionen: Int?
    var maxOffenesRisiko: Decimal?
    var maxOffenesRisikoProzent: Decimal?
    var kontostandBetrag: Decimal?
    var kontostandSeit: Date?
    var geaendert: Date

    init(kontoId: Int64, _ r: Handelsregeln, geaendert: Date) {
        self.kontoId = kontoId
        maxTagesverlust = r.maxTagesverlust
        maxTradesJeTag = r.maxTradesJeTag
        stoppNachVerlusten = r.stoppNachVerlusten
        maxRisikoJeTrade = r.maxRisikoJeTrade
        let p = r.propFirm
        pfName = p?.name
        pfStartkapital = p?.startkapital
        pfZeitzone = p?.zeitzone
        pfTageswechselMinuten = p?.tageswechselMinuten
        pfMaxTagesverlust = p?.maxTagesverlust
        pfMaxGesamtverlust = p?.maxGesamtverlust
        pfGesamtverlustart = p?.gesamtverlustart.rawValue
        pfEinfrierenBeiSaldo = p?.einfrierenBeiSaldo
        pfGewinnziel = p?.gewinnziel
        pfMindestHandelstage = p?.mindestHandelstage
        pfHandelstagzaehlung = p?.handelstagzaehlung.rawValue
        pfMindestTagesgewinn = p?.mindestTagesgewinn
        pfKonsistenzMaxAnteil = p?.konsistenzMaxAnteil
        pfKonsistenzbezug = p?.konsistenzbezug.rawValue
        pfKeinHaltenUeberTageswechsel = p?.keinHaltenUeberTageswechsel
        pfKeinHaltenUeberWochenende = p?.keinHaltenUeberWochenende
        pfMaxLotsJeTrade = p?.maxLotsJeTrade
        pfStopPflicht = p?.stopPflicht
        maxTagesverlustProzent = r.maxTagesverlustProzent
        maxRisikoJeTradeProzent = r.maxRisikoJeTradeProzent
        maxMonatsverlust = r.maxMonatsverlust
        maxMonatsverlustProzent = r.maxMonatsverlustProzent
        maxOffenePositionen = r.maxOffenePositionen
        maxOffenesRisiko = r.maxOffenesRisiko
        maxOffenesRisikoProzent = r.maxOffenesRisikoProzent
        kontostandBetrag = r.kontostand?.betrag
        kontostandSeit = r.kontostand?.seit
        self.geaendert = geaendert
    }

    func modell() throws -> Handelsregeln {
        let pf = try propFirm()
        var kontostand: Kontostandbezug?
        if let kontostandBetrag, let kontostandSeit {
            kontostand = Kontostandbezug(betrag: kontostandBetrag, seit: kontostandSeit)
        }
        return Handelsregeln(maxTagesverlust: maxTagesverlust, maxTradesJeTag: maxTradesJeTag,
                             stoppNachVerlusten: stoppNachVerlusten, maxRisikoJeTrade: maxRisikoJeTrade,
                             propFirm: pf, maxTagesverlustProzent: maxTagesverlustProzent,
                             maxRisikoJeTradeProzent: maxRisikoJeTradeProzent, maxMonatsverlust: maxMonatsverlust,
                             maxMonatsverlustProzent: maxMonatsverlustProzent, maxOffenePositionen: maxOffenePositionen,
                             maxOffenesRisiko: maxOffenesRisiko, maxOffenesRisikoProzent: maxOffenesRisikoProzent,
                             kontostand: kontostand)
    }

    private func propFirm() throws -> PropFirmRegeln? {
        guard let pfName else { return nil }
        guard let pfStartkapital, let pfZeitzone, let pfTageswechselMinuten else {
            throw SpeicherFehler.unbekannterWert("Prop-Firm-Regeln von Konto \(kontoId) unvollständig")
        }
        let verlustart = try Self.art(pfGesamtverlustart, PropFirmRegeln.Gesamtverlustart.self)
        let zaehlung = try Self.art(pfHandelstagzaehlung, PropFirmRegeln.Handelstagzaehlung.self)
        let bezug = try Self.art(pfKonsistenzbezug, PropFirmRegeln.Konsistenzbezug.self)
        return PropFirmRegeln(
            name: pfName, startkapital: pfStartkapital, zeitzone: pfZeitzone,
            tageswechselMinuten: pfTageswechselMinuten, maxTagesverlust: pfMaxTagesverlust,
            maxGesamtverlust: pfMaxGesamtverlust, gesamtverlustart: verlustart,
            einfrierenBeiSaldo: pfEinfrierenBeiSaldo, gewinnziel: pfGewinnziel,
            mindestHandelstage: pfMindestHandelstage, handelstagzaehlung: zaehlung,
            mindestTagesgewinn: pfMindestTagesgewinn, konsistenzMaxAnteil: pfKonsistenzMaxAnteil,
            konsistenzbezug: bezug,
            keinHaltenUeberTageswechsel: pfKeinHaltenUeberTageswechsel ?? false,
            keinHaltenUeberWochenende: pfKeinHaltenUeberWochenende ?? false,
            maxLotsJeTrade: pfMaxLotsJeTrade, stopPflicht: pfStopPflicht ?? false)
    }

    private static func art<A: RawRepresentable>(_ text: String?, _: A.Type) throws -> A where A.RawValue == String {
        guard let text, let wert = A(rawValue: text) else { throw SpeicherFehler.unbekannterWert(text ?? "leer") }
        return wert
    }
}

extension Journal {
    /// Handelsregeln des Kontos. Ohne gespeicherte Regeln leer (`Handelsregeln().leer`).
    public func handelsregeln(konto: Konto) throws -> Handelsregeln {
        try lies { db in
            try RegelZeile.fetchOne(db, key: konto.id!)?.modell() ?? Handelsregeln()
        }
    }

    /// Ersetzt die Handelsregeln des Kontos. Leere Regeln ohne Kontostand entfernen die gespeicherten.
    ///
    /// Abgelehnt werden Grenzen, die keine sind: Beträge und Anzahlen nicht größer als 0, ein leerer
    /// Prop-Firm-Name, eine unbekannte Zeitzone, ein Tageswechsel außerhalb des Tages, ein Konsistenzanteil
    /// über 1, ein Konto, das es nicht gibt.
    public func setzeHandelsregeln(_ regeln: Handelsregeln, konto: Konto, jetzt: Date = Date()) throws {
        try Self.pruefe(regeln)
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        try schreibe { db in
            guard try Konto.exists(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            // Ein Kontostand ohne Regel bleibt gespeichert: Er ist der Bezug für spätere Prozentregeln.
            if regeln.leer && regeln.kontostand == nil {
                _ = try RegelZeile.deleteOne(db, key: kontoId)
            } else {
                try RegelZeile(kontoId: kontoId, regeln, geaendert: jetzt).save(db)
            }
        }
    }

    static func pruefe(_ r: Handelsregeln) throws {
        try positiv("Höchster Tagesverlust", r.maxTagesverlust)
        try positiv("Trades je Tag", r.maxTradesJeTag)
        try positiv("Stopp nach Verlusten", r.stoppNachVerlusten)
        try positiv("Risiko je Trade", r.maxRisikoJeTrade)
        try prozent("Tagesverlust in Prozent", r.maxTagesverlustProzent)
        try prozent("Risiko je Trade in Prozent", r.maxRisikoJeTradeProzent)
        try positiv("Monatsverlust", r.maxMonatsverlust)
        try prozent("Monatsverlust in Prozent", r.maxMonatsverlustProzent)
        try positiv("Offene Positionen", r.maxOffenePositionen)
        try positiv("Offenes Risiko", r.maxOffenesRisiko)
        try prozent("Offenes Risiko in Prozent", r.maxOffenesRisikoProzent)
        try positiv("Kontostand", r.kontostand?.betrag)
        guard let p = r.propFirm else { return }
        guard !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeicherFehler.ungueltigerWert("Prop-Firm ohne Namen")
        }
        try positiv("Startkapital", p.startkapital)
        guard TimeZone(identifier: p.zeitzone) != nil else {
            throw SpeicherFehler.ungueltigerWert("Unbekannte Zeitzone \(p.zeitzone)")
        }
        guard (0..<24 * 60).contains(p.tageswechselMinuten) else {
            throw SpeicherFehler.ungueltigerWert("Tageswechsel \(p.tageswechselMinuten) Minuten liegt nicht im Tag")
        }
        try positiv("Prop-Firm Tagesverlust", p.maxTagesverlust)
        try positiv("Prop-Firm Gesamtverlust", p.maxGesamtverlust)
        try positiv("Einfrieren bei Saldo", p.einfrierenBeiSaldo)
        try positiv("Gewinnziel", p.gewinnziel)
        try positiv("Mindest-Handelstage", p.mindestHandelstage)
        try positiv("Mindest-Tagesgewinn", p.mindestTagesgewinn)
        try positiv("Konsistenzanteil", p.konsistenzMaxAnteil)
        try positiv("Lots je Trade", p.maxLotsJeTrade)
        if let anteil = p.konsistenzMaxAnteil, anteil > 1 {
            throw SpeicherFehler.ungueltigerWert("Konsistenzanteil \(anteil) ist größer als 1")
        }
    }

    /// Prozentzahl über 0 und höchstens 100.
    private static func prozent(_ name: String, _ wert: Decimal?) throws {
        try positiv(name, wert)
        if let wert, wert > 100 { throw SpeicherFehler.ungueltigerWert("\(name) über 100") }
    }

    private static func positiv<Z: Comparable & ExpressibleByIntegerLiteral>(_ name: String, _ wert: Z?) throws {
        if let wert, wert <= 0 { throw SpeicherFehler.ungueltigerWert("\(name) muss größer als 0 sein") }
    }
}

extension Journal {
    /// Setzt Echtgeld oder Demo/Paper für das Konto (E1). Gibt das Konto mit der neuen Art zurück.
    @discardableResult
    public func setzeKontoart(_ art: Kontoart, konto: Konto) throws -> Konto {
        guard let kontoId = konto.id else { throw SpeicherFehler.ungueltigerWert("Konto ohne ID") }
        return try schreibe { db in
            try db.execute(sql: "UPDATE konto SET kontoart = ? WHERE id = ?", arguments: [art.rawValue, kontoId])
            guard db.changesCount == 1, let neu = try Konto.fetchOne(db, key: kontoId) else {
                throw SpeicherFehler.ungueltigerWert("Konto \(kontoId) gibt es nicht")
            }
            return neu
        }
    }
}
