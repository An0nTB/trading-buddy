import ConnectorKern
import Foundation
import MCP
import TradingCore

/// Werkzeuge und Vorlagen, die Claude Desktop angezeigt bekommt. Alles nur lesend.
enum Katalog {
    static let zeitraum: [String: Value] = [
        "monat": text("Kalendermonat JJJJ-MM, z. B. 2025-05"),
        "woche": text("Ein beliebiger Tag der gewünschten Woche (Montag bis Sonntag), JJJJ-MM-TT"),
        "kw": text("ISO-Kalenderwoche JJJJ-Www, z. B. 2026-W40 (Montag bis Sonntag)"),
        "von": text("Erster Tag JJJJ-MM-TT, nur zusammen mit bis"),
        "bis": text("Letzter Tag JJJJ-MM-TT (einschließlich), nur zusammen mit von"),
        "konto": text("Konto über Endziffern oder Broker; nur nötig, wenn es mehrere gibt"),
        "waehrung": text("Nur Trades dieser Währung ohne Umrechnung, z. B. USD; ohne Angabe alles in Kontowährung (EZB-Kurs)")
    ]
    static let nurLesen = Tool.Annotations(readOnlyHint: true, openWorldHint: false)

    static let werkzeuge = [
        Tool(name: "henry_status",
             description: "Prüft die Verbindung zu Henry: Version der Erweiterung, Export-Ordner, Zeitpunkt des letzten Exports, Konten und Trades, mit Hinweis, was zu tun ist, wenn Daten fehlen oder veraltet sind. Aufrufen bei „Henry-Status“, „Verbindung prüfen“ oder wenn ein anderes Werkzeug keine Daten findet.",
             inputSchema: schema([:]), annotations: nurLesen),
        Tool(name: "hole_datenstand",
             description: "Welche Konten und welcher Zeitraum in Henry vorliegen. Zuerst aufrufen, wenn unklar ist, welche Daten es gibt.",
             inputSchema: schema([:]), annotations: nurLesen),
        Tool(name: "hole_auswertung",
             description: "Auswertung einer Woche (auch Kalenderwoche), eines Monats oder freier Tage wie der Wochenbericht der App: Kennzahlen mit Vorzeitraum, Ergebnis je Tag, Kosten, Symbole, Fehlermuster, Verstöße gegen die eigenen Handelsregeln und Prop-Firm-Grenzen, Muster mit Zufallsprüfung, auffällige Trades, Ausstieg (MAE und MFE aus Kerzen der App), Plan und verpasste Trades, Ziele früherer Reviews mit Istwert, Steuer-Orientierung je Topf seit Jahresbeginn, dazu das Rezept für die Antwort. Für Fragen wie „Wie lief mein Mai?“. Ohne Zeitraum gilt der letzte Monat mit Trades.",
             inputSchema: schema(zeitraum), annotations: nurLesen),
        Tool(name: "hole_aufschluesselung",
             description: "Kennzahlen je Gruppe: Symbol, Produktart (laut Broker), Richtung, Wochentag, Stunde, Trade-Nummer am Tag, Ergebnis des vorherigen Trades, Haltedauer oder eigene Journalangaben (Setup, Regeltreue, Zustand).",
             inputSchema: schema(zeitraum.merging(
                 ["dimension": text("Wonach aufgeteilt wird", werte: Aufschluesselung.alleWerte)]) { $1 },
                 pflicht: ["dimension"]),
             annotations: nurLesen),
        Tool(name: "hole_trades",
             description: "Einzelne Trades eines Zeitraums mit Journalangaben (Setup, Regeltreue, Zustand, Grund), Produktart, Einstieg, Ausstieg, Stop, Ziel, Playbook-Checkliste und, wenn die App Kerzen hat, MAE und MFE, für den Review nach Plan oder eigener Fehler; wahlweise nur bestimmte Tickets, ein Symbol oder die Trades eines Fehlermusters, sortiert nach bestem oder schlechtestem Ergebnis.",
             inputSchema: schema(zeitraum.merging([
                 "auswahl": text("Sortierung, Vorgabe chronologisch", werte: Tradeauswahl.allCases.map(\.rawValue)),
                 "muster": text("Nur Trades dieses Fehlermusters", werte: Fehlermuster.allCases.map(\.rawValue)),
                 "ticket": text("Nur diese Tickets (erste Spalte der Trade-Liste), mehrere mit Komma; ohne Zeitraum gelten ihre Monate"),
                 "symbol": text("Nur Trades dieses Symbols, z. B. BTCUSD"),
                 "anzahl": .object(["type": .string("integer"),
                                    "description": .string("Höchstens so viele Trades, 1 bis 50, Vorgabe 10")])
             ]) { $1 }),
             annotations: nurLesen),
        Tool(name: "hole_notizen",
             description: "Tagesnotizen (Plan vor dem Handel, Rückblick, Verfassung) und verpasste Trades mit Grund im Wortlaut, je Tag mit Trades und Netto des Kontos.",
             inputSchema: schema(zeitraum), annotations: nurLesen),
        Tool(name: "hole_nachrichten",
             description: "Überschriften und Anrisse der Nachrichten aus Henry (RSS-Quellen, Alpaca, Marketaux) der letzten Tage, zuerst zur eigenen Merkliste, mit Quelle und Link, dazu das Rezept für die Zusammenfassung. Nur, wenn die Nachrichten in der App eingeschaltet sind.",
             inputSchema: schema([
                 "tage": .object(["type": .string("integer"),
                                  "description": .string("Wie viele Tage zurück, 1 bis 7, Vorgabe 1")]),
                 "begriff": text("Nur Meldungen zu diesem Begriff der Merkliste oder Symbol; Symbole wie im Journal (AAPL.US, BTC/EUR, BTCUSD) finden auch das Basis-Symbol und bei Krypto den Namen; Index-CFDs (DE40.c, US500, NAS100, US30, UK100, JP225, EU50, FRA40) finden den Indexnamen")
             ]),
             annotations: nurLesen),
        Tool(name: "hole_kursanalyse",
             description: "Beschreibende Kursanalyse eines Werts aus den Tageskerzen der App: Veränderung über Woche, Monat, Quartal und Jahr, Schwankung, Tagesspanne, Abstand zum 52-Wochen-Hoch und -Tief, größter Rückgang, dazu die eigenen Trades im Wert und das Rezept. Keine Prognose.",
             inputSchema: schema([
                 "symbol": text("Symbol wie im Journal, z. B. BTCUSD oder AAPL"),
                 "monate": .object(["type": .string("integer"),
                                    "description": .string("Zeitraum der eigenen Trades in Monaten, 1 bis 12, Vorgabe 12; die Kennzahlen gelten immer für 12 Monate")])
             ], pflicht: ["symbol"]),
             annotations: nurLesen)
    ]

    static let vorlagen = [
        Prompt(name: "status", title: "Henry-Status",
               description: "Prüfen, ob Claude Henrys Daten bekommt", arguments: []),
        Prompt(name: "monatsauswertung", title: "Monatsauswertung",
               description: "Monat nach Henrys Rezept auswerten",
               arguments: [.init(name: "monat", description: "JJJJ-MM, leer für den letzten Monat mit Trades")]),
        Prompt(name: "wochenauswertung", title: "Wochenauswertung",
               description: "Woche nach Henrys Rezept auswerten",
               arguments: [.init(name: "datum", description: "Ein Tag der Woche, JJJJ-MM-TT, leer für die letzte abgeschlossene Woche")]),
        Prompt(name: "nachrichten", title: "Nachrichten zusammenfassen",
               description: "Nachrichten zur Merkliste und zum Markt zusammenfassen",
               arguments: [.init(name: "tage", description: "1 bis 7, leer für die letzten 24 Stunden")])
    ]

    static func schema(_ eigenschaften: [String: Value], pflicht: [String] = []) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object(eigenschaften),
            "required": .array(pflicht.map { .string($0) })
        ])
    }

    static func text(_ beschreibung: String, werte: [String]? = nil) -> Value {
        var feld: [String: Value] = ["type": .string("string"), "description": .string(beschreibung)]
        if let werte { feld["enum"] = .array(werte.map { .string($0) }) }
        return .object(feld)
    }
}

enum Ausfuehrung {
    /// Export-Ordner aus den Einstellungen der Erweiterung (manifest.json, user_config)
    static let exportOrdner = ProcessInfo.processInfo.environment["TB_EXPORT_DIR"]

    /// Argumente als Text; Zahlen werden umgewandelt.
    static func texte(_ argumente: [String: Value]?) -> [String: String] {
        (argumente ?? [:]).compactMapValues { wert in
            wert.stringValue ?? wert.intValue.map { String($0) } ?? wert.doubleValue.map(Anfrage.zahltext)
        }
    }

    static func werkzeug(_ name: String, _ argumente: [String: String]) -> CallTool.Result {
        let geladen = Exportdatei.lade(ordner: exportOrdner)
        if name == "henry_status" { return antwort(Verbindungsstatus.text(geladen, ordner: exportOrdner)) }
        guard case let .geladen(export) = geladen else {
            return antwort(Exportdatei.meldung(geladen) ?? "Keine Daten", fehler: true)
        }
        do {
            switch name {
            case "hole_datenstand":
                return antwort(Ausgabe.datenstand(export))
            case "hole_auswertung":
                return antwort(Ausgabe.auswertung(try Anfrage.lies(argumente, export: export)))
            case "hole_aufschluesselung":
                guard let dimension = argumente["dimension"].flatMap(Aufschluesselung.init(rawValue:)) else {
                    let erlaubt = Aufschluesselung.alleWerte.joined(separator: ", ")
                    return antwort("DIMENSION FEHLT: eine von \(erlaubt).", fehler: true)
                }
                return antwort(Ausgabe.aufschluesselung(try Anfrage.lies(argumente, export: export), nach: dimension))
            case "hole_nachrichten":
                let tage = argumente["tage"].flatMap { Int($0) } ?? 1
                return antwort(Ausgabe.nachrichten(export, tage: tage, begriff: argumente["begriff"]))
            case "hole_kursanalyse":
                let monate = argumente["monate"].flatMap { Int($0) } ?? 12
                return antwort(Ausgabe.kursanalyse(export, symbol: argumente["symbol"] ?? "", monate: monate))
            case "hole_notizen":
                return antwort(Ausgabe.notizen(try Anfrage.lies(argumente, export: export)))
            case "hole_trades":
                let auswahl = argumente["auswahl"].flatMap(Tradeauswahl.init(rawValue:)) ?? .chronologisch
                let muster = argumente["muster"].flatMap(Fehlermuster.init(rawValue:))
                let anzahl = argumente["anzahl"].flatMap { Int($0) } ?? 10
                return antwort(Ausgabe.trades(try Anfrage.lies(argumente, export: export), auswahl: auswahl,
                                              muster: muster, anzahl: anzahl, symbol: argumente["symbol"]))
            default:
                return antwort("Unbekanntes Werkzeug \(name)", fehler: true)
            }
        } catch let fehler as AnfrageFehler {
            return antwort(fehler.text, fehler: true)
        } catch {
            return antwort("FEHLER: \(error.localizedDescription)", fehler: true)
        }
    }

    static func vorlage(_ name: String, _ argumente: [String: String]?) -> GetPrompt.Result {
        let inhalt = switch name {
        case "wochenauswertung": Rezept.wochenvorlage(datum: argumente?["datum"])
        case "nachrichten": Rezept.nachrichtenvorlage(tage: argumente?["tage"])
        case "status": "Prüfe mit henry_status, ob du Henrys Daten bekommst, und sag mir das Ergebnis in ein bis zwei Sätzen."
        default: Rezept.monatsvorlage(monat: argumente?["monat"].flatMap { $0.isEmpty ? nil : $0 })
        }
        return .init(description: nil, messages: [.user(.text(text: inhalt))])
    }

    static func antwort(_ text: String, fehler: Bool = false) -> CallTool.Result {
        .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: fehler)
    }
}

let server = Server(
    name: "trading-buddy",
    version: Verbindungsstatus.connectorVersion,
    capabilities: .init(prompts: .init(listChanged: false), tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in .init(tools: Katalog.werkzeuge) }
await server.withMethodHandler(CallTool.self) { Ausfuehrung.werkzeug($0.name, Ausfuehrung.texte($0.arguments)) }
await server.withMethodHandler(ListPrompts.self) { _ in .init(prompts: Katalog.vorlagen) }
await server.withMethodHandler(GetPrompt.self) { Ausfuehrung.vorlage($0.name, $0.arguments) }

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
