import Foundation
import TradingCore

/// Produktart der Trades laut Broker-Export (Rechenkern 0.10.0, Doc 23). Beschreibt das Produkt, nicht den Steuertopf.
extension Produktart {
    var bezeichnung: String {
        switch self {
        case .aktie: "Aktie"
        case .fonds: "Fonds/ETF"
        case .anleihe: "Anleihe"
        case .derivat: "Derivat"
        case .cfd: "CFD/Forex"
        case .krypto: "Krypto"
        case .sonstiges: "Sonstiges"
        case .unbekannt: "unbekannt"
        }
    }
}

extension Anfrage {
    /// Kennzahlen je Produktart in der Reihenfolge von `Produktart.allCases`; leere Arten fehlen.
    func produktgruppen(_ trades: [Trade]) -> [(art: Produktart, kennzahlen: Kennzahlen)] {
        let nachArt = Dictionary(grouping: trades, by: \.produktart)
        return Produktart.allCases.compactMap { art in
            nachArt[art].map { (art: art, kennzahlen: Kennzahlen(trades: $0)) }
        }
    }

    /// Abschnitt „Nach Produktart“ der Auswertung; leer, wenn der Export für keinen Trade eine Art nennt.
    func produktartabschnitt(_ trades: [Trade]) -> [String] {
        let gruppen = produktgruppen(trades)
        guard gruppen.contains(where: { $0.art != .unbekannt }) else { return [] }
        if gruppen.count == 1, let g = gruppen.first {
            return ["\nProduktart laut Broker-Export: alle \(g.kennzahlen.anzahl) Trades \(g.art.bezeichnung)."]
        }
        return ["\n## Nach Produktart (laut Broker-Export)", produkttabelle(gruppen)]
    }

    func produkttabelle(_ gruppen: [(art: Produktart, kennzahlen: Kennzahlen)]) -> String {
        Format.tabelle(["Produktart", "Trades", "Netto", "Treffer", "Profitfaktor", "Erw. R"], gruppen.map { g in
            [g.art.bezeichnung, "\(g.kennzahlen.anzahl)", Format.zahl(g.kennzahlen.netto),
             Format.prozent(g.kennzahlen.trefferquote), Format.zahl(g.kennzahlen.profitfaktor),
             Format.r(g.kennzahlen.erwartungswertR)]
        })
    }
}

extension JournalExport {
    /// Trades nur mit Datum (Trade Republic, XTB) tragen 00:00 UTC. Westlich von UTC fiele das in der Zeitzone
    /// des Nutzers auf den Vortag (Befund Doc 36, Doc 40). Dort setzt der Connector sie auf 12:00 UTC desselben
    /// Datums; das liegt von UTC−11 bis UTC+11 am selben Kalendertag. Östlich von UTC und für Zeiten zur
    /// Mitternacht in Ortszeit (Scalable) bleibt alles, wie die App es rechnet.
    func mitTageslage() -> JournalExport {
        let zone = nutzerZeitzone
        var export = self
        for i in export.konten.indices {
            export.konten[i].trades = export.konten[i].trades.map { Self.tageslage($0, zone) }
        }
        return export
    }

    static func tageslage(_ trade: Trade, _ zone: TimeZone) -> Trade {
        guard trade.nurDatum else { return trade }
        var t = trade
        t.openTime = mittag(trade.openTime, zone)
        t.closeTime = mittag(trade.closeTime, zone)
        return t
    }

    private static func mittag(_ zeit: Date, _ zone: TimeZone) -> Date {
        let mitternachtUTC = zeit.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0
        guard mitternachtUTC, zone.secondsFromGMT(for: zeit) < 0 else { return zeit }
        return zeit.addingTimeInterval(12 * 3_600)
    }
}
