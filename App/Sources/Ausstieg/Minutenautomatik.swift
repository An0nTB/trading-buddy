import Foundation
import TradingCore
import TradingQuotes

/// Holt Minutenkerzen für die Ausstiegsanalyse ohne Knopfdruck (Tim 05.10.2026, Option 1): beim Start und nach
/// jedem Import, auch dem stillen aus dem Import-Ordner. Beide laufen über `AppModell.laden()`; ein Abruf beginnt
/// nur, wenn dort Trades auftauchen, die beim letzten Abruf noch nicht da waren. Fehler bleiben still, die Trades
/// ohne Kerzen kommen beim nächsten Anlass wieder dran.
///
/// Eine geteilte Instanz wie `Ausstiegsdienst.geteilt`, damit `AppModell` nur eine Zeile braucht.
@MainActor
final class Minutenautomatik {
    static let geteilt = Minutenautomatik()

    /// Automatisch nur Trades, die höchstens so lange geschlossen sind; ältere holt weiter der Knopf.
    nonisolated static let hoechstalter: TimeInterval = 31 * 86_400

    /// Trade-IDs aller bisherigen Abrufe (alle Konten); `nil` vor dem ersten (Start). Ein Kontowechsel zurück
    /// löst so keinen neuen Abruf aus, ein Import mit neuen Trades schon.
    private var bekannt: Set<String>?
    private var laeuft = false
    /// Während eines Abrufs kam ein neuer Anlass; danach noch einmal.
    private var nochmal = false

    /// Aufruf aus `AppModell.laden()`. Tut nichts ohne eingeschaltete Kurse, im Beispielkonto (#229) und ohne neue Trades.
    func stosseAn(_ modell: AppModell) {
        guard modell.kurse.aktiv, let konto = modell.konto, !Beispieldaten.istBeispiel(konto) else { return }
        let ids = Set(modell.alleTrades.map(\.id))
        guard Self.neuerAnlass(bekannt: bekannt, ids: ids) else { return }
        guard !laeuft else { nochmal = true; return }
        bekannt = (bekannt ?? []).union(ids)
        laeuft = true
        Task {
            await rufeAb(modell)
            laeuft = false
            if nochmal {
                nochmal = false
                stosseAn(modell)
            }
        }
    }

    private func rufeAb(_ modell: AppModell) async {
        let dienst = Ausstiegsdienst.geteilt
        await dienst.ladeBestand()
        let jetzt = Date()
        let infrage = Self.kandidaten(modell.alleTrades, jetzt: jetzt)
        guard !infrage.isEmpty else { return }
        let mitKerzen = Set(await dienst.analysen(infrage).keys)
        let fehlend = infrage.filter { !mitKerzen.contains($0.id) }
        guard !fehlend.isEmpty else { return }
        let abruf = await modell.kurse.ladeMinutenkerzen(fuer: fehlend, jetzt: jetzt)
        if abruf.geladen > 0 { modell.exportiere() }
    }

    /// Erster Aufruf oder mindestens eine Trade-ID, die beim letzten Abruf fehlte.
    nonisolated static func neuerAnlass(bekannt: Set<String>?, ids: Set<String>) -> Bool {
        guard let bekannt else { return !ids.isEmpty }
        return !ids.isSubset(of: bekannt)
    }

    /// Dieselben Filter wie „Kurse abrufen“: Uhrzeit vorhanden, Fenster höchstens 31 Tage, Fenster vorbei
    /// (Ausstieg plus eine Stunde); dazu höchstens 31 Tage geschlossen. Die Quelle (Binance, Alpaca mit Schlüssel)
    /// prüft `Kursdienst.ladeMinutenkerzen`.
    nonisolated static func kandidaten(_ trades: [Trade], jetzt: Date) -> [Trade] {
        trades.filter { t in
            guard !t.nurDatum, jetzt.timeIntervalSince(t.closeTime) <= hoechstalter,
                  let fenster = Minutenlader.fenster(t, nachlauf: Ausstiegsdienst.nachlauf)
            else { return false }
            return fenster.bis <= jetzt && fenster.bis.timeIntervalSince(fenster.von) <= Minutenlader.hoechstdauer
        }
    }
}
