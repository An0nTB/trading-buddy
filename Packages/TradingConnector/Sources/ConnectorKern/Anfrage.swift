import Foundation
import TradingCore

/// Werkzeug-Argumente, aufgelöst gegen die Exportdatei: welches Konto, welcher Zeitraum.
public struct Anfrage: Sendable {
    public var export: JournalExport
    public var konto: JournalExport.Kontodaten
    public var zeitraum: Zeitspanne
    /// Hinweis, wenn der Zeitraum nicht ausdrücklich gewählt wurde.
    public var vorgabe: String?
    /// Kontowährung laut Export; `konto` enthält nur Trades in `konto.waehrung` (Summen nie über Währungen).
    public var kontowaehrung: String = ""
    /// Trades des Kontos in anderen Währungen, je Währung; sie stehen nicht in den Summen dieser Antwort.
    public var andereWaehrungen: [String: [Trade]] = [:]
    /// Trades in fremder Währung ohne EZB-Kurs, wenn diese Anfrage in Kontowährung rechnet (wie
    /// `Waehrungsangleich.ohneKurs` der App); sonst leer. Sie zählen bei den Regeln nach Anzahl mit, ohne Betrag.
    public var ohneKurs: [Trade] = []
    /// Mit EZB-Referenzkursen in die Kontowährung umgerechnete Trades, Anzahl je Ursprungswährung.
    public var umgerechnet: [String: Int] = [:]
    /// Alle Trades des Kontos vor Währungswahl und Umrechnung, für `Zeitraumbericht` (Steuer, Umrechnung wie die App).
    public var alleTrades: [Trade] = []
    /// Kurse der Datei, wenn diese Anfrage in die Kontowährung umrechnet; sonst `nil`.
    public var angleichskurse: Referenzkurse?
    /// Gesuchte Tickets (`ticket`, mehrere mit Komma); leer ohne Filter.
    public var tickets: [String] = []

    public var zeitzone: TimeZone { export.nutzerZeitzone }
    public var kontoname: String { export.kurzname(konto) }

    /// Zeitraum aus `monat` („JJJJ-MM“), `woche` (ein Tag der Woche, „JJJJ-MM-TT“), `kw` (ISO-Kalenderwoche,
    /// „JJJJ-Www“ oder „JJJJ-WW“) oder `von` und `bis` („JJJJ-MM-TT“, beide einschließlich). Ohne Angabe:
    /// der letzte Monat mit Trades, mit `ticket` die Monate dieser Trades. Konto über `konto` (Endziffern oder
    /// Broker), bei nur einem Konto entbehrlich.
    /// Ohne `waehrung` rechnet sie Trades in fremder Währung mit den EZB-Kursen der Datei in die Kontowährung um
    /// (`Waehrungsangleich` wie die App); ohne Kurs bleiben sie draußen. Mit `waehrung` oder ohne Kurse in der Datei
    /// nur Trades dieser Währung; ohne Angabe die Kontowährung, gibt es darin keine Trades, die häufigste.
    public static func lies(_ argumente: [String: String], export: JournalExport) throws -> Anfrage {
        var konto = try waehleKonto(argumente["konto"], in: export)
        let alleTrades = konto.trades
        var angleichskurse: Referenzkurse?
        let kontowaehrung = konto.waehrung.uppercased()
        var (waehrung, andere) = try waehleWaehrung(argumente["waehrung"], konto)
        var umgerechnet: [String: Int] = [:]
        let wunsch = argumente["waehrung"]?.trimmingCharacters(in: .whitespaces) ?? ""
        // Ohne Kurse in der Datei gleicht sie trotzdem an, wenn sie in der Kontowährung rechnet: Gleichgesetztes
        // (USDT wie USD) zählt wie in App und Bericht mit, statt einmal in den Summen und einmal als „ohne Kurs“.
        if wunsch.isEmpty, export.angleichskurse != nil || waehrung == kontowaehrung, konto.trades.contains(where: {
            $0.waehrung(kontowaehrung: kontowaehrung) != kontowaehrung
        }) {
            // Kurstag in deutscher Zeit wie in App und Bericht (Dritter Gegencheck G6).
            let angleich = Waehrungsangleich(konto.trades, kontowaehrung: kontowaehrung, kurse: export.angleichskurse)
            for t in konto.trades where angleich.umgerechnet.contains(t.id) {
                umgerechnet[t.waehrung(kontowaehrung: kontowaehrung), default: 0] += 1
            }
            andere = Dictionary(grouping: angleich.ohneKurs) { $0.waehrung(kontowaehrung: kontowaehrung) }
            waehrung = kontowaehrung
            konto.trades = angleich.trades
            angleichskurse = export.angleichskurse
        } else {
            konto.trades = konto.trades.filter { $0.waehrung(kontowaehrung: kontowaehrung) == waehrung }
            // Das geplante Risiko steht in Kontowährung; gegen Ergebnisse in anderer Währung gäbe es ein falsches R.
            // Umgerechnete Trades (oben) behalten es wie in der App (AppModell, nach dem Angleich).
            if waehrung != kontowaehrung { konto.trades = konto.trades.map { $0.mitGeplantemRisiko(nil) } }
        }
        konto.waehrung = waehrung
        if waehrung != kontowaehrung {
            // Ziele und Betragsgrenzen sind in Kontowährung eingetragen; gegen andere Beträge sind sie bedeutungslos.
            konto.ziele = []
            konto.regeln?.maxTagesverlust = nil
            konto.regeln?.maxRisikoJeTrade = nil
        }
        let zone = export.nutzerZeitzone
        var vorgabe: String?
        let zeitraum: Zeitspanne
        let tickets = (argumente["ticket"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let gesucht = konto.trades.filter { tickets.contains($0.id) }
        if !tickets.isEmpty, gesucht.isEmpty {
            let fremd = alleTrades.first { tickets.contains($0.id) }?.waehrung(kontowaehrung: kontowaehrung)
            throw AnfrageFehler.ticketUnbekannt(tickets.joined(separator: ", "), export.kurzname(konto), fremd)
        }
        if let text = argumente["monat"] {
            let teile = zahlen(text)
            guard teile.count == 2, let z = Zeitspanne.monat(jahr: teile[0], monat: teile[1], zeitzone: zone) else {
                throw AnfrageFehler.ungueltigerMonat(text)
            }
            zeitraum = z
        } else if let text = argumente["kw"] {
            zeitraum = try kalenderwoche(text, zone)
        } else if let text = argumente["woche"] {
            zeitraum = Zeitspanne.woche(mit: try tag(text, zone), zeitzone: zone)
        } else if argumente["von"] != nil || argumente["bis"] != nil {
            guard let von = argumente["von"], let bis = argumente["bis"] else { throw AnfrageFehler.vonOhneBis }
            guard let z = Zeitspanne.tage(von: try komponenten(von), bis: try komponenten(bis), zeitzone: zone) else {
                throw AnfrageFehler.bisVorVon(von, bis)
            }
            zeitraum = z
        } else if let erster = gesucht.map(\.closeTime).min(), let letzter = gesucht.map(\.closeTime).max() {
            zeitraum = Zeitspanne(von: Zeitspanne.monat(mit: erster, zeitzone: zone).von,
                                  bis: Zeitspanne.monat(mit: letzter, zeitzone: zone).bis)
            vorgabe = "Kein Zeitraum angegeben, daher die Monate der gesuchten Tickets."
        } else {
            guard let letzter = konto.trades.map(\.closeTime).max() else {
                throw AnfrageFehler.keineTrades(export.kurzname(konto))
            }
            zeitraum = Zeitspanne.monat(mit: letzter, zeitzone: zone)
            vorgabe = "Kein Zeitraum angegeben, daher der letzte Monat mit Trades."
        }
        // In Kontowährung ohne Wahl sind die übrigen Trades genau die ohne Kurs, mit oder ohne Kurse in der Datei.
        let ohneKurs = wunsch.isEmpty && waehrung == kontowaehrung ? andere.values.flatMap { $0 } : []
        return Anfrage(export: export, konto: konto, zeitraum: zeitraum, vorgabe: vorgabe,
                       kontowaehrung: kontowaehrung, andereWaehrungen: andere, ohneKurs: ohneKurs,
                       umgerechnet: umgerechnet, alleTrades: alleTrades, angleichskurse: angleichskurse,
                       tickets: tickets)
    }

    /// Gewählte Währung und die Trades der übrigen Währungen des Kontos.
    static func waehleWaehrung(_ wunsch: String?, _ konto: JournalExport.Kontodaten) throws
        -> (String, [String: [Trade]]) {
        let kontowaehrung = konto.waehrung.uppercased()
        let jeWaehrung = Dictionary(grouping: konto.trades) { $0.waehrung(kontowaehrung: kontowaehrung) }
        let wunsch = wunsch?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
        let gewaehlt: String
        if !wunsch.isEmpty {
            guard wunsch == kontowaehrung || jeWaehrung[wunsch] != nil else {
                throw AnfrageFehler.waehrungUnbekannt(wunsch, Set(jeWaehrung.keys).union([kontowaehrung]).sorted())
            }
            gewaehlt = wunsch
        } else if let haeufigste = jeWaehrung.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }),
                  jeWaehrung[kontowaehrung] == nil {
            gewaehlt = haeufigste.key
        } else {
            gewaehlt = kontowaehrung
        }
        var andere = jeWaehrung
        andere[gewaehlt] = nil
        return (gewaehlt, andere)
    }

    public func auswertung() -> Auswertung {
        Auswertung(trades: konto.trades, geloeschteOrders: konto.geloeschteOrders, zeitraum: zeitraum,
                   zeitzone: zeitzone)
    }

    /// Zahl aus den Werkzeug-Argumenten als Text. Ganze Zahlen wie „5“, alles andere (2.5, 1e100, NaN)
    /// unverändert als Text, damit die Prüfung danach es ablehnt, statt dass die Umwandlung den Server beendet.
    public static func zahltext(_ wert: Double) -> String {
        Int(exactly: wert).map { String($0) } ?? String(wert)
    }

    static func waehleKonto(_ wunsch: String?, in export: JournalExport) throws -> JournalExport.Kontodaten {
        let konten = export.konten
        let namen = konten.map(export.kurzname)
        guard !konten.isEmpty else { throw AnfrageFehler.keineKonten }
        let wunsch = wunsch?.trimmingCharacters(in: .whitespaces) ?? ""
        if wunsch.isEmpty {
            guard konten.count == 1 else { throw AnfrageFehler.kontoUnklar(namen) }
            return konten[0]
        }
        var treffer = konten.indices.filter {
            konten[$0].kontonummer.hasSuffix(wunsch) || namen[$0].localizedCaseInsensitiveContains(wunsch)
        }
        // Genau der Kurzname oder genau die Nummer gewinnt, wenn der Wunsch auch in anderen Namen steckt.
        let genau = treffer.filter {
            namen[$0].caseInsensitiveCompare(wunsch) == .orderedSame || konten[$0].kontonummer == wunsch
        }
        if genau.count == 1 { treffer = genau }
        if treffer.count == 1 { return konten[treffer[0]] }
        throw treffer.isEmpty
            ? AnfrageFehler.kontoUnbekannt(wunsch, namen)
            : AnfrageFehler.kontoUnklar(treffer.map { namen[$0] })
    }

    private static func zahlen(_ text: String) -> [Int] {
        let teile = text.trimmingCharacters(in: .whitespaces).split(separator: "-").map { Int($0) }
        return teile.contains(nil) ? [] : teile.compactMap { $0 }
    }

    /// ISO-Kalenderwoche aus „2026-W40“, „2026-w40“ oder „2026-40“.
    private static func kalenderwoche(_ text: String, _ zone: TimeZone) throws -> Zeitspanne {
        let teile = zahlen(text.uppercased().replacingOccurrences(of: "W", with: ""))
        guard teile.count == 2, let z = Zeitspanne.kalenderwoche(jahr: teile[0], woche: teile[1], zeitzone: zone) else {
            throw AnfrageFehler.ungueltigeKalenderwoche(text)
        }
        return z
    }

    private static func komponenten(_ text: String) throws -> DateComponents {
        let teile = zahlen(text)
        guard teile.count == 3 else { throw AnfrageFehler.ungueltigesDatum(text) }
        return DateComponents(year: teile[0], month: teile[1], day: teile[2])
    }

    private static func tag(_ text: String, _ zone: TimeZone) throws -> Date {
        guard let z = Zeitspanne.tage(von: try komponenten(text), bis: try komponenten(text), zeitzone: zone) else {
            throw AnfrageFehler.ungueltigesDatum(text)
        }
        return z.von
    }
}

public enum AnfrageFehler: Error, Equatable, Sendable {
    case keineKonten
    case kontoUnklar([String])
    case kontoUnbekannt(String, [String])
    case ungueltigerMonat(String)
    case ungueltigesDatum(String)
    case ungueltigeKalenderwoche(String)
    /// Ticket, Konto, Währung des Trades, wenn er nur in einer anderen Währung vorkommt.
    case ticketUnbekannt(String, String, String?)
    case vonOhneBis
    case bisVorVon(String, String)
    case keineTrades(String)
    case waehrungUnbekannt(String, [String])

    /// Meldung für Claude, mit dem, was stattdessen geht.
    public var text: String {
        switch self {
        case .keineKonten:
            "KEINE KONTEN: Die Exportdatei enthält noch kein Konto. Erst in der App einen Auszug importieren."
        case let .kontoUnklar(konten):
            "KONTO UNKLAR: Bitte `konto` angeben, eines von: \(konten.joined(separator: "; "))."
        case let .kontoUnbekannt(wunsch, konten):
            "KONTO UNBEKANNT: „\(wunsch)“ passt zu keinem Konto. Vorhanden: \(konten.joined(separator: "; "))."
        case let .ungueltigerMonat(text):
            "UNGÜLTIGER MONAT: „\(text)“. Format JJJJ-MM, etwa 2025-05."
        case let .ungueltigesDatum(text):
            "UNGÜLTIGES DATUM: „\(text)“. Format JJJJ-MM-TT, etwa 2025-05-12."
        case let .ungueltigeKalenderwoche(text):
            "UNGÜLTIGE KALENDERWOCHE: „\(text)“. Format JJJJ-Www nach ISO, etwa 2026-W40."
        case let .ticketUnbekannt(ticket, konto, waehrung?):
            "TICKET NICHT IN DIESER ABFRAGE: „\(ticket)“ ist im Konto \(konto) ein Trade in \(waehrung) und fehlt "
                + "in diesen Summen; abfragen mit waehrung=\(waehrung)."
        case let .ticketUnbekannt(ticket, konto, nil):
            "TICKET UNBEKANNT: „\(ticket)“ steht nicht im Konto \(konto). Tickets nennt hole_trades in der ersten Spalte."
        case .vonOhneBis:
            "ZEITRAUM UNVOLLSTÄNDIG: `von` und `bis` nur zusammen angeben."
        case let .bisVorVon(von, bis):
            "ZEITRAUM UNGÜLTIG: \(von) bis \(bis). Gültige Tage angeben, `bis` nicht vor `von`."
        case let .keineTrades(konto):
            "KEINE TRADES: Für \(konto) sind noch keine abgeschlossenen Trades exportiert."
        case let .waehrungUnbekannt(wunsch, vorhanden):
            "WÄHRUNG UNBEKANNT: „\(wunsch)“ kommt in diesem Konto nicht vor. "
                + "Vorhanden: \(vorhanden.joined(separator: ", "))."
        }
    }
}
