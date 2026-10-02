import Foundation

/// Positionsgrößen-Rechner vor dem Trade (F6, Doc 18; Formeln R5 Kapitel 07 Abschnitt 2):
/// Risiko in Kontowährung ÷ Risiko je Einheit = Größe, abgerundet auf den Lotschritt,
/// damit das geplante Risiko nie überschritten wird. Rückrichtung: Risiko einer gegebenen Größe.
/// Beispiel R5: Konto 10.000 €, 1 % Risiko, DAX-CFD 1 € je Punkt, Stop 40 Punkte → 2,5 Kontrakte.
public struct Positionsrechnung: Sendable, Hashable {
    /// Wie viel des Kontos ein Trade höchstens kosten darf.
    public enum Risiko: Sendable, Hashable {
        /// In Prozent: 1 heißt 1 %.
        case prozent(Decimal)
        /// Fester Betrag in Kontowährung.
        case betrag(Decimal)
    }

    /// Abstand zwischen Einstieg und Stop.
    public enum StopAbstand: Sendable, Hashable {
        /// Einstiegs- und Stopkurs.
        case kurs(einstieg: Decimal, stop: Decimal)
        /// Punkte in Kurseinheiten, zum Beispiel 40 Punkte beim DAX oder 1,50 bei einer Aktie.
        case punkte(Decimal)
        /// Pips; die Pipgröße steht am Instrument (meist 0,0001, bei JPY-Paaren 0,01).
        case pips(Decimal)
        /// Prozent vom Einstiegskurs: 2 heißt 2 %.
        case prozent(Decimal, einstieg: Decimal)
    }

    public enum Einheit: String, Sendable, Hashable, CaseIterable {
        case lot, kontrakt, stueck
    }

    /// Was eine Einheit ausmacht. Vorlagen: `forexLot`, `indexCFD`, `aktie`.
    public struct Instrument: Sendable, Hashable {
        public var einheit: Einheit
        /// Wie viele Stück Basiswert eine Einheit umfasst (Forex-Standardlot 100.000; CFD mit 1 € je Punkt: 1).
        public var kontraktgroesse: Decimal
        /// Kleinster Schritt der Größe, zum Beispiel 0,01 Lot.
        public var schritt: Decimal
        /// Kleinste handelbare Größe; ohne Angabe gleich dem Schritt.
        public var minimum: Decimal?
        public var pipGroesse: Decimal

        public init(einheit: Einheit, kontraktgroesse: Decimal, schritt: Decimal, minimum: Decimal? = nil,
                    pipGroesse: Decimal = Decimal(string: "0.0001")!) {
            self.einheit = einheit
            self.kontraktgroesse = kontraktgroesse
            self.schritt = schritt
            self.minimum = minimum
            self.pipGroesse = pipGroesse
        }

        public static let forexLot = Instrument(einheit: .lot, kontraktgroesse: 100_000, schritt: Decimal(string: "0.01")!)
        public static let indexCFD = Instrument(einheit: .kontrakt, kontraktgroesse: 1, schritt: Decimal(string: "0.1")!)
        public static let aktie = Instrument(einheit: .stueck, kontraktgroesse: 1, schritt: 1)
    }

    public struct Ergebnis: Sendable, Hashable {
        /// Geplantes Risiko in Kontowährung.
        public var risikoBetrag: Decimal
        /// Verlust je Einheit bis zum Stop, in Kontowährung, mit Kosten.
        public var risikoJeEinheit: Decimal
        /// Rechnerische Größe vor dem Runden.
        public var roheGroesse: Decimal
        /// Auf den Schritt abgerundete Größe; 0, wenn sie unter dem Minimum läge.
        public var groesse: Decimal
        /// Verlust bis zum Stop mit der gerundeten Größe.
        public var tatsaechlichesRisiko: Decimal
        /// Dasselbe in Prozent vom Konto (1 = 1 %).
        public var tatsaechlichesRisikoProzent: Decimal
        /// Die kleinste handelbare Größe übersteigt das geplante Risiko.
        public var unterMinimum: Bool
        /// Risiko bei der kleinsten handelbaren Größe, für den Hinweis „schon das Minimum riskiert …“.
        public var risikoBeiMinimum: Decimal
    }

    public enum Fehler: Error, Equatable, Sendable {
        case kontogroesseUngueltig, risikoUngueltig, stopAbstandUngueltig, instrumentUngueltig, groesseUngueltig
    }

    /// Kontostand in Kontowährung.
    public var kontogroesse: Decimal
    public var risiko: Risiko
    public var stopAbstand: StopAbstand
    public var instrument: Instrument
    /// Wert einer Einheit der Kurswährung in Kontowährung, zum Beispiel 0,92 für USD auf einem EUR-Konto.
    public var umrechnung: Decimal
    /// Spread und Gebühren je Einheit in Kontowährung; zählen zum Risiko (R5 Kapitel 07).
    public var kostenJeEinheit: Decimal

    public init(kontogroesse: Decimal, risiko: Risiko, stopAbstand: StopAbstand, instrument: Instrument,
                umrechnung: Decimal = 1, kostenJeEinheit: Decimal = 0) {
        self.kontogroesse = kontogroesse
        self.risiko = risiko
        self.stopAbstand = stopAbstand
        self.instrument = instrument
        self.umrechnung = umrechnung
        self.kostenJeEinheit = kostenJeEinheit
    }

    /// Abstand zum Stop in Kurseinheiten.
    public func kursabstand() throws -> Decimal {
        let abstand: Decimal
        switch stopAbstand {
        case .kurs(let einstieg, let stop): abstand = abs(einstieg - stop)
        case .punkte(let punkte): abstand = punkte
        case .pips(let pips): abstand = pips * instrument.pipGroesse
        case .prozent(let prozent, let einstieg):
            guard einstieg > 0 else { throw Fehler.stopAbstandUngueltig }
            abstand = einstieg * prozent / 100
        }
        guard abstand > 0 else { throw Fehler.stopAbstandUngueltig }
        return abstand
    }

    /// Verlust je Einheit bis zum Stop, in Kontowährung, mit Kosten.
    public func risikoJeEinheit() throws -> Decimal {
        guard instrument.kontraktgroesse > 0, instrument.schritt > 0, umrechnung > 0, kostenJeEinheit >= 0,
              (instrument.minimum ?? instrument.schritt) > 0, instrument.pipGroesse > 0
        else { throw Fehler.instrumentUngueltig }
        return try kursabstand() * instrument.kontraktgroesse * umrechnung + kostenJeEinheit
    }

    /// Größe aus Risiko: die eigentliche Rechnung vor dem Trade.
    public func berechne() throws -> Ergebnis {
        guard kontogroesse > 0 else { throw Fehler.kontogroesseUngueltig }
        let betrag: Decimal
        switch risiko {
        case .prozent(let prozent): betrag = kontogroesse * prozent / 100
        case .betrag(let wert): betrag = wert
        }
        guard betrag > 0, betrag <= kontogroesse else { throw Fehler.risikoUngueltig }
        let jeEinheit = try risikoJeEinheit()
        let roh = betrag / jeEinheit
        let minimum = instrument.minimum ?? instrument.schritt
        var groesse = Positionsrechnung.abrunden(roh, auf: instrument.schritt)
        let unterMinimum = groesse < minimum
        if unterMinimum { groesse = 0 }
        let tatsaechlich = groesse * jeEinheit
        return Ergebnis(risikoBetrag: betrag, risikoJeEinheit: jeEinheit, roheGroesse: roh, groesse: groesse,
                        tatsaechlichesRisiko: tatsaechlich,
                        tatsaechlichesRisikoProzent: tatsaechlich / kontogroesse * 100,
                        unterMinimum: unterMinimum, risikoBeiMinimum: minimum * jeEinheit)
    }

    /// Rückrichtung: Was riskiert eine gegebene Größe? Ergebnis als Betrag und Prozent vom Konto (1 = 1 %).
    /// Das Feld `risiko` spielt hier keine Rolle.
    public func risikoBei(groesse: Decimal) throws -> (betrag: Decimal, prozent: Decimal) {
        guard kontogroesse > 0 else { throw Fehler.kontogroesseUngueltig }
        guard groesse > 0 else { throw Fehler.groesseUngueltig }
        let betrag = groesse * (try risikoJeEinheit())
        return (betrag, betrag / kontogroesse * 100)
    }

    /// Rundet nach unten auf ein Vielfaches von `schritt`.
    static func abrunden(_ wert: Decimal, auf schritt: Decimal) -> Decimal {
        var anzahl = wert / schritt
        var ganz = Decimal()
        NSDecimalRound(&ganz, &anzahl, 0, .down)
        return ganz * schritt
    }
}
