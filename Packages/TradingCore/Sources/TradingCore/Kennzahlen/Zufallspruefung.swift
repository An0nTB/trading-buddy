import Foundation

/// Zufallszahlen mit festem Startwert (SplitMix64), auf jeder Plattform gleich.
/// Gleicher Startwert, gleiche Folge: Ergebnisse und Tests bleiben reproduzierbar.
public struct Zufallsgenerator: RandomNumberGenerator, Sendable {
    private var zustand: UInt64

    public init(seed: UInt64) { zustand = seed }

    public mutating func next() -> UInt64 {
        zustand &+= 0x9E37_79B9_7F4A_7C15
        var z = zustand
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Gleichverteilte Zahl in `0..<n` ohne Modulo-Verzerrung (Ablehnung oberhalb der Grenze).
    /// Bewusst eigene Formel statt `Int.random(in:using:)`, damit sie nachrechenbar bleibt.
    public mutating func zahl(unter n: Int) -> Int {
        precondition(n > 0)
        let m = UInt64(n)
        let grenze = (UInt64.max / m) * m
        while true {
            let r = next()
            if r < grenze { return Int(r % m) }
        }
    }
}

/// Untere (5 %), mittlere (50 %) und obere (95 %) Stelle einer Verteilung.
public struct Bandbreite<Wert: Sendable & Equatable & Comparable>: Sendable, Equatable {
    public var unten: Wert
    public var mitte: Wert
    public var oben: Wert

    public init(unten: Wert, mitte: Wert, oben: Wert) {
        self.unten = unten
        self.mitte = mitte
        self.oben = oben
    }

    /// Stelle `(anzahl − 1) × p ÷ 100`, abgerundet, in den sortierten Werten.
    init(_ werte: [Wert]) {
        let sortiert = werte.sorted()
        let letzte = sortiert.count - 1
        unten = sortiert[letzte * 5 / 100]
        mitte = sortiert[letzte * 50 / 100]
        oben = sortiert[letzte * 95 / 100]
    }
}

/// Monte-Carlo-Bandbreite der eigenen Trades (R5, 07 Abschnitt 5): Die Netto-Ergebnisse werden
/// je Lauf so oft mit Zurücklegen gezogen, wie es Trades gibt. Zeigt, wie stark Endstand,
/// Drawdown und Verlustserien bei gleicher Trefferquote und gleichem Payoff vom Zufall abhängen.
/// Bandbreite der Vergangenheit, keine Prognose; setzt unabhängige Trades voraus.
public struct MonteCarlo: Sendable, Equatable {
    public var laeufe: Int
    public var endstand: Bandbreite<Decimal>
    /// Größter Rückgang vom bisherigen Hoch, positiv; Start bei 0.
    public var maxDrawdown: Bandbreite<Decimal>
    public var laengsteVerlustserie: Bandbreite<Int>

    /// `nil` ohne Trades oder ohne Läufe.
    public init?(trades: [Trade], laeufe: Int = 1000, seed: UInt64 = 1) {
        let werte = Zufallspruefung.nettoSortiert(trades)
        guard !werte.isEmpty, laeufe > 0 else { return nil }
        var generator = Zufallsgenerator(seed: seed)
        var endstaende: [Decimal] = []
        var drawdowns: [Decimal] = []
        var serien: [Int] = []
        for _ in 0..<laeufe {
            var stand: Decimal = 0
            var hoch: Decimal = 0
            var dd: Decimal = 0
            var serie = 0
            var laengste = 0
            for _ in werte.indices {
                let wert = werte[generator.zahl(unter: werte.count)]
                stand += wert
                if stand > hoch { hoch = stand }
                if hoch - stand > dd { dd = hoch - stand }
                serie = wert < 0 ? serie + 1 : 0
                laengste = max(laengste, serie)
            }
            endstaende.append(stand)
            drawdowns.append(dd)
            serien.append(laengste)
        }
        self.laeufe = laeufe
        endstand = Bandbreite(endstaende)
        maxDrawdown = Bandbreite(drawdowns)
        laengsteVerlustserie = Bandbreite(serien)
    }
}

public enum Zufallspruefung {
    /// Netto-Ergebnisse nach Schlusszeit und ID sortiert, damit die Eingabereihenfolge
    /// das Ergebnis nicht verändert (wie `Kapitalverlauf`).
    static func nettoSortiert(_ trades: [Trade]) -> [Decimal] {
        trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }.map(\.netProfit)
    }

    /// Effekt mal k × (n − k): n × Gruppensumme − k × Gesamtsumme.
    /// Gleiches Vorzeichen und gleiche Reihenfolge wie der Effekt, aber ohne Division und damit exakt.
    static func skalierterEffekt(gruppensumme: Decimal, k: Int, n: Int, gesamt: Decimal) -> Decimal {
        Decimal(n) * gruppensumme - Decimal(k) * gesamt
    }
}

extension Muster {
    /// Anteil zufällig gezogener Gruppen gleicher Größe (ohne Zurücklegen aus denselben Trades),
    /// deren Effekt dem Betrag nach mindestens so groß ist wie der dieses Musters.
    /// Klein (z. B. unter 0,05): Der Unterschied ist mit Zufall schwer zu erklären.
    /// Groß: Ein Zufallsgriff liefert oft Ähnliches. `nil`, wenn die Trades nicht passen.
    /// - Parameter trades: dieselben Trades, aus denen das Muster gefunden wurde.
    public func zufallsanteil(trades: [Trade], laeufe: Int = 1000, seed: UInt64 = 1) -> Decimal? {
        let werte = Zufallspruefung.nettoSortiert(trades)
        let n = werte.count
        let k = anzahl
        guard laeufe > 0, k > 0, k < n, n - k == anzahlRest else { return nil }
        let gesamt: Decimal = werte.reduce(0, +)
        let beobachtet = abs(Zufallspruefung.skalierterEffekt(
            gruppensumme: kennzahlen.netto, k: k, n: n, gesamt: gesamt))
        var generator = Zufallsgenerator(seed: seed)
        var treffer = 0
        for _ in 0..<laeufe {
            var indizes = Array(0..<n)
            var summe: Decimal = 0
            for i in 0..<k {
                let j = i + generator.zahl(unter: n - i)
                indizes.swapAt(i, j)
                summe += werte[indizes[i]]
            }
            let effekt = Zufallspruefung.skalierterEffekt(gruppensumme: summe, k: k, n: n, gesamt: gesamt)
            if abs(effekt) >= beobachtet { treffer += 1 }
        }
        return Decimal(treffer) / Decimal(laeufe)
    }
}
