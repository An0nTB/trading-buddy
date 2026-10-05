import Foundation
import TradingCore
import TradingQuotes

/// Ergebnis eines Abrufs von Minutenkerzen über mehrere Trades.
struct Minutenabruf: Equatable {
    /// Trades, für die Kerzen geholt und gespeichert wurden.
    var geladen = 0
    /// Trades ohne freie Minutenkurse (CFD, Devisen, ISIN) oder ohne Uhrzeit.
    var ohneQuelle = 0
    /// Trades, deren Fenster noch nicht vorbei ist (Ausstieg + 1 Stunde); später erneut abrufen.
    var nochOffen = 0
    /// Trades, für die die Quelle keine Kerzen lieferte (etwa IEX ohne Umsatz); gespeicherte Kerzen bleiben.
    var ohneKerzen = 0
    /// Fehler je Journal-Symbol, etwa „Schlüssel fehlt“.
    var fehler: [String: String] = [:]
}

/// Minutenkerzen für die Ausstiegsanalyse (Doc 39, Paket B2): holt je Trade das Fenster vom Einstieg bis eine
/// Stunde nach dem Ausstieg und übergibt die Kerzen dem Ausstiegsdienst (Paket B3). Krypto über Binance ohne
/// Schlüssel, US-Aktien über Alpaca mit dem Schlüssel der Echtzeitkurse. Auf Knopfdruck und automatisch nach
/// Start und Import (`Minutenautomatik`), nur bei eingeschalteten Kursen.
extension Kursdienst {
    func ladeMinutenkerzen(fuer trades: [Trade], jetzt: Date = Date()) async -> Minutenabruf {
        var ergebnis = Minutenabruf()
        guard aktiv else { return ergebnis }
        let lader = Minutenkerzen.lader(schluessel: schluesselbund, abruf: abruf)
        var erster = true
        for trade in trades.sorted(by: { $0.openTime < $1.openTime }) {
            guard let ziel = zuordnung(fuer: trade.symbol).zuordnung.flatMap(Minutenlader.zuordnung(aus:)),
                  let fenster = Minutenlader.fenster(trade, nachlauf: Ausstiegsdienst.nachlauf)
            else { ergebnis.ohneQuelle += 1; continue }
            guard fenster.bis <= jetzt else { ergebnis.nochOffen += 1; continue }
            if ergebnis.fehler[trade.symbol] != nil { continue }
            // Eine Sekunde Abstand hält die freien Abrufgrenzen (wie der Verlaufslader).
            if !erster { try? await Task.sleep(for: .seconds(1)) }
            erster = false
            do {
                let kerzen = try await lader.lade(ziel, von: fenster.von, bis: fenster.bis, jetzt: jetzt)
                // Ohne Kerzen nichts ersetzen: Sonst löscht eine leere Antwort gespeicherte Kerzen dieses Fensters,
                // etwa aus dem MT4-Import (Gegencheck P1).
                guard !kerzen.isEmpty else { ergebnis.ohneKerzen += 1; continue }
                try await Ausstiegsdienst.geteilt.uebernimm(kerzen, symbol: trade.symbol,
                                                           quelle: quellenname(ziel.quelle),
                                                           fenster: DateInterval(start: fenster.von, end: fenster.bis))
                ergebnis.geladen += 1
            } catch {
                ergebnis.fehler[trade.symbol] = (error as? Verlaufsfehler)?.description ?? error.localizedDescription
            }
        }
        return ergebnis
    }
}
