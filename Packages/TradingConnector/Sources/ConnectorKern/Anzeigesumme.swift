import Foundation
import TradingCore

/// Summen in der Anzeigewährung der App (Vierter Gegencheck H21): Übersicht und Kennzahlen der App summieren in
/// ihr, der Connector rechnet in Kontowährung. Damit Claude dieselbe Zahl nennen kann wie die App, steht das Netto
/// des Zeitraums in der Anzeigewährung im Kopf jeder Antwort. Regeln, Ziele und Prop-Firm bleiben wie in der App in
/// Kontowährung.
public struct Anzeigesumme: Sendable, Equatable {
    public var waehrung: String
    public var netto: Decimal
    /// Trades, die in die Summe eingehen, und Trades ohne Kurs, die fehlen.
    public var trades: Int
    public var ohneKurs: Int
}

extension Anfrage {
    /// Netto des Zeitraums in der Anzeigewährung, umgerechnet wie in der App: jeder Trade aus seiner Währung mit dem
    /// EZB-Referenzkurs am Schlusstag. `nil` ohne gewählte Anzeigewährung, wenn sie die Währung dieser Antwort ist,
    /// wenn die Antwort ausdrücklich nur eine Fremdwährung zeigt, oder ohne Kurse in der Datei.
    public var anzeigesumme: Anzeigesumme? {
        guard let ziel = export.anzeigewaehrung, ziel != konto.waehrung, konto.waehrung == kontowaehrung,
              let kurse = export.angleichskurse else { return nil }
        // Trades ohne eigene Währung stehen in Kontowährung; ausdrücklich setzen, sonst gälten sie als Zielwährung.
        let imZeitraum = alleTrades.filter { zeitraum.enthaelt($0.closeTime) }.map { trade in
            var t = trade
            t.waehrung = trade.waehrung(kontowaehrung: kontowaehrung)
            return t
        }
        let angleich = Waehrungsangleich(imZeitraum, kontowaehrung: ziel, kurse: kurse)
        return Anzeigesumme(waehrung: ziel, netto: Kennzahlen(trades: angleich.trades).netto,
                            trades: angleich.trades.count, ohneKurs: angleich.ohneKurs.count)
    }
}

extension Ausgabe {
    /// Satz für den Kopf; leer ohne `Anfrage.anzeigesumme`.
    static func anzeigehinweis(_ anfrage: Anfrage) -> String {
        guard let s = anfrage.anzeigesumme else { return "" }
        var text = "Die App zeigt Summen in \(s.waehrung) (Anzeigewährung): netto im Zeitraum \(Format.zahl(s.netto)) "
            + "\(s.waehrung) aus \(s.trades) Trades (EZB-Referenzkurs am Schlusstag, Näherung"
        text += s.ohneKurs > 0 ? "; \(s.ohneKurs) Trades ohne Kurs fehlen). " : "). "
        return text + "Alle anderen Beträge hier in \(anfrage.konto.waehrung). "
    }
}
