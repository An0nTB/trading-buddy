import Foundation

// MARK: - Drawdown und Serien

extension Tiefenanalyse {
    public struct Drawdownpunkt: Sendable, Equatable {
        public var tradeID: Trade.ID
        /// Schlusszeit des Trades.
        public var zeit: Date
        /// Kontostand nach dem Trade (Startkapital plus Summe netto), wie `Kapitalverlauf.punkte`.
        public var kapital: Decimal
        /// Bisheriges Hoch einschließlich Startkapital.
        public var hoch: Decimal
        /// Abstand zum bisherigen Hoch, nicht negativ.
        public var abstand: Decimal
    }

    /// Ununterbrochene Folge von Gewinnern bzw. Verlierern nach Schlusszeit; Breakeven unterbricht wie in
    /// `Kapitalverlauf`. Bei gleicher Länge zählt die früheste.
    public struct Serie: Sendable, Equatable {
        public var anzahl: Int
        public var summe: Decimal
        public var tradeIDs: [Trade.ID]
        /// Schluss des ersten und des letzten Trades; `nil` ohne Serie.
        public var von: Date?
        public var bis: Date?
    }

    public struct Drawdownanalyse: Sendable, Equatable {
        /// Ein Punkt je Trade nach Schlusszeit.
        public var punkte: [Drawdownpunkt]
        /// Größter Rückgang vom bisherigen Hoch, positiv (`Kapitalverlauf.maxDrawdown`).
        public var maxDrawdown: Decimal
        /// Schluss des Trades, der das Hoch vor dem größten Rückgang setzte; `nil`, wenn es das Startkapital war
        /// oder es keinen Rückgang gibt.
        public var hochVorMaxDrawdown: Date?
        /// Schluss des Trades am Tiefpunkt des größten Rückgangs; `nil` ohne Rückgang.
        public var tiefpunkt: Date?
        /// Schluss des ersten Trades, mit dem das alte Hoch wieder erreicht ist; `nil` ohne Rückgang oder solange
        /// nicht erholt.
        public var erholt: Date?
        /// Sekunden vom Tiefpunkt bis zur Erholung; `nil`, solange nicht erholt.
        public var dauerBisErholung: TimeInterval?
        public var laengsteVerlustserie: Serie
        public var laengsteGewinnserie: Serie
    }

    /// Kapitalkurve mit Abstand zum Hoch, größter Rückgang mit Erholung und längste Serien.
    /// Reihenfolge und Werte wie `Kapitalverlauf` (nach Schlusszeit, bei gleicher Zeit nach ID).
    public static func drawdown(_ trades: [Trade], startkapital: Decimal = 0) -> Drawdownanalyse {
        let verlauf = Kapitalverlauf(trades: trades, startkapital: startkapital)
        let sortiert = nachSchluss(trades)
        var hoch = startkapital
        var hochZeit: Date?
        var groesster: Decimal = 0
        var tiefIndex: Int?
        var hochVorTief = startkapital
        var hochZeitVorTief: Date?
        var punkte: [Drawdownpunkt] = []
        for (i, t) in sortiert.enumerated() {
            let kapital = verlauf.punkte[i]
            if kapital > hoch {
                hoch = kapital
                hochZeit = t.closeTime
            }
            let abstand = hoch - kapital
            punkte.append(Drawdownpunkt(tradeID: t.id, zeit: t.closeTime, kapital: kapital, hoch: hoch,
                                        abstand: abstand))
            if abstand > groesster {
                groesster = abstand
                tiefIndex = i
                hochVorTief = hoch
                hochZeitVorTief = hochZeit
            }
        }
        var erholt: Date?
        var tief: Date?
        if let ti = tiefIndex {
            tief = sortiert[ti].closeTime
            let danach = sortiert.indices.dropFirst(ti + 1)
            if let j = danach.first(where: { verlauf.punkte[$0] >= hochVorTief }) { erholt = sortiert[j].closeTime }
        }
        var dauer: TimeInterval?
        if let erholt, let tief { dauer = erholt.timeIntervalSince(tief) }
        return Drawdownanalyse(
            punkte: punkte, maxDrawdown: verlauf.maxDrawdown, hochVorMaxDrawdown: hochZeitVorTief, tiefpunkt: tief,
            erholt: erholt, dauerBisErholung: dauer,
            laengsteVerlustserie: laengsteSerie(sortiert, .loss), laengsteGewinnserie: laengsteSerie(sortiert, .win))
    }

    static func laengsteSerie(_ sortiert: [Trade], _ ergebnis: Trade.Outcome) -> Serie {
        let leer = Serie(anzahl: 0, summe: 0, tradeIDs: [], von: nil, bis: nil)
        var beste = leer
        var laufend = leer
        for t in sortiert {
            guard t.outcome == ergebnis else {
                laufend = leer
                continue
            }
            laufend.anzahl += 1
            laufend.summe += t.netProfit
            laufend.tradeIDs.append(t.id)
            if laufend.von == nil { laufend.von = t.closeTime }
            laufend.bis = t.closeTime
            if laufend.anzahl > beste.anzahl { beste = laufend }
        }
        return beste
    }
}

// MARK: - Kosten je Fehlermuster

extension Tiefenanalyse {
    public struct Fehlermusterkosten: Sendable, Equatable {
        public var muster: Fehlermuster
        public var anzahl: Int
        /// Summe netto der betroffenen Trades (`Befund.netto`); negativ heißt Kosten.
        public var netto: Decimal
        /// Summe R der betroffenen Trades mit bekanntem Risiko (`Befund.summeR`).
        public var summeR: Decimal?
        public var anzahlMitR: Int
        /// Siehe `Fehlermuster.istRegelbruch`; sonst beschreibt das Muster nur ein Verhalten (etwa alle Verlierer).
        public var istRegelbruch: Bool
        /// Netto des Zeitraums ohne diese Trades (`Auswertung.ohne`); `nil`, wenn das Muster kein Regelbruch ist.
        public var nettoOhne: Decimal?
        public var tradeIDs: [Trade.ID]
    }

    /// Je Fehlermuster mit betroffenen Trades die Summe netto und R, teuerstes zuerst (netto aufsteigend);
    /// bei gleichem Netto in der Reihenfolge von `Fehlermuster.allCases`. Muster ohne Trades fehlen.
    public static func fehlermusterKosten(_ auswertung: Auswertung) -> [Fehlermusterkosten] {
        let jeID = Dictionary(auswertung.trades.map { ($0.id, $0) }, uniquingKeysWith: { erster, _ in erster })
        let reihenfolge = Fehlermuster.allCases
        var ergebnis: [Fehlermusterkosten] = []
        for b in auswertung.befunde where !b.trades.isEmpty {
            let mitR = b.trades.filter { jeID[$0]?.rMultiple != nil }.count
            ergebnis.append(Fehlermusterkosten(
                muster: b.muster, anzahl: b.trades.count, netto: b.netto, summeR: b.summeR, anzahlMitR: mitR,
                istRegelbruch: b.muster.istRegelbruch, nettoOhne: auswertung.ohne(b)?.netto, tradeIDs: b.trades))
        }
        return ergebnis.sorted { a, b in
            if a.netto != b.netto { return a.netto < b.netto }
            let ia = reihenfolge.firstIndex(of: a.muster) ?? 0
            let ib = reihenfolge.firstIndex(of: b.muster) ?? 0
            return ia < ib
        }
    }
}

// MARK: - Stärken und Schwächen

extension Tiefenanalyse {
    /// Merkmal einer Gruppe bei Stärken und Schwächen. Eigener Typ, weil `Aufteilung` kein Setup kennt.
    public enum Gruppendimension: String, Sendable, CaseIterable {
        case wochentag
        case stunde
        case haltedauer
        case symbol
        case setup
        /// Schlussmonat in der Zeitzone des Nutzers, Schlüssel „JJJJ-MM“.
        case monat

        var aufteilung: Aufteilung? {
            switch self {
            case .wochentag: Aufteilung.wochentag
            case .stunde: Aufteilung.stunde
            case .haltedauer: Aufteilung.haltedauer
            case .symbol: Aufteilung.symbol
            case .setup, .monat: nil
            }
        }
    }

    public struct Gruppenbefund: Sendable, Equatable {
        public var dimension: Gruppendimension
        /// Wie `Gruppe.schluessel` (Wochentag „1“–„7“, Stunde „0“–„23“, Haltedauerklasse, Symbol), Setup-Name
        /// oder Monat „JJJJ-MM“.
        public var schluessel: String
        public var anzahl: Int
        public var netto: Decimal
        public var trefferquote: Decimal?
        /// Ø R der Trades mit bekanntem Risiko; `nil` ohne solche.
        public var durchschnittR: Decimal?
        public var r: RKennzahlen
        public var tradeIDs: [Trade.ID]
    }

    public struct StaerkenUndSchwaechen: Sendable, Equatable {
        /// Gruppen mit positivem Netto, höchstes zuerst.
        public var staerkste: [Gruppenbefund]
        /// Gruppen mit negativem Netto, niedrigstes zuerst.
        public var schwaechste: [Gruppenbefund]
        public var mindestanzahl: Int
    }

    /// Die stärksten und schwächsten Gruppen über Wochentag, Stunde, Haltedauerklasse, Symbol, Schlussmonat
    /// und, wenn übergeben, Setup. Nur Gruppen mit mindestens `mindestanzahl` Trades; „ohne Uhrzeit“ ist keine Gruppe.
    /// Eine Gruppe mit Netto 0 ist weder Stärke noch Schwäche. Bei gleichem Netto entscheidet die Reihenfolge
    /// von `Gruppendimension.allCases`, dann der Schlüssel.
    /// - Parameter setups: Setup-Name je Trade-ID; leer lässt die Dimension Setup weg.
    public static func staerkenUndSchwaechen(_ trades: [Trade], zeitzone: TimeZone, setups: [Trade.ID: String] = [:],
                                             mindestanzahl: Int = 10, anzahl: Int = 3) -> StaerkenUndSchwaechen {
        let alle = gruppenbefunde(trades, zeitzone: zeitzone, setups: setups)
            .filter { $0.anzahl >= mindestanzahl }
        let reihenfolge = Gruppendimension.allCases
        func vorher(_ a: Gruppenbefund, _ b: Gruppenbefund, absteigend: Bool) -> Bool {
            if a.netto != b.netto { return absteigend ? a.netto > b.netto : a.netto < b.netto }
            let ia = reihenfolge.firstIndex(of: a.dimension) ?? 0
            let ib = reihenfolge.firstIndex(of: b.dimension) ?? 0
            if ia != ib { return ia < ib }
            return a.schluessel < b.schluessel
        }
        let positiv = alle.filter { $0.netto > 0 }.sorted { vorher($0, $1, absteigend: true) }
        let negativ = alle.filter { $0.netto < 0 }.sorted { vorher($0, $1, absteigend: false) }
        let n = max(anzahl, 0)
        return StaerkenUndSchwaechen(staerkste: Array(positiv.prefix(n)), schwaechste: Array(negativ.prefix(n)),
                                     mindestanzahl: mindestanzahl)
    }

    /// Alle Gruppen aller Dimensionen, ohne Mindestanzahl. Der Schlüssel je Trade kommt aus
    /// `Kennzahlen.aufschluesseln`, damit Wochentag, Stunde und Haltedauer genau wie dort gelten.
    static func gruppenbefunde(_ trades: [Trade], zeitzone: TimeZone,
                               setups: [Trade.ID: String]) -> [Gruppenbefund] {
        let sortiert = nachSchluss(trades)
        let k = kalender(zeitzone)
        var ergebnis: [Gruppenbefund] = []
        for dimension in Gruppendimension.allCases {
            var jeSchluessel: [String: [Trade]] = [:]
            for t in sortiert {
                let roh: String?
                if let aufteilung = dimension.aufteilung {
                    roh = Kennzahlen.aufschluesseln([t], nach: aufteilung, zeitzone: zeitzone).first?.schluessel
                } else if dimension == .monat {
                    roh = monatsschluessel(t, kalender: k)
                } else {
                    roh = setups[t.id]
                }
                guard let schluessel = roh, !schluessel.isEmpty, schluessel != Gruppe.ohneUhrzeit else { continue }
                jeSchluessel[schluessel, default: []].append(t)
            }
            for schluessel in jeSchluessel.keys.sorted() {
                let teil = jeSchluessel[schluessel] ?? []
                let kz = Kennzahlen(trades: teil)
                ergebnis.append(Gruppenbefund(
                    dimension: dimension, schluessel: schluessel, anzahl: kz.anzahl, netto: kz.netto,
                    trefferquote: kz.trefferquote, durchschnittR: kz.erwartungswertR, r: RKennzahlen(trades: teil),
                    tradeIDs: teil.map(\.id)))
            }
        }
        return ergebnis
    }
}

// MARK: - Monate

extension Tiefenanalyse {
    public struct Monatsgruppe: Sendable, Equatable {
        public var jahr: Int
        public var monat: Int
        public var anzahl: Int
        public var netto: Decimal
        public var trefferquote: Decimal?
        public var durchschnittR: Decimal?
        public var r: RKennzahlen
        public var tradeIDs: [Trade.ID]
    }

    /// Kennzahlen je Schlussmonat in der Zeitzone des Nutzers, ältester zuerst; Monate ohne Trades fehlen.
    /// Trades nur mit Datum zählen mit ihrem Buchungstag (`Trade.schlusstag`).
    public static func monate(_ trades: [Trade], zeitzone: TimeZone) -> [Monatsgruppe] {
        let k = kalender(zeitzone)
        var jeMonat: [Int: [Trade]] = [:]
        for t in nachSchluss(trades) {
            let teile = k.dateComponents([.year, .month], from: t.schlusstag(k))
            jeMonat[(teile.year ?? 0) * 100 + (teile.month ?? 0), default: []].append(t)
        }
        var ergebnis: [Monatsgruppe] = []
        for schluessel in jeMonat.keys.sorted() {
            let teil = jeMonat[schluessel] ?? []
            let kz = Kennzahlen(trades: teil)
            ergebnis.append(Monatsgruppe(
                jahr: schluessel / 100, monat: schluessel % 100, anzahl: kz.anzahl, netto: kz.netto,
                trefferquote: kz.trefferquote, durchschnittR: kz.erwartungswertR, r: RKennzahlen(trades: teil),
                tradeIDs: teil.map(\.id)))
        }
        return ergebnis
    }

    /// „JJJJ-MM“ des Schlusstags.
    static func monatsschluessel(_ t: Trade, kalender: Calendar) -> String {
        let teile = kalender.dateComponents([.year, .month], from: t.schlusstag(kalender))
        let monat = teile.month ?? 0
        return "\(teile.year ?? 0)-\(monat < 10 ? "0" : "")\(monat)"
    }
}
