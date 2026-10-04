import Foundation

/// Alles, was eine Wochen- oder Monatsauswertung braucht (R5, Kapitel 10 Abschnitt 5),
/// für einen Zeitraum gerechnet, dazu der gleich lange Zeitraum davor zum Vergleich.
/// Gerechnet wird hier; Claude bekommt nur die Ergebnisse.
public struct Auswertung: Sendable {
    public var zeitraum: Zeitspanne
    public var vorzeitraum: Zeitspanne
    /// Im Zeitraum geschlossene Trades, nach Schlusszeit.
    public var trades: [Trade]
    /// Im Zeitraum gelöschte Pending Orders.
    public var geloeschteOrders: Int
    public var kennzahlen: Kennzahlen
    public var kennzahlenVorzeitraum: Kennzahlen
    public var kapitalverlauf: Kapitalverlauf
    public var befunde: [Befund]

    /// - Parameters:
    ///   - alle: Trades eines Kontos, auch außerhalb des Zeitraums (für den Vergleich).
    ///   - zeitzone: Zeitzone des Nutzers für Tagesgrenzen und Vorzeitraum.
    public init(trades alle: [Trade], geloeschteOrders: [Date] = [], zeitraum: Zeitspanne,
                zeitzone: TimeZone, schwellen: Fehlermuster.Schwellen = Fehlermuster.Schwellen()) {
        let vor = zeitraum.vorzeitraum(zeitzone: zeitzone)
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        // Buchungen nur mit Datum (00:00 UTC) zählen mit ihrem Buchungstag, sonst landen sie westlich von UTC
        // im Vormonat (Codex 04.10.2026, M3); Trades mit Uhrzeit mit ihrer Schlusszeit.
        func schluss(_ t: Trade) -> Date { t.nurDatum ? t.schlusstag(kalender) : t.closeTime }
        let imZeitraum = alle.filter { zeitraum.enthaelt(schluss($0)) }
            .sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
        let geloescht = geloeschteOrders.filter { zeitraum.enthaelt($0) }.count

        self.zeitraum = zeitraum
        vorzeitraum = vor
        trades = imZeitraum
        self.geloeschteOrders = geloescht
        kennzahlen = Kennzahlen(trades: imZeitraum)
        kennzahlenVorzeitraum = Kennzahlen(trades: alle.filter { vor.enthaelt(schluss($0)) })
        kapitalverlauf = Kapitalverlauf(trades: imZeitraum)
        befunde = Fehlermuster.pruefe(imZeitraum, geloeschteOrders: geloescht, zeitzone: zeitzone,
                                      schwellen: schwellen)
    }

    public var stornoquote: Decimal? {
        Kennzahlen.stornoquote(ausgefuehrt: kennzahlen.anzahl, geloescht: geloeschteOrders)
    }

    /// Kennzahlen ohne die Trades eines Befunds: Was hätte der Zeitraum ohne diesen Regelbruch
    /// gebracht? (R5, Kapitel 10, Frage 5). `nil` bei Mustern, die kein Regelbruch je Trade sind.
    public func ohne(_ befund: Befund) -> Kennzahlen? {
        guard befund.muster.istRegelbruch, !befund.trades.isEmpty else { return nil }
        let ids = Set(befund.trades)
        return Kennzahlen(trades: trades.filter { !ids.contains($0.id) })
    }

    /// Muster, die bei einem Trade angeschlagen haben.
    public func muster(_ trade: Trade) -> [Fehlermuster] {
        befunde.filter { $0.trades.contains(trade.id) }.map(\.muster)
    }

    /// Die besten Trades nach Netto, bester zuerst.
    public func beste(_ anzahl: Int) -> [Trade] { Array(nachNetto.reversed().prefix(anzahl)) }

    /// Die schlechtesten Trades nach Netto, schlechtester zuerst.
    public func schlechteste(_ anzahl: Int) -> [Trade] { Array(nachNetto.prefix(anzahl)) }

    private var nachNetto: [Trade] { trades.sorted { ($0.netProfit, $0.id) < ($1.netProfit, $1.id) } }
}

extension Fehlermuster {
    /// Regelbruch eines einzelnen Trades. Bei den übrigen Mustern beschreiben die Trades
    /// ein Verhalten über viele Trades (etwa alle Verlierer) oder es gibt keine Trades;
    /// sie herauszurechnen ergäbe keine sinnvolle Zahl.
    public var istRegelbruch: Bool {
        switch self {
        case .revancheTrade, .ueberhandeln, .stopNichtEingehalten, .verbilligen, .ohneStop,
             .groesseNachGewinnserie:
            true
        case .gewinneZuFrueh, .verliererLaufenLassen, .schwankendeGroesse, .staendigesUmplanen:
            false
        }
    }
}
