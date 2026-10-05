import Foundation

/// Best-Exit-Analyse eines Trades: Wie wäre ein fester Ausstieg bei einem Ziel in R ausgegangen,
/// verglichen mit dem tatsächlichen Ausstieg? Nur Daten, Rückblick auf vergangene Kurse, keine Empfehlung.
///
/// Annahmen:
/// - 1 R ist der Abstand Einstieg bis Stop wie bei `Trade.risk` (bei MetaTrader der letzte Stand des Stops).
/// - Kerzen wie bei `Ausstiegsanalyse`: von der Kerze des Einstiegs bis zur Kerze des Ausstiegs, Auflösung
///   eine Kerze. Erste und letzte Kerze können Kurse kurz vor dem Einstieg oder nach dem Ausstieg enthalten.
/// - Kerze für Kerze: Berührt eine Kerze zuerst den Stop, endet die Variante bei −1 R, berührt sie zuerst
///   das Ziel, bei +Ziel R. Berührt dieselbe Kerze beide, ist die Reihenfolge unbekannt: Es zählt
///   vorsichtig der Stop, und die Stufe ist `unscharf`. Berührt keine Kerze eines von beiden, gilt das
///   tatsächliche Ergebnis.
/// - Ausführung genau am Stop- bzw. Zielkurs, ohne Schlupf und ohne Kurslücken. Bei MetaTrader sind die
///   Kerzen Geldkurse (Bid); den Spread, über den ein Verkauf ausgestiegen wäre, kennt die Analyse nicht.
/// - Die Kosten des Trades (Kommission, Swap, Steuern) gelten für jede Variante gleich (`kostenR`).
///   So ist `tatsaechlichR` gleich `Trade.rMultiple`, und die Differenz zeigt allein den Ausstieg.
public struct BestExit: Sendable, Equatable {
    /// Wie eine Variante endet.
    public enum Ausgang: Sendable, Equatable {
        /// Ziel vor dem Stop erreicht.
        case ziel
        /// Stop zuerst erreicht, oder Stop und Ziel in derselben Kerze (dann `unscharf`).
        case stop
        /// Bis zum tatsächlichen Ausstieg weder Stop noch Ziel: Ergebnis wie tatsächlich.
        case tatsaechlich
    }

    /// Ergebnis einer Ziel-Stufe.
    public struct Stufe: Sendable, Equatable {
        /// Ziel in R, z. B. 2 für einen Ausstieg bei 2 R.
        public var ziel: Decimal
        public var ausgang: Ausgang
        /// Ergebnis der Variante in R nach Kosten.
        public var r: Decimal
        /// `r` − `tatsaechlichR`: positiv heißt, die Variante hätte mehr gebracht.
        public var differenz: Decimal
        /// `differenz` × Risiko, in der Währung des Trades wie `Trade.risk`.
        public var differenzBetrag: Decimal
        /// Dieselbe Kerze berührte Stop und Ziel; gezählt ist der Stop.
        public var unscharf: Bool
    }

    /// Standard-Stufen 1 R, 1,5 R, 2 R und 3 R.
    public static let standardZiele: [Decimal] = [1, Decimal(15) / 10, 2, 3]

    public var tradeID: String
    /// 1 R in der Währung des Trades (`Trade.risk`).
    public var risiko: Decimal
    /// Tatsächliches Ergebnis in R nach Kosten (`Trade.rMultiple`).
    public var tatsaechlichR: Decimal
    /// Kosten des Trades in R (meist negativ), in jeder Variante enthalten.
    public var kostenR: Decimal
    /// Je Ziel eine Stufe, aufsteigend nach Ziel.
    public var stufen: [Stufe]
    /// Theoretisches Maximum: Ausstieg genau am besten Kurs bis zum tatsächlichen Ausstieg
    /// (MFE in R aus der `Ausstiegsanalyse`, zuzüglich `kostenR`). Im Voraus nicht planbar; nur als Obergrenze.
    public var theoretischesMaximumR: Decimal
    /// `theoretischesMaximumR` − `tatsaechlichR`, nie negativ.
    public var differenzTheoretischesMaximum: Decimal
    /// Kerzen reichen deutlich über Ein- oder Ausstieg hinaus (siehe `Ausstiegsanalyse.unscharf`).
    public var kerzenUnscharf: Bool
    /// Anteil der Haltedauer, den Kerzen abdecken (siehe `Ausstiegsanalyse.abdeckung`).
    public var abdeckung: Decimal

    /// `nil` ohne Risiko (kein Stop, Stop auf der Gewinnseite, keine Kursbewegung), ohne Uhrzeit
    /// (`nurDatum`) oder ohne Kerze in der Haltedauer.
    /// - Parameters:
    ///   - kerzen: beliebig sortiert; doppelte Kerzen (gleicher Beginn) zählen einmal, die letzte gilt.
    ///   - ziele: Ziele in R; Werte ≤ 0 und doppelte fallen weg, sortiert wird aufsteigend.
    public init?(trade: Trade, kerzen: [Zeitkerze], ziele: [Decimal] = BestExit.standardZiele) {
        guard let risiko = trade.risk, risiko > 0, let stop = trade.stopLoss,
              let tatsaechlich = trade.rMultiple else { return nil }
        guard let analyse = Ausstiegsanalyse(trade: trade, kerzen: kerzen, nachlauf: 0),
              let mfeR = analyse.mfeR else { return nil }
        let kauf = trade.side == .buy
        let abstand = kauf ? trade.openPrice - stop : stop - trade.openPrice
        guard abstand > 0 else { return nil }
        let verlauf = Self.kerzenImTrade(trade, kerzen)
        let kostenR = trade.costs / risiko

        var stufen: [Stufe] = []
        for ziel in Self.bereinigt(ziele) {
            let lauf = Self.simuliere(verlauf, kauf: kauf, einstieg: trade.openPrice, abstand: abstand, ziel: ziel)
            let r: Decimal
            switch lauf.ausgang {
            case .ziel: r = ziel + kostenR
            case .stop: r = kostenR - 1
            case .tatsaechlich: r = tatsaechlich
            }
            let differenz = r - tatsaechlich
            let stufe = Stufe(ziel: ziel, ausgang: lauf.ausgang, r: r, differenz: differenz,
                              differenzBetrag: differenz * risiko, unscharf: lauf.unscharf)
            stufen.append(stufe)
        }

        let maximum = mfeR + kostenR
        tradeID = trade.id
        self.risiko = risiko
        tatsaechlichR = tatsaechlich
        self.kostenR = kostenR
        self.stufen = stufen
        theoretischesMaximumR = maximum
        differenzTheoretischesMaximum = max(0, maximum - tatsaechlich)
        kerzenUnscharf = analyse.unscharf
        abdeckung = analyse.abdeckung
    }

    /// Ziele > 0, aufsteigend, ohne doppelte.
    static func bereinigt(_ ziele: [Decimal]) -> [Decimal] {
        let positiv = ziele.filter { $0 > 0 }.sorted()
        var ergebnis: [Decimal] = []
        for ziel in positiv where ergebnis.last != ziel {
            ergebnis.append(ziel)
        }
        return ergebnis
    }

    /// Kerzen in der Haltedauer, sortiert, je Beginn die letzte; Auswahl wie in `Ausstiegsanalyse`.
    static func kerzenImTrade(_ trade: Trade, _ kerzen: [Zeitkerze]) -> [Zeitkerze] {
        var jeBeginn: [Date: Zeitkerze] = [:]
        for k in kerzen where k.dauer > 0 { jeBeginn[k.beginn] = k }
        let sortiert = jeBeginn.values.sorted { $0.beginn < $1.beginn }
        return sortiert.filter {
            $0.ende > trade.openTime && ($0.beginn < trade.closeTime || $0.beginn == trade.openTime)
        }
    }

    /// Geht die Kerzen der Reihe nach durch, bis Stop oder Ziel berührt sind.
    static func simuliere(_ verlauf: [Zeitkerze], kauf: Bool, einstieg: Decimal, abstand: Decimal,
                          ziel: Decimal) -> (ausgang: Ausgang, unscharf: Bool) {
        let zielAbstand = ziel * abstand
        let stopKurs = kauf ? einstieg - abstand : einstieg + abstand
        let zielKurs = kauf ? einstieg + zielAbstand : einstieg - zielAbstand
        for k in verlauf {
            let stopBeruehrt = kauf ? k.low <= stopKurs : k.high >= stopKurs
            let zielBeruehrt = kauf ? k.high >= zielKurs : k.low <= zielKurs
            if stopBeruehrt { return (.stop, zielBeruehrt) }
            if zielBeruehrt { return (.ziel, false) }
        }
        return (.tatsaechlich, false)
    }
}

/// Best-Exit-Analyse über alle Trades: je Ziel-Stufe Summe und Schnitt in R gegenüber dem tatsächlichen
/// Ausstieg. Nur Daten, keine Empfehlung.
public struct BestExitAuswertung: Sendable, Equatable {
    /// Summen einer Ziel-Stufe über alle analysierten Trades.
    public struct Stufe: Sendable, Equatable {
        public var ziel: Decimal
        /// Trades mit dieser Stufe (bei einheitlichen Zielen gleich `BestExitAuswertung.anzahl`).
        public var anzahl: Int
        public var summeR: Decimal
        /// `nil` ohne Trades.
        public var durchschnittR: Decimal?
        /// Ziel vor dem Stop erreicht.
        public var zielErreicht: Int
        /// Stop zuerst, einschließlich der unscharfen Fälle.
        public var stopZuerst: Int
        /// Weder Stop noch Ziel bis zum Ausstieg; Ergebnis wie tatsächlich.
        public var ohneEntscheidung: Int
        /// `zielErreicht` ÷ `anzahl`, 0 bis 1; `nil` ohne Trades.
        public var trefferquote: Decimal?
        /// Summe der Differenzen zum tatsächlichen R; positiv heißt, die Stufe hätte mehr gebracht.
        public var differenzR: Decimal
        /// Summe `differenzBetrag`, nur bei einer gemeinsamen Währung und mindestens einem Trade; sonst `nil`.
        public var differenzBetrag: Decimal?
        /// Fälle, in denen dieselbe Kerze Stop und Ziel berührte (als Stop gezählt).
        public var anzahlUnscharf: Int
    }

    /// Ziele der Auswertung, aufsteigend.
    public var ziele: [Decimal]
    /// Die einzelnen Analysen, in der Reihenfolge der Trades.
    public var einzeln: [BestExit]
    /// Analysierte Trades.
    public var anzahl: Int
    /// Ausgelassen: ohne Risiko (kein Stop, Stop auf der Gewinnseite, keine Kursbewegung).
    public var ohneRisiko: Int
    /// Ausgelassen: mit Risiko, aber ohne nutzbare Kerzen (keine Kerze in der Haltedauer oder ohne Uhrzeit).
    public var ohneKerzen: Int
    /// Analysierte Trades, deren Kerzen deutlich über Ein- oder Ausstieg hinausreichen.
    public var anzahlKerzenUnscharf: Int
    public var summeTatsaechlichR: Decimal
    public var durchschnittTatsaechlichR: Decimal?
    public var stufen: [Stufe]
    /// Ziel der Stufe mit der höchsten Summe R; bei Gleichstand die niedrigere. `nil` ohne Trades.
    public var besteStufe: Decimal?
    /// Summe `theoretischesMaximumR`: Obergrenze, Ausstieg jeweils am besten Kurs.
    public var summeTheoretischesMaximumR: Decimal
    /// `summeTheoretischesMaximumR` − `summeTatsaechlichR`.
    public var differenzTheoretischesMaximum: Decimal

    /// Analysiert alle Trades und zählt die ausgelassenen.
    /// - Parameters:
    ///   - kerzenJeTrade: Kerzen je `Trade.id`; ein fehlender Eintrag zählt als ohne Kerzen.
    ///   - gleicheWaehrung: Die Trades lauten alle auf eine Währung; nur dann gibt es Beträge.
    public init(trades: [Trade], kerzenJeTrade: [String: [Zeitkerze]], ziele: [Decimal] = BestExit.standardZiele,
                gleicheWaehrung: Bool) {
        var einzeln: [BestExit] = []
        var ohneRisiko = 0
        var ohneKerzen = 0
        for trade in trades {
            guard let risiko = trade.risk, risiko > 0 else {
                ohneRisiko += 1
                continue
            }
            let kerzen = kerzenJeTrade[trade.id] ?? []
            if let analyse = BestExit(trade: trade, kerzen: kerzen, ziele: ziele) {
                einzeln.append(analyse)
            } else {
                ohneKerzen += 1
            }
        }
        self.init(einzeln, ziele: ziele, ohneRisiko: ohneRisiko, ohneKerzen: ohneKerzen,
                  gleicheWaehrung: gleicheWaehrung)
    }

    /// Fasst fertige Analysen zusammen; die Zähler der ausgelassenen Trades gibt der Aufrufer mit.
    public init(_ einzeln: [BestExit], ziele: [Decimal] = BestExit.standardZiele, ohneRisiko: Int = 0,
                ohneKerzen: Int = 0, gleicheWaehrung: Bool) {
        let bereinigt = BestExit.bereinigt(ziele)
        var summeTatsaechlich: Decimal = 0
        var summeMaximum: Decimal = 0
        for analyse in einzeln {
            summeTatsaechlich += analyse.tatsaechlichR
            summeMaximum += analyse.theoretischesMaximumR
        }
        var stufen: [Stufe] = []
        var beste: Stufe?
        for ziel in bereinigt {
            let stufe = Self.stufe(ziel, einzeln, gleicheWaehrung: gleicheWaehrung)
            stufen.append(stufe)
            guard stufe.anzahl > 0 else { continue }
            if let bisher = beste, bisher.summeR >= stufe.summeR { continue }
            beste = stufe
        }

        self.ziele = bereinigt
        self.einzeln = einzeln
        anzahl = einzeln.count
        self.ohneRisiko = ohneRisiko
        self.ohneKerzen = ohneKerzen
        anzahlKerzenUnscharf = einzeln.filter(\.kerzenUnscharf).count
        summeTatsaechlichR = summeTatsaechlich
        durchschnittTatsaechlichR = einzeln.isEmpty ? nil : summeTatsaechlich / Decimal(einzeln.count)
        self.stufen = stufen
        besteStufe = beste?.ziel
        summeTheoretischesMaximumR = summeMaximum
        differenzTheoretischesMaximum = summeMaximum - summeTatsaechlich
    }

    static func stufe(_ ziel: Decimal, _ einzeln: [BestExit], gleicheWaehrung: Bool) -> Stufe {
        var anzahl = 0
        var summeR: Decimal = 0
        var differenzR: Decimal = 0
        var differenzBetrag: Decimal = 0
        var treffer = 0
        var stops = 0
        var offen = 0
        var unscharf = 0
        for analyse in einzeln {
            guard let s = analyse.stufen.first(where: { $0.ziel == ziel }) else { continue }
            anzahl += 1
            summeR += s.r
            differenzR += s.differenz
            differenzBetrag += s.differenzBetrag
            switch s.ausgang {
            case .ziel: treffer += 1
            case .stop: stops += 1
            case .tatsaechlich: offen += 1
            }
            if s.unscharf { unscharf += 1 }
        }
        let n = Decimal(anzahl)
        let durchschnitt: Decimal? = anzahl > 0 ? summeR / n : nil
        let quote: Decimal? = anzahl > 0 ? Decimal(treffer) / n : nil
        let betrag: Decimal? = gleicheWaehrung && anzahl > 0 ? differenzBetrag : nil
        return Stufe(ziel: ziel, anzahl: anzahl, summeR: summeR, durchschnittR: durchschnitt,
                     zielErreicht: treffer, stopZuerst: stops, ohneEntscheidung: offen, trefferquote: quote,
                     differenzR: differenzR, differenzBetrag: betrag, anzahlUnscharf: unscharf)
    }
}
