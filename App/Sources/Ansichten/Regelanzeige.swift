import Foundation
import TradingCore

/// Wann die Übersicht die Regelkarten zeigt (Codex-Befund, Tim 17.10.2026): `Handelsregeln.leer` kennt die Grenzen
/// der Playbook-Karten nicht, und ohne geschlossenen Trade gibt es keinen Tagesstand. Beides darf Warnungen zu
/// Setups und offenen Positionen (E4 bis E6) nicht verstecken.
extension AppModell {
    /// Eigene Regeln oder eine Playbook-Karte mit Grenze je Tag oder Haltedauer.
    var regelnAktiv: Bool {
        !regeln.leer || playbook.contains { $0.maxTradesJeTag != nil || $0.haltedauer != nil }
    }

    /// Bezug der Ampel nur für die jetzt offenen Positionen, ohne Handelstag (E5, E6): Kontostand von heute und
    /// die Verstöße dieser Positionen, wie in `ampelbezug(_:)`.
    var offenerAmpelbezug: Ampelbezug {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        var bezug = Ampelbezug()
        bezug.haltedauerAktiv = playbook.contains { $0.haltedauer != nil }
        let offene = offeneRegelpositionen
        bezug.offene = offene
        bezug.standHeute = regeln.kontostand?.stand(bei: kalender.startOfDay(for: Date()), trades: angleich.trades)
        let offenIDs = Set(offene.map(\.id))
        bezug.offeneVerstoesse = verstoesse.filter { offenIDs.contains($0.trade) }
        return bezug
    }
}

extension Ampellampe {
    /// Lampen der offenen Positionen, wenn im Zeitraum kein Handelstag mit Trade liegt: Haltedauer, offene
    /// Positionen und offenes Risiko. Der Monatsverlust bleibt weg, er braucht einen Handelstag.
    static func positionslampen(regeln: Handelsregeln, waehrung: String, bezug: Ampelbezug) -> [Ampellampe] {
        var ohneMonat = regeln
        ohneMonat.maxMonatsverlust = nil
        ohneMonat.maxMonatsverlustProzent = nil
        return erweiterteLampen(regeln: ohneMonat, verstoesse: [], waehrung: waehrung, bezug: bezug)
    }
}
