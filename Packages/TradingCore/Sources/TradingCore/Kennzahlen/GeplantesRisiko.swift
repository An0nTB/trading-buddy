import Foundation

/// Geplantes Risiko für Trades ohne Stop: Scalable und Trade Republic exportieren keinen Stop, also gäbe
/// es dort weder R noch R-Auswertungen. Mit einem geplanten Risiko (Vorgabe je Konto, je Setup oder je
/// Trade; gespeichert wird es außerhalb des Kerns) rechnet Henry R trotzdem, markiert als angenommen.
/// Ein echter Stop hat immer Vorrang. Der Befund „ohne Stop“ bleibt, er fragt `stopLoss` ab.
extension Trade {
    /// Risiko (1 R) in Kontowährung: aus dem Stop (`stopRisiko`), sonst das geplante Risiko, wenn es
    /// positiv ist. `nil`, wenn beides fehlt.
    public var risk: Decimal? {
        if let ausStop = stopRisiko { return ausStop }
        return wirksamesGeplantesRisiko
    }

    /// `true` genau dann, wenn `risk` (und damit `rMultiple`) aus `geplantesRisiko` stammt.
    public var risikoAngenommen: Bool {
        stopRisiko == nil && wirksamesGeplantesRisiko != nil
    }

    /// Kopie mit diesem geplanten Risiko; `nil` entfernt es.
    public func mitGeplantemRisiko(_ betrag: Decimal?) -> Trade {
        var kopie = self
        kopie.geplantesRisiko = betrag
        return kopie
    }

    /// Geplantes Risiko, wenn es positiv ist; 0 und negative Beträge zählen nicht.
    private var wirksamesGeplantesRisiko: Decimal? {
        guard let betrag = geplantesRisiko, betrag > 0 else { return nil }
        return betrag
    }
}
