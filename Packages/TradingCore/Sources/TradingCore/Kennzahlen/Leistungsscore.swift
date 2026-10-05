import Foundation

/// Gesamtnote 0 bis 100 aus sechs Komponenten, für eine Kennzahl auf der Auswertungsseite und ein Netzdiagramm
/// (Tim 05.10.2026). Jede Komponente wird stückweise linear zwischen öffentlichen Ankerwerten auf 0 bis 100
/// abgebildet und außerhalb der Anker gekappt; der Gesamtwert ist der gewichtete Mittelwert. Die Anker sind
/// Vorschläge aus R5 (Kapitel 07 und 08) und am echten Datensatz zu kalibrieren. Beschreibt die Vergangenheit,
/// keine Prognose. Beträge in Kontowährung (vorher `Waehrungsangleich`).
public struct Leistungsscore: Sendable, Equatable {
    public enum Komponente: String, Sendable, CaseIterable {
        /// Anteil Gewinner.
        case trefferquote
        /// Ø Gewinn ÷ |Ø Verlust| (`Kennzahlen.payoff`).
        case payoff
        /// Summe Gewinne ÷ |Summe Verluste|.
        case profitfaktor
        /// Anteil profitabler Handelstage (Schlusstag, Netto > 0). Gewählt statt 1 − Variationskoeffizient der
        /// Tagesergebnisse, weil der Variationskoeffizient bei einem Mittel nahe 0 beliebig groß wird.
        case bestaendigkeit
        /// Maximaler Drawdown ÷ Summe der Gewinne (netto aller Gewinner). Bezug auf die Gewinne statt auf ein
        /// Kapitalhoch, weil der Kern kein Startkapital kennt: Wie viel des Verdienten ging im schlimmsten
        /// Rückgang wieder verloren? Kleiner ist besser.
        case drawdown
        /// Anteil regeltreuer Trades 0 bis 1, von außen (liegt im Store).
        case regeltreue
    }

    /// Stützstelle der Skalierung: Rohwert `x` ergibt `punkte`.
    public struct Anker: Sendable, Equatable {
        public var x: Decimal
        public var punkte: Decimal

        public init(_ x: Decimal, _ punkte: Decimal) {
            self.x = x
            self.punkte = punkte
        }
    }

    /// Eine Achse des Netzdiagramms.
    public struct Komponentenwert: Sendable, Equatable {
        public var komponente: Komponente
        /// Rohwert vor der Skalierung; `nil`, wenn er nicht definiert ist (etwa Payoff ohne Verlierer).
        public var rohwert: Decimal?
        /// 0 bis 100.
        public var wert: Decimal
        /// Gewicht nach Normierung auf die vorhandenen Komponenten; zusammen 1.
        public var gewicht: Decimal

        /// `Komponente.rawValue`, für die Achsenbeschriftung in der App.
        public var schluessel: String { komponente.rawValue }
    }

    /// Unter dieser Zahl Trades gibt es keinen Score.
    public static let mindestanzahl = 20

    /// Gewichte vor der Normierung. Der Profitfaktor zählt am meisten, weil er Trefferquote und Payoff verbindet
    /// und allein über Gewinn oder Verlust entscheidet.
    public static let gewichte: [Komponente: Decimal] = [
        .trefferquote: 15, .payoff: 15, .profitfaktor: 25, .bestaendigkeit: 15, .drawdown: 15, .regeltreue: 15,
    ]

    /// Anker je Komponente, nach `x` aufsteigend.
    /// - Trefferquote 25 % → 0, 40 % → 50, 60 % → 100: unter einem Viertel Treffer ist eine Serie kaum
    ///   durchzuhalten, 60 % ist für diskretionäres Daytrading sehr hoch.
    /// - Payoff 0,5 → 0, 1 → 50, 2 → 100: Gewinner halb so groß wie Verlierer ist ein Warnsignal, doppelt so groß
    ///   gilt als Ziel (R5).
    /// - Profitfaktor 1 → 0, 1,5 → 50, 2,5 → 100: unter 1 verliert das System, ab 1,5 gilt es als solide.
    /// - Beständigkeit 30 % → 0, 50 % → 50, 70 % → 100 profitable Tage.
    /// - Drawdown 0 → 100, 0,25 → 60, 0,5 → 30, 1 → 0: Ein Rückgang so groß wie alle Gewinne ergibt 0.
    /// - Regeltreue 50 % → 0, 75 % → 50, 100 % → 100: unter der Hälfte regeltreu ist kein System erkennbar.
    public static let anker: [Komponente: [Anker]] = [
        .trefferquote: [Anker(ankerwert("0.25"), 0), Anker(ankerwert("0.4"), 50), Anker(ankerwert("0.6"), 100)],
        .payoff: [Anker(ankerwert("0.5"), 0), Anker(1, 50), Anker(2, 100)],
        .profitfaktor: [Anker(1, 0), Anker(ankerwert("1.5"), 50), Anker(ankerwert("2.5"), 100)],
        .bestaendigkeit: [Anker(ankerwert("0.3"), 0), Anker(ankerwert("0.5"), 50), Anker(ankerwert("0.7"), 100)],
        .drawdown: [Anker(0, 100), Anker(ankerwert("0.25"), 60), Anker(ankerwert("0.5"), 30), Anker(1, 0)],
        .regeltreue: [Anker(ankerwert("0.5"), 0), Anker(ankerwert("0.75"), 50), Anker(1, 100)],
    ]

    /// Gewichteter Mittelwert der Komponenten, 0 bis 100, ungerundet.
    public var gesamt: Decimal
    /// In der Reihenfolge von `Komponente.allCases`; ohne Regeltreue, wenn keine übergeben wurde.
    public var komponenten: [Komponentenwert]
    public var anzahl: Int

    public func wert(_ komponente: Komponente) -> Decimal? {
        komponenten.first { $0.komponente == komponente }?.wert
    }

    /// `nil` unter `mindestanzahl` Trades.
    /// - Parameters:
    ///   - zeitzone: Tagesgrenze für die Beständigkeit.
    ///   - regeltreue: Anteil regeltreuer Trades 0 bis 1; ohne Wert fällt die Komponente weg und die übrigen
    ///     Gewichte werden neu normiert.
    public init?(trades: [Trade], zeitzone: TimeZone, regeltreue: Decimal? = nil,
                 mindestanzahl: Int = Leistungsscore.mindestanzahl) {
        guard !trades.isEmpty, trades.count >= mindestanzahl else { return nil }
        let k = Kennzahlen(trades: trades)
        let verlauf = Kapitalverlauf(trades: trades)
        let summeGewinne: Decimal = trades.filter { $0.outcome == .win }.map(\.netProfit).reduce(0, +)

        var werte: [Komponentenwert] = []
        func neu(_ komponente: Komponente, _ rohwert: Decimal?, _ punkte: Decimal) {
            werte.append(Komponentenwert(komponente: komponente, rohwert: rohwert, wert: punkte, gewicht: 0))
        }
        let treffer = k.trefferquote ?? 0
        neu(.trefferquote, treffer, Self.skaliert(treffer, .trefferquote))
        // Ohne Verlierer sind Payoff und Profitfaktor unendlich: volle Punkte, wenn es Gewinner gibt; ohne
        // Gewinner keine Punkte.
        let ohneWert: Decimal = k.gewinner > 0 && k.verlierer == 0 ? 100 : 0
        let payoffPunkte = k.payoff.map { Self.skaliert($0, .payoff) } ?? ohneWert
        neu(.payoff, k.payoff, payoffPunkte)
        let faktorPunkte = k.profitfaktor.map { Self.skaliert($0, .profitfaktor) } ?? ohneWert
        neu(.profitfaktor, k.profitfaktor, faktorPunkte)
        let tage = Self.anteilProfitableTage(trades, zeitzone: zeitzone)
        neu(.bestaendigkeit, tage, Self.skaliert(tage, .bestaendigkeit))
        if summeGewinne > 0 {
            let verhaeltnis = verlauf.maxDrawdown / summeGewinne
            neu(.drawdown, verhaeltnis, Self.skaliert(verhaeltnis, .drawdown))
        } else {
            // Ohne Gewinne: ohne Rückgang volle Punkte, sonst keine.
            neu(.drawdown, nil, verlauf.maxDrawdown > 0 ? 0 : 100)
        }
        if let regeltreue {
            neu(.regeltreue, regeltreue, Self.skaliert(regeltreue, .regeltreue))
        }

        let summeGewichte: Decimal = werte.map { Self.gewichte[$0.komponente] ?? 0 }.reduce(0, +)
        var summe: Decimal = 0
        for i in werte.indices {
            let gewicht = Self.gewichte[werte[i].komponente] ?? 0
            summe += gewicht * werte[i].wert
            werte[i].gewicht = summeGewichte > 0 ? gewicht / summeGewichte : 0
        }
        gesamt = summeGewichte > 0 ? summe / summeGewichte : 0
        komponenten = werte
        anzahl = trades.count
    }

    /// Stückweise linear zwischen den Ankern der Komponente, außerhalb gekappt.
    public static func skaliert(_ x: Decimal, _ komponente: Komponente) -> Decimal {
        skaliert(x, anker: anker[komponente] ?? [])
    }

    static func skaliert(_ x: Decimal, anker: [Anker]) -> Decimal {
        guard let erster = anker.first, let letzter = anker.last else { return 0 }
        if x <= erster.x { return erster.punkte }
        if x >= letzter.x { return letzter.punkte }
        for i in anker.indices.dropLast() where x < anker[i + 1].x {
            let a = anker[i]
            let b = anker[i + 1]
            return a.punkte + (x - a.x) * (b.punkte - a.punkte) / (b.x - a.x)
        }
        return letzter.punkte
    }

    /// Anteil der Handelstage (Schlusstag in der Zeitzone) mit Netto > 0; 0 ohne Trades.
    static func anteilProfitableTage(_ trades: [Trade], zeitzone: TimeZone) -> Decimal {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        var jeTag: [Date: Decimal] = [:]
        for t in trades { jeTag[t.schlusstag(kalender), default: 0] += t.netProfit }
        guard !jeTag.isEmpty else { return 0 }
        let profitabel = jeTag.values.filter { $0 > 0 }.count
        return Decimal(profitabel) / Decimal(jeTag.count)
    }
}

private func ankerwert(_ text: String) -> Decimal { Decimal(string: text)! }
