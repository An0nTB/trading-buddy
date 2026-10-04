import Foundation
import Testing
@testable import TradingCore

/// Beta-Tester liefern abgeschnittene, von Hand bearbeitete oder falsche Dateien. Jeder Importer muss dann
/// mit einem eigenen Fehler antworten oder ein Teilergebnis liefern, nie abstürzen (03.10.2026).
/// Die Veränderungen sind fest gesät, damit ein Fehlschlag in CI nachstellbar ist.
private func fixture(_ pfad: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    return try String(contentsOf: url, encoding: .utf8)
}

private func fixtureDaten(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    return try Data(contentsOf: url)
}

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private let plus3 = TimeZone(secondsFromGMT: 3 * 3_600)!

/// Einfacher, fest gesäter Zufallsgenerator (LCG), gleich auf Linux und macOS.
struct Saat: RandomNumberGenerator {
    var zustand: UInt64
    mutating func next() -> UInt64 {
        zustand = zustand &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return zustand
    }
}

enum KaputtLeser: String, Sendable, CaseIterable {
    case tradeRepublic, scalable, kraken, binance, coinbase, bitpanda, ibkr, mt5, mt4, mt4Verlauf

    /// Liest den Text; `erkennt` läuft immer mit, weil die App ihn vor jedem Import aufruft.
    func lies(_ text: String) throws {
        switch self {
        case .tradeRepublic: _ = TradeRepublicCSV.erkennt(text); _ = try TradeRepublicCSV.lies(text)
        case .scalable: _ = ScalableCSV.erkennt(text); _ = try ScalableCSV.lies(text, zeitzone: berlin)
        case .kraken: _ = KrakenCSV.erkennt(text); _ = try KrakenCSV.lies(text)
        case .binance: _ = BinanceCSV.erkennt(text); _ = try BinanceCSV.lies(text)
        case .coinbase: _ = CoinbaseCSV.erkennt(text); _ = try CoinbaseCSV.lies(text)
        case .bitpanda: _ = BitpandaCSV.erkennt(text); _ = try BitpandaCSV.lies(text)
        case .ibkr: _ = IBKRCSV.erkennt(text); _ = try IBKRCSV.lies(text)
        case .mt5: _ = MT5Bericht.erkennt(text); _ = try MT5Bericht.lies(text, serverZeitzone: plus3)
        case .mt4: _ = try MT4Statement.parse(html: text, serverZeitzone: plus3)
        case .mt4Verlauf: _ = try MT4Verlauf.parse(text: text, serverZeitzone: plus3)
        }
    }

    func vorlagen() throws -> [String] {
        switch self {
        case .tradeRepublic:
            return try ["R2/trade_republic_2026_komma.csv", "R2/trade_republic_alt_semikolon.csv",
                        "Sonderfaelle/trade_republic_sonderfaelle.csv"].map(fixture)
        case .scalable: return try ["R2/scalable_2026.csv", "Sonderfaelle/scalable_englisch.csv"].map(fixture)
        case .kraken: return try ["Krypto/Kraken/kraken_sonderfaelle.csv"].map(fixture)
        case .binance: return try ["Krypto/Binance/binance_sonderfaelle.csv"].map(fixture)
        case .coinbase: return try ["Krypto/Coinbase/coinbase_v1.csv", "Krypto/Coinbase/coinbase_v4.csv"].map(fixture)
        case .bitpanda: return try ["Krypto/Bitpanda/bitpanda_alt.csv", "Krypto/Bitpanda/bitpanda_neu.csv"].map(fixture)
        case .ibkr: return [ibkrCSV]
        case .mt5: return [mt5HTML]
        case .mt4: return try ["MT4/beispiel-2026-05-17-daily.html"].map(fixture)
        case .mt4Verlauf:
            return ["2026.05.06,10:42,197.840,197.866,197.812,197.829,28\n2026.05.06,10:41,197.851,197.873,197.836,197.840,41\n",
                    "<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\t<TICKVOL>\t<VOL>\t<SPREAD>\n"
                        + "2025.05.05\t12:00:00\t1.15\t1.3\t1.1\t1.2\t12\t0\t5\n"
                        + "2025.05.05\t11:00:00\t1.1\t1.2\t1.0\t1.15\t10\t0\t5\n"]
        }
    }
}

/// Typen, die die App als verständliche Meldung kennt. Alles andere wäre ein durchgereichter Systemfehler.
private func bekannterFehler(_ fehler: Error) -> Bool {
    fehler is CSVImportFehler || fehler is MT4ImportFehler || fehler is XLSXFehler
}

private let seltsameWerte = ["", "x", "-", "--1", "99999999999999999999999999", "1e400", "NaN", "0,0,0", "1.2.3",
                             "\u{2212}5", "\"", "2026-13-45", "31.02.2026", "25:61:99", "  ", "€", "1/0"]

/// Veränderte Fassungen eines Textes: abgeschnitten, Zeile fehlt, Zahl ersetzt, Anführungszeichen offen,
/// nur Kopf, doppelte Zeilen, Zeilen vertauscht.
func kaputteFassungen(_ text: String, saat: UInt64) -> [String] {
    var zufall = Saat(zustand: saat)
    let zeichen = Array(text)
    var ergebnis: [String] = ["", " ", "\n", "\n\n\n", "\u{FEFF}"]
    for k in 1...20 { ergebnis.append(String(zeichen.prefix(zeichen.count * k / 21))) }

    let zeilen = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    ergebnis.append(zeilen.first ?? "")
    let schritt = max(1, zeilen.count / 40)
    for i in stride(from: 0, to: zeilen.count, by: schritt) {
        var ohne = zeilen
        ohne.remove(at: i)
        ergebnis.append(ohne.joined(separator: "\n"))
    }
    if zeilen.count > 2 {
        ergebnis.append((zeilen + zeilen.dropFirst()).joined(separator: "\n"))
        ergebnis.append(([zeilen[0]] + zeilen.dropFirst().reversed()).joined(separator: "\n"))
    }

    let ns = NSString(string: text)
    let zahlen = (try? NSRegularExpression(pattern: "[0-9]+([.,][0-9]+)?"))?
        .matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
    if !zahlen.isEmpty {
        for _ in 0..<40 {
            let treffer = zahlen[Int(zufall.next() % UInt64(zahlen.count))]
            let wert = seltsameWerte[Int(zufall.next() % UInt64(seltsameWerte.count))]
            ergebnis.append(ns.replacingCharacters(in: treffer.range, with: wert))
        }
    }
    for _ in 0..<10 where !zeichen.isEmpty {
        var neu = zeichen
        neu.insert("\"", at: Int(zufall.next() % UInt64(neu.count)))
        ergebnis.append(String(neu))
    }
    let alphabet = Array("abc019;,.\t\"\n-:/ ÄÖÜ€<>")
    ergebnis.append(String((0..<2_000).map { _ in alphabet[Int(zufall.next() % UInt64(alphabet.count))] }))
    return ergebnis
}

@Test(arguments: KaputtLeser.allCases)
func kaputteDateienStuerzenNichtAb(_ leser: KaputtLeser) throws {
    var fremdeFehler: Set<String> = []
    for (nummer, vorlage) in try leser.vorlagen().enumerated() {
        for fassung in kaputteFassungen(vorlage, saat: UInt64(nummer + 1) * 7_919) {
            do { try leser.lies(fassung) } catch let fehler where !bekannterFehler(fehler) {
                fremdeFehler.insert(String(describing: type(of: fehler)) + ": \(fehler)")
            } catch {}
            _ = AnonymeProbe.erstelle(fassung, hoechstensZeilen: 50)
        }
    }
    #expect(fremdeFehler.isEmpty, "\(leser.rawValue): \(fremdeFehler.sorted().prefix(5))")
}

@Test func kaputteXTBMappeStuerztNichtAb() throws {
    var fremdeFehler: Set<String> = []
    for name in ["XTB/xtb_einfach.xlsx", "XTB/xtb_sonderfaelle.xlsx"] {
        let daten = [UInt8](try fixtureDaten(name))
        var zufall = Saat(zustand: UInt64(daten.count))
        var fassungen: [[UInt8]] = [[], [0x50, 0x4B, 0x03, 0x04]]
        for k in 1...20 { fassungen.append(Array(daten.prefix(daten.count * k / 21))) }
        for _ in 0..<30 {
            var neu = daten
            for _ in 0..<4 { neu[Int(zufall.next() % UInt64(neu.count))] = UInt8(truncatingIfNeeded: zufall.next()) }
            fassungen.append(neu)
        }
        for fassung in fassungen {
            let daten = Data(fassung)
            _ = XTBAuszug.erkennt(daten)
            _ = Importtext.lies(daten)
            do { _ = try XTBAuszug.lies(daten, zeitzone: berlin) } catch let fehler where !bekannterFehler(fehler) {
                fremdeFehler.insert(String(describing: type(of: fehler)) + ": \(fehler)")
            } catch {}
        }
    }
    #expect(fremdeFehler.isEmpty, "\(fremdeFehler.sorted().prefix(5))")
}

@Test func zufaelligeBytesSindKeinText() {
    var zufall = Saat(zustand: 42)
    for laenge in [1, 2, 3, 19, 20, 21, 199, 200, 201, 4_096] {
        let daten = Data((0..<laenge).map { _ in UInt8(truncatingIfNeeded: zufall.next()) })
        if let text = Importtext.lies(daten) {
            _ = CSVTabelle(text: text)
            _ = AnonymeProbe.erstelle(text)
        }
    }
}
