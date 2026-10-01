import Foundation

/// Kleiner XML-Leser für die festen Strukturen in Excel-Dateien: Elemente, Attribute, Text.
/// Kein vollständiger XML-Parser (keine DTD, kein CDATA), dafür ohne Abhängigkeit und auf
/// Apple-Systemen wie Linux gleich. Namensraum-Präfixe fallen weg (`r:id` wird `id`).
enum XMLLeser {
    enum Ereignis: Equatable {
        case start(name: String, attribute: [String: String])
        case ende(name: String)
        case text(String)
    }

    static func ereignisse(_ daten: Data) -> [Ereignis] {
        let b = [UInt8](daten)
        let auf = UInt8(ascii: "<"), zu = UInt8(ascii: ">"), schraeg = UInt8(ascii: "/")
        var ergebnis: [Ereignis] = []
        var i = 0
        while i < b.count {
            guard b[i] == auf else {
                let ende = b[i...].firstIndex(of: auf) ?? b.count
                ergebnis.append(.text(entschluesselt(String(decoding: b[i..<ende], as: UTF8.self))))
                i = ende
                continue
            }
            guard let ende = b[i...].firstIndex(of: zu) else { break }
            let inhalt = b[(i + 1)..<ende]
            i = ende + 1
            guard let erstes = inhalt.first, erstes != UInt8(ascii: "?"), erstes != UInt8(ascii: "!") else { continue }
            if erstes == schraeg {
                let name = String(decoding: inhalt.dropFirst(), as: UTF8.self).trimmingCharacters(in: .whitespaces)
                ergebnis.append(.ende(name: lokal(name)))
                continue
            }
            let leer = inhalt.last == schraeg
            let (name, attribute) = zerlegeTag(String(decoding: leer ? inhalt.dropLast() : inhalt, as: UTF8.self))
            ergebnis.append(.start(name: name, attribute: attribute))
            if leer { ergebnis.append(.ende(name: name)) }
        }
        return ergebnis
    }

    /// Name ohne Namensraum-Präfix.
    static func lokal(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    static func zerlegeTag(_ text: String) -> (String, [String: String]) {
        let teile = text.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        let name = lokal(teile.first.map(String.init) ?? "")
        var attribute: [String: String] = [:]
        var rest: Substring = teile.count > 1 ? teile[1] : ""
        while let gleich = rest.firstIndex(of: "=") {
            let schluessel = rest[..<gleich].trimmingCharacters(in: .whitespacesAndNewlines)
            let nachGleich = rest[rest.index(after: gleich)...].drop(while: { $0.isWhitespace })
            guard let zeichen = nachGleich.first, zeichen == "\"" || zeichen == "'" else { break }
            let wert = nachGleich.dropFirst()
            guard let schluss = wert.firstIndex(of: zeichen) else { break }
            attribute[lokal(schluessel)] = entschluesselt(String(wert[..<schluss]))
            rest = wert[wert.index(after: schluss)...]
        }
        return (name, attribute)
    }

    /// Löst die fünf XML-Entities und Zeichenreferenzen (`&#228;`, `&#xE4;`) auf.
    static func entschluesselt(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var ergebnis = ""
        var rest = Substring(text)
        while let und = rest.firstIndex(of: "&"), let semikolon = rest[und...].firstIndex(of: ";") {
            ergebnis += rest[..<und]
            let name = String(rest[rest.index(after: und)..<semikolon])
            switch name {
            case "lt": ergebnis += "<"
            case "gt": ergebnis += ">"
            case "amp": ergebnis += "&"
            case "quot": ergebnis += "\""
            case "apos": ergebnis += "'"
            default:
                let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
                let zahl = hex ? UInt32(name.dropFirst(2), radix: 16) : (name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil)
                if let zahl, let zeichen = Unicode.Scalar(zahl) {
                    ergebnis.unicodeScalars.append(zeichen)
                } else {
                    ergebnis += rest[und...semikolon]
                }
            }
            rest = rest[rest.index(after: semikolon)...]
        }
        return ergebnis + String(rest)
    }
}
