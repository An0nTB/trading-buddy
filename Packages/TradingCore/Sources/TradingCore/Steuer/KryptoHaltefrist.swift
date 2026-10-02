import Foundation

/// Krypto im Privatvermögen: Verkauf innerhalb eines Jahres nach Anschaffung ist steuerpflichtig,
/// danach steuerfrei; Gewinne eines Jahres unter 1.000 € bleiben frei (Freigrenze, kein Freibetrag).
/// § 23 Abs. 1 Nr. 2 und Abs. 3 EStG, Rechtsstand 2026 unverändert (Doc 22). FIFO je Wallet
/// (BMF-Schreiben 06.03.2025): hier je Aufruf, also je Konto, und je Coin über alle Paare.
/// Orientierung, keine Steuerberechnung.
public enum KryptoHaltefrist {
    public static let freigrenze: Decimal = 1000

    /// Offener Kauf: Restmenge, Anschaffungszeit, Kosten in Euro samt Gebühr (`nil` ohne Euro).
    struct Kauf {
        var menge: Decimal
        var zeit: Date
        var kosten: Decimal?
    }

    /// Teil eines Verkaufs mit einem Anschaffungsdatum. Beträge in Euro samt anteiliger Gebühr.
    public struct Los: Sendable, Equatable {
        public var coin: String
        public var menge: Decimal
        public var kaufzeit: Date
        public var verkaufzeit: Date
        /// Anschaffungskosten; `nil`, wenn der Kauf nicht in Euro war.
        public var einstand: Decimal?
        /// Veräußerungserlös nach Gebühr; `nil`, wenn der Verkauf nicht in Euro war.
        public var erloes: Decimal?
        public var steuerfrei: Bool

        public var gewinn: Decimal? {
            guard let einstand, let erloes else { return nil }
            return erloes - einstand
        }
    }

    /// Noch gehaltene Menge eines Kaufs mit dem ersten steuerfreien Verkaufstag.
    public struct Bestand: Sendable, Equatable {
        public var coin: String
        public var menge: Decimal
        public var kaufzeit: Date
        public var steuerfreiAb: Date
    }

    public struct Jahr: Sendable, Equatable {
        public var jahr: Int
        /// Lose der Verkäufe in diesem Jahr, nach Verkaufszeit.
        public var lose: [Los]
        /// Saldo der steuerpflichtigen Lose mit Euro-Werten.
        public var steuerpflichtig: Decimal
        /// Saldo der steuerfreien Lose mit Euro-Werten.
        public var steuerfrei: Decimal
        /// Lose ohne Euro-Wert (Kauf oder Verkauf in USD, USDT …); fehlen in den Summen.
        public var ohneEuro: Int
        /// Verkaufte Mengen ohne Kauf in den Daten (z. B. von einer anderen Börse übertragen).
        public var ohneAnschaffung: [Ausfuehrung]
        /// Nicht verbuchte Importzeilen (Krypto gegen Krypto, Gebühr in BNB); Jahr unbekannt.
        public var importhinweise: Int
        /// Bestand am Ende der Daten.
        public var offen: [Bestand]

        public var unterFreigrenze: Bool { steuerpflichtig < KryptoHaltefrist.freigrenze }
        public var vollstaendig: Bool { ohneEuro == 0 && ohneAnschaffung.isEmpty && importhinweise == 0 }
    }

    /// Erster Tag, an dem ein Verkauf steuerfrei ist: Tag nach dem Jahrestag des Kaufs in deutscher Zeit
    /// (Fristende nach §§ 187, 188 BGB, Einschätzung). Kauf am 29.02. endet am 28.02. des Folgejahres.
    public static func steuerfreiAb(_ kauf: Date, zeitzone: TimeZone = Steuerorientierung.deutscheZeit) -> Date {
        let k = Steuerorientierung.kalender(in: zeitzone)
        let jahrestag = k.date(byAdding: .year, value: 1, to: k.startOfDay(for: kauf))!
        return k.date(byAdding: .day, value: 1, to: jahrestag)!
    }

    /// Mit `kurse` rechnet eine Ausführung in anderer Währung zum Kurs an ihrem Tag in Euro um;
    /// ohne Kurs zählt das Los wie bisher als `ohneEuro`.
    public static func jahr(_ jahr: Int, ausfuehrungen: [Ausfuehrung], importhinweise: [Importhinweis] = [],
                            zeitzone: TimeZone = Steuerorientierung.deutscheZeit,
                            kurse: Referenzkurse? = nil) -> Jahr {
        let k = Steuerorientierung.kalender(in: zeitzone)
        // Bei gleicher Zeit erst Käufe, dann Verkäufe, sonst Reihenfolge der Datei.
        let nummeriert = Array(ausfuehrungen.filter { $0.produktart == .krypto }.enumerated())
        let krypto: [Ausfuehrung] = nummeriert.sorted { x, y in
            let rx = x.element.seite == .buy ? 0 : 1
            let ry = y.element.seite == .buy ? 0 : 1
            if x.element.zeit != y.element.zeit { return x.element.zeit < y.element.zeit }
            return rx != ry ? rx < ry : x.offset < y.offset
        }.map { $0.element }
        var bestand: [String: [Kauf]] = [:]
        var lose: [Los] = []
        var ohneAnschaffung: [Ausfuehrung] = []
        for a in krypto where a.menge > 0 {
            let coin = a.name.uppercased()
            let euroBetrag: Decimal? = a.waehrung.uppercased() == "EUR" ? a.betrag + a.gebuehr
                : kurse?.inEuro(a.betrag + a.gebuehr, waehrung: a.waehrung, am: a.zeit, zeitzone: zeitzone)
            if a.seite == .buy {
                let kosten: Decimal? = euroBetrag.map { -$0 }
                bestand[coin, default: []].append(Kauf(menge: a.menge, zeit: a.zeit, kosten: kosten))
                continue
            }
            let imJahr = k.component(.year, from: a.zeit) == jahr
            var rest = a.menge
            var kaeufe = bestand[coin] ?? []
            while rest > 0, let kauf = kaeufe.first {
                let menge = min(rest, kauf.menge)
                let anteilKauf = menge / kauf.menge
                if imJahr {
                    lose.append(Los(coin: coin, menge: menge, kaufzeit: kauf.zeit, verkaufzeit: a.zeit,
                                    einstand: kauf.kosten.map { $0 * anteilKauf },
                                    erloes: euroBetrag.map { $0 * menge / a.menge },
                                    steuerfrei: a.zeit >= steuerfreiAb(kauf.zeit, zeitzone: zeitzone)))
                }
                rest -= menge
                if menge == kauf.menge {
                    kaeufe.removeFirst()
                } else {
                    kaeufe[0] = Kauf(menge: kauf.menge - menge, zeit: kauf.zeit, kosten: kauf.kosten.map { $0 * (1 - anteilKauf) })
                }
            }
            bestand[coin] = kaeufe
            if rest > 0, imJahr {
                var teil = a
                teil.menge = rest
                ohneAnschaffung.append(teil)
            }
        }
        let mitEuro: [Los] = lose.filter { $0.gewinn != nil }
        let pflichtig: [Decimal] = mitEuro.filter { !$0.steuerfrei }.compactMap { $0.gewinn }
        let frei: [Decimal] = mitEuro.filter { $0.steuerfrei }.compactMap { $0.gewinn }
        var offen: [Bestand] = []
        for (coin, kaeufe) in bestand {
            for kauf in kaeufe {
                offen.append(Bestand(coin: coin, menge: kauf.menge, kaufzeit: kauf.zeit,
                                     steuerfreiAb: steuerfreiAb(kauf.zeit, zeitzone: zeitzone)))
            }
        }
        offen.sort { $0.kaufzeit != $1.kaufzeit ? $0.kaufzeit < $1.kaufzeit : $0.coin < $1.coin }
        return Jahr(jahr: jahr, lose: lose, steuerpflichtig: pflichtig.reduce(0, +), steuerfrei: frei.reduce(0, +),
                    ohneEuro: lose.count - mitEuro.count, ohneAnschaffung: ohneAnschaffung,
                    importhinweise: importhinweise.filter { $0.folge == .nichtVerbucht }.count, offen: offen)
    }
}
