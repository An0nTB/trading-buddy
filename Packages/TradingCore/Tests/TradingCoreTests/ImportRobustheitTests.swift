import Foundation
import Testing
@testable import TradingCore

/// Dieselbe Datei in anderer Kodierung, mit anderen Zeilenenden oder neu gespeichert (Excel) liefert
/// dieselben Bewegungen. Grundlage sind die synthetischen Fixtures der Importer (03.10.2026).
private func fixture(_ pfad: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    let text = try String(contentsOf: url, encoding: .utf8)
    guard text.unicodeScalars.first == "\u{FEFF}" else { return text }
    return String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
}

private let berlin = TimeZone(identifier: "Europe/Berlin")!

enum RobustheitsLeser: Sendable {
    case tradeRepublic, scalable, kraken, binance, coinbase, bitpanda

    func erkennt(_ text: String) -> Bool {
        switch self {
        case .tradeRepublic: TradeRepublicCSV.erkennt(text)
        case .scalable: ScalableCSV.erkennt(text)
        case .kraken: KrakenCSV.erkennt(text)
        case .binance: BinanceCSV.erkennt(text)
        case .coinbase: CoinbaseCSV.erkennt(text)
        case .bitpanda: BitpandaCSV.erkennt(text)
        }
    }

    func lies(_ text: String) throws -> Kontobewegungen {
        switch self {
        case .tradeRepublic: try TradeRepublicCSV.lies(text)
        case .scalable: try ScalableCSV.lies(text, zeitzone: berlin)
        case .kraken: try KrakenCSV.lies(text)
        case .binance: try BinanceCSV.lies(text)
        case .coinbase: try CoinbaseCSV.lies(text)
        case .bitpanda: try BitpandaCSV.lies(text)
        }
    }
}

struct RobustheitsFall: CustomTestStringConvertible, Sendable {
    let pfad: String
    let leser: RobustheitsLeser
    var testDescription: String { pfad }
    init(_ pfad: String, _ leser: RobustheitsLeser) { self.pfad = pfad; self.leser = leser }
}

private let faelle: [RobustheitsFall] = [
    RobustheitsFall("R2/trade_republic_2026_komma.csv", .tradeRepublic),
    RobustheitsFall("R2/trade_republic_alt_semikolon.csv", .tradeRepublic),
    RobustheitsFall("Sonderfaelle/trade_republic_sonderfaelle.csv", .tradeRepublic),
    RobustheitsFall("R2/scalable_2026.csv", .scalable),
    RobustheitsFall("Sonderfaelle/scalable_englisch.csv", .scalable),
    RobustheitsFall("Krypto/Kraken/kraken_einfach.csv", .kraken),
    RobustheitsFall("Krypto/Kraken/kraken_sonderfaelle.csv", .kraken),
    RobustheitsFall("Krypto/Binance/binance_einfach.csv", .binance),
    RobustheitsFall("Krypto/Binance/binance_sonderfaelle.csv", .binance),
    RobustheitsFall("Krypto/Coinbase/coinbase_v1.csv", .coinbase),
    RobustheitsFall("Krypto/Coinbase/coinbase_v3.csv", .coinbase),
    RobustheitsFall("Krypto/Coinbase/coinbase_v4.csv", .coinbase),
    RobustheitsFall("Krypto/Bitpanda/bitpanda_alt.csv", .bitpanda),
    RobustheitsFall("Krypto/Bitpanda/bitpanda_neu.csv", .bitpanda),
]

private func zeilen(_ text: String) -> [Substring] {
    text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
}

private func utf16(_ text: String, kleinesEnde: Bool, mark: Bool) -> Data {
    var bytes: [UInt8] = mark ? (kleinesEnde ? [0xFF, 0xFE] : [0xFE, 0xFF]) : []
    for einheit in text.utf16 {
        let hoch = UInt8(einheit >> 8), tief = UInt8(einheit & 0xFF)
        bytes += kleinesEnde ? [tief, hoch] : [hoch, tief]
    }
    return Data(bytes)
}

/// Windows-1252, wenn jedes Zeichen darstellbar ist.
private func windows1252(_ text: String) -> Data? {
    let rueck = Dictionary(uniqueKeysWithValues: Importtext.sonderzeichen1252.map { ($0.value, $0.key) })
    var bytes: [UInt8] = []
    for s in text.unicodeScalars {
        if s.value < 0x80 || (0xA0...0xFF).contains(s.value) { bytes.append(UInt8(s.value)) }
        else if let b = rueck[s.value] { bytes.append(b) }
        else { return nil }
    }
    return Data(bytes)
}

@Test(arguments: faelle)
func gleicheBewegungenInJederKodierung(_ fall: RobustheitsFall) throws {
    let basis = try fixture(fall.pfad)
    let soll = try fall.leser.lies(basis)
    let lf = zeilen(basis).joined(separator: "\n")
    var varianten: [(String, Data)] = [
        ("UTF-8", Data(basis.utf8)),
        ("UTF-8 mit BOM", Data([0xEF, 0xBB, 0xBF]) + Data(basis.utf8)),
        ("CRLF", Data(zeilen(basis).joined(separator: "\r\n").utf8)),
        ("nur CR", Data(zeilen(basis).joined(separator: "\r").utf8)),
        ("Leerzeilen am Ende", Data((lf + "\n\n\n").utf8)),
        ("UTF-16 LE mit BOM", utf16(basis, kleinesEnde: true, mark: true)),
        ("UTF-16 LE ohne BOM", utf16(basis, kleinesEnde: true, mark: false)),
        ("UTF-16 BE mit BOM", utf16(basis, kleinesEnde: false, mark: true)),
    ]
    if let ansi = windows1252(basis) { varianten.append(("Windows-1252", ansi)) }
    for (name, daten) in varianten {
        let text = try #require(Importtext.lies(daten), "\(name)")
        #expect(fall.leser.erkennt(text), "\(name)")
        #expect(try fall.leser.lies(text) == soll, "\(name)")
    }
}

@Test func kodierungWirdErkannt() throws {
    #expect(Importtext.erkenne(Data("a,b\n1,2".utf8))?.kodierung == .utf8)
    #expect(Importtext.erkenne(Data([0x61, 0x80, 0x0A]))?.kodierung == .windows1252)
    #expect(Importtext.lies(Data([0x61, 0x80, 0xE4])) == "a€ä")
    #expect(Importtext.erkenne(utf16("Datum;Betrag\n2026-03-02;1,00", kleinesEnde: true, mark: false))?.kodierung
        == .utf16LE)
    #expect(Importtext.erkenne(utf16("Datum;Betrag\n2026-03-02;1,00", kleinesEnde: false, mark: false))?.kodierung
        == .utf16BE)
    // Binärdaten (ZIP-Kopf einer Excel-Datei) sind kein Text.
    #expect(Importtext.lies(Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00, 0x08, 0x00])) == nil)
    #expect(Importtext.lies(Data()) == "")
}

@Test func tabulatorUndLeerzeichenImKopf() throws {
    let tabelle = CSVTabelle(text: "\u{FEFF} date \ttime\t status \n2026-03-02\t10:00:00\tExecuted\n")
    #expect(tabelle.kopf == ["date", "time", "status"])
    #expect(tabelle.zeilen == [["2026-03-02", "10:00:00", "Executed"]])
    // Scalable mit Tabulatoren (Excel „Unicode-Text“) wird erkannt und gelesen.
    let basis = try fixture("R2/scalable_2026.csv")
    let mitTab = zeilen(basis).map { $0.replacingOccurrences(of: ";", with: "\t") }.joined(separator: "\n")
    #expect(ScalableCSV.erkennt(mitTab))
    #expect(try ScalableCSV.lies(mitTab, zeitzone: berlin) == ScalableCSV.lies(basis, zeitzone: berlin))
}

@Test func mt4InUtf16() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/MT4/gbe-2025-05-31-monthly.html")
    let html = try String(contentsOf: url, encoding: .utf8)
    let soll = try MT4Statement.parse(html: html, serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    for daten in [utf16(html, kleinesEnde: true, mark: true), Data(html.utf8)] {
        let text = try #require(Importtext.lies(daten))
        let ist = try MT4Statement.parse(html: text, serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
        #expect(ist == soll)
    }
}
