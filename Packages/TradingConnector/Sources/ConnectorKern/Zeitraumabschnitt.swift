import Foundation
import TradingCore

/// Teile der Auswertung aus `Zeitraumbericht` (Rechenkern 0.20.0, Doc 47): derselbe Bericht wie der Wochen- und
/// Monatsbericht der App, damit Claude für jede Spanne dieselben Zahlen nennt.
extension Anfrage {
    /// Bericht über den Zeitraum dieser Anfrage. In der Kontowährung bekommt er alle Trades des Kontos und gleicht
    /// selbst an wie die App: mit den Kursen der Datei, wenn die Anfrage umrechnet, sonst bleiben fremde Trades
    /// draußen wie in `lies`. Mit `waehrung` die Trades dieser Währung.
    func bericht() -> Zeitraumbericht {
        let regeln = konto.regeln ?? Handelsregeln()
        // Alle Muster, damit `musterabschnitt` sie nicht ein zweites Mal sucht.
        guard inKontowaehrung else {
            return Zeitraumbericht(trades: konto.trades, zeitraum: zeitraum, zeitzone: zeitzone,
                                   kontowaehrung: konto.waehrung, regeln: regeln, manuell: manuellVerletzt,
                                   ziele: konto.ziele, geloeschteOrders: konto.geloeschteOrders, musterAnzahl: .max)
        }
        return Zeitraumbericht(trades: alleTrades, zeitraum: zeitraum, zeitzone: zeitzone,
                               kontowaehrung: konto.waehrung, regeln: regeln, manuell: manuellVerletzt,
                               ziele: konto.ziele, geloeschteOrders: konto.geloeschteOrders, kurse: angleichskurse,
                               musterAnzahl: .max)
    }

    /// Antwortet die Anfrage in der Kontowährung? Nur dann gelten Prop-Firm-Grenzen und Steuer-Orientierung.
    var inKontowaehrung: Bool { kontowaehrung.isEmpty || konto.waehrung == kontowaehrung }

    /// Abschnitt „Tage“ für Spannen bis 31 Tage (Woche, Monat, freie Tage): Ergebnis je Handelstag.
    func tagesabschnitt(_ b: Zeitraumbericht) -> [String] {
        guard !b.tage.isEmpty, b.zeitraum.bis.timeIntervalSince(b.zeitraum.von) <= 31 * 86_400 + 3_600 else { return [] }
        let zone = zeitzone
        let zeilen: [[String]] = b.tage.map { t in
            let beginn = t.tag.beginn(in: zone)
            return ["\(Format.wochentag(beginn, zone)) \(Format.datum(beginn, zone, mitZeit: false))", "\(t.anzahl)",
                    Format.zahl(t.netto)]
        }
        let plus = b.tage.filter { $0.netto > 0 }.count
        let minus = b.tage.filter { $0.netto < 0 }.count
        return ["\n## Tage (Schlusstag der Trades)",
                Format.tabelle(["Tag", "Trades", "Netto"], zeilen),
                "\(b.tage.count) Handelstage, davon \(plus) im Plus und \(minus) im Minus."]
    }

    /// Prop-Firm-Verstöße wie in der App (`PropFirmPruefung`); `nil` ohne Prop-Firm-Regeln oder in fremder Währung.
    func propFirmzeile(_ b: Zeitraumbericht) -> String? {
        guard konto.regeln?.propFirm != nil, inKontowaehrung else { return nil }
        guard !b.propFirmVerstoesse.isEmpty else {
            return "Prop-Firm-Regeln: kein Verstoß im Zeitraum (\(b.auswertung.trades.count) Trades geprüft)."
        }
        let teile = PropFirmPruefung.Art.allCases.compactMap { art -> String? in
            let n = Set(b.propFirmVerstoesse.filter { $0.art == art }.map(\.trade)).count
            return n > 0 ? "\(art.bezeichnung) \(n)" : nil
        }
        return "Prop-Firm-Regeln, Trades mit Verstoß: " + teile.joined(separator: ", ") + ". Tages- und Gesamtverlust "
            + "nur auf realisierten Salden, offene Verluste fehlen; maßgeblich ist die Prüfung der Firma."
    }

    /// Abschnitt „Steuer-Orientierung“: Summen je Verlusttopf in Euro vom Beginn des Jahres bis zum Ende des
    /// Zeitraums, über alle Trades des Kontos mit den Kursen der Datei wie die Steuerseite der App. Leer mit
    /// `waehrung` in fremder Währung oder ohne Trades im Jahr.
    func steuerabschnitt(_ b: Zeitraumbericht) -> [String] {
        let bisEnde = alleTrades.filter { $0.closeTime < zeitraum.bis }
        let toepfe = Steuerorientierung.toepfe(bisEnde, kontowaehrung: konto.waehrung, jahr: b.steuerjahr,
                                               kurse: export.angleichskurse).filter { $0.anzahl > 0 }
        guard inKontowaehrung, !toepfe.isEmpty else { return [] }
        let zeilen: [[String]] = toepfe.map {
            [$0.topf.bezeichnung, "\($0.anzahl)", Format.zahl($0.gewinne), Format.zahl($0.verluste), Format.zahl($0.saldo)]
        }
        var t = ["\n## Steuer-Orientierung \(b.steuerjahr) bis Ende des Zeitraums in EUR (keine Steuerberechnung)",
                 Format.tabelle(["Topf", "Trades", "Gewinne", "Verluste", "Saldo"], zeilen)]
        let ohneEuro = toepfe.map(\.ohneEuro).reduce(0, +)
        if ohneEuro > 0 { t.append("\(ohneEuro) Trades ohne Euro-Kurs fehlen in den Summen.") }
        t.append("Summen wie auf der Steuerseite der App; maßgeblich sind Steuerbescheinigung und Steuerberatung.")
        return t
    }
}

/// Wortwahl wie in der App (RegelnView, SteuerView).
extension PropFirmPruefung.Art {
    var bezeichnung: String {
        switch self {
        case .tagesverlust: "Tagesverlust"
        case .gesamtverlust: "Gesamtgrenze"
        case .haltenUeberTageswechsel: "Halten über den Tageswechsel"
        case .haltenUeberWochenende: "Halten übers Wochenende"
        case .lotsJeTrade: "Lots je Trade"
        case .ohneStop: "Ohne Stop"
        }
    }
}

extension Verlusttopf {
    var bezeichnung: String {
        switch self {
        case .aktien: "Aktien"
        case .allgemein: "Allgemein (Fonds, Anleihen, Derivate, CFDs)"
        case .krypto: "Krypto (Haltefrist ein Jahr)"
        case .nichtZugeordnet: "Nicht zugeordnet"
        }
    }
}
