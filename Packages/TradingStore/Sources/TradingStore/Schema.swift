import GRDB

/// Aufbau der Datenbank als Folge von Migrationen.
///
/// Eine Migration ist ein benannter, einmaliger Umbauschritt. GRDB merkt sich in der
/// Datenbank, welche Schritte schon gelaufen sind, und führt beim Öffnen nur die neuen aus.
/// Bestehende Migrationen werden nie geändert; jede Änderung am Aufbau kommt als neuer Schritt
/// ans Ende, sonst passen ältere Datenbanken nicht mehr.
///
/// Geldbeträge und Mengen stehen als Text in der Datenbank (`.text`), weil SQLite keinen
/// exakten Dezimaltyp kennt. Eine Spalte vom Typ Zahl würde `0.1` in eine Kommazahl mit
/// Rundungsfehler verwandeln. Zeiten stehen als UTC-Text (`2025-05-14 09:51:41.000`).
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1 Konten, Importe, MT4-Auszüge") { db in
            // Ein Handelskonto bei einem Broker. Kontowährung je Konto, Vorgabe EUR (Entscheidung 16).
            try db.create(table: "konto") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("broker", .text).notNull()
                t.column("kontonummer", .text).notNull()
                t.column("kontoname", .text).notNull()
                t.column("waehrung", .text).notNull()
                t.uniqueKey(["broker", "kontonummer"])
            }

            // Schicht 1 (R2 Abschnitt 5): jede importierte Datei mit Fingerabdruck und Inhalt.
            try db.create(table: "importlauf") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto").notNull()
                t.column("importer", .text).notNull()
                t.column("importerVersion", .text).notNull()
                t.column("dateiname", .text).notNull()
                // SHA-256 des Dateiinhalts. Dieselbe Datei ein zweites Mal wird daran erkannt.
                t.column("dateiHash", .text).notNull().unique()
                // Originaldatei, damit sich jeder Datensatz nachprüfen und neu einlesen lässt.
                t.column("datei", .blob).notNull()
                t.column("art", .text).notNull()
                t.column("stichtag", .datetime).notNull()
                t.column("serverZeitzone", .text).notNull()
                t.column("importiertAm", .datetime).notNull()
            }

            // Kontoübersicht am Ende eines Auszugs (eine Zeile je Import).
            try db.create(table: "kontostand") { t in
                t.primaryKey("importlaufId", .integer)
                    .references("importlauf", onDelete: .cascade)
                t.column("previousBalance", .text)
                t.column("closedTradePL", .text).notNull()
                t.column("depositWithdrawal", .text).notNull()
                t.column("balance", .text).notNull()
                t.column("floatingPL", .text).notNull()
                t.column("equity", .text).notNull()
                t.column("creditFacility", .text).notNull()
                t.column("marginRequirement", .text).notNull()
                t.column("availableMargin", .text).notNull()
            }

            // Geschlossene Positionen: je Konto und Ticket genau einmal, egal in wie vielen
            // Auszügen sie vorkommen. `importlaufId` zeigt auf den ersten Import.
            try db.create(table: "geschlossenePosition") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto").notNull()
                t.belongsTo("importlauf").notNull()
                t.column("ticket", .text).notNull()
                // Zelltexte der Originalzeile als JSON-Liste (Regel 9: Rohzeile aufbewahren).
                t.column("rohzeile", .text).notNull()
                t.column("side", .text).notNull()
                t.column("lots", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("openTime", .datetime).notNull()
                t.column("openPrice", .text).notNull()
                t.column("stopLoss", .text)
                t.column("takeProfit", .text)
                t.column("closeTime", .datetime).notNull().indexed()
                t.column("closePrice", .text).notNull()
                t.column("commission", .text).notNull()
                t.column("swap", .text).notNull()
                t.column("profit", .text).notNull()
                t.uniqueKey(["kontoId", "ticket"])
            }

            // Gelöschte Pending Orders: gespeichert für „wie oft storniere ich“, nie ein Trade.
            try db.create(table: "geloeschteOrder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto").notNull()
                t.belongsTo("importlauf").notNull()
                t.column("ticket", .text).notNull()
                // Zelltexte der Originalzeile als JSON-Liste (Regel 9: Rohzeile aufbewahren).
                t.column("rohzeile", .text).notNull()
                t.column("type", .text).notNull()
                t.column("lots", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("placedAt", .datetime).notNull()
                t.column("orderPrice", .text).notNull()
                t.column("stopLoss", .text)
                t.column("takeProfit", .text)
                t.column("cancelledAt", .datetime).notNull()
                t.column("marketPrice", .text).notNull()
                t.uniqueKey(["kontoId", "ticket"])
            }

            // Offene Positionen sind eine Momentaufnahme je Auszug, keine Trades. Ihr Ergebnis
            // (inklusive Kommission) steckt schon im Floating P/L des Auszugs; deshalb werden
            // sie nie über mehrere Auszüge aufsummiert.
            try db.create(table: "offenePosition") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("importlauf", onDelete: .cascade).notNull()
                t.column("ticket", .text).notNull()
                // Zelltexte der Originalzeile als JSON-Liste (Regel 9: Rohzeile aufbewahren).
                t.column("rohzeile", .text).notNull()
                t.column("side", .text).notNull()
                t.column("lots", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("openTime", .datetime).notNull()
                t.column("openPrice", .text).notNull()
                t.column("stopLoss", .text)
                t.column("takeProfit", .text)
                t.column("currentPrice", .text).notNull()
                t.column("commission", .text).notNull()
                t.column("swap", .text).notNull()
                t.column("profit", .text).notNull()
                t.uniqueKey(["importlaufId", "ticket"])
            }

            // Wartende Orders, ebenfalls als Momentaufnahme je Auszug.
            try db.create(table: "wartendeOrder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("importlauf", onDelete: .cascade).notNull()
                t.column("ticket", .text).notNull()
                // Zelltexte der Originalzeile als JSON-Liste (Regel 9: Rohzeile aufbewahren).
                t.column("rohzeile", .text).notNull()
                t.column("type", .text).notNull()
                t.column("lots", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("placedAt", .datetime).notNull()
                t.column("orderPrice", .text).notNull()
                t.column("stopLoss", .text)
                t.column("takeProfit", .text)
                t.column("marketPrice", .text).notNull()
                t.uniqueKey(["importlaufId", "ticket"])
            }
        }

        migrator.registerMigration("v2 Journal je Trade") { db in
            // Eigene Angaben zu einem Trade (Setup, Regeltreue, Zustand, nachgetragener Stop).
            // Schlüssel ist Konto + Ticket, nicht die Zeile in `geschlossenePosition`: So darf ein
            // Eintrag auch vor dem Import der Position stehen und übersteht jeden Re-Import.
            // Der Stop aus dem Export bleibt unverändert in `geschlossenePosition`; der
            // nachgetragene Einstiegs-Stop steht hier daneben, damit die Herkunft erkennbar bleibt.
            try db.create(table: "journal") { t in
                t.column("kontoId", .integer).notNull()
                    .references("konto", onDelete: .cascade)
                t.column("ticket", .text).notNull()
                t.column("setup", .text)
                t.column("regeltreue", .boolean)
                t.column("zustand", .integer).check { (1...5).contains($0) }
                t.column("marktumfeld", .text)
                t.column("grund", .text)
                t.column("stopEinstieg", .text)
                t.column("geaendertAm", .datetime).notNull()
                t.primaryKey(["kontoId", "ticket"])
            }
        }

        migrator.registerMigration("v3 Broker-Importe CSV") { db in
            // Schicht 2 aus R2 für Broker, die Käufe, Verkäufe und Geld einzeln exportieren
            // (Trade Republic, Scalable). Doppelte erkennt die Datenbank über Konto und
            // Vorgangs-ID des Brokers (transaction_id, reference), je Tabelle.
            try db.create(table: "ausfuehrung") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto").notNull()
                t.belongsTo("importlauf").notNull()
                t.column("vorgangId", .text).notNull()
                t.column("zeit", .datetime).notNull().indexed()
                t.column("nurDatum", .boolean).notNull()
                t.column("kennung", .text).notNull()
                t.column("name", .text).notNull()
                t.column("seite", .text).notNull()
                t.column("menge", .text).notNull()
                t.column("preis", .text).notNull()
                t.column("betrag", .text).notNull()
                t.column("gebuehr", .text).notNull()
                t.column("steuer", .text).notNull()
                t.column("waehrung", .text).notNull()
                t.column("sparplan", .boolean).notNull()
                t.column("rohzeile", .text).notNull()
                t.uniqueKey(["kontoId", "vorgangId"])
            }

            // Ein- und Auszahlungen, Dividenden, Zinsen, Steuern, Gebühren, Sonstiges.
            try db.create(table: "geldbewegung") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto").notNull()
                t.belongsTo("importlauf").notNull()
                t.column("vorgangId", .text).notNull()
                t.column("zeit", .datetime).notNull().indexed()
                t.column("nurDatum", .boolean).notNull()
                t.column("art", .text).notNull()
                t.column("betrag", .text).notNull()
                t.column("gebuehr", .text).notNull()
                t.column("steuer", .text).notNull()
                t.column("waehrung", .text).notNull()
                t.column("kennung", .text)
                t.column("rohzeile", .text).notNull()
                t.uniqueKey(["kontoId", "vorgangId"])
            }

            // Split, Ausbuchung und Unbekanntes: Bestandsänderung ohne Kauf oder Verkauf.
            try db.create(table: "kapitalmassnahme") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto").notNull()
                t.belongsTo("importlauf").notNull()
                t.column("vorgangId", .text).notNull()
                t.column("zeit", .datetime).notNull()
                t.column("art", .text).notNull()
                t.column("vorgang", .text).notNull()
                t.column("kennung", .text).notNull()
                t.column("menge", .text).notNull()
                t.column("rohzeile", .text).notNull()
                t.uniqueKey(["kontoId", "vorgangId"])
            }

            // Nicht ausgeführte Orders (storniert, abgelehnt): nur die Kennung, nie ein Trade.
            try db.create(table: "verworfenerVorgang") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto").notNull()
                t.belongsTo("importlauf").notNull()
                t.column("vorgangId", .text).notNull()
                t.uniqueKey(["kontoId", "vorgangId"])
            }

            // Zeilen, die der Importer nicht sicher zuordnen konnte; gehören zur Datei, daher je Import.
            try db.create(table: "importhinweis") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("importlauf", onDelete: .cascade).notNull()
                t.column("zeile", .integer).notNull()
                t.column("vorgang", .text).notNull()
                t.column("folge", .text).notNull()
            }
        }

        migrator.registerMigration("v4 Review-Ziele") { db in
            // Ziele aus der Wochen- oder Monatsauswertung (Rezept Punkt 7) je Konto, damit das nächste
            // Review sie aufgreift (Punkt 6). Zeitraum: von einschließlich, bis ausschließlich. Status als
            // Text (offen, erreicht, verfehlt, verworfen), geprüft im Code. Zielwert als Text wie alle Beträge.
            try db.create(table: "reviewziel") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("konto", onDelete: .cascade).notNull()
                t.column("text", .text).notNull()
                t.column("von", .datetime).notNull()
                t.column("bis", .datetime).notNull()
                t.column("messgroesse", .text)
                t.column("zielwert", .text)
                t.column("status", .text).notNull()
                t.column("ergebnis", .text)
                t.column("erstellt", .datetime).notNull()
                t.column("geaendert", .datetime).notNull()
            }
        }

        migrator.registerMigration("v5 Handelsregeln je Konto") { db in
            // Eigene Handelsregeln (Doc 18 F1) und Prop-Firm-Regeln (F10), eine Zeile je Konto. Jede Grenze
            // ist freiwillig, NULL heißt „Regel aus“. Die Prop-Firm-Felder tragen das Präfix `pf` und sind
            // entweder alle leer (kein Prop-Firm-Konto) oder `pfName` ist gesetzt. Einzelne Spalten statt
            // JSON, damit Beträge wie überall exakt als Text stehen. Arten als Text, geprüft im Code.
            try db.create(table: "handelsregeln") { t in
                t.primaryKey("kontoId", .integer).references("konto", onDelete: .cascade)
                t.column("maxTagesverlust", .text)
                t.column("maxTradesJeTag", .integer)
                t.column("stoppNachVerlusten", .integer)
                t.column("maxRisikoJeTrade", .text)
                t.column("pfName", .text)
                t.column("pfStartkapital", .text)
                t.column("pfZeitzone", .text)
                t.column("pfTageswechselMinuten", .integer)
                t.column("pfMaxTagesverlust", .text)
                t.column("pfMaxGesamtverlust", .text)
                t.column("pfGesamtverlustart", .text)
                t.column("pfEinfrierenBeiSaldo", .text)
                t.column("pfGewinnziel", .text)
                t.column("pfMindestHandelstage", .integer)
                t.column("pfHandelstagzaehlung", .text)
                t.column("pfMindestTagesgewinn", .text)
                t.column("pfKonsistenzMaxAnteil", .text)
                t.column("pfKonsistenzbezug", .text)
                t.column("pfKeinHaltenUeberTageswechsel", .boolean)
                t.column("pfKeinHaltenUeberWochenende", .boolean)
                t.column("pfMaxLotsJeTrade", .text)
                t.column("pfStopPflicht", .boolean)
                t.column("geaendert", .datetime).notNull()
            }
        }

        // v6 kam vor v5 auf main (#53 vor #54). Eine Datenbank, die v6 schon hat, bekommt v5 beim nächsten
        // Öffnen nachgeholt: GRDB führt alle fehlenden Migrationen in der Reihenfolge des Codes aus.
        migrator.registerMigration("v6 Produktart") { db in
            // Produktart je Ausführung und Position (TradingCore 0.10.0) als Rohwert von `Produktart`.
            // Alte Zeilen bleiben `unbekannt`, außer MT4-Positionen: Die sind CFD, wie sie der MT4-Leser
            // jetzt liefert. Andere alte Zeilen ergänzt der nächste Import, der die Art kennt.
            for tabelle in ["ausfuehrung", "geschlossenePosition", "offenePosition"] {
                try db.alter(table: tabelle) { t in
                    t.add(column: "produktart", .text).notNull().defaults(to: "unbekannt")
                }
            }
            for tabelle in ["geschlossenePosition", "offenePosition"] {
                try db.execute(sql: """
                    UPDATE \(tabelle) SET produktart = 'cfd'
                    WHERE importlaufId IN (SELECT id FROM importlauf WHERE importer = 'MT4-Auszug')
                    """)
            }
        }

        migrator.registerMigration("v7 Playbook") { db in
            // Setup-Karten (Doc 18 F3) für alle Konten gemeinsam: Ein Setup ist eine Handelsidee, kein
            // Konto. Der Name verbindet die Karte mit `journal.setup` und ist deshalb eindeutig.
            try db.create(table: "setup") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("stopRegel", .text)
                t.column("zielRegel", .text)
                t.column("marktumfeld", .text)
                t.column("notiz", .text)
                t.column("status", .text).notNull()
                t.column("statusSeit", .datetime).notNull()
            }
            // Kriterien einer Karte in ihrer Reihenfolge. Die Kennung bleibt beim Umformulieren gleich.
            try db.create(table: "kriterium") { t in
                t.belongsTo("setup", onDelete: .cascade).notNull()
                t.column("kennung", .text).notNull()
                t.column("text", .text).notNull()
                t.column("position", .integer).notNull()
                t.primaryKey(["setupId", "kennung"])
            }
            // Abgehakte Kriterien je Trade. Welches Setup der Trade hatte, steht nur in `journal.setup`;
            // ohne Journaleintrag gibt es keine Häkchen, und sie verschwinden mit ihm.
            try db.create(table: "haken") { t in
                t.column("kontoId", .integer).notNull()
                t.column("ticket", .text).notNull()
                t.column("kennung", .text).notNull()
                t.primaryKey(["kontoId", "ticket", "kennung"])
                t.foreignKey(["kontoId", "ticket"], references: "journal", onDelete: .cascade)
            }
        }

        migrator.registerMigration("v8 Tagesnotiz, verpasste Trades, Bilder") { db in
            // Notiz je Kalendertag (Doc 18 F4) für alle Konten gemeinsam, wie das Playbook: Plan und
            // Rückblick gelten dem Handelstag, nicht einem Konto. Tag als Text „JJJJ-MM-TT“.
            try db.create(table: "tagesnotiz") { t in
                t.primaryKey("tag", .text)
                t.column("plan", .text).notNull()
                t.column("planErstellt", .datetime)
                t.column("rueckblick", .text).notNull()
                t.column("verfassung", .integer)
                t.column("erstellt", .datetime).notNull()
                t.column("geaendert", .datetime).notNull()
            }
            try db.create(table: "verpassterTrade") { t in
                t.primaryKey("id", .text)
                t.column("zeit", .datetime).notNull().indexed()
                t.column("symbol", .text).notNull()
                t.column("seite", .text).notNull()
                t.column("setup", .text)
                t.column("grund", .text).notNull()
                t.column("notiz", .text).notNull()
                t.column("ergebnisR", .text)
            }
            // Verweise auf Bilder im Bilderordner der App; die Bilddaten liegen nie in der Datenbank.
            // Eine Datei gehört zu genau einem Bezug: Trade (Konto und Ticket), Tag oder verpasster Trade.
            // Bilder zu Trades verschwinden mit dem Konto, Bilder zu verpassten Trades mit dem Eintrag.
            try db.create(table: "bild") { t in
                t.primaryKey("datei", .text)
                t.column("art", .text).notNull()
                t.belongsTo("konto", onDelete: .cascade)
                t.column("ticket", .text)
                t.column("tag", .text).indexed()
                t.belongsTo("verpassterTrade", onDelete: .cascade)
                t.column("beschriftung", .text).notNull()
                t.column("erstellt", .datetime).notNull()
            }
            try db.create(index: "bild_trade", on: "bild", columns: ["kontoId", "ticket"])
        }

        migrator.registerMigration("v9 Merkliste") { db in
            // Merkliste für Nachrichten (Doc 26), für alle Konten. `schluessel` ist der Begriff in
            // Kleinbuchstaben und verhindert Doppelte. Abgelehnte Vorschläge bleiben stehen, damit sie
            // beim nächsten Vorschlag nicht wiederkommen.
            try db.create(table: "merkliste") { t in
                t.primaryKey("id", .text)
                t.column("begriff", .text).notNull()
                t.column("schluessel", .text).notNull().unique()
                t.column("art", .text).notNull()
                t.column("anzeigename", .text).notNull()
                t.column("herkunft", .text).notNull()
                t.column("status", .text).notNull()
                t.column("notiz", .text).notNull()
                t.column("erstellt", .datetime).notNull()
            }
        }

        return migrator
    }
}
