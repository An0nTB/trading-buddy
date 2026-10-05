import Foundation

/// Von Hand eingetragener, geschlossener Trade (Formular „Trade eintragen“, Import der Journal-Sicherung).
/// Eine Stelle für Ergebnis und Stop, damit Formular und Import gleich rechnen.
/// Beträge in Kontowährung; die Journal-Sicherung kennt nur Euro.
public struct ManuellerTrade: Sendable, Equatable {
    public enum Problem: Sendable, Equatable {
        case symbolLeer
        case groesseNichtPositiv
        /// Einstieg nicht über 0, Ausstieg unter 0 oder (ohne Schein) nicht über 0.
        case kursNichtPositiv
        case ausstiegVorEinstieg
        /// Stop nicht auf der Verlustseite des Einstiegs (Kauf: darunter, Verkauf: darüber).
        case stopAufFalscherSeite
    }

    public var symbol: String
    public var einstieg: Date
    /// `nil`: Ausstiegszeit unbekannt, die Position schließt dann zur Einstiegszeit (`ausstiegszeitBekannt` false).
    public var ausstieg: Date?
    /// Erwartete Marktrichtung. Bei Scheinen nicht die Handelsseite: Ein Short-Schein wird gekauft.
    public var markterwartung: Side
    /// Optionsschein, Knock-out oder Zertifikat: gekauft und verkauft, Gewinn bei steigendem Scheinpreis.
    public var schein: Bool
    public var groesse: Decimal
    public var einstiegskurs: Decimal
    public var ausstiegskurs: Decimal
    /// Stop als Kurs; hat Vorrang vor `risiko`.
    public var stopKurs: Decimal?
    /// Geplantes Risiko in Kontowährung; ergibt den Stop, wenn `stopKurs` fehlt.
    public var risiko: Decimal?
    public var ziel: Decimal?
    /// Positiv eingegeben, als negative Kommission gebucht.
    public var gebuehren: Decimal
    public var produktart: Produktart

    public init(symbol: String, einstieg: Date, ausstieg: Date? = nil, markterwartung: Side, schein: Bool = false,
                groesse: Decimal, einstiegskurs: Decimal, ausstiegskurs: Decimal, stopKurs: Decimal? = nil,
                risiko: Decimal? = nil, ziel: Decimal? = nil, gebuehren: Decimal = 0,
                produktart: Produktart = .unbekannt) {
        self.symbol = symbol
        self.einstieg = einstieg
        self.ausstieg = ausstieg
        self.markterwartung = markterwartung
        self.schein = schein
        self.groesse = groesse
        self.einstiegskurs = einstiegskurs
        self.ausstiegskurs = ausstiegskurs
        self.stopKurs = stopKurs
        self.risiko = risiko
        self.ziel = ziel
        self.gebuehren = gebuehren
        self.produktart = produktart
    }

    /// Scheine werden immer gekauft; sonst handelt man in Richtung der Erwartung.
    public var handelsseite: Side { schein ? .buy : markterwartung }

    /// Kursergebnis ohne Gebühren: (Ausstieg − Einstieg) × Größe, bei Verkauf mit umgekehrtem Vorzeichen.
    /// Kaufmännisch auf 2 Stellen gerundet, halbe Cent vom Betrag weg. Rundet das Journal mit Math.round,
    /// weicht es nur bei genau −x,5 Cent ab (dort zur Null hin).
    public var ergebnis: Decimal {
        let faktor: Decimal = handelsseite == .buy ? 1 : -1
        return ((ausstiegskurs - einstiegskurs) * groesse * faktor).gerundet(2)
    }

    /// `stopKurs`, sonst aus dem Risiko: Abstand = |Risiko| ÷ Größe unter (Kauf) oder über (Verkauf) dem Einstieg.
    /// `nil` ohne Stop, bei Risiko 0 oder Größe nicht über 0.
    public var stop: Decimal? {
        if let stopKurs { return stopKurs }
        guard let risiko, risiko != 0, groesse > 0 else { return nil }
        let abstand = abs(risiko) / groesse
        return handelsseite == .buy ? einstiegskurs - abstand : einstiegskurs + abstand
    }

    /// Eingabefehler in fester Reihenfolge; leer, wenn der Trade gespeichert werden kann.
    /// Ein Schein darf mit 0 schließen (Knock-out ausgeknockt).
    public func pruefe() -> [Problem] {
        var probleme: [Problem] = []
        if symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { probleme.append(.symbolLeer) }
        if groesse <= 0 { probleme.append(.groesseNichtPositiv) }
        let ausstiegOk = schein ? ausstiegskurs >= 0 : ausstiegskurs > 0
        if einstiegskurs <= 0 || !ausstiegOk { probleme.append(.kursNichtPositiv) }
        if let ausstieg, ausstieg < einstieg { probleme.append(.ausstiegVorEinstieg) }
        if let stop {
            let falsch = handelsseite == .buy ? stop >= einstiegskurs : stop <= einstiegskurs
            if falsch { probleme.append(.stopAufFalscherSeite) }
        }
        return probleme
    }

    /// Geschlossene Position mit leerer Rohzeile; der Import setzt sie selbst.
    /// Ohne Ausstiegszeit schließt sie zur Einstiegszeit und trägt `ausstiegszeitBekannt` false.
    public func position(ticket: String) -> ClosedPosition {
        ClosedPosition(ticket: ticket, rohzeile: [], side: handelsseite, lots: groesse,
                       symbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines), openTime: einstieg,
                       openPrice: einstiegskurs, stopLoss: stop, takeProfit: ziel, closeTime: ausstieg ?? einstieg,
                       closePrice: ausstiegskurs, commission: gebuehren == 0 ? 0 : -abs(gebuehren), swap: 0,
                       profit: ergebnis, produktart: produktart, ausstiegszeitBekannt: ausstieg != nil)
    }
}
