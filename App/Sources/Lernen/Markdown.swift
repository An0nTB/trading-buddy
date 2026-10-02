import Foundation

/// Ein Block der Lerntexte. Die Kapitel sind einfaches Markdown: Überschriften mit Stufen-Marke
/// (`## 2. Positionsgröße berechnen [G]`), Absätze, Listen, Tabellen und Code-Blöcke.
/// Zeilenformat (fett, Links, Code) übernimmt `AttributedString(markdown:)` in der Ansicht.
struct Markdownblock: Identifiable, Hashable {
    enum Art: Hashable {
        /// `ebene` 1 ist der Kapiteltitel, 2 ein Abschnitt, 3 ein Unterabschnitt.
        /// `nummer` ist die führende Abschnittsnummer („2.“), `stufen` die Marke am Ende.
        case ueberschrift(ebene: Int, text: String, nummer: Int?, stufen: [Lernstufe])
        case absatz(String)
        case liste([String], nummeriert: Bool)
        case tabelle(kopf: [String], zeilen: [[String]])
        case code(String)
    }

    let id: Int
    let art: Art
}

/// Zerlegt Markdown-Text in Blöcke. Kein vollständiges CommonMark: nur, was die Kapitel brauchen.
enum MarkdownParser {
    static func bloecke(_ text: String) -> [Markdownblock] {
        let zeilen = text.components(separatedBy: "\n")
        var ergebnis: [Markdownblock.Art] = []
        var absatz: [String] = []
        var i = 0

        func absatzAbschliessen() {
            if !absatz.isEmpty {
                ergebnis.append(.absatz(absatz.joined(separator: " ")))
                absatz = []
            }
        }

        while i < zeilen.count {
            let zeile = zeilen[i]
            let getrimmt = zeile.trimmingCharacters(in: .whitespaces)

            if getrimmt.hasPrefix("```") {
                absatzAbschliessen()
                var code: [String] = []
                i += 1
                while i < zeilen.count, !zeilen[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(zeilen[i])
                    i += 1
                }
                ergebnis.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }

            if getrimmt.hasPrefix("#") {
                absatzAbschliessen()
                ergebnis.append(ueberschrift(getrimmt))
                i += 1
                continue
            }

            if getrimmt.hasPrefix("|") {
                absatzAbschliessen()
                var reihen: [[String]] = []
                while i < zeilen.count, zeilen[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let zellen = tabellenzeile(zeilen[i])
                    if !istTrennzeile(zellen) { reihen.append(zellen) }
                    i += 1
                }
                if let kopf = reihen.first {
                    ergebnis.append(.tabelle(kopf: kopf, zeilen: Array(reihen.dropFirst())))
                }
                continue
            }

            if let punkt = listenpunkt(getrimmt, nummeriert: false) {
                absatzAbschliessen()
                var punkte = [punkt]
                i += 1
                while i < zeilen.count, let weiterer = listenpunkt(zeilen[i].trimmingCharacters(in: .whitespaces), nummeriert: false) {
                    punkte.append(weiterer)
                    i += 1
                }
                ergebnis.append(.liste(punkte, nummeriert: false))
                continue
            }

            if let punkt = listenpunkt(getrimmt, nummeriert: true) {
                absatzAbschliessen()
                var punkte = [punkt]
                i += 1
                while i < zeilen.count, let weiterer = listenpunkt(zeilen[i].trimmingCharacters(in: .whitespaces), nummeriert: true) {
                    punkte.append(weiterer)
                    i += 1
                }
                ergebnis.append(.liste(punkte, nummeriert: true))
                continue
            }

            if getrimmt.isEmpty {
                absatzAbschliessen()
            } else {
                absatz.append(getrimmt)
            }
            i += 1
        }
        absatzAbschliessen()
        return ergebnis.enumerated().map { Markdownblock(id: $0.offset, art: $0.element) }
    }

    /// `## 2. Titel [G/F]` → Ebene 2, Nummer 2, Text „2. Titel“, Stufen Grundlagen und Fortgeschritten.
    static func ueberschrift(_ zeile: String) -> Markdownblock.Art {
        var ebene = 0
        var rest = Substring(zeile)
        while rest.first == "#" {
            ebene += 1
            rest = rest.dropFirst()
        }
        var text = rest.trimmingCharacters(in: .whitespaces)
        var stufen: [Lernstufe] = []
        if text.hasSuffix("]"), let klammer = text.lastIndex(of: "[") {
            let inhalt = text[text.index(after: klammer)..<text.index(before: text.endIndex)]
            let kuerzel = inhalt.split(separator: "/").map(String.init)
            let gefunden = kuerzel.compactMap(Lernstufe.init(kuerzel:))
            if !kuerzel.isEmpty, gefunden.count == kuerzel.count {
                stufen = gefunden
                text = text[..<klammer].trimmingCharacters(in: .whitespaces)
            }
        }
        var nummer: Int?
        if let punkt = text.firstIndex(of: "."), let zahl = Int(text[..<punkt]), zahl > 0 {
            nummer = zahl
        }
        return .ueberschrift(ebene: ebene, text: text, nummer: nummer, stufen: stufen)
    }

    /// `- Text` oder `1. Text`; nil, wenn die Zeile kein Listenpunkt ist.
    static func listenpunkt(_ zeile: String, nummeriert: Bool) -> String? {
        if nummeriert {
            guard let punkt = zeile.firstIndex(of: "."), Int(zeile[..<punkt]) != nil else { return nil }
            let rest = zeile[zeile.index(after: punkt)...]
            guard rest.first == " " else { return nil }
            return rest.trimmingCharacters(in: .whitespaces)
        }
        guard zeile.hasPrefix("- ") || zeile.hasPrefix("* ") else { return nil }
        return zeile.dropFirst(2).trimmingCharacters(in: .whitespaces)
    }

    /// `| a | b \| c |` → ["a", "b | c"]; ein maskiertes `\|` bleibt in der Zelle.
    static func tabellenzeile(_ zeile: String) -> [String] {
        var inhalt = Substring(zeile.trimmingCharacters(in: .whitespaces))
        if inhalt.hasPrefix("|") { inhalt = inhalt.dropFirst() }
        if inhalt.hasSuffix("|") { inhalt = inhalt.dropLast() }
        var zellen: [String] = []
        var aktuell = ""
        var maskiert = false
        for zeichen in inhalt {
            if maskiert {
                aktuell.append(zeichen == "|" ? "|" : "\\\(zeichen)")
                maskiert = false
            } else if zeichen == "\\" {
                maskiert = true
            } else if zeichen == "|" {
                zellen.append(aktuell.trimmingCharacters(in: .whitespaces))
                aktuell = ""
            } else {
                aktuell.append(zeichen)
            }
        }
        zellen.append(aktuell.trimmingCharacters(in: .whitespaces))
        return zellen
    }

    /// `|---|---|` unter dem Tabellenkopf.
    static func istTrennzeile(_ zellen: [String]) -> Bool {
        !zellen.isEmpty && zellen.allSatisfy { zelle in
            !zelle.isEmpty && zelle.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
}

/// Was die Kapitelseite zeigt: Blöcke der gewählten Stufe, ein Hinweis auf ausgeblendete Abschnitte,
/// der Selbsttest vor den Quellen.
enum Seitenblock: Identifiable, Hashable {
    case markdown(Markdownblock)
    /// Abschnitte, die erst in einer höheren Stufe erscheinen (Titel und niedrigste Stufe).
    case ausgeblendet([String], ab: Lernstufe)
    case selbsttest

    var id: String {
        switch self {
        case .markdown(let block): "b\(block.id)"
        case .ausgeblendet: "ausgeblendet"
        case .selbsttest: "selbsttest"
        }
    }

    /// Abschnitte mit Stufen-Marke erscheinen kumulativ: die niedrigste Marke muss zur gewählten Stufe passen.
    /// Abschnitte ohne Marke (Einleitung, Quellen) stehen immer. Der Hinweis auf Ausgeblendetes sitzt an der
    /// Stelle des ersten ausgeblendeten Abschnitts; der Selbsttest kommt vor „Quellen“, sonst ans Ende.
    static func seite(_ bloecke: [Markdownblock], stufe: Lernstufe, mitSelbsttest: Bool) -> [Seitenblock] {
        var ergebnis: [Seitenblock] = []
        var sichtbar = true
        var ausgeblendet: [String] = []
        var niedrigste: Lernstufe = .profi
        var hinweisGesetzt = false
        var selbsttestGesetzt = false

        for block in bloecke {
            if case .ueberschrift(let ebene, let text, _, let stufen) = block.art, ebene == 2 {
                if let minimum = stufen.min() {
                    sichtbar = minimum <= stufe
                    if !sichtbar {
                        ausgeblendet.append(text)
                        niedrigste = min(niedrigste, minimum)
                        if !hinweisGesetzt {
                            ergebnis.append(.ausgeblendet([], ab: .profi)) // Platzhalter, unten ersetzt
                            hinweisGesetzt = true
                        }
                    }
                } else {
                    sichtbar = true
                    if mitSelbsttest, !selbsttestGesetzt, text == "Quellen" {
                        ergebnis.append(.selbsttest)
                        selbsttestGesetzt = true
                    }
                }
            }
            if sichtbar { ergebnis.append(.markdown(block)) }
        }
        if mitSelbsttest, !selbsttestGesetzt { ergebnis.append(.selbsttest) }
        if hinweisGesetzt, let platz = ergebnis.firstIndex(of: .ausgeblendet([], ab: .profi)) {
            ergebnis[platz] = .ausgeblendet(ausgeblendet, ab: niedrigste)
        }
        return ergebnis
    }
}
