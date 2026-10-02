import SwiftUI

extension String {
    /// Zeilenformat (fett, kursiv, Links, Code) aus Markdown; bei Fehlern der rohe Text.
    var markdownZeile: AttributedString {
        let optionen = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: self, options: optionen)) ?? AttributedString(self)
    }
}

/// Ein Block eines Kapitels in den Design-Token. Abschnittsüberschriften tragen den Anker „abschnitt-N“,
/// damit die Kapitelseite zu einem Baustein springen kann.
struct MarkdownBlockView: View {
    let block: Markdownblock
    @Environment(\.thema) private var thema

    var body: some View {
        switch block.art {
        case .ueberschrift(let ebene, let text, let nummer, let stufen):
            MarkdownUeberschrift(ebene: ebene, text: text, stufen: stufen)
                .id(nummer.map { "abschnitt-\($0)" } ?? "block-\(block.id)")
        case .absatz(let text):
            Text(text.markdownZeile)
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .liste(let punkte, let nummeriert):
            MarkdownListe(punkte: punkte, nummeriert: nummeriert)
        case .tabelle(let kopf, let zeilen):
            MarkdownTabelle(kopf: kopf, zeilen: zeilen)
        case .code(let text):
            MarkdownCode(text: text)
        }
    }
}

private struct MarkdownUeberschrift: View {
    let ebene: Int
    let text: String
    let stufen: [Lernstufe]
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
            Text(text.markdownZeile)
                .font(schrift)
                .foregroundStyle(thema.text)
            ForEach(stufen) { StufenMarke(stufe: $0) }
        }
        .padding(.top, ebene == 2 ? Abstand.kachelAbstand : Abstand.raster)
    }

    private var schrift: Font {
        switch ebene {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct MarkdownListe: View {
    let punkte: [String]
    let nummeriert: Bool
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            ForEach(Array(punkte.enumerated()), id: \.offset) { eintrag in
                HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
                    Text(verbatim: nummeriert ? "\(eintrag.offset + 1)." : "•")
                        .font(Schrift.fliesstext)
                        .monospacedDigit()
                        .foregroundStyle(thema.textSchwach)
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(eintrag.element.markdownZeile)
                        .font(Schrift.fliesstext)
                        .foregroundStyle(thema.text)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Tabelle mit gleich breiten Spalten und Haarlinien (Doc 10, Abschnitt 6): sicher auf allen Breiten,
/// die Kapitel halten ihre Tabellen deshalb bei höchstens vier kurzen Spalten.
private struct MarkdownTabelle: View {
    let kopf: [String]
    let zeilen: [[String]]
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reihe(kopf, kopfzeile: true)
            linie
            ForEach(Array(zeilen.enumerated()), id: \.offset) { eintrag in
                reihe(eintrag.element, kopfzeile: false)
                linie
            }
        }
    }

    private var linie: some View {
        Rectangle().fill(thema.linie).frame(height: 1)
    }

    private func reihe(_ zellen: [String], kopfzeile: Bool) -> some View {
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            ForEach(0..<kopf.count, id: \.self) { spalte in
                Text((spalte < zellen.count ? zellen[spalte] : "").markdownZeile)
                    .font(kopfzeile ? Schrift.beschriftung : .callout)
                    .monospacedDigit()
                    .foregroundStyle(kopfzeile ? thema.textSchwach : thema.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.vertical, Abstand.raster + 2)
    }
}

private struct MarkdownCode: View {
    let text: String
    @Environment(\.thema) private var thema

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(verbatim: text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(thema.text)
                .padding(Abstand.kachelInnen)
        }
        .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
    }
}

/// Kleine Kapsel mit dem Namen der Stufe, an Überschriften und im Selbsttest.
struct StufenMarke: View {
    let stufe: Lernstufe
    @Environment(\.thema) private var thema

    var body: some View {
        Text(stufe.titel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Abstand.raster * 1.5)
            .padding(.vertical, 2)
            .background(thema.flaeche2, in: Capsule())
            .foregroundStyle(thema.textSchwach)
    }
}
