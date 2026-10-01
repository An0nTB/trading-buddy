import Foundation
import TradingCore

/// Werkzeug-Argumente, aufgelöst gegen die Exportdatei: welches Konto, welcher Zeitraum.
public struct Anfrage: Sendable {
    public var export: JournalExport
    public var konto: JournalExport.Kontodaten
    public var zeitraum: Zeitspanne
    /// Hinweis, wenn der Zeitraum nicht ausdrücklich gewählt wurde.
    public var vorgabe: String?

    public var zeitzone: TimeZone { export.nutzerZeitzone }
    public var kontoname: String { export.kurzname(konto) }

    /// Zeitraum aus `monat` („JJJJ-MM“), `woche` (ein Tag der Woche, „JJJJ-MM-TT“)
    /// oder `von` und `bis` („JJJJ-MM-TT“, beide einschließlich). Ohne Angabe:
    /// der letzte Monat mit Trades. Konto über `konto` (Endziffern oder Broker), bei nur einem Konto entbehrlich.
    public static func lies(_ argumente: [String: String], export: JournalExport) throws -> Anfrage {
        let konto = try waehleKonto(argumente["konto"], in: export)
        let zone = export.nutzerZeitzone
        var vorgabe: String?
        let zeitraum: Zeitspanne
        if let text = argumente["monat"] {
            let teile = zahlen(text)
            guard teile.count == 2, let z = Zeitspanne.monat(jahr: teile[0], monat: teile[1], zeitzone: zone) else {
                throw AnfrageFehler.ungueltigerMonat(text)
            }
            zeitraum = z
        } else if let text = argumente["woche"] {
            zeitraum = Zeitspanne.woche(mit: try tag(text, zone), zeitzone: zone)
        } else if argumente["von"] != nil || argumente["bis"] != nil {
            guard let von = argumente["von"], let bis = argumente["bis"] else { throw AnfrageFehler.vonOhneBis }
            guard let z = Zeitspanne.tage(von: try komponenten(von), bis: try komponenten(bis), zeitzone: zone) else {
                throw AnfrageFehler.bisVorVon(von, bis)
            }
            zeitraum = z
        } else {
            guard let letzter = konto.trades.map(\.closeTime).max() else {
                throw AnfrageFehler.keineTrades(export.kurzname(konto))
            }
            zeitraum = Zeitspanne.monat(mit: letzter, zeitzone: zone)
            vorgabe = "Kein Zeitraum angegeben, daher der letzte Monat mit Trades."
        }
        return Anfrage(export: export, konto: konto, zeitraum: zeitraum, vorgabe: vorgabe)
    }

    public func auswertung() -> Auswertung {
        Auswertung(trades: konto.trades, geloeschteOrders: konto.geloeschteOrders, zeitraum: zeitraum,
                   zeitzone: zeitzone)
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
    case vonOhneBis
    case bisVorVon(String, String)
    case keineTrades(String)

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
        case .vonOhneBis:
            "ZEITRAUM UNVOLLSTÄNDIG: `von` und `bis` nur zusammen angeben."
        case let .bisVorVon(von, bis):
            "ZEITRAUM UNGÜLTIG: \(von) bis \(bis). Gültige Tage angeben, `bis` nicht vor `von`."
        case let .keineTrades(konto):
            "KEINE TRADES: Für \(konto) sind noch keine abgeschlossenen Trades exportiert."
        }
    }
}
