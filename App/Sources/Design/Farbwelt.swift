import SwiftUI

/// Design-Token: Farben nach Bedeutung, nie als Hex-Wert in den Ansichten (Doc 10, Abschnitt 3).
/// Die Hex-Werte in dieser Datei sind die einzige Stelle im App-Code;
/// `scripts/token_pruefen.py` vergleicht sie mit `Design/tokens.json`, `scripts/kontrast_pruefen.py` rechnet den Kontrast.
struct Thema: Equatable {
    var akzent: Color
    var gewinn: Color
    var verlust: Color
    /// Warnstufe (Ampel „gelb“, Hinweise): Bernstein, in allen Farbwelten gleich (Doc 55 J6).
    var warnung: Color
    /// Schrift auf Akzentflächen (Knöpfe).
    var textAufAkzent: Color
    var grund: Color
    var flaeche: Color
    var flaeche2: Color
    var linie: Color
    var text: Color
    var textSchwach: Color
    /// Flächen in der Farbwelt getönt (Einstellung „Flächen tönen“, Entscheidung Tim 01.10.2026).
    var flaechenGetoent = false

    /// Akzent mit 18 % Deckkraft für gewählte Zeilen und Seitenleisten-Einträge.
    var akzentTint: Color { akzent.opacity(0.18) }
    /// Feiner Rand um Kacheln und Karten, nur bei getönten Flächen sichtbar.
    var kachelRand: Color { flaechenGetoent ? akzentTint : .clear }
    /// Titel einer Kennzahl-Kachel: im Akzent bei getönten Flächen, sonst schwache Textfarbe.
    var kachelTitel: Color { flaechenGetoent ? akzent : textSchwach }

    /// Gewinn- oder Verlustfarbe nach Vorzeichen; null bleibt Textfarbe.
    func vorzeichen(_ wert: Decimal) -> Color {
        wert > 0 ? gewinn : (wert < 0 ? verlust : text)
    }
}

/// Die vier Farbwelten aus AP10, je in Hell und Dunkel. Kontrast geprüft mit `scripts/kontrast_pruefen.py` (Doc 10, Doc 55).
enum Farbwelt: String, CaseIterable, Identifiable {
    case nordlicht, graphit, lavendel, terminal

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .nordlicht: "Nordlicht"
        case .graphit: "Graphit"
        case .lavendel: "Lavendel"
        case .terminal: "Terminal"
        }
    }

    /// `getoent`: Grund, Flächen und Linien in der Farbwelt getönt statt neutral (Schalter „Flächen tönen“).
    func thema(_ modus: ColorScheme, getoent: Bool = false) -> Thema {
        let dunkel = modus == .dark
        // Akzent, Gewinn, Verlust, Warnung je Farbwelt: (dunkel, hell), Werte aus Design/tokens.json
        let farben: [(UInt32, UInt32)] = switch self {
        case .nordlicht: [(0x6fa8ff, 0x2560c4), (0x3dbf9a, 0x127255), (0xff7a59, 0xb83d16), (0xf0a030, 0x8a5300)]
        case .graphit: [(0xe0a458, 0x8f5a0e), (0x5cc48a, 0x176f3d), (0xf07070, 0xb03434), (0xf0a030, 0x8a5300)]
        case .lavendel: [(0xb39dff, 0x6c4fd1), (0x4fc3a1, 0x127257), (0xff8a80, 0xc62828), (0xf0a030, 0x8a5300)]
        case .terminal: [(0x4dd0e1, 0x0b6b78), (0x4cd964, 0x16702a), (0xff5a5a, 0xc62828), (0xf0a030, 0x8a5300)]
        }
        func waehle(_ paar: (UInt32, UInt32)) -> Color { Color(hex: dunkel ? paar.0 : paar.1) }
        // Textfarben sind in allen Farbwelten gleich; Flächen neutral oder getönt (Flaechen).
        let flaechen = getoent ? Flaechen.getoent(self) : Flaechen.neutral
        return Thema(
            akzent: waehle(farben[0]),
            gewinn: waehle(farben[1]),
            verlust: waehle(farben[2]),
            warnung: waehle(farben[3]),
            textAufAkzent: waehle((0x121316, 0xffffff)),
            grund: waehle(flaechen.grund),
            flaeche: waehle(flaechen.flaeche),
            flaeche2: waehle(flaechen.flaeche2),
            linie: waehle(flaechen.linie),
            text: waehle((0xe8e9ec, 0x1b1d21)),
            textSchwach: waehle((0x9a9ea6, 0x5c606a)),
            flaechenGetoent: getoent
        )
    }
}

/// Flächenfarben als (dunkel, hell): neutral für alle Welten (kein reines Schwarz, kein reines Weiß als Grund)
/// oder je Farbwelt getönt (Entscheidung Tim 01.10.2026, Variante C „etwas stärker“).
/// Tönung Hell: Akzent zu 12 / 4 / 14 / 26 % in Weiß. Dunkel: Akzent × 0,3 zu 30 / 30 / 30 / 34 % in die Neutralfläche.
/// Kontrast gerechnet (WCAG, scripts/kontrast_pruefen.py): Text, schwacher Text, Akzent, Gewinn, Verlust und Warnung
/// auf allen Flächen und auf Kapselgrund (Farbe 18 % über Fläche) ≥ 4,5:1, neutral und getönt (Doc 55 J22/J23).
struct Flaechen {
    var grund: (UInt32, UInt32)
    var flaeche: (UInt32, UInt32)
    var flaeche2: (UInt32, UInt32)
    var linie: (UInt32, UInt32)

    static let neutral = Flaechen(grund: (0x121316, 0xf2f2f4), flaeche: (0x1b1d21, 0xffffff), flaeche2: (0x24272c, 0xe9eaee), linie: (0x2c2f35, 0xd9dadf))

    static func getoent(_ welt: Farbwelt) -> Flaechen {
        switch welt {
        case .nordlicht: Flaechen(grund: (0x171c26, 0xe5ecf8), flaeche: (0x1d232e, 0xf6f9fd), flaeche2: (0x232a36, 0xe0e9f7), linie: (0x28303d, 0xc6d6f0))
        case .graphit: Flaechen(grund: (0x211c17, 0xf2ebe2), flaeche: (0x27231f, 0xfbf8f5), flaeche2: (0x2d2a27, 0xefe8dd), linie: (0x34302c, 0xe2d4c0))
        case .lavendel: Flaechen(grund: (0x1d1b26, 0xedeaf9), flaeche: (0x23222e, 0xf9f8fd), flaeche2: (0x292936, 0xeae6f9), linie: (0x2f2f3d, 0xd9d1f3))
        case .terminal: Flaechen(grund: (0x142024, 0xe2edef), flaeche: (0x1a272b, 0xf5f9fa), flaeche2: (0x202e33, 0xddeaec), linie: (0x25343a, 0xc0d9dc))
        }
    }
}

/// Einstellung „Erscheinungsbild“: System, Hell oder Dunkel (Doc 10, E1).
enum Erscheinungsbild: String, CaseIterable, Identifiable {
    case system, hell, dunkel

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .hell: "Hell"
        case .dunkel: "Dunkel"
        }
    }

    var farbschema: ColorScheme? {
        switch self {
        case .system: nil
        case .hell: .light
        case .dunkel: .dark
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

extension EnvironmentValues {
    @Entry var thema: Thema = Farbwelt.nordlicht.thema(.dark)
}
