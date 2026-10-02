import Foundation

/// Regeln einer Prop-Firm-Challenge oder eines finanzierten Kontos (Doc 18, F10; Tim 02.10.2026: E4 „nehmen wir mit rein“).
/// Recherche 02.10.2026 (FTMO, The5ers, FundedNext, Topstep, Apex; Quellen in Doc 18 Nachtrag): Die Firmen
/// unterscheiden sich vor allem in Tagesgrenze, Bezug des Verlusts und Nachziehen der Gesamtgrenze.
/// Beträge absolut in Kontowährung; Prozentwerte rechnet die App beim Erfassen aus dem Startkapital um.
public struct PropFirmRegeln: Codable, Sendable, Equatable {
    public enum Gesamtverlustart: String, Codable, Sendable, CaseIterable {
        /// Fest ab Startkapital (FTMO 2-Step, The5ers, FundedNext 2-Step).
        case statisch
        /// Folgt dem höchsten Saldo zum Tagesende, bis `einfrierenBeiSaldo` (Topstep MLL, Apex EOD, FTMO 1-Step).
        /// Intraday nachgezogene Varianten (Apex Intraday) lassen sich ohne Kursdaten nur so annähern.
        case nachgezogenTagesende
    }

    /// Was als Handelstag zählt: FTMO Tag mit Eröffnung, FundedNext Tag mit Ergebnis ungleich 0,
    /// The5ers, Topstep und Apex Gewinntage ab einem Mindestgewinn.
    public enum Handelstagzaehlung: String, Codable, Sendable, CaseIterable {
        case eroeffnung, ergebnis, gewinntag
    }

    /// Nenner der Konsistenzregel: Topstep und Apex Nettogewinn, FTMO 1-Step Summe der Gewinntage.
    public enum Konsistenzbezug: String, Codable, Sendable, CaseIterable {
        case nettogewinn, summeGewinntage
    }

    /// Freier Name, z. B. „FTMO 2-Step 100K Phase 1“.
    public var name: String
    public var startkapital: Decimal
    /// Zeitzone der Firma als IANA-Name, z. B. „Europe/Prague“ (FTMO) oder „America/Chicago“ (Topstep).
    public var zeitzone: String
    /// Beginn des Handelstags in Minuten nach Mitternacht Ortszeit: FTMO 0, Topstep 17 × 60, Apex 18 × 60.
    public var tageswechselMinuten: Int
    /// Höchster Verlust je Handelstag ab dem Saldo zu Tagesbeginn.
    public var maxTagesverlust: Decimal?
    public var maxGesamtverlust: Decimal?
    public var gesamtverlustart: Gesamtverlustart
    /// Saldo, bei dem die nachgezogene Grenze stehen bleibt (Topstep: Startkapital, Apex PA: Start + 100).
    public var einfrierenBeiSaldo: Decimal?
    public var gewinnziel: Decimal?
    public var mindestHandelstage: Int?
    public var handelstagzaehlung: Handelstagzaehlung
    /// Nur bei `gewinntag`: Tagesgewinn ab dem ein Tag zählt; ohne Wert jeder Tag mit Gewinn.
    public var mindestTagesgewinn: Decimal?
    /// Bester Tag höchstens dieser Anteil, z. B. 0,5.
    public var konsistenzMaxAnteil: Decimal?
    public var konsistenzbezug: Konsistenzbezug
    public var keinHaltenUeberTageswechsel: Bool
    public var keinHaltenUeberWochenende: Bool
    public var maxLotsJeTrade: Decimal?
    public var stopPflicht: Bool

    public init(name: String, startkapital: Decimal, zeitzone: String = "Europe/Prague", tageswechselMinuten: Int = 0,
                maxTagesverlust: Decimal? = nil, maxGesamtverlust: Decimal? = nil,
                gesamtverlustart: Gesamtverlustart = .statisch, einfrierenBeiSaldo: Decimal? = nil,
                gewinnziel: Decimal? = nil, mindestHandelstage: Int? = nil,
                handelstagzaehlung: Handelstagzaehlung = .eroeffnung, mindestTagesgewinn: Decimal? = nil,
                konsistenzMaxAnteil: Decimal? = nil, konsistenzbezug: Konsistenzbezug = .nettogewinn,
                keinHaltenUeberTageswechsel: Bool = false, keinHaltenUeberWochenende: Bool = false,
                maxLotsJeTrade: Decimal? = nil, stopPflicht: Bool = false) {
        self.name = name
        self.startkapital = startkapital
        self.zeitzone = zeitzone
        self.tageswechselMinuten = tageswechselMinuten
        self.maxTagesverlust = maxTagesverlust
        self.maxGesamtverlust = maxGesamtverlust
        self.gesamtverlustart = gesamtverlustart
        self.einfrierenBeiSaldo = einfrierenBeiSaldo
        self.gewinnziel = gewinnziel
        self.mindestHandelstage = mindestHandelstage
        self.handelstagzaehlung = handelstagzaehlung
        self.mindestTagesgewinn = mindestTagesgewinn
        self.konsistenzMaxAnteil = konsistenzMaxAnteil
        self.konsistenzbezug = konsistenzbezug
        self.keinHaltenUeberTageswechsel = keinHaltenUeberTageswechsel
        self.keinHaltenUeberWochenende = keinHaltenUeberWochenende
        self.maxLotsJeTrade = maxLotsJeTrade
        self.stopPflicht = stopPflicht
    }
}
