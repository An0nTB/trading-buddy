import Foundation
import Observation
import TradingCore
import TradingNews
import TradingQuotes
import TradingStore

/// Nachrichten in der App (Doc 26; Tims Entscheidungen 02.10.2026 02:01 UTC, Aufbau 02:54 UTC): Abruf über das
/// Paket TradingNews (RSS-Mix, Alpaca News, Marketaux), Zwischenspeicher als JSON in Application Support
/// (14 Tage), Merkliste im Journal (TradingStore v9, Tabelle `merkliste`, für alle Konten; ohne Journal nur im
/// Arbeitsspeicher). Schlüssel nur im Schlüsselbund. Standard aus wie die Kurse: Die App verbindet sich erst
/// nach dem Einschalten mit den Quellen, und nichts davon läuft beim Start der App.
@Observable @MainActor
final class Nachrichtendienst {
    nonisolated static let schluesselAktiv = "nachrichtenAktiv"
    static let schluesselBudget = "marketauxBudget"
    static let schluesselQuellenAus = "nachrichtenQuellenAus"
    static let schluesselGesehenBis = "nachrichtenGesehenBis"
    /// Zwischenspeicher der Meldungen (Application Support/TradingBuddy/nachrichten.json). Nur der Pfad; Ordner
    /// und Datei entstehen erst beim ersten Schreiben. `nonisolated`, damit auch der Export für den Connector
    /// (ExportOrdner, AP12) denselben Pfad liest.
    nonisolated static let zwischenspeicherDatei: URL = {
        let ordner = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ordner.appendingPathComponent("TradingBuddy/nachrichten.json")
    }()
    /// Anzeigenamen der Quellen ohne RSS.
    static let alpaca = "Alpaca News"
    static let marketaux = "Marketaux"
    /// RSS-Quellen in der Reihenfolge der Feedliste, je Anbieter einmal.
    static let rssQuellen: [String] = {
        var gesehen = Set<String>()
        return Feedliste.standard.map(\.quelle).filter { gesehen.insert($0).inserted }
    }()

    private(set) var aktiv: Bool
    /// Alle Meldungen aus dem Zwischenspeicher, neueste zuerst.
    private(set) var meldungen: [Meldung] = []
    /// Meldungen je aktivem Eintrag der Merkliste (Schlüssel: Eintrags-ID).
    private(set) var zuordnung: [String: [Meldung]] = [:]
    /// Meldungen zur Merkliste insgesamt, ohne Doppelte, neueste zuerst.
    private(set) var zurMerkliste: [Meldung] = []
    /// Meldungen, die zu keinem Eintrag der Merkliste passen.
    private(set) var markt: [Meldung] = []
    /// Fehler je Quelle aus dem letzten Abruf (Schlüssel wie im Paket: „Quelle Feedtitel“, „Alpaca“, „Marketaux“).
    private(set) var fehler: [String: String] = [:]
    private(set) var letzterAbruf: Date?
    private(set) var laedt = false
    /// Freie Marketaux-Abrufe heute nach dem letzten Abruf; `nil` vor dem ersten Abruf.
    private(set) var marketauxRest: Int?
    private(set) var merkliste: [Merklisteneintrag]
    /// Quellen, die der Nutzer abgeschaltet hat (Anzeigenamen).
    private(set) var quellenAus: Set<String>
    /// Bis zu dieser Zeit hat der Nutzer die Seite zuletzt gesehen; neuere Meldungen gelten als neu.
    private(set) var gesehenBis: Date?

    private let speicher: UserDefaults
    private let zwischenspeicher: Zwischenspeicher
    private var abruf: Nachrichtenabruf?
    private var gestartet = false
    private var journal: Journal?

    /// Alpaca- und Marketaux-Schlüssel; in den App-Tests mit `SpeicherSchluesselablage` (Paket A7).
    let schluesselbund: Schluesselbund

    init(speicher: UserDefaults = .standard, schluesselbund: Schluesselbund = Schluesselbund()) {
        self.speicher = speicher
        self.schluesselbund = schluesselbund
        aktiv = speicher.bool(forKey: Self.schluesselAktiv)
        merkliste = []
        quellenAus = Set(speicher.stringArray(forKey: Self.schluesselQuellenAus) ?? [])
        gesehenBis = speicher.object(forKey: Self.schluesselGesehenBis) as? Date
        zwischenspeicher = Zwischenspeicher(datei: Self.zwischenspeicherDatei)
    }

    // MARK: Schalter und Quellen

    var quellen: [String] { Self.rssQuellen + [Self.alpaca, Self.marketaux] }

    func istAn(_ quelle: String) -> Bool { !quellenAus.contains(quelle) }

    var aktiveQuellen: Int { quellen.filter { istAn($0) }.count }

    /// Feed-Titel eines RSS-Anbieters, zum Beispiel „News, Analysen“.
    static func feedTitel(_ quelle: String) -> String {
        Feedliste.standard.filter { $0.quelle == quelle }.map(\.titel).joined(separator: ", ")
    }

    func setzeAktiv(_ neu: Bool) {
        aktiv = neu
        speicher.set(neu, forKey: Self.schluesselAktiv)
        if !neu { abruf = nil }
        #if os(macOS)
        // Ausgeschaltet: Meldungen verschwinden auch aus dem Export für den Connector (AP12).
        if !neu { ExportOrdner.schreibe(journal) }
        #endif
    }

    func setzeQuelle(_ quelle: String, an: Bool) {
        if an { quellenAus.remove(quelle) } else { quellenAus.insert(quelle) }
        speicher.set(quellenAus.sorted(), forKey: Self.schluesselQuellenAus)
        abruf = nil
    }

    /// Nach geändertem Schlüssel: Der nächste Abruf baut die Verbindung neu auf.
    func neustart() { abruf = nil }

    /// Fehlertext für eine Quelle; bei RSS alle Feeds des Anbieters zusammen.
    func fehlerText(_ quelle: String) -> String? {
        let kern = quelle == Self.alpaca ? "Alpaca" : quelle
        let treffer = fehler.filter { $0.key == kern || $0.key.hasPrefix(kern + " ") }
            .sorted { $0.key < $1.key }
            .map { $0.key == kern ? $0.value : String($0.key.dropFirst(kern.count + 1)) + ": " + $0.value }
        return treffer.isEmpty ? nil : treffer.joined(separator: "; ")
    }

    // MARK: Merkliste (Journal, TradingStore v9)

    /// Hängt die Merkliste ans Journal; die App ruft das einmal nach dem Öffnen der Datenbank auf.
    func verbinde(_ journal: Journal) {
        self.journal = journal
        schreibe { _ in }
    }

    var aktiveEintraege: [Merklisteneintrag] { merkliste.filter { $0.status == .aktiv } }
    var vorschlaege: [Merklisteneintrag] { merkliste.filter { $0.status == .vorgeschlagen } }
    var begriffe: [Merkbegriff] { aktiveEintraege.map(Self.begriff) }
    /// Letzter Fehler beim Lesen oder Schreiben der Merkliste, für die Karte.
    var merklisteFehler: String? { fehler["Merkliste"] }

    /// Eintrag aus TradingCore als Suchbegriff des Nachrichtenpakets; die Arten heißen in beiden gleich.
    nonisolated static func begriff(_ eintrag: Merklisteneintrag) -> Merkbegriff {
        Merkbegriff(art: Merkbegriff.Art(rawValue: eintrag.art.rawValue) ?? .stichwort, text: eintrag.begriff)
    }

    /// Vorschläge aus offenen Positionen und Trades der letzten 30 Tage; nichts davon wird still aktiv.
    func ergaenzeVorschlaege(trades: [Trade], offeneSymbole: [String], jetzt: Date = .now) {
        let neue = Merkliste.vorschlag(trades: trades, offeneSymbole: offeneSymbole, bestehend: merkliste, jetzt: jetzt)
        guard !neue.isEmpty else { return }
        schreibe { journal in
            for eintrag in neue { try journal.speichereMerklisteneintrag(eintrag) }
        } sonst: {
            merkliste.append(contentsOf: neue)
        }
    }

    /// Eintrag von Hand; ein schon bekannter Begriff wird wieder aktiv statt doppelt angelegt.
    /// `false`, wenn der Begriff leer ist oder das Journal ihn ablehnt (Fehlertext in `merklisteFehler`).
    @discardableResult
    func fuegeHinzu(_ text: String, art: Merklisteneintrag.Art? = nil, jetzt: Date = .now) -> Bool {
        var eintrag = Merklisteneintrag(begriff: text, art: art, herkunft: .vonHand, status: .aktiv, erstellt: jetzt)
        guard !eintrag.begriff.isEmpty else { return false }
        if let bekannt = merkliste.first(where: { $0.schluessel == eintrag.schluessel }) {
            eintrag = bekannt
            eintrag.status = .aktiv
            if let art { eintrag.art = art }
        }
        let neu = eintrag
        return schreibe { journal in
            try journal.speichereMerklisteneintrag(neu)
        } sonst: {
            if let i = merkliste.firstIndex(where: { $0.id == neu.id }) { merkliste[i] = neu } else { merkliste.append(neu) }
        }
    }

    func setzeStatus(_ id: String, _ status: Merklisteneintrag.Status) {
        guard var eintrag = merkliste.first(where: { $0.id == id }) else { return }
        eintrag.status = status
        let neu = eintrag
        schreibe { journal in
            try journal.speichereMerklisteneintrag(neu)
        } sonst: {
            if let i = merkliste.firstIndex(where: { $0.id == id }) { merkliste[i] = neu }
        }
    }

    /// Entfernt einen aktiven Eintrag: von Hand angelegte verschwinden, Vorschläge werden „abgelehnt“,
    /// damit sie beim nächsten Vorschlag nicht wiederkommen.
    func entferne(_ id: String) {
        guard let eintrag = merkliste.first(where: { $0.id == id }) else { return }
        if eintrag.herkunft == .vonHand {
            schreibe { journal in
                try journal.loescheMerklisteneintrag(id: id)
            } sonst: {
                merkliste.removeAll { $0.id == id }
            }
        } else {
            setzeStatus(id, .abgelehnt)
        }
    }

    /// Schreibt über das Journal und liest die Liste danach neu; ohne Journal läuft `sonst` im Arbeitsspeicher.
    /// `false`, wenn das Journal die Änderung ablehnt; der Text steht dann in `merklisteFehler`.
    @discardableResult
    private func schreibe(_ aenderung: (Journal) throws -> Void, sonst: () -> Void = {}) -> Bool {
        var ok = true
        if let journal {
            do {
                try aenderung(journal)
                merkliste = try journal.merkliste()
                fehler["Merkliste"] = nil
            } catch {
                fehler["Merkliste"] = error.localizedDescription
                ok = false
            }
        } else {
            sonst()
        }
        ordneZu()
        return ok
    }

    // MARK: Meldungen

    /// Liest den Zwischenspeicher einmal, abseits des Hauptthreads; der Start der App bleibt unberührt.
    func starte(jetzt: Date = .now) async {
        guard !gestartet else { return }
        gestartet = true
        let ablage = zwischenspeicher
        let geladen = await Task.detached(priority: .utility) { ablage.lies(jetzt: jetzt) }.value
        if meldungen.isEmpty { meldungen = Self.sortiert(geladen) }
        ordneZu()
    }

    /// Holt neue Meldungen. `wennAelterAls` überspringt den Abruf, wenn der letzte jünger ist (Seite öffnen:
    /// 15 Minuten, Übersicht: 60 Minuten). Das Paket hält zusätzlich je Quelle 15 Minuten Abstand und das
    /// Marketaux-Tagesbudget (100 Abrufe gratis).
    func aktualisiere(wennAelterAls abstand: TimeInterval = 0, jetzt: Date = .now) async {
        guard aktiv, !laedt else { return }
        if let letzterAbruf, abstand > 0, jetzt.timeIntervalSince(letzterAbruf) < abstand { return }
        laedt = true
        defer { laedt = false }
        let abruf = self.abruf ?? neuerAbruf(jetzt: jetzt)
        let ergebnis = await abruf.aktualisiere(begriffe: begriffe, jetzt: jetzt)
        let budget = await abruf.budget
        Self.speichere(budget, in: speicher, schluessel: Self.schluesselBudget)
        // Während des Abrufs ausgeschaltet oder Quelle gewechselt (`abruf = nil`): Ergebnis verwerfen,
        // sonst landen Meldungen abgeschalteter Quellen in Liste, Zwischenspeicher und Export.
        guard aktiv, self.abruf === abruf else { return }
        // Der Fehler der Merkliste gehört nicht zum Abruf und bleibt stehen, bis die Merkliste wieder schreibt.
        var neueFehler = ergebnis.fehler
        neueFehler["Merkliste"] = fehler["Merkliste"]
        fehler = neueFehler
        marketauxRest = ergebnis.marketauxRest
        letzterAbruf = jetzt
        let ablage = zwischenspeicher
        let neue = ergebnis.meldungen
        do {
            let alle = try await Task.detached(priority: .utility) { try ablage.ergaenze(neue, jetzt: jetzt) }.value
            meldungen = Self.sortiert(alle)
            #if os(macOS)
            // Exportdatei für den Connector neu schreiben, damit sie die neuen Meldungen trägt (AP12, hole_nachrichten).
            _ = ExportOrdner.schreibe(journal)
            #endif
        } catch {
            fehler["Zwischenspeicher"] = error.localizedDescription
            meldungen = Self.sortiert(Doppelte.entferne(neue + meldungen))
        }
        ordneZu()
    }

    func markiereGesehen(jetzt: Date = .now) {
        gesehenBis = jetzt
        speicher.set(jetzt, forKey: Self.schluesselGesehenBis)
    }

    private func neuerAbruf(jetzt: Date) -> Nachrichtenabruf {
        let feeds = Feedliste.standard.filter { !quellenAus.contains($0.quelle) }
        var alpaca: Schluesselquelle<AlpacaNewsSchluessel>?
        if istAn(Self.alpaca) {
            // Derselbe Alpaca-Schlüssel wie für die Kurse (P10); Alpaca News läuft über dieselbe Kennung.
            let schluesselbund = self.schluesselbund
            alpaca = { @Sendable in
                try schluesselbund.lies().map { AlpacaNewsSchluessel(schluesselID: $0.schluesselID, geheimnis: $0.geheimnis) }
            }
        }
        var marketaux: Schluesselquelle<String>?
        if istAn(Self.marketaux) {
            let schluesselbund = self.schluesselbund
            marketaux = { @Sendable in try schluesselbund.liesText(dienst: Schluesselbund.dienstMarketaux) }
        }
        let budget = Self.lade(Abrufbudget.self, aus: speicher, schluessel: Self.schluesselBudget)
            ?? Abrufbudget(grenzeJeTag: Marketaux.abrufeJeTagGratis, jetzt: jetzt)
        let neu = Nachrichtenabruf(feeds: feeds, alpacaSchluessel: alpaca, marketauxToken: marketaux, budget: budget)
        abruf = neu
        return neu
    }

    private func ordneZu() {
        let aktive = aktiveEintraege
        let gruppen = Zuordnung.gruppiert(meldungen, nach: aktive.map(Self.begriff))
        var neu: [String: [Meldung]] = [:]
        var treffer: [String: Meldung] = [:]
        for eintrag in aktive {
            let passend = gruppen[Self.begriff(eintrag)] ?? []
            neu[eintrag.id] = passend
            for meldung in passend { treffer[meldung.id] = meldung }
        }
        zuordnung = neu
        zurMerkliste = Self.sortiert(Array(treffer.values))
        markt = meldungen.filter { treffer[$0.id] == nil }
    }

    private static func sortiert(_ meldungen: [Meldung]) -> [Meldung] {
        meldungen.sorted { a, b in a.zeit != b.zeit ? a.zeit > b.zeit : a.id < b.id }
    }

    private static func lade<T: Decodable>(_ typ: T.Type, aus speicher: UserDefaults, schluessel: String) -> T? {
        guard let daten = speicher.data(forKey: schluessel) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(typ, from: daten)
    }

    private static func speichere<T: Encodable>(_ wert: T, in speicher: UserDefaults, schluessel: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let daten = try? encoder.encode(wert) { speicher.set(daten, forKey: schluessel) }
    }
}
