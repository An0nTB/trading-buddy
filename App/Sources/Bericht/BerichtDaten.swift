import Foundation
import TradingCore
import TradingStore

// Monatsbericht als PDF (Doc 18 F11, Doc 32, Entscheidung 47 vom 02.10.2026). Gerechnet wird in
// TradingCore (`Monatsbericht`); die Dateien unter Bericht/ holen nur die Eingaben und zeichnen.

/// Kopfangaben des PDFs neben dem `Monatsbericht`. Die Kontonummer steht höchstens mit den letzten
/// vier Stellen drin, weil das PDF zum Weitergeben gedacht ist.
struct BerichtKontext {
    var jahr: Int
    var monat: Int
    /// z. B. „März 2026“.
    var monatsname: String
    /// z. B. „XTB · Konto …1234“.
    var konto: String
    var waehrung: String
    var zeitzone: TimeZone
    var erstellt: Date
    var regelnHinterlegt: Bool
    /// Trade Republic und Scalable ja, MetaTrader, XTB und Krypto-Börsen nein, sonst unbekannt.
    var brokerFuehrtSteuerAb: Bool?

    /// Broker und höchstens die letzten vier Stellen der Kontonummer.
    static func kontoText(broker: String, kontonummer: String) -> String {
        let nummer = kontonummer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nummer.isEmpty else { return broker }
        let ende = String(nummer.suffix(4))
        return broker + " · " + String(localized: "Konto …\(ende)")
    }

    /// Dateiname ohne Kontonummer, z. B. „Brad Monatsbericht 2026-03.pdf“.
    var dateiname: String {
        String(format: "Brad Monatsbericht %04d-%02d.pdf", jahr, monat)
    }
}

extension AppModell {
    /// Monatsbericht für den Kalendermonat von `monat` (Zeitzone des Nutzers) über alle Trades des
    /// gewählten Kontos, unabhängig vom Zeitraum- und Instrumentfilter der Oberfläche.
    /// Tagesnotizen und verpasste Trades gelten für alle Konten, wie auf der Tagesseite.
    func monatsbericht(_ monat: Date, jetzt: Date = Date()) -> (bericht: Monatsbericht, kontext: BerichtKontext)? {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let teile = kalender.dateComponents([.year, .month], from: monat)
        guard let jahr = teile.year, let nummer = teile.month,
              let spanne = kalender.dateInterval(of: .month, for: monat) else { return nil }
        let erster = Journaltag(spanne.start, zeitzone: zeitzone)
        let letzter = Journaltag(spanne.end.addingTimeInterval(-1), zeitzone: zeitzone)
        let notizen = (try? journal?.tagesnotizen(von: erster, bis: letzter)) ?? []
        let verpasst = (try? journal?.verpassteTrades(von: spanne.start, bis: spanne.end)) ?? []
        guard let bericht = Monatsbericht(trades: alleTrades, jahr: jahr, monat: nummer, zeitzone: zeitzone,
                                          kontowaehrung: waehrung, regeln: regeln, manuell: manuellVerletzt,
                                          ziele: ziele, notizen: notizen, verpasst: verpasst,
                                          geloeschteOrders: alleGeloeschten.map(\.cancelledAt))
        else { return nil }
        let kontoText = konto.map { BerichtKontext.kontoText(broker: $0.broker, kontonummer: $0.kontonummer) }
        let kontext = BerichtKontext(jahr: jahr, monat: nummer, monatsname: Format.monat(spanne.start),
                                     konto: kontoText ?? String(localized: "Ohne Konto"), waehrung: waehrung,
                                     zeitzone: zeitzone, erstellt: jetzt, regelnHinterlegt: !regeln.leer,
                                     brokerFuehrtSteuerAb: brokerFuehrtSteuerAb)
        return (bericht, kontext)
    }
}
