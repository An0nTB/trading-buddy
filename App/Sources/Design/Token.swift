import SwiftUI

/// Abstände und Radien aus `Design/tokens.json` (Abschnitt „abstaende“), in Punkt.
enum Abstand {
    static let raster: CGFloat = 4
    static let kachelInnen: CGFloat = 14
    static let kachelAbstand: CGFloat = 12
    static let radiusKnopf: CGFloat = 6
    static let radiusChip: CGFloat = 10
    static let seitenleiste: CGFloat = 220
    static let inspektor: CGFloat = 320
    static let kopfzeile: CGFloat = 52

    #if os(macOS)
    static let seitenrand: CGFloat = 20
    static let radiusKachel: CGFloat = 10
    #else
    static let seitenrand: CGFloat = 16
    static let radiusKachel: CGFloat = 14
    #endif
}

/// Schriftstufen (Doc 10, Abschnitt 5) als System-Textstile, damit Dynamic Type greift.
/// Die Punktgrößen weichen deshalb um ein bis zwei Punkt von der Tabelle in Doc 10 ab.
enum Schrift {
    static var grosserTitel: Font { .largeTitle.weight(.bold) }
    static var titel: Font { .title2.weight(.semibold) }
    static var fliesstext: Font { .body }
    static var beschriftung: Font { .caption }
    /// Große Einzelzahl in Kacheln: proportionale Ziffern (Tabellenziffern wirken dort löchrig).
    static var zahlGross: Font { .title.weight(.semibold) }
    /// Zahlen in Spalten und Summenzeilen: Tabellenziffern, damit Kommas untereinander stehen.
    static var tabelle: Font { .body.monospacedDigit() }
}

/// Diagrammwerte (Doc 10, Abschnitt 6), in Punkt.
enum Diagramm {
    static let balkenMax: CGFloat = 24
    static let balkenEndeRadius: CGFloat = 4
    static let linie: CGFloat = 2
    static let marker: CGFloat = 8
}

/// Raster für Kennzahl-Kacheln: am Mac vier nebeneinander, am iPhone zwei.
enum Raster {
    static var kacheln: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 360), spacing: Abstand.kachelAbstand)]
    }
}
