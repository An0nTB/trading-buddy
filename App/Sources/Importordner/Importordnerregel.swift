import Foundation
import TradingCore
import TradingStore

/// Entscheidet für eine Datei aus dem Import-Ordner (Frage 6, Tim 02.10.2026, Doc 45), ob die App sie still
/// importiert oder nachfragt. Still nur, wenn nichts zu wählen bleibt: Format erkannt, genau ein passendes Konto,
/// Zeitzone aus dem letzten Import dieses Kontos. Ein neues Konto legt der Nutzer einmal im Import-Blatt an;
/// mögliche Doppelte fängt die Speicherung ab (gleiche Datei, bekannte Tickets und Vorgänge).
/// Die Erkennung folgt derselben Reihenfolge wie `ImportBlatt.lies()`.
enum Importordnerregel {
    enum Entscheidung: Equatable {
        /// MetaTrader 4: Konto steht in der Datei; Serverzeit wie beim letzten Auszug dieses Kontos.
        case mt4(Konto, serverZeitzone: TimeZone)
        /// CSV ohne Kontonummer: das einzige Konto dieses Brokers, und die Datei überschneidet sich mit ihm.
        case csv(CSVBroker, Konto)
        /// XTB-Kontohistorie mit Kontonummer im Kopf; Zeitzone wie beim letzten Import dieses Kontos.
        case xtb(Konto, zeitzone: TimeZone)
        /// Die App fragt nach; `grund` steht in der Liste auf der Import-Seite.
        case rueckfrage(String)
    }

    /// `zeitzone(konto)` liefert die Zeitzone des letzten Imports dieses Kontos (`Importlauf.serverZeitzone`),
    /// `vorgaenge(konto)` die schon gespeicherten Vorgangskennungen (Ausführungen, Geldbewegungen,
    /// Kapitalmaßnahmen) dieses Kontos.
    static func entscheide(daten: Data, dateiname: String, konten: [Konto],
                           zeitzone: (Konto) -> TimeZone?,
                           vorgaenge: (Konto) -> Set<String> = { _ in [] }) -> Entscheidung {
        if XTBAuszug.erkennt(daten) {
            return xtb(daten, konten: konten, zeitzone: zeitzone)
        }
        if dateiname.lowercased().hasSuffix(".xlsx") {
            return .rueckfrage(String(localized: "Excel-Datei, aber keine XTB-Kontohistorie."))
        }
        guard let text = String(data: daten, encoding: .utf8) else {
            return .rueckfrage(String(localized: "Format nicht erkannt: weder Text noch Excel."))
        }
        if let broker = csvBroker(text) {
            return csv(broker, text: text, konten: konten, vorgaenge: vorgaenge)
        }
        if BinanceCSV.istTransaktionsverlauf(text) {
            return .rueckfrage(String(localized: "Binance-Transaktionsverlauf: Den liest die App nicht, bitte die Trade History exportieren."))
        }
        // MT4: Zeitzone hier nur zum Lesen von Broker und Konto, der Import nimmt die des Kontos.
        guard let auszug = try? MT4Statement.parse(html: text, serverZeitzone: .gmt) else {
            return .rueckfrage(String(localized: "Format nicht erkannt."))
        }
        guard let konto = konten.first(where: { $0.broker == auszug.broker && $0.kontonummer == auszug.accountNumber })
        else {
            return .rueckfrage(String(localized: "Neues Konto bei \(auszug.broker): bitte einmal von Hand importieren."))
        }
        guard let zone = zeitzone(konto) else {
            return .rueckfrage(String(localized: "Serverzeit des Kontos unbekannt: bitte im Blatt wählen."))
        }
        return .mt4(konto, serverZeitzone: zone)
    }

    /// CSV-Köpfe in der Reihenfolge von `Journal.importiereCSV`.
    static func csvBroker(_ text: String) -> CSVBroker? {
        if TradeRepublicCSV.erkennt(text) { return .tradeRepublic }
        if ScalableCSV.erkennt(text) { return .scalable }
        if KrakenCSV.erkennt(text) { return .kraken }
        if BinanceCSV.erkennt(text) { return .binance }
        if CoinbaseCSV.erkennt(text) { return .coinbase }
        if BitpandaCSV.erkennt(text) { return .bitpanda }
        return nil
    }

    /// Still nur, wenn die Datei mindestens einen Vorgang enthält, den das einzige Konto des Brokers schon kennt
    /// (Tim 02.10.2026, G21 Option 2): Folgeexporte überschneiden sich mit dem letzten, ein fremdes Depot nicht.
    private static func csv(_ broker: CSVBroker, text: String, konten: [Konto],
                            vorgaenge: (Konto) -> Set<String>) -> Entscheidung {
        let passend = konten.filter { $0.broker == broker.name }
        switch passend.count {
        case 0:
            return .rueckfrage(String(localized: "Noch kein Konto bei \(broker.name): bitte einmal von Hand importieren."))
        case 1:
            guard let bewegungen = try? lies(broker, text) else {
                return .rueckfrage(String(localized: "Import abgebrochen: bitte im Blatt prüfen."))
            }
            let kennungen = bewegungen.ausfuehrungen.map(\.id) + bewegungen.geldbewegungen.map(\.id)
                + bewegungen.kapitalmassnahmen.map(\.id)
            guard !vorgaenge(passend[0]).isDisjoint(with: kennungen) else {
                return .rueckfrage(String(localized: "Keine Überschneidung mit dem Konto bei \(broker.name): anderes Depot? Bitte im Blatt zuordnen."))
            }
            return .csv(broker, passend[0])
        default:
            return .rueckfrage(String(localized: "Mehrere Konten bei \(broker.name): bitte das Konto wählen."))
        }
    }

    /// Liest die CSV mit dem Importer des Brokers, wie das Import-Blatt.
    private static func lies(_ broker: CSVBroker, _ text: String) throws -> Kontobewegungen {
        switch broker {
        case .tradeRepublic: return try TradeRepublicCSV.lies(text)
        case .scalable: return try ScalableCSV.lies(text, zeitzone: broker.zeitzone)
        case .kraken: return try KrakenCSV.lies(text)
        case .binance: return try BinanceCSV.lies(text)
        case .coinbase: return try CoinbaseCSV.lies(text)
        case .bitpanda: return try BitpandaCSV.lies(text)
        }
    }

    private static func xtb(_ daten: Data, konten: [Konto], zeitzone: (Konto) -> TimeZone?) -> Entscheidung {
        // Zeitzone hier nur zum Lesen des Kopfs; der Import nimmt die des Kontos.
        guard let auszug = try? XTBAuszug.lies(daten, zeitzone: .gmt) else {
            return .rueckfrage(String(localized: "XTB-Kontohistorie nicht lesbar."))
        }
        guard let nummer = auszug.konto else {
            return .rueckfrage(String(localized: "XTB-Datei ohne Kontonummer: bitte im Blatt angeben."))
        }
        guard let konto = konten.first(where: { $0.broker == Importer.xtbBroker && $0.kontonummer == nummer }) else {
            return .rueckfrage(String(localized: "Neues Konto bei XTB: bitte einmal von Hand importieren."))
        }
        return .xtb(konto, zeitzone: zeitzone(konto) ?? Serverzeit.mitteleuropa.zeitzone)
    }

    /// Dateien, die die App im Ordner gar nicht ansieht: versteckte, halb geladene (Safari, Chrome, Firefox)
    /// und andere Endungen als die der Importer.
    static func kommtInFrage(_ dateiname: String) -> Bool {
        guard !dateiname.hasPrefix("."), !dateiname.hasPrefix("~$") else { return false }
        let endung = (dateiname as NSString).pathExtension.lowercased()
        return ["csv", "html", "htm", "xlsx", "txt"].contains(endung)
    }
}
