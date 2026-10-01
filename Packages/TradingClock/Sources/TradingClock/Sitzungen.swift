import Foundation

/// Eine konkrete Handelssitzung als Zeitspanne. `ende` gehört nicht mehr dazu:
/// Um 17:30:00 ist Xetra geschlossen.
public struct Sitzung: Sendable, Hashable {
    public var beginn: Date
    public var ende: Date
    /// Name des verkürzten Tages, wenn die Sitzung früher endet.
    public var verkuerzt: String?

    public init(beginn: Date, ende: Date, verkuerzt: String? = nil) {
        self.beginn = beginn
        self.ende = ende
        self.verkuerzt = verkuerzt
    }

    public func enthaelt(_ zeitpunkt: Date) -> Bool { beginn <= zeitpunkt && zeitpunkt < ende }
}

/// Antwort der Uhr für einen Zeitpunkt.
public struct Boersenstatus: Sendable, Hashable {
    public var offen: Bool
    /// Wenn offen: nächste Schließung. Wenn geschlossen: nächste Öffnung.
    /// `nil` bei durchgehend geöffneten Märkten.
    public var naechsterWechsel: Date?
    /// Name des Feiertags, wenn der Tag (Ortszeit der Börse) ein Feiertag ist.
    public var feiertag: String?
    /// Name des verkürzten Tages, wenn die laufende oder nächste Sitzung früher endet.
    public var verkuerzt: String?
    /// `false`, wenn der Zeitpunkt oder der nächste Wechsel hinter `datenGueltigBis` liegt.
    /// Dann fehlen womöglich Feiertage; die Anzeige sollte das sagen.
    public var datenGueltig: Bool
}

extension Boerse {
    /// Wie weit die Uhr nach der nächsten Öffnung oder Schließung sucht.
    static let suchtageMaximal = 400

    /// Alle Sitzungen, die die Spanne `von` bis `bis` berühren, nach Beginn sortiert.
    /// Sitzungen, die nahtlos aneinander anschließen (Forex), werden zu einer zusammengefasst.
    /// Bei durchgehend geöffneten Märkten eine einzige Sitzung über die ganze Spanne.
    public func sitzungen(von: Date, bis: Date) -> [Sitzung] {
        guard von < bis else { return [] }
        if durchgehend { return [Sitzung(beginn: von, ende: bis)] }

        let zone = timeZone
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zone
        let feiertagSet = Set(feiertage.map(\.datum))
        var verkuerzt: [Kalendertag: VerkuerzterTag] = [:]
        for tag in verkuerzteTage { verkuerzt[tag.datum] = tag }
        let laengsteSitzung = handelszeiten.map(\.endeNachTagen).max() ?? 0

        // Einen Tag Puffer auf beiden Seiten, damit Sitzungen über Mitternacht nicht fehlen.
        var tag = Kalendertag(von, in: zone).plus(tage: -(laengsteSitzung + 1))
        let letzterTag = Kalendertag(bis, in: zone).plus(tage: 1)
        var roh: [Sitzung] = []
        while tag <= letzterTag {
            defer { tag = tag.plus(tage: 1) }
            if feiertagSet.contains(tag) { continue }
            for zeit in handelszeiten where zeit.tage.contains(tag.wochentag) {
                let endTag = tag.plus(tage: zeit.endeNachTagen)
                var endUhrzeit = zeit.ende
                var verkuerztName: String?
                if let kurz = verkuerzt[endTag], kurz.ende < endUhrzeit {
                    endUhrzeit = kurz.ende
                    verkuerztName = kurz.name
                }
                guard let beginn = Boerse.zeitpunkt(tag, zeit.beginn, kalender),
                      let ende = Boerse.zeitpunkt(endTag, endUhrzeit, kalender),
                      beginn < ende
                else { continue }
                if ende > von && beginn < bis {
                    roh.append(Sitzung(beginn: beginn, ende: ende, verkuerzt: verkuerztName))
                }
            }
        }

        roh.sort { $0.beginn < $1.beginn }
        var zusammen: [Sitzung] = []
        for sitzung in roh {
            if let letzte = zusammen.last, sitzung.beginn <= letzte.ende {
                if sitzung.ende > letzte.ende {
                    zusammen[zusammen.count - 1].ende = sitzung.ende
                    zusammen[zusammen.count - 1].verkuerzt = sitzung.verkuerzt
                }
            } else {
                zusammen.append(sitzung)
            }
        }
        return zusammen
    }

    /// Ist die Börse zu diesem Zeitpunkt geöffnet?
    public func istOffen(_ zeitpunkt: Date) -> Bool {
        laufendeSitzung(zeitpunkt) != nil
    }

    /// Die Sitzung, in der `zeitpunkt` liegt, oder `nil`.
    /// Schließen Sitzungen nahtlos an (Forex), reicht sie bis zur echten Schließung.
    public func laufendeSitzung(_ zeitpunkt: Date) -> Sitzung? {
        guard var laufend = sitzungen(von: zeitpunkt, bis: zeitpunkt.addingTimeInterval(1))
            .first(where: { $0.enthaelt(zeitpunkt) }) else { return nil }
        if durchgehend { return laufend }
        for _ in 0..<Boerse.suchtageMaximal {
            guard let anschluss = sitzungen(von: laufend.ende, bis: laufend.ende.addingTimeInterval(1))
                .first(where: { $0.enthaelt(laufend.ende) }) else { break }
            laufend.ende = anschluss.ende
            laufend.verkuerzt = anschluss.verkuerzt
        }
        return laufend
    }

    /// Nächste Öffnung echt nach `zeitpunkt`. `nil` bei durchgehend geöffneten Märkten
    /// oder wenn in 400 Tagen keine Sitzung kommt.
    public func naechsteOeffnung(nach zeitpunkt: Date) -> Date? {
        naechsteSitzung(nach: zeitpunkt)?.beginn
    }

    /// Nächste Schließung echt nach `zeitpunkt`. Ist die Börse gerade offen, ist das das Ende
    /// der laufenden Sitzung, sonst das Ende der nächsten. `nil` bei durchgehend geöffneten Märkten.
    public func naechsteSchliessung(nach zeitpunkt: Date) -> Date? {
        if durchgehend { return nil }
        if let laufend = laufendeSitzung(zeitpunkt) { return laufend.ende }
        guard let naechste = naechsteSitzung(nach: zeitpunkt) else { return nil }
        return (laufendeSitzung(naechste.beginn) ?? naechste).ende
    }

    /// Erste Sitzung, die echt nach `zeitpunkt` beginnt.
    public func naechsteSitzung(nach zeitpunkt: Date) -> Sitzung? {
        if durchgehend { return nil }
        let schritt: TimeInterval = 14 * 86_400
        var von = zeitpunkt
        let grenze = zeitpunkt.addingTimeInterval(TimeInterval(Boerse.suchtageMaximal) * 86_400)
        while von < grenze {
            // Fenster ab `zeitpunkt`, damit eine laufende Sitzung mit der folgenden verschmilzt
            // und nicht als neue Öffnung gilt.
            let bis = von.addingTimeInterval(schritt)
            if let treffer = sitzungen(von: zeitpunkt, bis: bis).first(where: { $0.beginn > zeitpunkt }) {
                return treffer
            }
            von = bis
        }
        return nil
    }

    /// Alles, was die Anzeige braucht, für einen Zeitpunkt.
    public func status(_ zeitpunkt: Date) -> Boersenstatus {
        let zone = timeZone
        let heute = Kalendertag(zeitpunkt, in: zone)
        if durchgehend {
            return Boersenstatus(offen: true, naechsterWechsel: nil, feiertag: nil, verkuerzt: nil, datenGueltig: true)
        }
        let feiertag = feiertage.first(where: { $0.datum == heute })?.name
        let laufend = laufendeSitzung(zeitpunkt)
        let wechsel: Date?
        let verkuerzt: String?
        if let laufend {
            wechsel = laufend.ende
            verkuerzt = laufend.verkuerzt
        } else {
            let naechste = naechsteSitzung(nach: zeitpunkt)
            wechsel = naechste?.beginn
            verkuerzt = naechste.flatMap { laufendeSitzung($0.beginn) ?? $0 }?.verkuerzt
        }
        var gueltig = true
        if let grenze = datenGueltigBis {
            let spaetester = wechsel.map { Kalendertag($0, in: zone) } ?? heute
            gueltig = heute <= grenze && spaetester <= grenze
        }
        return Boersenstatus(offen: laufend != nil, naechsterWechsel: wechsel, feiertag: feiertag,
                             verkuerzt: verkuerzt, datenGueltig: gueltig)
    }

    static func zeitpunkt(_ tag: Kalendertag, _ uhrzeit: Uhrzeit, _ kalender: Calendar) -> Date? {
        kalender.date(from: DateComponents(year: tag.jahr, month: tag.monat, day: tag.tag,
                                           hour: uhrzeit.stunde, minute: uhrzeit.minute))
    }
}
