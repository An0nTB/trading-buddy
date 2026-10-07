import Foundation
import TradingCore
import TradingQuotes

/// Holt Minutenkerzen für die Ausstiegsanalyse ohne Knopfdruck (Tim 05.10.2026, Option 1): beim Start und nach
/// jedem Import, auch dem stillen aus dem Import-Ordner. Beide laufen über `AppModell.laden()`; ein Abruf beginnt
/// für fällige Trades ohne erfolgreichen Abruf. Fehler bleiben still, die Trades ohne Kerzen kommen beim
/// nächsten Anlass wieder dran.
///
/// Eine geteilte Instanz wie `Ausstiegsdienst.geteilt`, damit `AppModell` nur eine Zeile braucht.
@MainActor
final class Minutenautomatik {
    static let geteilt = Minutenautomatik()

    /// Automatisch nur Trades, die höchstens so lange geschlossen sind; ältere holt weiter der Knopf.
    nonisolated static let hoechstalter: TimeInterval = 31 * 86_400

    /// Erfolgreich bearbeitete Trades je Konto; frühe und fehlgeschlagene Abrufe bleiben ausstehend.
    private var bekannt: [Int64: Set<String>] = [:]
    private var laeuft = false
    /// Während eines Abrufs kam ein neuer Anlass; danach noch einmal.
    private var nochmal = false

    /// Aufruf aus `AppModell.laden()`. Tut nichts ohne eingeschaltete Kurse und im Beispielkonto (#229).
    func stosseAn(_ modell: AppModell) {
        guard modell.kurse.aktiv, let konto = modell.konto, let kontoId = konto.id,
              !Beispieldaten.istBeispiel(konto) else { return }
        guard !laeuft else { nochmal = true; return }
        let trades = modell.alleTrades
        laeuft = true
        Task {
            let dienst = Ausstiegsdienst.geteilt
            await dienst.ladeBestand()
            await rufeAb(kontoId: kontoId, trades: trades, jetzt: Date(), vorhandene: { trades in
                Set(await dienst.analysen(trades).keys)
            }, lade: { trades in
                let abruf = await modell.kurse.ladeMinutenkerzen(fuer: trades)
                if abruf.geladen > 0 { modell.exportiere() }
            })
            laeuft = false
            if nochmal {
                nochmal = false
                stosseAn(modell)
            }
        }
    }

    /// Merkt erst vorhandene oder nach dem Abruf gespeicherte Kurse. Konto und Trades stammen vom Anlass,
    /// auch wenn während des Wartens das Konto wechselt. Die Aufrufe sind für Tests ohne Netz austauschbar.
    func rufeAb(kontoId: Int64, trades: [Trade], jetzt: Date,
                vorhandene: @MainActor ([Trade]) async -> Set<String>, lade: @MainActor ([Trade]) async -> Void) async {
        let erledigt = bekannt[kontoId] ?? []
        let infrage = Self.kandidaten(trades, jetzt: jetzt).filter { !erledigt.contains($0.id) }
        guard !infrage.isEmpty else { return }
        let mitKerzen = await vorhandene(infrage)
        bekannt[kontoId, default: []].formUnion(mitKerzen)
        let fehlend = infrage.filter { !mitKerzen.contains($0.id) }
        guard !fehlend.isEmpty else { return }
        await lade(fehlend)
        let gespeichert = await vorhandene(fehlend)
        bekannt[kontoId, default: []].formUnion(gespeichert)
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
