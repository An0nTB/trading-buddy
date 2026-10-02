import SwiftUI

/// Maße und Schriften für das PDF. Papier hat keine Dynamic-Type-Stufen, deshalb feste Punktgrößen;
/// Farben kommen aus dem Thema (Doc 10), Abstände folgen dem 4-Punkt-Raster aus `Abstand`.
enum BerichtMass {
    /// A4 in Punkt (1 pt = 1/72 Zoll).
    static let seite = CGSize(width: 595.28, height: 841.89)
    static let randSeitlich: CGFloat = 40
    static let randOben: CGFloat = 36
    static var breite: CGFloat { seite.width - 2 * randSeitlich }
    static let abschnittAbstand: CGFloat = Abstand.raster * 4
    static let radius: CGFloat = 6
}

enum BerichtSchrift {
    static var titel: Font { Font.system(size: 20, weight: .bold) }
    static var abschnitt: Font { Font.system(size: 12, weight: .semibold) }
    static var text: Font { Font.system(size: 9.5) }
    static var klein: Font { Font.system(size: 8) }
    static var zahl: Font { Font.system(size: 14, weight: .semibold) }
    static var tabelle: Font { Font.system(size: 9).monospacedDigit() }
}

/// Überschrift eines Abschnitts mit feiner Linie darunter.
struct BerichtAbschnitt<Inhalt: View>: View {
    let titel: LocalizedStringKey
    var untertitel: String?
    @ViewBuilder var inhalt: () -> Inhalt
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titel)
                    .font(BerichtSchrift.abschnitt)
                    .foregroundStyle(thema.text)
                if let untertitel {
                    Text(verbatim: untertitel)
                        .font(BerichtSchrift.klein)
                        .foregroundStyle(thema.textSchwach)
                }
                Rectangle()
                    .fill(thema.linie)
                    .frame(height: 0.5)
            }
            inhalt()
        }
        .frame(width: BerichtMass.breite, alignment: .leading)
    }
}

/// Kennzahl-Kachel für Papier: Titel, Zahl, eine Zusatzzeile.
struct BerichtKachel: View {
    let titel: LocalizedStringKey
    let wert: String
    var zusatz: String?
    var farbe: Color?
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titel)
                .font(BerichtSchrift.klein)
                .foregroundStyle(thema.textSchwach)
            Text(verbatim: wert)
                .font(BerichtSchrift.zahl)
                .foregroundStyle(farbe ?? thema.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let zusatz {
                Text(verbatim: zusatz)
                    .font(BerichtSchrift.klein)
                    .monospacedDigit()
                    .foregroundStyle(thema.textSchwach)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .padding(Abstand.raster * 2)
        .background(thema.grund, in: RoundedRectangle(cornerRadius: BerichtMass.radius))
    }
}

/// Fließtext in schwacher Farbe für Hinweise und Erklärungen.
struct BerichtHinweis: View {
    let text: String
    @Environment(\.thema) private var thema

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(BerichtSchrift.klein)
            .foregroundStyle(thema.textSchwach)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Zeile aus Bezeichnung links und Wert rechts, Werte mit Tabellenziffern.
struct BerichtZeile: View {
    let titel: String
    let wert: String
    var farbe: Color?
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: titel)
                .font(BerichtSchrift.text)
                .foregroundStyle(thema.text)
                .lineLimit(2)
            Spacer(minLength: Abstand.raster * 2)
            Text(verbatim: wert)
                .font(BerichtSchrift.tabelle)
                .foregroundStyle(farbe ?? thema.text)
                .lineLimit(1)
        }
    }
}
