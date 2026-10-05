import Foundation

/// Sicherung des Browser-Journals „Trading Journal“ (Einzeldatei-HTML, Daten im localStorage),
/// Dateiname `journal-sicherung-JJJJ-MM-TT.json`. Aufbau laut HTML-Quelltext:
/// `{"trades": […], "setups": […]}`, dazu optional `assets` und `klassen` (hier nicht gebraucht).
/// Zahlenfelder stehen als Text („1.234,50“) oder als JSON-Zahl, deshalb JSONSerialization statt Codable.
/// Alle Beträge in Euro. Das Journal kennt keine Ausstiegszeit: Positionen schließen zur Einstiegszeit
/// und tragen `ausstiegszeitBekannt` false. Trades ohne Exit sind offen und werden nur gezählt.
/// Status: an einer synthetischen Datei geprüft, an einer echten ungeprüft.
public struct JournalSicherung: Sendable, Equatable {
    /// Was der Trade im Journal mitbringt, das keine ClosedPosition-Spalte hat.
    public struct Eintrag: Sendable, Equatable {
        public var ticket: String
        public var setup: String?
        public var zeiteinheit: String?
        /// Feld `regel`: Regeln eingehalten; fehlt es, `nil`.
        public var regeltreue: Bool?
        public var notiz: String?
        public var link: String?
        public var klasse: String?
        /// Markterwartung laut Journal; bei Scheinen nicht gleich der Handelsseite.
        public var markterwartung: Side
        public var schein: Bool
        /// Risiko in Euro laut Journal (Grundlage für stopLoss und R); leer oder 0 ergibt `nil`.
        public var risiko: Decimal?

        public init(ticket: String, setup: String? = nil, zeiteinheit: String? = nil, regeltreue: Bool? = nil,
                    notiz: String? = nil, link: String? = nil, klasse: String? = nil, markterwartung: Side,
                    schein: Bool = false, risiko: Decimal? = nil) {
            self.ticket = ticket
            self.setup = setup
            self.zeiteinheit = zeiteinheit
            self.regeltreue = regeltreue
            self.notiz = notiz
            self.link = link
            self.klasse = klasse
            self.markterwartung = markterwartung
            self.schein = schein
            self.risiko = risiko
        }
    }

    public var positionen: [ClosedPosition]
    /// Gleiche Reihenfolge wie `positionen`, je Position einer.
    public var eintraege: [Eintrag]
    public var setups: [String]
    /// Trades ohne Exit, nicht übernommen.
    public var offen: Int
    /// Zeile ist die Stelle in der Liste `trades` ab 1, Vorgang „Asset Datum“.
    public var hinweise: [Importhinweis]

    public init(positionen: [ClosedPosition] = [], eintraege: [Eintrag] = [], setups: [String] = [], offen: Int = 0,
                hinweise: [Importhinweis] = []) {
        self.positionen = positionen
        self.eintraege = eintraege
        self.setups = setups
        self.offen = offen
        self.hinweise = hinweise
    }

    /// Felder eines Trades in fester Reihenfolge; ihre Texte bilden die Rohzeile (Regel 9).
    static let felder = ["id", "datum", "uhrzeit", "asset", "klasse", "richtung", "art", "setup", "zeiteinheit",
                         "groesse", "entry", "exit", "risiko", "regel", "link", "notiz"]
    static let posix = Locale(identifier: "en_US_POSIX")

    /// JSON-Objekt mit Liste `trades`, deren erster Eintrag `datum` und `entry` hat. Eine leere Liste zählt auch.
    public static func erkennt(_ daten: Data) -> Bool {
        guard let json = try? wurzel(daten), let trades = json["trades"] as? [Any] else { return false }
        guard let erster = trades.first else { return true }
        guard let ersterTrade = erster as? [String: Any] else { return false }
        return ersterTrade["datum"] != nil && ersterTrade["entry"] != nil
    }

    public static func lies(_ daten: Data,
                            zeitzone: TimeZone = TimeZone(identifier: "Europe/Berlin")!) throws -> JournalSicherung {
        let json = try wurzel(daten)
        var ergebnis = JournalSicherung()
        ergebnis.setups = (json["setups"] as? [Any] ?? []).compactMap { text($0) }
        let trades = json["trades"] as? [Any] ?? []
        for (n, element) in trades.enumerated() {
            let zeile = n + 1
            guard let t = element as? [String: Any] else {
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: "", folge: .nichtVerbucht))
                continue
            }
            let asset = text(t["asset"]) ?? ""
            let vorgang = "\(asset) \(text(t["datum"]) ?? "")".trimmingCharacters(in: .whitespaces)
            // Offen geht vor: Ein laufender Trade ist kein Fehler und kommt mit dem Exit beim nächsten Import.
            let exitFeld = zahlfeld(t["exit"])
            if exitFeld == .leer {
                ergebnis.offen += 1
                continue
            }
            let risikoFeld = zahlfeld(t["risiko"])
            guard let einstieg = zeitpunkt(datum: text(t["datum"]) ?? "", uhrzeit: text(t["uhrzeit"]) ?? "",
                                           zeitzone: zeitzone),
                  case .wert(let groesse) = zahlfeld(t["groesse"]), groesse > 0,
                  case .wert(let entryKurs) = zahlfeld(t["entry"]),
                  case .wert(let exitKurs) = exitFeld,
                  risikoFeld != .ungueltig
            else {
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: vorgang, folge: .nichtVerbucht))
                continue
            }
            var risiko: Decimal?
            if case .wert(let r) = risikoFeld, r != 0 { risiko = r }
            let schein = text(t["art"])?.lowercased() == "schein"
            // Wie im Journal: alles außer „Short“ ist Long.
            let markterwartung: Side = text(t["richtung"])?.lowercased() == "short" ? .sell : .buy
            let klasse = text(t["klasse"])
            let art: Produktart = schein ? .derivat : produktart(klasse: klasse)
            let manuell = ManuellerTrade(symbol: asset, einstieg: einstieg, markterwartung: markterwartung,
                                         schein: schein, groesse: groesse, einstiegskurs: entryKurs,
                                         ausstiegskurs: exitKurs, risiko: risiko, produktart: art)
            let ticket = text(t["id"]).map { "js-\($0)" } ?? "js-zeile-\(zeile)"
            var position = manuell.position(ticket: ticket)
            position.rohzeile = felder.map { rohtext(t[$0]) }
            ergebnis.positionen.append(position)
            ergebnis.eintraege.append(Eintrag(
                ticket: ticket, setup: text(t["setup"]), zeiteinheit: text(t["zeiteinheit"]),
                regeltreue: wahrheitswert(t["regel"]), notiz: text(t["notiz"]), link: text(t["link"]),
                klasse: klasse, markterwartung: markterwartung, schein: schein, risiko: risiko))
        }
        return ergebnis
    }

    /// Oberstes JSON-Objekt mit Liste `trades`. Kodierung und Byte-Order-Mark wie bei jedem Import.
    static func wurzel(_ daten: Data) throws -> [String: Any] {
        guard let text = Importtext.lies(daten),
              let wert = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        else { throw JournalSicherungFehler.keinJSON }
        guard let objekt = wert as? [String: Any], objekt["trades"] as? [Any] != nil else {
            throw JournalSicherungFehler.keineTradesListe
        }
        return objekt
    }

    /// Assetklasse des Journals → Produktart für direkt gehandelte Werte; Unbekanntes bleibt `unbekannt`.
    static func produktart(klasse: String?) -> Produktart {
        switch (klasse ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
        case "aktie": return .aktie
        case "etf", "fonds": return .fonds
        case "krypto", "crypto": return .krypto
        case "index", "rohstoff", "forex", "devisen", "cfd": return .cfd
        default: return .unbekannt
        }
    }

    // MARK: - Werte

    /// Inhalt eines Zahlenfelds.
    enum Zahlfeld: Equatable {
        case leer, ungueltig
        case wert(Decimal)
    }

    /// Zahlenfeld als Text oder JSON-Zahl. Fehlt es oder ist es `null`, ist es leer.
    static func zahlfeld(_ wert: Any?) -> Zahlfeld {
        if let s = wert as? String { return zahl(s) }
        if wert == nil || wert is NSNull { return .leer }
        // JSON-Zahlen haben einen Punkt als Dezimaltrenner und keine Tausender. Double zuerst: Die kürzeste
        // Schreibweise („148.2“) ist auf macOS und Linux gleich; ein Int-Cast könnte Nachkommastellen abschneiden.
        let text: String
        if let d = wert as? Double {
            text = "\(d)"
        } else if let i = wert as? Int {
            text = String(i)
        } else if let n = wert as? NSNumber {
            text = n.stringValue
        } else {
            return .ungueltig
        }
        if let d = Decimal(string: text, locale: posix) { return .wert(d) }
        return .ungueltig
    }

    /// Zahlenregel des Journals: Leerraum und € fallen weg. Komma und Punkt: das hintere trennt die
    /// Dezimalen. Nur Komma: das letzte trennt die Dezimalen, weitere fallen weg. Nur Punkt: deutsche
    /// Tausender („18.872“) fallen weg, sonst ist er Dezimaltrenner („148.20“). Folge der Vorlage:
    /// „6,106“ ist 6,106, „6.106“ aber 6106.
    static func zahl(_ roh: String) -> Zahlfeld {
        var t = roh.filter { !$0.isWhitespace && $0 != "€" }
        guard !t.isEmpty else { return .leer }
        let letztesKomma = t.lastIndex(of: ","), letzterPunkt = t.lastIndex(of: ".")
        if let k = letztesKomma, let p = letzterPunkt {
            t = k > p ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                      : t.replacingOccurrences(of: ",", with: "")
        } else if let k = letztesKomma {
            let vorne = String(t[..<k]).replacingOccurrences(of: ",", with: "")
            t = vorne + "." + String(t[t.index(after: k)...])
        } else if letzterPunkt != nil, deutscheTausender(t) {
            t = t.replacingOccurrences(of: ".", with: "")
        }
        // Abschließendes Trennzeichen wie in echten Sicherungen („3,“, „3.“): Das Journal liest 3 (parseFloat).
        if t.hasSuffix(".") { t.removeLast() }
        // Decimal(string:) liest auch „12abc“ als 12; deshalb vorher streng prüfen.
        guard istZahltext(t), let wert = Decimal(string: t, locale: posix) else { return .ungueltig }
        return .wert(wert)
    }

    /// `^-?\d{1,3}(\.\d{3})+$`: „18.872“, „1.234.567“.
    static func deutscheTausender(_ t: String) -> Bool {
        let ohneVorzeichen = t.hasPrefix("-") ? t.dropFirst() : Substring(t)
        let gruppen = ohneVorzeichen.split(separator: ".", omittingEmptySubsequences: false)
        guard gruppen.count >= 2, (1...3).contains(gruppen[0].count) else { return false }
        let nurZiffern = gruppen.allSatisfy { gruppe in gruppe.allSatisfy { $0.isASCII && $0.isNumber } }
        return nurZiffern && gruppen.dropFirst().allSatisfy { $0.count == 3 }
    }

    /// Vorzeichen, Ziffern, höchstens ein Punkt, mindestens eine Ziffer.
    static func istZahltext(_ t: String) -> Bool {
        let ohneVorzeichen = (t.hasPrefix("-") || t.hasPrefix("+")) ? t.dropFirst() : Substring(t)
        let teile = ohneVorzeichen.split(separator: ".", omittingEmptySubsequences: false)
        guard teile.count <= 2, teile.contains(where: { !$0.isEmpty }) else { return false }
        return teile.allSatisfy { teil in teil.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// Getrimmter Text eines Felds; leer, fehlend oder kein Text ergibt `nil`. Zahlen als Text (etwa eine id).
    static func text(_ wert: Any?) -> String? {
        let roh: String
        if let s = wert as? String {
            roh = s
        } else if let n = wert as? NSNumber {
            roh = n.stringValue
        } else if let i = wert as? Int {
            roh = String(i)
        } else {
            return nil
        }
        let getrimmt = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        return getrimmt.isEmpty ? nil : getrimmt
    }

    /// Feld so, wie es in der Datei steht; fehlend oder `null` ergibt "".
    static func rohtext(_ wert: Any?) -> String {
        if let s = wert as? String { return s }
        if let n = wert as? NSNumber { return n.stringValue }
        if let i = wert as? Int { return String(i) }
        if let d = wert as? Double { return "\(d)" }
        return ""
    }

    /// JSON-Wahrheitswert oder Text „true“/„false“; sonst `nil`.
    static func wahrheitswert(_ wert: Any?) -> Bool? {
        if let s = wert as? String {
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "ja": return true
            case "false", "nein": return false
            default: return nil
            }
        }
        if let b = wert as? Bool { return b }
        if let n = wert as? NSNumber { return n.boolValue }
        return nil
    }

    /// „2026-03-02“ und „10:00“ (oder „10:00:15“) in der Zeitzone des Journals; leere Uhrzeit ist 00:00.
    /// `nil` bei ungültigem Datum, auch bei Tagen, die es nicht gibt (30. Februar).
    static func zeitpunkt(datum: String, uhrzeit: String, zeitzone: TimeZone) -> Date? {
        let d = datum.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        let u: [Int?] = uhrzeit.isEmpty ? [0, 0]
            : uhrzeit.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        let sekundeRoh: Int? = u.count == 3 ? u[2] : 0
        guard d.count == 3, u.count == 2 || u.count == 3,
              let jahr = d[0], let monat = d[1], let tag = d[2],
              let stunde = u[0], let minute = u[1], let sekunde = sekundeRoh,
              (1...12).contains(monat), (1...31).contains(tag),
              (0...23).contains(stunde), (0...59).contains(minute), (0...59).contains(sekunde)
        else { return nil }
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let teile = DateComponents(year: jahr, month: monat, day: tag, hour: stunde, minute: minute, second: sekunde)
        guard let zeit = kalender.date(from: teile), kalender.component(.day, from: zeit) == tag else { return nil }
        return zeit
    }
}

public enum JournalSicherungFehler: Error, Equatable, Sendable {
    /// Kein Text oder kein gültiges JSON.
    case keinJSON
    /// JSON, aber kein Objekt mit Liste `trades`.
    case keineTradesListe
}
