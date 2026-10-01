import SwiftUI

/// Design-Token: Farben nach Bedeutung, nie als Hex-Wert in den Ansichten (Doc 10, Abschnitt 3).
/// Die Hex-Werte in dieser Datei sind die einzige Stelle im App-Code;
/// `scripts/token_pruefen.py` vergleicht sie mit `Design/tokens.json`.
struct Thema: Equatable {
    var akzent: Color
    var gewinn: Color
    var verlust: Color
    /// Schrift auf Akzentflächen (Knöpfe).
    var textAufAkzent: Color
    var grund: Color
    var flaeche: Color
    var flaeche2: Color
    var linie: Color
    var text: Color
    var textSchwach: Color

    /// Akzent mit 18 % Deckkraft für gewählte Zeilen und Seitenleisten-Einträge.
    var akzentTint: Color { akzent.opacity(0.18) }

    /// Gewinn- oder Verlustfarbe nach Vorzeichen; null bleibt Textfarbe.
    func vorzeichen(_ wert: Decimal) -> Color {
        wert > 0 ? gewinn : (wert < 0 ? verlust : text)
    }
}

/// Die vier Farbwelten aus AP10, je in Hell und Dunkel. Kontrast geprüft mit `kontrast.py` (Doc 10).
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

    func thema(_ modus: ColorScheme) -> Thema {
        let dunkel = modus == .dark
        // Akzent, Gewinn, Verlust je Farbwelt: (dunkel, hell), Werte aus Design/tokens.json
        let farben: [(UInt32, UInt32)] = switch self {
        case .nordlicht: [(0x6fa8ff, 0x2560c4), (0x3dbf9a, 0x127255), (0xff7a59, 0xb83d16)]
        case .graphit: [(0xe0a458, 0x8f5a0e), (0x5cc48a, 0x176f3d), (0xf07070, 0xb03434)]
        case .lavendel: [(0xb39dff, 0x6c4fd1), (0x4fc3a1, 0x127257), (0xff8a80, 0xc62828)]
        case .terminal: [(0x4dd0e1, 0x0b6b78), (0x4cd964, 0x1a7a2e), (0xff5a5a, 0xc62828)]
        }
        func waehle(_ paar: (UInt32, UInt32)) -> Color { Color(hex: dunkel ? paar.0 : paar.1) }
        // Neutralfarben sind in allen Farbwelten gleich: kein reines Schwarz, kein reines Weiß als Grund.
        return Thema(
            akzent: waehle(farben[0]),
            gewinn: waehle(farben[1]),
            verlust: waehle(farben[2]),
            textAufAkzent: waehle((0x121316, 0xffffff)),
            grund: waehle((0x121316, 0xf2f2f4)),
            flaeche: waehle((0x1b1d21, 0xffffff)),
            flaeche2: waehle((0x24272c, 0xe9eaee)),
            linie: waehle((0x2c2f35, 0xd9dadf)),
            text: waehle((0xe8e9ec, 0x1b1d21)),
            textSchwach: waehle((0x9a9ea6, 0x5c606a))
        )
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
