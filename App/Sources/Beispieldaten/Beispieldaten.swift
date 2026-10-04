import Foundation
import TradingCore
import TradingStore

/// Beispieldaten für Beta-Tester (Hauptthread 03.10.2026 15:15 UTC): ein klar benanntes Konto mit 60 erfundenen
/// Krypto-Trades über drei Monate, damit Übersicht, Kennzahlen, Tagesseite, Bericht und Claude ohne eigenen Import
/// etwas zeigen. Der Weg führt über einen gewöhnlichen Kraken-Import (CSV), damit alles wie bei echten Daten läuft.
/// Erzeugt aus festem Startwert; Preise sind erfunden, keine echten Kurse.
enum Beispieldaten {
    static let kontonummer = "BEISPIEL-0001"
    static let dateiname = "Beispieldaten.csv"
    static let anzahl = 60
    /// Grenze „Trades je Tag“: an zwei Tagen liegen vier Trades, der vierte ist je ein Verstoß.
    static let maxTradesJeTag = 3
    static let zeitzone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    /// Werktage (ab 0) mit vier Trades; am ersten steht auch die Tagesnotiz.
    static let vierTradesTage: Set<Int> = [9, 33]

    static var broker: String { CSVBroker.kraken.name }
    static var kontoname: String { String(localized: "Beispielkonto") }

    static func istBeispiel(_ konto: Konto) -> Bool {
        konto.broker == broker && konto.kontonummer == kontonummer
    }

    /// Ein Trade: Kauf und Verkauf desselben Paars; Preise in Cent der Gegenwährung.
    struct Geschaeft: Equatable {
        var paar: String
        var menge: String
        var auf: Date
        var zu: Date
        var kauf: Int
        var verkauf: Int
        var kostenKauf: Int
        var kostenVerkauf: Int
    }

    struct Plan: Equatable {
        var geschaefte: [Geschaeft]
        var notizTag: Journaltag
        var notizZeit: Date
    }

    /// Paar, Menge und Ausgangspreis in Cent. Die Kosten (Preis × Menge) sind ganze Cent, wenn der Preis ein
    /// Vielfaches von `teiler` ist: Kosten = Preis × `zaehler` / `teiler`.
    private struct Wert {
        var paar: String
        var menge: String
        var zaehler: Int
        var teiler: Int
        var start: Int
    }

    private static let werte = [
        Wert(paar: "XXBTZEUR", menge: "0.01000000", zaehler: 1, teiler: 100, start: 5_800_000),
        Wert(paar: "XETHZEUR", menge: "0.20000000", zaehler: 1, teiler: 5, start: 260_000),
        Wert(paar: "SOLEUR", menge: "4.00000000", zaehler: 4, teiler: 1, start: 14_000),
        Wert(paar: "XETHZUSD", menge: "0.20000000", zaehler: 1, teiler: 5, start: 281_000),
    ]

    /// SplitMix64: gleicher Startwert, gleiche Folge, auf jedem Gerät.
    struct Zufall {
        private var zustand: UInt64
        init(_ start: UInt64) { zustand = start }
        mutating func naechste() -> UInt64 {
            zustand &+= 0x9E37_79B9_7F4A_7C15
            var z = zustand
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func bis(_ grenze: Int) -> Int { Int(naechste() % UInt64(grenze)) }
    }

    /// Werktage ab dem Monatsanfang drei Monate vor `heute`; je Tag 0 bis 2 Trades, an zwei Tagen vier.
    /// Der Startwert ergibt 33 Gewinner von 60 und gut 100 € netto in Euro (nachgerechnet, Doc 13).
    /// Jeder sechste bis achte Trade läuft in US-Dollar, damit der Währungsangleich etwas zu tun hat.
    static func plan(heute: Date) -> Plan {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let monat = kalender.dateInterval(of: .month, for: heute)?.start ?? heute
        var tag = kalender.date(byAdding: .month, value: -3, to: monat) ?? monat
        var zufall = Zufall(20_261_003)
        var preise = werte.map(\.start)
        var geschaefte: [Geschaeft] = []
        var werktag = 0
        var notiz = (Journaltag(tag, zeitzone: zeitzone), tag)
        let muster = [0, 1, 1, 1, 1, 2, 1, 1]
        let heuteBeginn = kalender.startOfDay(for: heute)
        // Rund 55 Werktage reichen für 60 Trades; nie über heute hinaus.
        while geschaefte.count < anzahl, tag < heuteBeginn {
            if !kalender.isDateInWeekend(tag) {
                let anzahlHeute = vierTradesTage.contains(werktag) ? 4 : muster[zufall.bis(muster.count)]
                if werktag == vierTradesTage.min() {
                    notiz = (Journaltag(tag, zeitzone: zeitzone), kalender.date(byAdding: .hour, value: 8, to: tag) ?? tag)
                }
                for n in 0..<min(anzahlHeute, anzahl - geschaefte.count) {
                    let nummer = geschaefte.count
                    let index = nummer % 8 == 5 ? 3 : zufall.bis(3)
                    let wert = werte[index]
                    // Tagesverlauf des Preises: ±1,5 %, auf den Teiler gerundet.
                    preise[index] = gerundet(preise[index] * (10_000 + zufall.bis(301) - 150) / 10_000, wert.teiler)
                    let kauf = preise[index]
                    // Ergebnis −2,2 % bis +3,3 %: etwas mehr Gewinner als Verlierer, nach Gebühren leicht im Plus.
                    let verkauf = gerundet(kauf * (10_000 + zufall.bis(551) - 220) / 10_000, wert.teiler)
                    let minute = 60 * (9 + 2 * n) + zufall.bis(40)
                    let auf = kalender.date(byAdding: .minute, value: minute, to: tag) ?? tag
                    let zu = auf.addingTimeInterval(TimeInterval(60 * (20 + zufall.bis(90))))
                    geschaefte.append(Geschaeft(paar: wert.paar, menge: wert.menge, auf: auf, zu: zu, kauf: kauf,
                                                verkauf: verkauf,
                                                kostenKauf: kauf * wert.zaehler / wert.teiler,
                                                kostenVerkauf: verkauf * wert.zaehler / wert.teiler))
                }
                werktag += 1
            }
            tag = kalender.date(byAdding: .day, value: 1, to: tag) ?? tag.addingTimeInterval(86_400)
        }
        return Plan(geschaefte: geschaefte, notizTag: notiz.0, notizZeit: notiz.1)
    }

    /// Handelsverlauf im Aufbau des Kraken-Exports (wie die App-Tests), Zeiten in UTC.
    static func csv(_ plan: Plan) -> String {
        let kopf = #""txid","ordertxid","pair","aclass","subclass","time","type","ordertype","price","cost","fee","vol","margin","misc","ledgers","posttxid","posstatuscode","cprice","ccost","cfee","cvol","cmargin","net","trades""#
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .gmt
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var zeilen = [kopf]
        var nummer = 0
        func zeile(_ g: Geschaeft, _ zeit: Date, _ art: String, _ preis: Int, _ kosten: Int) -> String {
            nummer += 1
            let id = String(format: "%06ld", nummer)
            let gebuehr = (kosten * 26 + 5_000) / 10_000 // 0,26 %, kaufmännisch gerundet
            return #""TBSP\#(id)-BEISP-\#(id)","OBSP\#(id)-BEISP-\#(id)","\#(g.paar)","forex","crypto","\#(format.string(from: zeit)).0000","\#(art)","limit","\#(betrag(preis))","\#(betrag(kosten))000","\#(betrag(gebuehr))000","\#(g.menge)","0.00000","","LBSP\#(id)-BEISP-\#(id)","","","","","","","","","""#
        }
        for g in plan.geschaefte {
            zeilen.append(zeile(g, g.auf, "buy", g.kauf, g.kostenKauf))
            zeilen.append(zeile(g, g.zu, "sell", g.verkauf, g.kostenVerkauf))
        }
        zeilen.append("")
        return zeilen.joined(separator: "\n")
    }

    /// Cent als Text mit Punkt und zwei Nachkommastellen.
    static func betrag(_ cent: Int) -> String {
        "\(cent / 100)." + String(format: "%02ld", cent % 100)
    }

    private static func gerundet(_ wert: Int, _ teiler: Int) -> Int {
        max(teiler, (wert + teiler / 2) / teiler * teiler)
    }

    /// Tagesnotiz am ersten Tag mit vier Trades. Plan und Rückblick gehen durch die Lokalisierung.
    static func notiz(_ plan: Plan) -> Tagesnotiz {
        Tagesnotiz(tag: plan.notizTag, plan: notizPlan, planErstellt: plan.notizZeit, rueckblick: notizRueckblick,
                   verfassung: 3, erstellt: plan.notizZeit)
    }

    static var notizPlan: String {
        String(localized: "Beispiel: Nur Ausbrüche über dem Vortageshoch, höchstens drei Trades.")
    }

    static var notizRueckblick: String {
        String(localized: "Beispiel: Vierter Trade aus Langeweile, gegen die eigene Regel.")
    }
}

extension AppModell {
    /// Das Beispielkonto, falls angelegt.
    var beispielkonto: Konto? { konten.first(where: Beispieldaten.istBeispiel) }

    /// Legt das Beispielkonto an und wählt es: Import, Regel „höchstens drei Trades je Tag“, Stops und Setups im
    /// Journal für zwei von drei Trades, eine Tagesnotiz. Regeln und Journal hängen am Beispielkonto, echte Konten
    /// bleiben unverändert. Nichts geschieht, wenn es schon existiert.
    func legeBeispieldatenAn(heute: Date = Date()) throws {
        guard beispielkonto == nil else { return }
        let plan = Beispieldaten.plan(heute: heute)
        _ = try importiereCSV(daten: Data(Beispieldaten.csv(plan).utf8), dateiname: Beispieldaten.dateiname,
                              kontonummer: Beispieldaten.kontonummer, kontoname: Beispieldaten.kontoname,
                              waehrung: "EUR", zeitzone: Beispieldaten.zeitzone)
        guard let konto = beispielkonto, let id = konto.id, let journal else { return }
        if self.konto?.id != id { waehleKonto(id) }
        try speichereRegeln(Handelsregeln(maxTradesJeTag: Beispieldaten.maxTradesJeTag))
        let setups = [String(localized: "Ausbruch"), String(localized: "Rücksetzer")]
        for (n, trade) in alleTrades.sorted(by: { ($0.openTime, $0.id) < ($1.openTime, $1.id) }).enumerated()
        where n % 3 != 2 {
            // Stop 1,5 % unter dem Einstieg, auf Cent gerundet.
            var stop = trade.openPrice * Decimal(985) / Decimal(1000)
            var gerundet = Decimal()
            NSDecimalRound(&gerundet, &stop, 2, .plain)
            speichereJournal(Journaleintrag(kontoId: id, ticket: trade.id, setup: setups[n % 2], stopEinstieg: gerundet))
        }
        // Tagesnotizen gelten für alle Konten: eine eigene Notiz an dem Tag bleibt, die Beispielnotiz entfällt dann.
        if try journal.tagesnotiz(plan.notizTag) == nil {
            try journal.speichereTagesnotiz(Beispieldaten.notiz(plan))
        }
        exportiere()
    }

    /// Entfernt das Beispielkonto mit allem, was daran hängt, und die Beispiel-Tagesnotiz. Andere Konten und
    /// eigene Notizen bleiben unberührt.
    func entferneBeispieldaten() throws {
        guard let konto = beispielkonto, let journal else { return }
        try journal.loescheKonto(konto)
        let plaene = [Beispieldaten.notizPlan, "Beispiel: Nur Ausbrüche über dem Vortageshoch, höchstens drei Trades."]
        if let von = Journaltag(jahr: 2000, monat: 1, tag: 1), let bis = Journaltag(jahr: 2100, monat: 12, tag: 31) {
            for notiz in try journal.tagesnotizen(von: von, bis: bis) where plaene.contains(notiz.plan) {
                try journal.speichereTagesnotiz(Tagesnotiz(tag: notiz.tag, erstellt: Date())) // leer: entfernt
            }
        }
        waehleKonto(nil)
        exportiere()
    }
}
