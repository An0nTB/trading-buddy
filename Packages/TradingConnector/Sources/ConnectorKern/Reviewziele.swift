import Foundation
import TradingCore

/// Ziele aus früheren Reviews für die Auswertung (Rezept Punkt 6). Gelesen aus der Exportdatei;
/// der Connector speichert keine Ziele, eingetragen werden sie in der App.
extension Anfrage {
    /// Ziele, deren Zeitraum den abgefragten überlappt; sonst das zuletzt geendete davor.
    func zieleZumZeitraum() -> (ziele: [Reviewziel], davor: Bool) {
        let ziele = konto.ziele
        let ueberlappend = ziele.filter { $0.von < zeitraum.bis && $0.bis > zeitraum.von }
        if !ueberlappend.isEmpty { return (ueberlappend, false) }
        let frueher = ziele.filter { $0.bis <= zeitraum.von }.max { ($0.bis, $0.von) < ($1.bis, $1.von) }
        return (frueher.map { [$0] } ?? [], true)
    }

    /// Istwert der Messgröße im Zeitraum des Ziels, wenn der Rechenkern sie kennt.
    func istwert(_ ziel: Reviewziel) -> (wert: String, trades: Int)? {
        guard let name = ziel.messgroesse?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty else { return nil }
        let a = Auswertung(trades: konto.trades, geloeschteOrders: konto.geloeschteOrders,
                           zeitraum: Zeitspanne(von: ziel.von, bis: ziel.bis), zeitzone: zeitzone)
        let k = a.kennzahlen
        if let muster = Fehlermuster.allCases.first(where: { name.hasPrefix($0.bezeichnung.lowercased()) }) {
            guard let befund = a.befunde.first(where: { $0.muster == muster }) else { return ("0", k.anzahl) }
            return befund.trades.isEmpty ? (Format.zahl(befund.wert), k.anzahl) : ("\(befund.trades.count)", k.anzahl)
        }
        switch name {
        case "trades je tag":
            var kalender = Calendar(identifier: .gregorian)
            kalender.timeZone = zeitzone
            let tage = Set(a.trades.map { kalender.startOfDay(for: $0.closeTime) }).count
            return (tage == 0 ? "–" : Format.zahl(Decimal(k.anzahl) / Decimal(tage), stellen: 1), k.anzahl)
        case "trades": return ("\(k.anzahl)", k.anzahl)
        case "netto": return (Format.zahl(k.netto), k.anzahl)
        case "trefferquote": return (Format.prozent(k.trefferquote), k.anzahl)
        case "profitfaktor": return (Format.zahl(k.profitfaktor), k.anzahl)
        case "erwartungswert in r", "r": return (Format.r(k.erwartungswertR), k.anzahl)
        default: return nil
        }
    }

    /// Eine Zeile je Ziel: Text, Zeitraum, Status, Zielwert, Istwert, Ergebnis laut App.
    func zielzeile(_ ziel: Reviewziel) -> String {
        let zeitraum = Format.zeitraum(Zeitspanne(von: ziel.von, bis: ziel.bis), zeitzone)
        var zeile = "- „\(Format.kurz(ziel.text))“ (\(zeitraum), Status \(ziel.status.rawValue))"
        if let messgroesse = ziel.messgroesse {
            zeile += ": \(Format.kurz(messgroesse, zeichen: 40)), Zielwert \(Format.zahl(ziel.zielwert))"
            if let ist = istwert(ziel) {
                zeile += ", Istwert \(ist.wert) im Zeitraum des Ziels (\(ist.trades) Trades)"
            } else {
                zeile += ", Istwert nicht berechenbar (Messgröße kennt der Rechenkern nicht)"
            }
        }
        if ziel.bis > export.erstellt { zeile += ". Zeitraum läuft beim Export noch" }
        if let ergebnis = ziel.ergebnis { zeile += ". Ergebnis laut App: \(Format.kurz(ergebnis))" }
        return zeile + "."
    }
}
