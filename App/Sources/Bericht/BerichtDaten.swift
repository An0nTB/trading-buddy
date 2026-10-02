import Foundation
import TradingCore
import TradingRates
import TradingStore

// Monats- und Wochenbericht als PDF (Doc 18 F11, Doc 32, Entscheidung 47 vom 02.10.2026; Wochenbericht
// Tim 02.10.2026, Frage 4, Doc 47). Gerechnet wird in TradingCore (`Zeitraumbericht`); die Dateien unter
// Bericht/ holen nur die Eingaben und zeichnen.

/// Welche Spanne der Bericht abdeckt; bestimmt Titel, Vergleichsname und Dateiname.
enum BerichtArt: Equatable {
    case monat
    /// ISO-Kalenderwoche (Montag bis Sonntag).
    case woche(jahr: Int, nummer: Int)
    /// Frei gewählte Tage.
    case zeitraum
}

/// Kopfangaben des PDFs neben dem `Zeitraumbericht`. Die Kontonummer steht höchstens mit den letzten
/// vier Stellen drin, weil das PDF zum Weitergeben gedacht ist.
struct BerichtKontext {
    var art: BerichtArt
    var zeitraum: Zeitspanne
    /// Erster und letzter Tag der Spanne in der Zeitzone des Nutzers.
    var erster: Journaltag
    var letzter: Journaltag
    /// z. B. „Monatsbericht März 2026“ oder „Wochenbericht KW 40/2026“.
    var titel: String
    /// z. B. „XTB · Konto …1234“.
    var konto: String
    var waehrung: String
    var zeitzone: TimeZone
    var erstellt: Date
    var regelnHinterlegt: Bool
    /// Trade Republic und Scalable ja, MetaTrader, XTB und Krypto-Börsen nein, sonst unbekannt.
    var brokerFuehrtSteuerAb: Bool?
    /// Letzter Tag mit EZB-Referenzkursen; `nil`, wenn keine geladen sind.
    var ezbBis: Journaltag?

    /// Broker und höchstens die letzten vier Stellen der Kontonummer.
    static func kontoText(broker: String, kontonummer: String) -> String {
        let nummer = kontonummer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nummer.isEmpty else { return broker }
        let ende = String(nummer.suffix(4))
        return broker + " · " + String(localized: "Konto …\(ende)")
    }

    /// „28.09.2026“, unabhängig von der Zeitzone des Geräts.
    static func datum(_ tag: Journaltag) -> String {
        String(format: "%02d.%02d.%d", tag.tag, tag.monat, tag.jahr)
    }

    /// z. B. „28.09.2026 bis 04.10.2026“.
    var spanneText: String {
        String(localized: "\(Self.datum(erster)) bis \(Self.datum(letzter))")
    }

    /// Dateiname ohne Kontonummer, z. B. „Henry Monatsbericht 2026-03.pdf“ oder „Henry Wochenbericht 2026-W40.pdf“.
    var dateiname: String {
        switch art {
        case .monat:
            String(format: "Henry Monatsbericht %04d-%02d.pdf", erster.jahr, erster.monat)
        case let .woche(jahr, nummer):
            String(format: "Henry Wochenbericht %04d-W%02d.pdf", jahr, nummer)
        case .zeitraum:
            String(format: "Henry Bericht %04d-%02d-%02d bis %04d-%02d-%02d.pdf",
                   erster.jahr, erster.monat, erster.tag, letzter.jahr, letzter.monat, letzter.tag)
        }
    }

    /// Name der gleich langen Spanne davor, für die Kennzahl-Kacheln.
    var vergleichsname: String {
        switch art {
        case .monat: String(localized: "Vormonat")
        case .woche: String(localized: "Vorwoche")
        case .zeitraum: String(localized: "Vorzeitraum")
        }
    }

    /// „in diesem Monat“, „in dieser Woche“ oder „in diesem Zeitraum“.
    var inDerSpanne: String {
        switch art {
        case .monat: String(localized: "in diesem Monat")
        case .woche: String(localized: "in dieser Woche")
        case .zeitraum: String(localized: "in diesem Zeitraum")
        }
    }
}

extension AppModell {
    /// Monatsbericht für den Kalendermonat von `monat` (Zeitzone des Nutzers).
    func monatsbericht(_ monat: Date, jetzt: Date = Date()) -> (bericht: Zeitraumbericht, kontext: BerichtKontext) {
        let zeitraum = Zeitspanne.monat(mit: monat, zeitzone: zeitzone)
        return bericht(zeitraum, art: .monat,
                       titel: String(localized: "Monatsbericht \(Format.monat(zeitraum.von))"), jetzt: jetzt)
    }

    /// Wochenbericht für die ISO-Kalenderwoche (Montag bis Sonntag), in die `datum` fällt.
    func wochenbericht(_ datum: Date, jetzt: Date = Date()) -> (bericht: Zeitraumbericht, kontext: BerichtKontext) {
        let zeitraum = Zeitspanne.woche(mit: datum, zeitzone: zeitzone)
        guard let kw = zeitraum.kalenderwoche(zeitzone: zeitzone) else {
            return bericht(zeitraum, art: .zeitraum, titel: String(localized: "Bericht"), jetzt: jetzt)
        }
        return bericht(zeitraum, art: .woche(jahr: kw.jahr, nummer: kw.woche),
                       titel: String(localized: "Wochenbericht KW \(kw.woche)/\(String(kw.jahr))"), jetzt: jetzt)
    }

    /// Bericht über `zeitraum` und alle Trades des gewählten Kontos, unabhängig vom Zeitraum- und
    /// Instrumentfilter der Oberfläche. Tagesnotizen und verpasste Trades gelten für alle Konten, wie auf
    /// der Tagesseite.
    func bericht(_ zeitraum: Zeitspanne, art: BerichtArt, titel: String,
                 jetzt: Date = Date()) -> (bericht: Zeitraumbericht, kontext: BerichtKontext) {
        let erster = Journaltag(zeitraum.von, zeitzone: zeitzone)
        let letzter = Journaltag(zeitraum.bis.addingTimeInterval(-1), zeitzone: zeitzone)
        let notizen = (try? journal?.tagesnotizen(von: erster, bis: letzter)) ?? []
        let verpasst = (try? journal?.verpassteTrades(von: zeitraum.von, bis: zeitraum.bis)) ?? []
        let bericht = Zeitraumbericht(trades: alleTrades, zeitraum: zeitraum, zeitzone: zeitzone,
                                      kontowaehrung: waehrung, regeln: regeln, manuell: manuellVerletzt,
                                      ziele: ziele, notizen: notizen, verpasst: verpasst,
                                      geloeschteOrders: alleGeloeschten.map(\.cancelledAt), kurse: ezb.kurse)
        let kontoText = konto.map { BerichtKontext.kontoText(broker: $0.broker, kontonummer: $0.kontonummer) }
        let kontext = BerichtKontext(art: art, zeitraum: zeitraum, erster: erster, letzter: letzter, titel: titel,
                                     konto: kontoText ?? String(localized: "Ohne Konto"), waehrung: waehrung,
                                     zeitzone: zeitzone, erstellt: jetzt, regelnHinterlegt: !regeln.leer,
                                     brokerFuehrtSteuerAb: brokerFuehrtSteuerAb, ezbBis: ezb.letzterTag)
        return (bericht, kontext)
    }

    /// Montage der Wochen mit mindestens einem geschlossenen Trade des Kontos, neueste zuerst.
    var berichtWochen: [Date] {
        let montage = Set(alleTrades.map { Zeitspanne.woche(mit: $0.closeTime, zeitzone: zeitzone).von })
        return montage.sorted(by: >)
    }
}

/// Fertiger Bericht samt Kopfangaben, wie ihn `BerichtPDF` zeichnet.
typealias BerichtErgebnis = (bericht: Zeitraumbericht, kontext: BerichtKontext)

extension AppModell {
    /// Bericht über frei gewählte Tage, `von` und `bis` einschließlich, in der Zeitzone des Nutzers.
    /// `nil`, wenn `bis` vor `von` liegt.
    func zeitraumbericht(von: Date, bis: Date, jetzt: Date = Date()) -> BerichtErgebnis? {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let teile: Set<Calendar.Component> = [.year, .month, .day]
        guard let zeitraum = Zeitspanne.tage(von: kalender.dateComponents(teile, from: von),
                                             bis: kalender.dateComponents(teile, from: bis), zeitzone: zeitzone)
        else { return nil }
        return bericht(zeitraum, art: .zeitraum, titel: String(localized: "Bericht für Zeitraum"), jetzt: jetzt)
    }
}
