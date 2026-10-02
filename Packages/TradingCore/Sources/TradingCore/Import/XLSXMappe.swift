import Foundation
import ZIPFoundation

/// Fehler beim Öffnen einer Excel-Datei.
public enum XLSXFehler: Error, Equatable, Sendable {
    /// Kein ZIP-Archiv, also keine XLSX-Datei.
    case keineXLSX
    case fehlenderTeil(String)
    case fehlendesBlatt(String)
}

/// Excel-Arbeitsmappe (XLSX): ein ZIP-Archiv mit XML-Teilen. Gelesen werden nur die Zellwerte
/// als Text, so wie Excel sie speichert (Zahlen mit Punkt, Datumswerte als Seriennummer).
/// Formeln, Formate und Formatierung bleiben außen vor.
public struct XLSXMappe: Sendable {
    public struct Blatt: Sendable, Equatable {
        public var name: String
        /// Zeilen in Dateireihenfolge ab Zeile 1; Spalte A ist Index 0, leere Zellen sind "".
        public var zeilen: [[String]]
    }

    public var blaetter: [Blatt]

    public init(daten: Data) throws {
        let archiv: Archive
        do { archiv = try Archive(data: daten, accessMode: .read) } catch { throw XLSXFehler.keineXLSX }
        func teil(_ pfad: String) throws -> Data? {
            guard let eintrag = archiv[pfad] else { return nil }
            var inhalt = Data()
            _ = try archiv.extract(eintrag) { inhalt.append($0) }
            return inhalt
        }
        guard let mappe = try teil("xl/workbook.xml") else { throw XLSXFehler.fehlenderTeil("xl/workbook.xml") }
        let beziehungen = try teil("xl/_rels/workbook.xml.rels").map(Self.beziehungen) ?? [:]
        let texte = try teil("xl/sharedStrings.xml").map(Self.gemeinsameTexte) ?? []
        var blaetter: [Blatt] = []
        for (name, id) in Self.blattliste(mappe) {
            guard let ziel = beziehungen[id] else { throw XLSXFehler.fehlenderTeil(name) }
            let pfad = ziel.hasPrefix("/") ? String(ziel.dropFirst()) : "xl/" + ziel
            guard let xml = try teil(pfad) else { throw XLSXFehler.fehlenderTeil(pfad) }
            blaetter.append(Blatt(name: name, zeilen: Self.zeilen(xml, texte: texte)))
        }
        self.blaetter = blaetter
    }

    /// Erstes Blatt, dessen Name alle Wörter enthält (ohne Groß- und Kleinschreibung).
    public func blatt(mit woerter: [String]) throws -> Blatt {
        guard let blatt = blaetter.first(where: { b in woerter.allSatisfy { b.name.lowercased().contains($0) } })
        else { throw XLSXFehler.fehlendesBlatt(woerter.joined(separator: " ")) }
        return blatt
    }

    static func blattliste(_ xml: Data) -> [(String, String)] {
        var liste: [(String, String)] = []
        for case let .start("sheet", attribute) in XMLLeser.ereignisse(xml) {
            if let name = attribute["name"], let id = attribute["id"] { liste.append((name, id)) }
        }
        return liste
    }

    static func beziehungen(_ xml: Data) -> [String: String] {
        var ziele: [String: String] = [:]
        for case let .start("Relationship", attribute) in XMLLeser.ereignisse(xml) {
            if let id = attribute["Id"], let ziel = attribute["Target"] { ziele[id] = ziel }
        }
        return ziele
    }

    /// Texte aus `sharedStrings.xml`; Zellen mit `t="s"` verweisen über den Index darauf.
    static func gemeinsameTexte(_ xml: Data) -> [String] {
        var texte: [String] = []
        var aktuell = "", inText = false, inLautschrift = false
        for ereignis in XMLLeser.ereignisse(xml) {
            switch ereignis {
            case .start("si", _): aktuell = ""
            case .start("rPh", _): inLautschrift = true
            case .ende("rPh"): inLautschrift = false
            case .start("t", _): inText = !inLautschrift
            case .ende("t"): inText = false
            case .text(let text) where inText: aktuell += text
            case .ende("si"): texte.append(aktuell)
            default: break
            }
        }
        return texte
    }

    static func zeilen(_ xml: Data, texte: [String]) -> [[String]] {
        var zeilen: [[String]] = []
        var zeile: [String] = []
        var spalte = 0, typ = "", wert = "", inWert = false
        for ereignis in XMLLeser.ereignisse(xml) {
            switch ereignis {
            case .start("row", let attribute):
                // Excel lässt leere Zeilen aus; die Nummer hält Abstände zwischen Zeilen fest.
                // Nummern außerhalb des Excel-Bereichs stammen aus einer kaputten Datei und zählen nicht.
                let nummer = attribute["r"].flatMap { Int($0) }.flatMap { (1...Self.hoechsteZeile).contains($0) ? $0 : nil }
                    ?? zeilen.count + 1
                while zeilen.count < nummer - 1 { zeilen.append([]) }
                zeile = []
            case .start("c", let attribute):
                typ = attribute["t"] ?? "n"
                wert = ""
                spalte = attribute["r"].flatMap(spaltenIndex) ?? zeile.count
            case .start("v", _), .start("t", _):
                inWert = true
            case .ende("v"), .ende("t"):
                inWert = false
            case .text(let text) where inWert:
                wert += text
            case .ende("c"):
                let text = typ == "s" ? Int(wert).flatMap { texte.indices.contains($0) ? texte[$0] : nil } ?? "" : wert
                while zeile.count <= spalte { zeile.append("") }
                zeile[spalte] = text
            case .ende("row"):
                zeilen.append(zeile)
            default:
                break
            }
        }
        return zeilen
    }

    /// Grenzen von Excel: Zeile 1 048 576, Spalte XFD.
    static let hoechsteZeile = 1_048_576
    static let spaltenzahl = 16_384

    /// „B5“ → 1, „AA7“ → 26. Nur A bis Z, höchstens drei Buchstaben und bis Spalte XFD; sonst `nil`.
    static func spaltenIndex(_ zelle: String) -> Int? {
        let buchstaben = zelle.prefix { $0.isLetter }.uppercased()
        guard (1...3).contains(buchstaben.count),
              buchstaben.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        let index = buchstaben.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
        return index < spaltenzahl ? index : nil
    }
}
