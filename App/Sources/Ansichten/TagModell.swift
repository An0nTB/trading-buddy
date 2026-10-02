import Foundation
import Observation
import TradingCore

/// Zustand der Tagesseite: gewählter Tag, Entwurf der Notiz, verpasste Trades und Bilder des Tages,
/// dazu die Grundlagen der zwei Auswertungskarten. Trades kommen aus dem `AppModell` (gewähltes Konto).
@Observable @MainActor
final class TagModell {
    let ablage: any TagAblage
    let zeitzone: TimeZone
    private(set) var tag: Journaltag
    /// Was in den Feldern steht; gespeichert wird nach kurzer Pause und beim Tageswechsel.
    var entwurf: Tagesnotiz
    /// Gespeicherte Fassung; `planErstellt` kommt von hier.
    private(set) var gespeichert: Tagesnotiz? = nil
    private(set) var verpasst: [VerpassterTrade] = []
    private(set) var bilder: [Bildverweis] = []
    /// Verpasste Trades im Monat des gewählten Tages, für die Karte „Verpasste Trades“.
    private(set) var verpasstImMonat: [VerpassterTrade] = []
    var fehler: String? = nil

    init(ablage: any TagAblage, zeitzone: TimeZone, tag: Journaltag? = nil, jetzt: Date = Date()) {
        self.ablage = ablage
        self.zeitzone = zeitzone
        let start = tag ?? Journaltag(jetzt, zeitzone: zeitzone)
        self.tag = start
        entwurf = Tagesnotiz(tag: start, erstellt: jetzt)
        laden()
    }

    var istHeute: Bool { tag == Journaltag(Date(), zeitzone: zeitzone) }

    /// Entwurf weicht von der gespeicherten Fassung ab.
    var ungesichert: Bool {
        let alt = gespeichert ?? Tagesnotiz(tag: tag, erstellt: entwurf.erstellt)
        func rein(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return rein(entwurf.plan) != alt.plan || rein(entwurf.rueckblick) != alt.rueckblick
            || entwurf.verfassung != alt.verfassung
    }

    /// Wechselt nur, wenn der Entwurf gespeichert ist; scheitert das Speichern, bleibt der Tag mit
    /// Plan und Rückblick stehen und die Fehlermeldung erscheint (Codex-Review 02.10.2026).
    func wechsle(zu neu: Journaltag) {
        guard neu != tag, sichere() else { return }
        tag = neu
        laden()
    }

    /// Lädt Notiz, verpasste Trades und Bilder des Tages; ersetzt den Entwurf. Nur beim Start und Tageswechsel.
    func laden() {
        do {
            gespeichert = try ablage.tagesnotiz(tag)
            entwurf = gespeichert ?? Tagesnotiz(tag: tag, erstellt: Date())
        } catch {
            fehler = error.localizedDescription
        }
        ladeEintraege()
    }

    /// Lädt nur verpasste Trades und Bilder neu; der Entwurf bleibt, auch wenn er noch nicht gespeichert ist
    /// (Gesamt-Gegencheck 02.10.2026, Befund T1).
    private func ladeEintraege() {
        do {
            let spanne = tag.spanne(in: zeitzone)
            verpasst = try ablage.verpassteTrades(von: spanne.von, bis: spanne.bis)
            bilder = try ablage.bilder(tag: tag)
            ladeMonat()
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Speichert den Entwurf, wenn er sich geändert hat. Leere Felder entfernen die Notiz.
    /// `false`, wenn das Speichern gescheitert ist; der Entwurf bleibt dann unverändert.
    @discardableResult
    func sichere(jetzt: Date = Date()) -> Bool {
        guard ungesichert else { return true }
        do {
            gespeichert = try ablage.speichereTagesnotiz(entwurf, jetzt: jetzt)
            // Nur die Zeitstempel übernehmen: der Nutzer tippt womöglich gerade weiter.
            entwurf.planErstellt = gespeichert?.planErstellt
            entwurf.erstellt = gespeichert?.erstellt ?? entwurf.erstellt
            entwurf.geaendert = gespeichert?.geaendert ?? entwurf.geaendert
            return true
        } catch {
            fehler = error.localizedDescription
            return false
        }
    }

    /// Klick auf die gewählte Zahl hebt die Wahl auf.
    func waehleVerfassung(_ wert: Int) {
        entwurf.verfassung = entwurf.verfassung == wert ? nil : wert
        sichere()
    }

    // MARK: Verpasste Trades

    func speichere(_ eintrag: VerpassterTrade) throws {
        try ablage.speichereVerpasstenTrade(eintrag)
        ladeEintraege()
    }

    func loesche(_ eintrag: VerpassterTrade) {
        do {
            try ablage.loescheVerpasstenTrade(id: eintrag.id)
            ladeEintraege()
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Ein neuer Eintrag für den gewählten Tag: heute mit der aktuellen Uhrzeit, sonst 12:00.
    func neuerVerpasster(jetzt: Date = Date()) -> VerpassterTrade {
        let zeit: Date
        if istHeute {
            zeit = jetzt
        } else {
            zeit = tag.beginn(in: zeitzone).addingTimeInterval(12 * 3600)
        }
        return VerpassterTrade(zeit: zeit, symbol: "", seite: .buy, grund: .zoegern)
    }

    private func ladeMonat() {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        guard let monat = kalender.dateInterval(of: .month, for: tag.beginn(in: zeitzone)) else { return }
        verpasstImMonat = (try? ablage.verpassteTrades(von: monat.start, bis: monat.end)) ?? []
    }

    // MARK: Bilder

    /// Kopiert die Bilder in den Bilderordner und legt Verweise auf den Tag an. Nicht unterstützte
    /// Dateien überspringt sie und meldet die erste.
    func fuegeBilderHinzu(_ quellen: [Bildquelle], jetzt: Date = Date()) {
        fehler = Bilderordner.lege(quellen, bezug: .tag(tag), jetzt: jetzt, zeitzone: zeitzone) { bild in
            try ablage.speichereBild(bild)
        }
        ladeEintraege()
    }

    func entferne(_ bild: Bildverweis) {
        do {
            try ablage.loescheBild(datei: bild.datei)
            Bilderordner.loesche(bild.datei)
            ladeEintraege()
        } catch {
            fehler = error.localizedDescription
        }
    }

    // MARK: Auswertungen

    /// Planwirkung über alle übergebenen Trades; die Notizen holt sie für die Spanne der Trades.
    func planwirkung(_ trades: [Trade]) -> Planwirkung? {
        let tage = trades.map { Journaltag($0.openTime, zeitzone: zeitzone) }
        guard let erster = tage.min(), let letzter = tage.max() else { return nil }
        let notizen = (try? ablage.tagesnotizen(von: erster, bis: letzter)) ?? []
        return Planwirkung(trades: trades, notizen: notizen, zeitzone: zeitzone)
    }

    var verpassteAuswertung: VerpassteAuswertung { VerpassteAuswertung(verpasstImMonat) }
}

extension VerpassterTrade.Grund {
    var titel: String {
        switch self {
        case .zoegern: String(localized: "Gezögert")
        case .zuSpaet: String(localized: "Zu spät")
        case .regelSperre: String(localized: "Regelsperre")
        case .nichtAmPlatz: String(localized: "Nicht am Platz")
        case .unsicheresSetup: String(localized: "Setup unsicher")
        case .sonstiges: String(localized: "Sonstiges")
        }
    }
}
