import Foundation
import Observation
import TradingCalendar
import TradingCore
import TradingRates
import TradingStore

/// Zeitraum-Filter: alles oder ein Kalendermonat (Monatsanfang in der Zeitzone des Nutzers).
enum Zeitraum: Hashable {
    case alle
    case monat(Date)
}

/// Eine importierte Datei in der Liste unter „Import“.
struct ImportEintrag: Identifiable {
    var id: Int64
    var konto: Konto
    var lauf: Importlauf
    /// Zeilen, die der Importer nicht sicher zuordnen konnte (Trade Republic, Scalable, XTB); bei MT4 leer.
    var hinweise: [Importhinweis] = []
}

/// Zustand der App: das Journal auf der Festplatte, die Trades des gewählten Kontos
/// und die Filter der Oberfläche. Kennzahlen und Fehlermuster rechnet der Rechenkern bei Bedarf neu.
@Observable @MainActor
final class AppModell {
    private(set) var journal: Journal?
    private(set) var konten: [Konto] = []
    private(set) var importe: [ImportEintrag] = []
    /// Geschlossene Positionen des gewählten Kontos, wie importiert (MetaTrader, XTB).
    private var positionen: [ClosedPosition] = []
    /// Ausführungen, Geldbewegungen und Kapitalmaßnahmen des gewählten Kontos (Trade Republic, Scalable).
    private(set) var kontobewegungen = Kontobewegungen()
    /// Trades aus den Ausführungen nach FIFO, dazu offene Käufe und Verkäufe ohne Kauf im Export.
    private(set) var positionsbildung = Positionsbildung.bilde([])
    /// Journaleinträge des gewählten Kontos, Schlüssel ist das Ticket.
    private(set) var journaleintraege: [String: Journaleintrag] = [:]
    /// Geplantes Risiko des Kontos: Angabe am Trade, Standard je Setup und je Konto (Doc 02 Nr. 64, Store v10).
    private(set) var risikoquellen = Risikoquellen()
    /// Freie Tags je Ticket des Kontos (Doc 02 Nr. 65).
    private(set) var tradeTags: [String: [String]] = [:]
    /// Markterwartung je Ticket aus dem Journal (v11): gekaufter Short-Schein ist side buy, Erwartung sell.
    private(set) var markterwartungen: [String: Side] = [:]
    /// Offen eingetragene Hand-Trades des Kontos (Trade eintragen, #294), für die Karte „Offene Positionen“.
    private(set) var offeneHandpositionen: [OffenerHandtrade] = []
    /// Alle Tags des Kontos für Vorschläge, häufigste zuerst.
    private(set) var tagVorschlaege: [String] = []
    /// Alle Trades des gewählten Kontos, vor Filtern; ein nachgetragener Stop ersetzt den aus dem Export.
    private(set) var alleTrades: [Trade] = []
    /// Alle gelöschten Pending Orders des gewählten Kontos, vor Filtern.
    private(set) var alleGeloeschten: [CancelledOrder] = []
    private(set) var kontoId: Int64?
    var fehler: String?
    /// Stand der Exportdatei für den Claude-Connector, angezeigt im Reiter Claude der Einstellungen.
    private(set) var exportStand = ""
    /// Börsenuhr: Auswahl des Nutzers und die daraus gebaute Uhr (Paket TradingClock, Stand-Doc 15).
    let boersen = Boersenverwaltung()
    /// Review-Ziele des gewählten Kontos, nach Beginn sortiert (Rezept Punkt 6 und 7, Migration v4 aus AP9 #37).
    private(set) var ziele: [Reviewziel] = []
    /// Handelsregeln des gewählten Kontos (P6; Migration v5 aus AP9 #54); ohne gespeicherte Regeln leer.
    private(set) var regeln = Handelsregeln()
    /// Setup-Karten des Playbooks, für alle Konten, nach Name (Doc 18 F3, Doc 23; Migration v7 aus AP9 #59).
    private(set) var playbook: [Setup] = []
    /// Checkliste je Trade des gewählten Kontos (Setup laut Journal und abgehakte Kriterien), Schlüssel ist das Ticket.
    private(set) var checklisten: [String: Checkliste] = [:]
    /// Offene Positionen laut dem jüngsten MT4-Auszug des Kontos (AP9 #50); `nil` ohne MT4-Auszug.
    private(set) var offenerAuszug: (importlauf: Importlauf, positionen: [OpenPosition])?
    /// Kurse offener Trades (P10): Zuordnungen, Beobachter, letzter Stand je Symbol.
    let kurse: Kursdienst
    /// Wirtschaftstermine (Paket TradingCalendar, Stand-Doc 25): nächste Termine und „über Termin gehalten“ (Doc 18 F9).
    let termine = Termindienst()
    /// Nachrichten und Merkliste (Doc 26); Standard aus, nichts davon läuft beim Start.
    let nachrichten: Nachrichtendienst

    // Zustand der Oberfläche
    var bereich: Bereich = .uebersicht
    var zeitraum: Zeitraum = .alle
    var instrument: String?
    /// Gewählter Trade in der Trade-Tabelle (Ticket); auch Ziel für Sprünge aus anderen Ansichten.
    var tradeAuswahl: String?
    /// Zeigt in Trades nur Trades mit diesem Fehlermuster (Sprung von der Fehlermuster-Seite).
    var musterFilter: Fehlermuster?
    /// Zeigt in Trades nur Trades, die über einen Termin ihrer Währung gehalten wurden (Sprung von der Kalender-Seite).
    var nurUeberTermin = false
    /// Tag, den die Tagesseite beim nächsten Erscheinen zeigen soll (Sprung aus dem Ergebnis-Kalender).
    var tagSprung: Journaltag?

    /// EZB-Referenzkurse für die Steuer-Seite (Doc 34). Leer beim Start, damit init keine Datei liest;
    /// `ladeEZBKurse()` liest den Zwischenspeicher und fragt die EZB nur, wenn der Kurs von heute fehlt.
    var ezb: EZBKurse.Stand = .leer

    /// Öffnet das Journal unter `Application Support`; ohne Datenbank bleibt `journal` leer. Ist die Datei
    /// beschädigt oder aus einer neueren Version, steht der Fehler in `startfehler` und das Hauptfenster bietet
    /// den Weg aus der Datei an (AP9 #225); sonst steht er in `fehler`.
    convenience init() {
        let pfad = Result { try Self.datenbankpfad() }
        let geoeffnet = pfad.flatMap { p in Result { try Journal(pfad: p) } }
        self.init(journal: try? geoeffnet.get())
        journalpfad = try? pfad.get()
        if case .failure(let error) = geoeffnet { meldeStartfehler(error) }
    }

    /// Mit Journal von außen. `nebenwirkungen: false` für Tests (App/Tests): kein Export in den Ordner des
    /// Nutzers und kein EZB-Abruf, sonst überschriebe ein Testlauf am Mac die echte Exportdatei.
    init(journal: Journal?, nebenwirkungen: Bool = true, testZeitzone: TimeZone? = nil) {
        self.testZeitzone = testZeitzone
        self.nebenwirkungen = nebenwirkungen
        if nebenwirkungen {
            kurse = Kursdienst()
            nachrichten = Nachrichtendienst()
        } else {
            // Tests (G27, Doc 49): eigene Einstellungen, Schlüsselbund im Arbeitsspeicher, Kursdatei im temporären Ordner.
            let speicher = UserDefaults(suiteName: "TradingBuddyTests.AppModell") ?? .standard
            let schluessel = Schluesselbund(ablage: SpeicherSchluesselablage())
            kurse = Kursdienst(speicher: speicher, schluesselbund: schluessel,
                               verlaufsdatei: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("appt-verlaeufe-\(UUID().uuidString).json"))
            nachrichten = Nachrichtendienst(speicher: speicher, schluesselbund: schluessel)
        }
        if nebenwirkungen { anzeigewaehrung = UserDefaults.standard.string(forKey: Self.anzeigewaehrungSchluessel) }
        if let journal { uebernimm(journal) }
        if nebenwirkungen {
            Task { await ladeEZBKurse() }
            // Lange Laufzeit ohne Import oder Kontowechsel: alle 5 Minuten prüfen (X6, Doc 49). Die Sperre in
            // `ladeEZBKurseFallsVeraltet` lässt ohne Fehler höchstens einen Abruf je Stunde zu, nach einem Fehler
            // (Erststart ohne Netz) einen je 5 Minuten (H8, Doc 55).
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5 * 60))
                    guard let self else { return }
                    self.ladeEZBKurseFallsVeraltet()
                }
            }
        }
    }

    /// `false` nur in Tests: kein Export, kein EZB-Abruf.
    private let nebenwirkungen: Bool

    /// Hängt ein geöffnetes Journal an: beim Start oder nach dem Weg aus einer beschädigten Datei.
    private func uebernimm(_ journal: Journal) {
        self.journal = journal
        nachrichten.verbinde(journal)
        schliesseAbgelaufeneZiele()
        laden()
        exportiere()
        #if os(macOS)
        if nebenwirkungen { Importordner.geteilt.verbinde(self) } // Import-Ordner beobachten (Doc 45)
        // Tägliche Datensicherung (Tagesseite-Thread, Doc 46): beim Start, dann stündlich prüfen.
        if nebenwirkungen { Task { [weak self] in await Sicherungsdienst.laufe { self?.journal } } }
        #endif
    }

    // MARK: Start mit beschädigter Journal-Datei (AP9 #225)

    /// Pfad der Journal-Datei; `nil` in Tests mit Journal von außen.
    private(set) var journalpfad: String?
    /// Fehler der Journal-Datei beim Start, für den das Hauptfenster einen Ausweg anbietet.
    private(set) var startfehler: JournalFehler?
    /// Meldung nach dem Ausweg, mit dem Ort der beiseitegelegten Datei.
    var startmeldung: (text: String, beiseite: URL?)?

    /// Nur für App-Tests: Start wie `init()`, aber mit eigenem Pfad und ohne Nebenwirkungen.
    convenience init(testpfad pfad: String) {
        let geoeffnet = Result { try Journal(pfad: pfad) }
        self.init(journal: try? geoeffnet.get(), nebenwirkungen: false)
        journalpfad = pfad
        if case .failure(let error) = geoeffnet { meldeStartfehler(error) }
    }

    private func meldeStartfehler(_ error: Error) {
        if let datei = error as? JournalFehler, Startwiederherstellung.bietetAusweg(datei) {
            startfehler = datei
        } else {
            fehler = error.localizedDescription
        }
    }

    /// Spielt die Sicherung in ein neues Journal ein; die alte Datei wird beiseitegelegt, nicht gelöscht.
    func startAusSicherung(_ angebot: Startwiederherstellung.Angebot, ordner: URL?) throws {
        guard let journalpfad, journal == nil else { return }
        let ergebnis = try Startwiederherstellung.ausSicherung(pfad: journalpfad, angebot: angebot, ordner: ordner)
        var text = String(localized: "Sicherung „\(angebot.datei.lastPathComponent)“ zurückgespielt.")
        #if os(macOS)
        if nebenwirkungen { text += " " + Self.holeBilder(neben: angebot.datei, ordner: ordner) }
        #endif
        startfehler = nil
        uebernimm(ergebnis.journal)
        startmeldung = (Self.mitAblage(text, ergebnis.beiseite), ergebnis.beiseite)
    }

    /// Beginnt mit einem leeren Journal; die alte Datei wird beiseitegelegt, nicht gelöscht.
    func startNeu() throws {
        guard let journalpfad, journal == nil else { return }
        let ergebnis = try Startwiederherstellung.neuBeginnen(pfad: journalpfad)
        startfehler = nil
        uebernimm(ergebnis.journal)
        startmeldung = (Self.mitAblage(String(localized: "Neues, leeres Journal angelegt."), ergebnis.beiseite),
                        ergebnis.beiseite)
    }

    private static func mitAblage(_ text: String, _ beiseite: URL?) -> String {
        guard let beiseite else { return text }
        return text + " " + String(localized: "Die alte Datei liegt unter \(beiseite.path).")
    }

    #if os(macOS)
    /// Fehlende Screenshots aus dem Bilder-Spiegel neben der Sicherung zurückholen (wie Sicherungsdienst).
    private static func holeBilder(neben datei: URL, ordner: URL?) -> String {
        let zugriff = ordner?.startAccessingSecurityScopedResource() ?? false
        defer { if zugriff { ordner?.stopAccessingSecurityScopedResource() } }
        let spiegel = datei.deletingLastPathComponent()
            .appending(path: Sicherungsdienst.bilderUnterordner, directoryHint: .isDirectory)
        let bilder = (try? Bilderordner.ordner()).map { Sicherungsdienst.kopiereFehlende(von: spiegel, nach: $0) } ?? 0
        Bilderordner.schuetzeBestand()
        return String(localized: "\(bilder) Bilder zurückgeholt.")
    }
    #endif
    /// Wie oft `exportiere()` angestoßen wurde, auch ohne Nebenwirkungen; Tests prüfen damit, dass Änderungen
    /// den Export für den Connector auslösen (G28, Doc 49).
    private(set) var exportAnstoesse = 0

    /// EZB-Kurse nachladen, wenn der letzte erfolgreiche Abruf älter als einen Tag ist (lange Laufzeit) oder der
    /// Start ohne Netz war; höchstens ein Versuch je Stunde. `EZBKurse.laden()` fragt die EZB nur außerhalb der
    /// Ruhezeit, sonst liest es nur den Zwischenspeicher (Zweiter Gegencheck X6).
    private func ladeEZBKurseFallsVeraltet() {
        guard nebenwirkungen else { return }
        let jetzt = Date()
        // Nach einem Fehler (etwa Erststart ohne Netz) schon nach 5 Minuten neu versuchen, sonst stündlich.
        let sperre: TimeInterval = ezb.fehler != nil ? 5 * 60 : 60 * 60
        if let versuch = ezbVersuch, jetzt.timeIntervalSince(versuch) < sperre { return }
        let veraltet = ezb.abgerufen.map { jetzt.timeIntervalSince($0) > 24 * 60 * 60 } ?? true
        guard veraltet || ezb.fehler != nil else { return }
        Task { await ladeEZBKurse() }
    }

    /// Tageskerzen für Frag Henry „Wert analysieren“ (Doc 38, Paket A5): eigene Symbole, offene Positionen und
    /// Merklisten-Symbole; hier höchstens einmal je Stunde angestoßen, der Kursdienst lädt höchstens alle 20 Stunden
    /// und nur bei eingeschalteten Kursen, sonst gilt sein Zwischenspeicher.
    private var verlaufVersuch: Date?
    private func ladeKursverlaeufe() {
        guard nebenwirkungen else { return }
        let jetzt = Date()
        if let versuch = verlaufVersuch, jetzt.timeIntervalSince(versuch) < 60 * 60 { return }
        verlaufVersuch = jetzt
        let merkliste = nachrichten.aktiveEintraege.filter { $0.art == .symbol }.map(\.begriff)
        let symbole = alleTrades.map(\.symbol) + offenePositionen.map(\.symbol) + merkliste
        Task {
            let vorher = kurse.verlaeufe
            await kurse.ladeVerlaeufe(fuer: symbole)
            // Neue Tageskerzen sofort in die Exportdatei, sonst sieht der Connector sie erst beim nächsten Anlass
            // (Doc 59, B6).
            if kurse.verlaeufe != vorher { exportiere() }
        }
    }

    var konto: Konto? { konten.first { $0.id == kontoId } ?? konten.first }
    var waehrung: String { konto?.waehrung ?? "EUR" }
    private let testZeitzone: TimeZone?
    /// Wochentag, Stunde und Tagesgrenze in der Zeitzone des Nutzers.
    var zeitzone: TimeZone { testZeitzone ?? .current }

    private var kalender: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        return kalender
    }

    /// Trades nach Zeitraum und Instrument in ihrer Originalwährung: Grundlage der Listen (Einzelbeträge, W1).
    var trades: [Trade] { gefiltert(alleTrades) }

    /// Trades nach Zeitraum und Instrument in der Anzeigewährung: Grundlage der Summen auf Übersicht, Kennzahlen und
    /// Fehlermuster (Doc 40 W3, B4). Trades ohne Kurs am Schlusstag fehlen hier, `waehrungsstand` zählt sie.
    var angeglicheneTrades: [Trade] { gefiltert(anzeige.trades) }

    /// Alle Trades des Kontos in der Anzeigewährung, nur nach Instrument gefiltert: Grundlage des Ergebnis-Kalenders,
    /// der selbst durch die Monate blättert. Trades ohne Kurs am Schlusstag fehlen wie in `angeglicheneTrades`.
    var kalenderTrades: [Trade] {
        guard let instrument else { return anzeige.trades }
        return anzeige.trades.filter { $0.symbol == instrument }
    }

    /// IDs der Trades im Ergebnis-Kalender, bei denen ein Fehlermuster anschlägt (alle Monate, nicht nur der Zeitraum).
    var kalenderTradesMitMuster: Set<String> {
        Set(Fehlermuster.pruefe(kalenderTrades, geloeschteOrders: geloeschteOrders, zeitzone: zeitzone,
                                schwellen: musterSchwellen).flatMap(\.trades))
    }

    /// Trades nach Zeitraum und Instrument in Kontowährung: Grundlage der Regel-Seite (Grenzen stehen in Kontowährung).
    var kontoTrades: [Trade] { gefiltert(angleich.trades) }

    private func gefiltert(_ trades: [Trade]) -> [Trade] {
        let kalender = self.kalender
        return trades.filter { trade in
            if let instrument, trade.symbol != instrument { return false }
            if case .monat(let monat) = zeitraum, monatsanfang(trade.schlusstag(kalender), kalender) != monat { return false }
            return true
        }
    }

    /// Alle Trades des Kontos in Kontowährung (Kern 0.19.0 `Waehrungsangleich`; Tim 02.10.2026 13:07 UTC „Umrechnen“):
    /// Fremdwährungsbeträge zum EZB-Referenzkurs am Schlusstag (Näherung, wie die Steuer-Orientierung), Trades ohne
    /// Kurs bleiben außen vor. Neu gerechnet nach jedem Trade-Aufbau und nach jedem EZB-Abruf.
    private(set) var angleich = Waehrungsangleich([], kontowaehrung: "EUR", kurse: nil)

    /// Dieselben Trades in der Anzeigewährung (Entscheidung B4: „Standard Euro, andere Währung per Klick“); gleich
    /// `angleich`, solange die Anzeigewährung die Kontowährung ist. Regeln und Prop-Firm bleiben in Kontowährung.
    private(set) var anzeige = Waehrungsangleich([], kontowaehrung: "EUR", kurse: nil)

    /// Gewählte Anzeigewährung der Summen; `nil` heißt Kontowährung. Gilt für alle Konten, bleibt über Neustarts.
    var anzeigewaehrung: String? {
        didSet {
            guard anzeigewaehrung != oldValue else { return }
            if nebenwirkungen { UserDefaults.standard.set(anzeigewaehrung, forKey: Self.anzeigewaehrungSchluessel) }
            gleicheWaehrungenAn()
            // Der Export trägt die Anzeigewährung für Claude (AP12, Vierter Gegencheck H21).
            exportiere()
        }
    }
    static let anzeigewaehrungSchluessel = "anzeige.waehrung"

    /// Währung, in der Übersicht, Kennzahlen und Fehlermuster summieren.
    var summenwaehrung: String { (anzeigewaehrung ?? waehrung).uppercased() }

    /// Wählbare Anzeigewährungen: die gängigen EZB-Währungen und die Währungen der eigenen Trades.
    var anzeigewaehrungen: [String] {
        Set(["EUR", "USD", "GBP", "CHF", "JPY"] + angleich.fremdwaehrungen + [waehrung.uppercased()])
            .subtracting(["USDT"]).sorted()
    }

    private func gleicheWaehrungenAn() {
        let konto = waehrung.uppercased()
        // Geplantes Risiko steht in Kontowährung (Kern, Hauptthread 05.10.2026): erst nach dem Angleich passt es zu
        // Fremdwährungs-Trades, deshalb hier auf alle Trades, in `alleTrades` nur auf die in Kontowährung.
        let quellen = risikoquellen
        let basis = alleTrades.map { $0.mitGeplantemRisiko(quellen.wirksam(ticket: $0.id)?.betrag) }
        angleich = Waehrungsangleich(basis, kontowaehrung: konto, kurse: ezb.kurse)
        let ziel = summenwaehrung
        guard ziel != konto else { anzeige = angleich; return }
        // Trades ohne eigene Währung stehen in Kontowährung; ausdrücklich setzen, sonst gälten sie als Zielwährung.
        let mitWaehrung = basis.map { trade in
            var t = trade
            t.waehrung = trade.waehrung(kontowaehrung: konto)
            return t
        }
        var umgerechnet = Waehrungsangleich(mitWaehrung, kontowaehrung: ziel, kurse: ezb.kurse)
        // Das geplante Risiko folgt dem Ergebnis in die Anzeigewährung; ohne Kurs entfällt es, R bleibt dann leer.
        let satz = ezb.kurse ?? Referenzkurse(kurse: [:])
        umgerechnet.trades = umgerechnet.trades.map { t in
            guard let risiko = t.geplantesRisiko else { return t }
            return t.mitGeplantemRisiko(satz.umrechnen(risiko, von: konto, nach: ziel, am: t.closeTime))
        }
        anzeige = umgerechnet
    }

    /// Was die Umrechnung im gewählten Zeitraum getan hat: Grundlage des Mischwährungshinweises.
    struct Waehrungsstand: Equatable {
        var umgerechnet = 0
        var ohneKurs = 0
        var waehrungen: [String] = []
        var leer: Bool { umgerechnet == 0 && ohneKurs == 0 }
    }

    var waehrungsstand: Waehrungsstand {
        let ohne = Set(anzeige.ohneKurs.map(\.id))
        var stand = Waehrungsstand(waehrungen: anzeige.fremdwaehrungen)
        for trade in trades {
            if anzeige.umgerechnet.contains(trade.id) { stand.umgerechnet += 1 }
            if ohne.contains(trade.id) { stand.ohneKurs += 1 }
        }
        return stand
    }

    /// Gelöschte Pending Orders im gewählten Zeitraum (für die Stornoquote), Instrumentfilter gilt mit.
    var geloeschteOrders: Int {
        let kalender = self.kalender
        return alleGeloeschten.filter { order in
            if let instrument, order.symbol != instrument { return false }
            if case .monat(let monat) = zeitraum, monatsanfang(order.cancelledAt, kalender) != monat { return false }
            return true
        }.count
    }

    /// Monate mit Trades, neuester zuerst.
    var monate: [Date] {
        let kalender = self.kalender
        return Set(alleTrades.map { monatsanfang($0.schlusstag(kalender), kalender) }).sorted(by: >)
    }

    var symbole: [String] { Set(alleTrades.map(\.symbol)).sorted() }

    var kennzahlen: Kennzahlen { Kennzahlen(trades: angeglicheneTrades) }
    var kapitalverlauf: Kapitalverlauf { Kapitalverlauf(trades: angeglicheneTrades) }
    var befunde: [Befund] {
        Fehlermuster.pruefe(angeglicheneTrades, geloeschteOrders: geloeschteOrders, zeitzone: zeitzone,
                            schwellen: musterSchwellen)
    }

    /// Trades nach Schlusszeit, neueste zuerst.
    var tradesNeuesteZuerst: [Trade] {
        trades.sorted { ($0.closeTime, $0.id) > ($1.closeTime, $1.id) }
    }

    /// Welche Fehlermuster bei welchem Trade angeschlagen haben.
    var musterJeTrade: [String: [Fehlermuster]] {
        var ergebnis: [String: [Fehlermuster]] = [:]
        for befund in befunde {
            for id in befund.trades { ergebnis[id, default: []].append(befund.muster) }
        }
        return ergebnis
    }

    /// Trades ohne Stop im Export: ohne Stop kein R.
    var ohneStop: Int { trades.filter { $0.stopLoss == nil }.count }

    /// Die Trades eines Befunds, neueste zuerst.
    func trades(zu befund: Befund) -> [Trade] {
        let ids = Set(befund.trades)
        return tradesNeuesteZuerst.filter { ids.contains($0.id) }
    }

    /// Springt in die Trade-Tabelle, gefiltert auf ein Fehlermuster, und wählt einen Trade für den Inspektor.
    func zeigeTrade(_ id: String, muster: Fehlermuster? = nil) {
        musterFilter = muster
        tradeAuswahl = id
        bereich = .trades
    }

    /// Springt in die Trade-Tabelle, gefiltert auf ein Fehlermuster.
    func zeigeTrades(mit muster: Fehlermuster) {
        musterFilter = muster
        bereich = .trades
    }

    func waehleKonto(_ id: Int64?) {
        kontoId = id
        // Filter gehören zum Konto: ein Monat oder Symbol des alten Kontos zeigt im neuen nur „Noch keine Trades“
        // (Gegencheck A3, Doc 36).
        zeitraum = .alle
        instrument = nil
        musterFilter = nil
        laden()
    }

    func laden() {
        guard let journal else { return }
        ladeEZBKurseFallsVeraltet()
        do {
            konten = try journal.konten()
            importe = try konten.flatMap { konto in
                try journal.importe(konto: konto).map { lauf in
                    try ImportEintrag(id: lauf.id ?? 0, konto: konto, lauf: lauf,
                                      hinweise: journal.importhinweise(importlauf: lauf))
                }
            }
            if let konto {
                positionen = try journal.geschlossenePositionen(konto: konto)
                kontobewegungen = try journal.kontobewegungen(konto: konto)
                journaleintraege = try journal.journaleintraege(konto: konto)
                alleGeloeschten = try journal.geloeschteOrders(konto: konto)
                ziele = try journal.ziele(konto: konto)
                regeln = try journal.handelsregeln(konto: konto)
                checklisten = try journal.checklisten(konto: konto)
                offenerAuszug = try journal.offenePositionenLetzterAuszug(konto: konto)
                risikoquellen = try journal.risikoquellen(konto: konto)
                tradeTags = try journal.tags(konto: konto)
                tagVorschlaege = try journal.alleTags(konto: konto)
                markterwartungen = try journal.markterwartungen(konto: konto)
                offeneHandpositionen = try journal.offeneManuelleTrades(konto: konto)
            } else {
                positionen = []
                kontobewegungen = Kontobewegungen()
                journaleintraege = [:]
                alleGeloeschten = []
                ziele = []
                regeln = Handelsregeln()
                checklisten = [:]
                offenerAuszug = nil
                risikoquellen = Risikoquellen()
                tradeTags = [:]
                tagVorschlaege = []
                markterwartungen = [:]
                offeneHandpositionen = []
            }
            playbook = try journal.playbook()
            positionsbildung = Positionsbildung.bilde(kontobewegungen.ausfuehrungen,
                                                      kapitalmassnahmen: kontobewegungen.kapitalmassnahmen)
            aktualisiereTrades()
            kurse.beobachte(offenePositionen.map(\.symbol))
            ladeKursverlaeufe()
            if nebenwirkungen { Minutenautomatik.geteilt.stosseAn(self) } // Start und Import (Kurse, 05.10.2026)
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Offene Positionen des Kontos: MT4-Auszug zuerst, dann offene Käufe aus der Positionsbildung
    /// (Trade Republic, Scalable, Krypto), dann offen eingetragene Hand-Trades (Tim 06.10.2026: auch in der Karte).
    /// Auszug und Käufe sind nur eine Momentaufnahme aus dem letzten Import (Stand-Doc 20).
    var offenePositionen: [OffenePosition] {
        let mt4 = (offenerAuszug?.positionen ?? []).map { OffenePosition(herkunft: .mt4($0)) }
        let kaeufe = positionsbildung.offen.map { OffenePosition(herkunft: .kauf($0)) }
        let hand = offeneHandpositionen.map { OffenePosition(herkunft: .hand($0)) }
        return mt4 + kaeufe + hand
    }

    /// Baut die Trades aus den Positionen (MetaTrader, XTB) und aus der Positionsbildung (Trade Republic,
    /// Scalable); ein Stop aus dem Journal ersetzt den aus dem Export (Entscheidung 8: der Export kennt
    /// nur den letzten Stand), damit Risiko und R stimmen. Das wirksame geplante Risiko (Trade vor Setup vor
    /// Konto) geht vor allen Auswertungen mit; ein echter Stop hat im Kern Vorrang (Doc 02 Nr. 64).
    private func aktualisiereTrades() {
        let quellen = risikoquellen
        let erwartungen = markterwartungen
        let konto = waehrung.uppercased()
        // Fremdwährungs-Trades bekommen das geplante Risiko (Kontowährung) erst im Angleich; roh gäbe es ein falsches R.
        alleTrades = (positionen.map(Trade.init) + positionsbildung.trades).map { trade in
            var mitJournal = trade.mitJournal(journaleintraege[trade.id])
            if mitJournal.markterwartung == nil { mitJournal.markterwartung = erwartungen[trade.id] }
            guard mitJournal.waehrung(kontowaehrung: konto) == konto else { return mitJournal }
            return mitJournal.mitGeplantemRisiko(quellen.wirksam(ticket: trade.id)?.betrag)
        }
        gleicheWaehrungenAn()
    }

    /// Wirksames geplantes Risiko des Trades mit Herkunft, `nil` ohne Angabe.
    func wirksamesRisiko(_ trade: Trade) -> WirksamesRisiko? {
        risikoquellen.wirksam(ticket: trade.id)
    }

    /// Schwellen der Fehlermuster: Die eigene Grenze „Höchstens Trades je Tag“ gilt für „Überhandeln“.
    var musterSchwellen: Fehlermuster.Schwellen {
        var schwellen = Fehlermuster.Schwellen()
        schwellen.maxTradesProTag = regeln.maxTradesJeTag
        return schwellen
    }

    /// Regel eines Fehlermusters im Klartext; „Überhandeln“ nennt die eigene Grenze, wenn es eine gibt.
    func regeltext(_ muster: Fehlermuster) -> String {
        if muster == .ueberhandeln, let grenze = regeln.maxTradesJeTag {
            return String(localized: "Tage mit mehr als \(grenze) Trades (eigene Regel).")
        }
        return muster.regel
    }

    // MARK: Geplantes Risiko und Tags (Doc 02 Nr. 64 und 65)

    /// Setzt das Standard-Risiko des gewählten Kontos; `nil` entfernt es.
    func setzeStandardRisiko(_ betrag: Decimal?) throws {
        guard let journal, let konto else { return }
        try journal.setzeStandardRisiko(betrag, konto: konto)
        risikoNeuLesen()
    }

    /// Setzt das Standard-Risiko einer Setup-Karte; `nil` entfernt es.
    func setzeStandardRisiko(_ betrag: Decimal?, setupId: Int64) throws {
        guard let journal else { return }
        try journal.setzeStandardRisiko(betrag, setupId: setupId)
        risikoNeuLesen()
    }

    private func risikoNeuLesen() {
        guard let journal, let konto else { return }
        do {
            risikoquellen = try journal.risikoquellen(konto: konto)
            aktualisiereTrades()
            exportiere()
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Ersetzt die Tags eines Trades im gewählten Konto.
    func setzeTags(_ tags: [String], trade: Trade) {
        guard let journal, let konto else { return }
        do {
            try journal.setzeTags(tags, konto: konto, ticket: trade.id)
            tradeTags = try journal.tags(konto: konto)
            tagVorschlaege = try journal.alleTags(konto: konto)
            exportiere()
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Stop, wie er im Export steht, auch wenn im Journal ein anderer nachgetragen ist.
    func stopLautExport(_ trade: Trade) -> Decimal? {
        positionen.first { $0.ticket == trade.id }?.stopLoss
    }

    /// Der Journaleintrag zum Trade, sonst ein leerer für dieses Konto; `nil` ohne Konto.
    func journaleintrag(_ trade: Trade) -> Journaleintrag? {
        if let vorhanden = journaleintraege[trade.id] { return vorhanden }
        guard let kontoId = konto?.id else { return nil }
        return Journaleintrag(kontoId: kontoId, ticket: trade.id)
    }

    /// Ob der Notiz-Editor speichern muss. Der Vergleich mit `journaleintraege` gilt nur fürs gewählte Konto; gehört
    /// der Eintrag nach einem Kontowechsel zu einem anderen Konto, wird immer gespeichert, sonst bliebe dort eine
    /// geleerte Notiz stehen (Codex-Fix-Prüfung zu B2, 04.10.2026).
    func journalGeaendert(_ eintrag: Journaleintrag) -> Bool {
        guard eintrag.kontoId == konto?.id else { return true }
        return !eintrag.gleicheAngaben(wie: journaleintraege[eintrag.ticket])
    }

    /// Speichert den Eintrag; ein Eintrag ohne Angaben wird gelöscht. Trades und Kennzahlen ziehen sofort mit.
    /// Geschrieben wird immer beim Konto des Eintrags: Nach einem Kontowechsel speichert der Notiz-Editor beim
    /// Verlassen noch den Eintrag des alten Kontos, und eine gleiche Ticketnummer im neuen Konto bleibt unberührt
    /// (Codex-Review 04.10.2026, B2).
    func speichereJournal(_ eintrag: Journaleintrag) {
        guard let journal, let ziel = konten.first(where: { $0.id == eintrag.kontoId }) else { return }
        guard let konto, konto.id == ziel.id else {
            do {
                if eintrag.ohneAngaben {
                    try journal.loescheJournal(konto: ziel, ticket: eintrag.ticket)
                } else {
                    var neu = eintrag
                    neu.geaendertAm = Date()
                    try journal.speichereJournal(neu)
                }
                exportiere()
            } catch {
                fehler = error.localizedDescription
            }
            return
        }
        do {
            if eintrag.ohneAngaben {
                try journal.loescheJournal(konto: konto, ticket: eintrag.ticket)
                journaleintraege[eintrag.ticket] = nil
            } else {
                var neu = eintrag
                neu.geaendertAm = Date()
                try journal.speichereJournal(neu)
                journaleintraege[eintrag.ticket] = neu
            }
            // Die Checkliste hängt am Setup-Namen des Journals: nach Änderung oder Löschung neu lesen,
            // sonst rechnet die Playbook-Auswertung mit dem alten Setup (Gegencheck A1, Doc 36).
            checklisten = try journal.checklisten(konto: konto)
            // Risiko am Trade und Setup-Name bestimmen das wirksame Risiko (Doc 02 Nr. 64).
            risikoquellen = try journal.risikoquellen(konto: konto)
            aktualisiereTrades()
            // Der Connector bekommt Stop und Journalangaben im selben Stand wie die App.
            exportiere()
        } catch {
            fehler = error.localizedDescription
        }
    }

    // MARK: Review-Ziele (Eingabe nur in der App; Export und Connector lesen sie, Entscheidung 28)

    /// Offene Ziele, frühester Beginn zuerst.
    var offeneZiele: [Reviewziel] { ziele.filter { $0.status == .offen } }

    /// Legt ein Ziel an, ohne `konto` für das gewählte Konto; die Speicherung lehnt leeren Text und einen Zeitraum
    /// ohne Dauer ab. Ein Entwurf merkt sich sein Konto: Nach einem Kontowechsel landet das Ziel trotzdem dort
    /// (Codex-Review 04.10.2026, M5), die Liste des gerade gewählten Kontos bleibt unberührt.
    func legeZielAn(_ ziel: Reviewziel, konto kontoId: Int64? = nil) throws {
        let zielkonto = kontoId == nil ? konto : konten.first { $0.id == kontoId }
        guard let journal, let zielkonto else { throw Zielfehler.keinKonto }
        try journal.legeZielAn(ziel, konto: zielkonto)
        if zielkonto.id == konto?.id { ziele = try journal.ziele(konto: zielkonto) }
        exportiere()
    }

    /// Hakt ein Ziel ab oder öffnet es wieder (dann ohne Ergebnis).
    func setzeZielstatus(_ ziel: Reviewziel, _ status: Reviewziel.Status, ergebnis: String?) {
        guard let journal, let konto, let id = ziel.id else { return }
        do {
            try journal.setzeZielstatus(id: id, status, ergebnis: status == .offen ? nil : ergebnis)
            ziele = try journal.ziele(konto: konto)
            exportiere()
        } catch {
            fehler = Zielfehler.text(error)
        }
    }

    func loescheZiel(_ ziel: Reviewziel) {
        guard let journal, let konto, let id = ziel.id else { return }
        do {
            try journal.loescheZiel(id: id)
            ziele = try journal.ziele(konto: konto)
            exportiere()
        } catch {
            fehler = Zielfehler.text(error)
        }
    }

    /// Setzt offene Ziele mit abgelaufener Frist in allen Konten auf „verfehlt“ (AP9 #75, Tim 02.10.2026) und lädt die
    /// Ziele des Kontos neu, wenn sich etwas geändert hat. Die App ruft das beim Start und beim Öffnen der Seite „Ziele“.
    func schliesseAbgelaufeneZiele() {
        guard let journal else { return }
        do {
            let geschlossen = try journal.schliesseAbgelaufeneZiele()
            guard !geschlossen.isEmpty, let konto else { return }
            ziele = try journal.ziele(konto: konto)
            exportiere()
        } catch {
            fehler = Zielfehler.text(error)
        }
    }

    // MARK: Terminkalender (Paket TradingCalendar, Stand-Doc 25; Doc 18 F9 „über Termin gehalten“)

    /// Währungen aus den Symbolen der Trades und offenen Positionen des Kontos; leer, wenn kein Symbol passt.
    var meineWaehrungen: Set<String> {
        Termindienst.waehrungen(symbole: alleTrades.map(\.symbol) + offenePositionen.map(\.symbol))
    }

    /// Termine in der Haltezeit je Trade des gewählten Zeitraums; nur Trades mit mindestens einem Termin.
    var termineJeTrade: [String: [Termin]] {
        var ergebnis: [String: [Termin]] = [:]
        for trade in trades {
            let gefunden = termine.termine(fuer: trade)
            if !gefunden.isEmpty { ergebnis[trade.id] = gefunden }
        }
        return ergebnis
    }

    // MARK: Steuer-Orientierung (Doc 22; E2, S1, S2 vom 02.10.2026; Orientierung, keine Steuerberechnung)
    /// Kalenderjahre mit Verkäufen (Trades nach Schlusszeit, Krypto-Ausführungen) in deutscher Zeit, jüngstes zuerst.
    var steuerjahre: [Int] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = Steuerorientierung.deutscheZeit
        var jahre = Set(alleTrades.map { kalender.component(.year, from: $0.closeTime) })
        for ausfuehrung in kontobewegungen.ausfuehrungen where ausfuehrung.produktart == .krypto {
            jahre.insert(kalender.component(.year, from: ausfuehrung.zeit))
        }
        return jahre.sorted(by: >)
    }

    /// Summen je Verlusttopf im Jahr über alle Trades des Kontos, unabhängig vom Zeitraum-Filter.
    func topfsummen(jahr: Int) -> [Topfsumme] {
        Steuerorientierung.toepfe(alleTrades, kontowaehrung: waehrung, jahr: jahr, kurse: ezb.kurse)
    }

    /// Lädt die EZB-Kurse, wenn der Zwischenspeicher nicht aktuell ist; ohne Netz bleibt er gültig.
    /// Läuft gerade ein Abruf, und wann der letzte Versuch war (Zweiter Gegencheck X6).
    private var ezbLaedt = false
    private var ezbVersuch: Date?

    func ladeEZBKurse() async {
        if ezbLaedt { return }
        ezbLaedt = true
        ezbVersuch = Date()
        defer { ezbLaedt = false }
        // Zwischenspeicher sofort nutzen: sonst fehlen Fremdwährungs-Trades bis zum Ende des Netzabrufs in den Summen.
        if ezb.quelle == .keine {
            ezb = EZBKurse().zwischenspeicher()
            gleicheWaehrungenAn()
        }
        ezb = await EZBKurse().laden()
        gleicheWaehrungenAn()
        // Der Export trägt die EZB-Kurse sofort (AP12, 02.10.2026 14:44 UTC), nicht erst nach dem nächsten Import.
        exportiere()
    }

    /// Ob das Konto Krypto-Ausführungen hat; dann zeigt die Steuerseite die Haltefrist.
    var hatKrypto: Bool { kontobewegungen.ausfuehrungen.contains { $0.produktart == .krypto } }

    /// Währungen der Trades, die von der Kontowährung abweichen (Kern 0.17.0 `Trade.waehrung`, Gegencheck A4),
    /// alphabetisch; leer bei MetaTrader und XTB, deren Trades in Kontowährung stehen.
    var fremdwaehrungen: [String] { angleich.fremdwaehrungen }

    /// Krypto-Haltefrist im Jahr: FIFO je Coin über alle Ausführungen des Kontos.
    func kryptoJahr(_ jahr: Int) -> KryptoHaltefrist.Jahr {
        KryptoHaltefrist.jahr(jahr, ausfuehrungen: kontobewegungen.ausfuehrungen, importhinweise: importhinweiseDesKontos,
                             kurse: ezb.kurse)
    }

    /// Nicht sicher zugeordnete Zeilen aller Importe des gewählten Kontos.
    var importhinweiseDesKontos: [Importhinweis] {
        importe.filter { $0.konto.id == konto?.id }.flatMap(\.hinweise)
    }

    /// Führt der Broker die Steuer ab? Trade Republic und Scalable Capital ja (Steuerbescheinigung maßgeblich),
    /// MetaTrader, XTB und Krypto-Börsen nein (R5, Doc 11 Abschnitt 3); sonst unbekannt.
    var brokerFuehrtSteuerAb: Bool? {
        guard let konto else { return nil }
        switch konto.broker {
        case "Trade Republic", "Scalable Capital": return true
        case "XTB": return false
        default: break
        }
        let importer = importe.filter { $0.konto.id == konto.id }.map(\.lauf.importer)
        if importer.contains(Journal.mt4Importer) { return false }
        let kryptoBoersen = ["kraken", "binance", "coinbase", "bitpanda"]
        if kryptoBoersen.contains(where: { konto.broker.lowercased().contains($0) }) { return false }
        return nil
    }

    // MARK: Handelsregeln (P6; geprüft nach dem Import, nicht live, Entscheidung E3)

    /// Tickets, die im Journal als „nicht regeltreu“ stehen; sie zählen als Verstoß der Art `manuell`.
    var manuellVerletzt: Set<String> {
        Set(journaleintraege.values.filter { $0.regeltreue == false }.map(\.ticket))
    }

    /// Verstöße gegen die eigenen Regeln, immer über alle Trades des Kontos (in Kontowährung, W3) und nicht über
    /// den Filter: „Trades je Tag“ und „Tagesverlust“ zählen den ganzen Tag, nicht nur ein Instrument. Trades ohne
    /// EZB-Kurs zählen bei den Zählregeln mit, ihre Beträge nicht (G1, TradingCore 0.22.0).
    var verstoesse: [Regelverstoss] {
        Regelpruefung.pruefe(angleich, regeln: regeln, zeitzone: zeitzone, manuell: manuellVerletzt)
    }

    /// Der letzte Handelstag im gewählten Zeitraum, Grundlage der Regel-Ampel.
    var letzterTagesstand: Regelpruefung.Tagesstand? {
        let kalender = self.kalender
        let staende = Regelpruefung.tagesstaende(angleich, regeln: regeln, zeitzone: zeitzone, manuell: manuellVerletzt)
        return staende.last { stand in
            if case .monat(let monat) = zeitraum { return monatsanfang(stand.tag, kalender) == monat }
            return true
        }
    }

    /// Trades, die an diesem Kalendertag (Zeitzone des Nutzers) eröffnet wurden, in Kontowährung wie die Grenzen der
    /// Regeln (Dritter Gegencheck G12: die Risiko-Ampel las sonst Fremdwährung als Kontowährung).
    func trades(eroeffnetAm tag: Date) -> [Trade] {
        let kalender = self.kalender
        return angleich.trades.filter { kalender.startOfDay(for: $0.openTime) == tag }
    }

    /// Trades mit Verstoß gegen eigene oder Prop-Firm-Regeln, dieselbe Quelle wie Disziplin und Monatsbericht.
    /// Fehlermuster wie „ohne Stop“ sind keine Regelverstöße (Codex-Review 04.10.2026, B1).
    var verletzteTrades: Set<String> {
        Set(verstoesse.map(\.trade)).union(propFirmErgebnis?.verstoesse.map(\.trade) ?? [])
    }

    /// Disziplin-Kurve der gefilterten Trades; die Verstöße stammen aus der Prüfung über alle Trades,
    /// Prop-Firm-Verstöße zählen mit (TradingCore 0.16.0; ein Trade mit beiden Arten zählt einmal). Trades ohne
    /// EZB-Kurs zählen bei Anzahl und Verstößen mit, ohne Betrag (Kern 0.24.0, Doc 52 H4); Disziplin sortiert selbst.
    var disziplin: Disziplin {
        Disziplin(trades: kontoTrades + gefiltert(angleich.ohneKurs), verstoesse: verstoesse,
                  propFirm: propFirmErgebnis?.verstoesse ?? [], ohneBetrag: angleich.ohneKursIDs)
    }

    /// Stand der Challenge über alle Trades des Kontos; `nil` ohne Prop-Firm-Regeln.
    var propFirmErgebnis: PropFirmPruefung.Ergebnis? {
        regeln.propFirm.map { PropFirmPruefung.pruefe(angleich.trades, regeln: $0) }
    }

    /// Ersetzt die Regeln des gewählten Kontos. Die Speicherung lehnt Grenzen ab, die keine sind
    /// (Beträge und Anzahlen nicht über 0, leerer Prop-Firm-Name, unbekannte Zeitzone); leere Regeln löschen die Zeile.
    func speichereRegeln(_ neu: Handelsregeln) throws {
        guard let journal, let konto else { throw Regelfehler.keinKonto }
        try journal.setzeHandelsregeln(neu, konto: konto)
        regeln = try journal.handelsregeln(konto: konto)
        exportiere() // Regeln stehen seit #100 im Export (Zweiter Gegencheck X4)
    }

    /// Setups, die schon einmal eingetragen wurden, alphabetisch.
    var bekannteSetups: [String] { Set(journaleintraege.values.compactMap(\.setup)).sorted() }

    // MARK: Playbook (Doc 18 F3, Doc 23): Karten je Setup, Checkliste je Trade

    /// Die Karte zum Setup-Namen aus dem Journal; `nil` ohne Namen oder ohne Karte dieses Namens.
    func setupKarte(_ name: String?) -> Setup? {
        guard let name else { return nil }
        return playbook.first { $0.name == name }
    }

    /// Trades des gewählten Kontos mit diesem Setup laut Journal.
    func anzahlTrades(setup name: String) -> Int {
        journaleintraege.values.filter { $0.setup == name }.count
    }

    /// Legt eine Karte an oder ändert sie; die Speicherung lehnt leere Namen, doppelte Namen und leere Kriterien ab.
    /// Beim Umbenennen ziehen die Journaleinträge mit.
    @discardableResult
    func speichereSetup(_ setup: Setup) throws -> Setup {
        guard let journal else { throw SpeicherFehler.ungueltigerWert(String(localized: "Kein Journal geöffnet.")) }
        let gespeichert = try journal.speichereSetup(setup)
        playbook = try journal.playbook()
        if let konto {
            journaleintraege = try journal.journaleintraege(konto: konto)
            checklisten = try journal.checklisten(konto: konto)
            aktualisiereTrades()
        }
        // Der Connector liest Setup-Namen aus dem Export (Gegencheck A6).
        exportiere()
        return gespeichert
    }

    /// Löscht die Karte; Setup-Namen im Journal und die Häkchen bleiben stehen.
    func loescheSetup(_ setup: Setup) throws {
        guard let journal, let id = setup.id else { return }
        try journal.loescheSetup(id: id)
        playbook = try journal.playbook()
    }

    /// Speichert die abgehakten Kriterien eines Trades; die Speicherung schreibt dabei das Setup ins Journal.
    func setzeCheckliste(_ checkliste: Checkliste, trade: Trade) {
        guard let journal, let konto else { return }
        do {
            try journal.setzeCheckliste(checkliste, konto: konto, ticket: trade.id)
            checklisten[trade.id] = checkliste
            var eintrag = journaleintraege[trade.id] ?? Journaleintrag(kontoId: konto.id ?? 0, ticket: trade.id)
            eintrag.setup = checkliste.setup
            eintrag.geaendertAm = Date()
            journaleintraege[trade.id] = eintrag
            aktualisiereTrades()
            exportiere()
        } catch {
            fehler = Regelfehler.text(error)
        }
    }

    /// Kennzahlen je Setup und Kriterium für die gefilterten Trades (TradingCore 0.11.0).
    var playbookAuswertung: PlaybookAuswertung {
        PlaybookAuswertung(trades: angeglicheneTrades, playbook: playbook, checklisten: checklisten)
    }

    /// Das Konto zu Broker und Nummer, falls schon angelegt.
    func bekanntesKonto(broker: String, kontonummer: String) -> Konto? {
        konten.first { $0.broker == broker && $0.kontonummer == kontonummer }
    }

    /// Konten eines Brokers, etwa zur Auswahl im Import-Blatt, wenn die Datei kein Konto nennt.
    func konten(broker: String) -> [Konto] {
        konten.filter { $0.broker == broker }
    }

    /// Tickets, die für dieses Konto schon gespeichert sind (Zahl „Schon bekannt“ im Import-Blatt).
    func bekannteTickets(broker: String, kontonummer: String) -> Set<String> {
        guard let journal,
              let konto = bekanntesKonto(broker: broker, kontonummer: kontonummer),
              let positionen = try? journal.geschlossenePositionen(konto: konto)
        else { return [] }
        return Set(positionen.map(\.ticket))
    }

    /// Vorgangskennungen (Ausführungen, Geldbewegungen, Kapitalmaßnahmen), die für dieses Konto
    /// schon gespeichert sind: Grundlage der Zahl „Schon bekannt“ bei Trade Republic und Scalable.
    func bekannteVorgaenge(broker: String, kontonummer: String) -> Set<String> {
        guard let journal,
              let konto = bekanntesKonto(broker: broker, kontonummer: kontonummer),
              let bewegungen = try? journal.kontobewegungen(konto: konto)
        else { return [] }
        return Set(bewegungen.ausfuehrungen.map(\.id) + bewegungen.geldbewegungen.map(\.id)
            + bewegungen.kapitalmassnahmen.map(\.id))
    }

    /// Speichert einen MetaTrader-4-Auszug (HTML); Konto und Nummer stehen in der Datei.
    func importiereMT4(daten: Data, dateiname: String, serverZeitzone: TimeZone,
                       waehrung: String) throws -> ImportErgebnis {
        guard let journal else { throw CocoaError(.fileNoSuchFile) }
        let ergebnis = try journal.importiereMT4(datei: daten, dateiname: dateiname,
                                                 serverZeitzone: serverZeitzone, kontowaehrung: waehrung)
        nachImport(ergebnis)
        return ergebnis
    }

    /// Speichert einen Transaktionsexport von Trade Republic oder Scalable (CSV). Die Datei nennt kein
    /// Konto, deshalb wählt der Nutzer es im Blatt; Doppelte erkennt die Speicherung über Konto und
    /// Vorgangskennung, ein anderes Konto ergäbe also doppelte Vorgänge.
    /// `produktartVorgabe` gilt nur für Zeilen, deren Art der Importer nicht kennt (Scalable; TradingStore #96).
    func importiereCSV(daten: Data, dateiname: String, kontonummer: String, kontoname: String,
                       waehrung: String, zeitzone: TimeZone, produktartVorgabe: Produktart? = nil) throws -> ImportErgebnis {
        guard let journal else { throw CocoaError(.fileNoSuchFile) }
        let ergebnis = try journal.importiereCSV(datei: daten, dateiname: dateiname, kontonummer: kontonummer,
                                                 kontoname: kontoname, kontowaehrung: waehrung, zeitzone: zeitzone,
                                                 produktartVorgabe: produktartVorgabe)
        nachImport(ergebnis)
        return ergebnis
    }

    /// Speichert eine XTB-Kontohistorie (Excel). Kontonummer und Währung stehen meist im Kopf der Datei;
    /// die App gibt sie nur mit, wenn sie dort fehlen (bei Widerspruch bricht die Speicherung ab).
    func importiereXTB(daten: Data, dateiname: String, kontonummer: String?, kontoname: String?,
                       waehrung: String?, zeitzone: TimeZone, produktartVorgabe: Produktart? = nil) throws -> ImportErgebnis {
        guard let journal else { throw CocoaError(.fileNoSuchFile) }
        let ergebnis = try journal.importiereXTB(datei: daten, dateiname: dateiname, kontonummer: kontonummer,
                                                 kontoname: kontoname, kontowaehrung: waehrung, zeitzone: zeitzone,
                                                 produktartVorgabe: produktartVorgabe)
        nachImport(ergebnis)
        return ergebnis
    }

    /// MetaTrader-5-Handelsbericht (Doc 48); Nummer und Währung nur, wenn der Bericht sie nicht nennt.
    func importiereMT5(daten: Data, dateiname: String, kontonummer: String?, kontoname: String?,
                       waehrung: String?, serverZeitzone: TimeZone) throws -> ImportErgebnis {
        guard let journal else { throw CocoaError(.fileNoSuchFile) }
        let ergebnis = try journal.importiereMT5(datei: daten, dateiname: dateiname, kontonummer: kontonummer,
                                                 kontoname: kontoname, kontowaehrung: waehrung,
                                                 serverZeitzone: serverZeitzone)
        nachImport(ergebnis)
        return ergebnis
    }

    // MARK: Produktart nachtragen (TradingStore #96)

    /// Wertpapiere des gewählten Kontos ohne Produktart (Scalable, XTB), nach Name.
    func produktartLuecken() -> [ProduktartLuecke] {
        guard let journal, let konto else { return [] }
        return (try? journal.symboleOhneProduktart(konto: konto)) ?? []
    }

    /// Setzt die Art für alle Zeilen des Kontos zu diesem Symbol, lädt neu und schreibt den Export.
    @discardableResult
    func setzeProduktart(symbol: String, _ art: Produktart) throws -> Int {
        guard let journal, let konto else { throw Regelfehler.keinKonto }
        let anzahl = try journal.setzeProduktart(konto: konto, symbol: symbol, art)
        laden()
        exportiere()
        return anzahl
    }

    /// Lädt neu und wechselt zum Konto des Imports, damit die neuen Trades sofort zu sehen sind.
    private func nachImport(_ ergebnis: ImportErgebnis) {
        laden()
        if let konto = importe.first(where: { $0.lauf.id == ergebnis.importlaufId })?.konto,
           let id = konto.id, id != self.konto?.id {
            waehleKonto(id) // setzt Filter zurück wie der Kontowechsel in der Seitenleiste (Zweiter Gegencheck X3)
        }
        exportiere()
    }

    /// Schreibt die Exportdatei für den Claude-Connector neu (AP12), nur am Mac.
    func exportiere() {
        exportAnstoesse += 1
        guard nebenwirkungen else { return }
        #if os(macOS)
        exportStand = ExportOrdner.schreibe(journal, zeitzone: zeitzone)
        #endif
    }

    /// `Application Support/Trading Buddy/journal.sqlite`, in der Sandbox im Container der App.
    static func datenbankpfad() throws -> String {
        let ordner = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Trading Buddy", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner.appendingPathComponent("journal.sqlite").path
    }
}

/// Eine offene Position für die Karte „Offene Positionen“: aus dem MT4-Auszug oder ein offener Kauf.
struct OffenePosition: Identifiable {
    enum Herkunft {
        case mt4(OpenPosition)
        case kauf(Ausfuehrung)
        /// Von Hand eingetragen und noch offen; Ergebnis in Kontowährung.
        case hand(OffenerHandtrade)
    }

    let herkunft: Herkunft

    var id: String {
        switch herkunft {
        case .mt4(let p): p.ticket
        case .kauf(let k): k.id
        case .hand(let h): "hand-\(h.ticket)" // eigener Raum: ein Hand-Trade im MT4-Konto trägt kein MT4-Ticket
        }
    }

    /// Symbol in Journal-Schreibweise, Schlüssel für die Kurszuordnung (wie `Trade.symbol`).
    var symbol: String {
        switch herkunft {
        case .mt4(let p): p.symbol
        case .kauf(let k): k.name.isEmpty ? k.kennung : k.name
        case .hand(let h): h.trade.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var seite: Side {
        switch herkunft {
        case .mt4(let p): p.side
        case .kauf: .buy
        case .hand(let h): h.trade.markterwartung // Richtung nach Markterwartung, wie Trade.richtung
        }
    }

    /// Lots (MetaTrader) oder Stück.
    var menge: Decimal {
        switch herkunft {
        case .mt4(let p): p.lots
        case .kauf(let k): k.menge
        case .hand(let h): h.trade.groesse
        }
    }

    var einstieg: Decimal {
        switch herkunft {
        case .mt4(let p): p.openPrice
        case .kauf(let k): k.menge == 0 ? k.preis : -k.betrag / k.menge
        case .hand(let h): h.trade.einstiegskurs
        }
    }

    /// Kurs zum Zeitpunkt des Auszugs; nur MetaTrader kennt ihn.
    var auszugskurs: Decimal? {
        if case .mt4(let p) = herkunft { return p.currentPrice }
        return nil
    }

    /// Schwebendes Ergebnis laut Auszug (Kursergebnis plus Kommission und Swap); nur MetaTrader.
    var ergebnisLautAuszug: Decimal? {
        if case .mt4(let p) = herkunft { return p.profit + p.commission + p.swap }
        return nil
    }

    /// Währung des Ergebnisses: `nil` heißt Kontowährung (MetaTrader), sonst die der Ausführung.
    var waehrung: String? {
        if case .kauf(let k) = herkunft { return k.waehrung }
        return nil
    }

    func bewertung(kurs: Decimal) -> OffeneBewertung.Ergebnis {
        switch herkunft {
        case .mt4(let p): OffeneBewertung.bewerte(p, kurs: kurs)
        case .kauf(let k): OffeneBewertung.bewerte(k, kurs: kurs)
        case .hand(let h): OffeneBewertung.bewerte(Self.bewertungsposition(h), kurs: kurs)
        }
    }

    /// Hand-Trade als Position mit Wert je Kurspunkt = Größe, wie `ManuellerTrade.ergebnis` rechnet
    /// ((Kurs − Einstieg) × Größe): Bezugskurs 1.000 Punkte im Gewinn, Ergebnis dort 1.000 × Größe. Ein Schein
    /// bleibt ohne Wert (Ergebnis 0): Der Kurs gehört zum Basiswert, nicht zum Schein.
    static func bewertungsposition(_ h: OffenerHandtrade) -> OpenPosition {
        var p = h.trade.offenePosition(ticket: h.ticket)
        guard !h.trade.schein else { return p }
        let bezug: Decimal = 1000
        p.currentPrice = p.side == .buy ? p.openPrice + bezug : p.openPrice - bezug
        p.profit = bezug * p.lots
        return p
    }
}

private func monatsanfang(_ datum: Date, _ kalender: Calendar) -> Date {
    kalender.dateInterval(of: .month, for: datum)?.start ?? datum
}

extension Journaleintrag {
    /// Kein Feld ausgefüllt: so ein Eintrag wird nicht gespeichert, ein vorhandener gelöscht.
    var ohneAngaben: Bool {
        setup == nil && regeltreue == nil && zustand == nil && marktumfeld == nil && grund == nil && stopEinstieg == nil
            && risikoEinstieg == nil && zeiteinheit == nil
    }

    /// Dieselben Angaben wie `andere` (ohne Zeitstempel); `nil` zählt wie ein Eintrag ohne Angaben.
    func gleicheAngaben(wie andere: Journaleintrag?) -> Bool {
        guard let andere else { return ohneAngaben }
        return setup == andere.setup && regeltreue == andere.regeltreue && zustand == andere.zustand
            && marktumfeld == andere.marktumfeld && grund == andere.grund && stopEinstieg == andere.stopEinstieg
            && risikoEinstieg == andere.risikoEinstieg && zeiteinheit == andere.zeiteinheit
    }

    /// Leerraum an den Rändern weg, leere Texte werden `nil`.
    var bereinigt: Journaleintrag {
        var kopie = self
        kopie.setup = Self.text(setup)
        kopie.marktumfeld = Self.text(marktumfeld)
        kopie.grund = Self.text(grund)
        kopie.zeiteinheit = Self.text(zeiteinheit)
        // Die Speicherung lehnt 0 und negative Beträge ab; ein geleertes oder unsinniges Feld heißt „keine Angabe“.
        if let risiko = risikoEinstieg, risiko <= 0 { kopie.risikoEinstieg = nil }
        return kopie
    }

    private static func text(_ wert: String?) -> String? {
        guard let wert else { return nil }
        let getrimmt = wert.trimmingCharacters(in: .whitespacesAndNewlines)
        return getrimmt.isEmpty ? nil : getrimmt
    }
}

extension Fehlermuster {
    var titel: String {
        switch self {
        case .revancheTrade: String(localized: "Revanche-Trade")
        case .ueberhandeln: String(localized: "Überhandeln")
        case .stopNichtEingehalten: String(localized: "Stop nicht eingehalten")
        case .gewinneZuFrueh: String(localized: "Gewinne zu früh")
        case .verliererLaufenLassen: String(localized: "Verlierer laufen lassen")
        case .verbilligen: String(localized: "Verbilligen")
        case .ohneStop: String(localized: "Ohne Stop")
        case .schwankendeGroesse: String(localized: "Schwankende Größe")
        case .groesseNachGewinnserie: String(localized: "Größe nach Gewinnserie")
        case .staendigesUmplanen: String(localized: "Ständiges Umplanen")
        }
    }

    /// Kurzform für Chips in Tabellen und Listen; der volle Titel steht im Tooltip.
    var kurz: String {
        switch self {
        case .revancheTrade: String(localized: "Revanche")
        case .ueberhandeln: String(localized: "Überhandelt")
        case .stopNichtEingehalten: String(localized: "Stop gerissen")
        case .gewinneZuFrueh: String(localized: "Zu früh raus")
        case .verliererLaufenLassen: String(localized: "Laufen lassen")
        case .verbilligen: String(localized: "Verbilligt")
        case .ohneStop: String(localized: "Ohne Stop")
        case .schwankendeGroesse: String(localized: "Größe schwankt")
        case .groesseNachGewinnserie: String(localized: "Größe nach Serie")
        case .staendigesUmplanen: String(localized: "Umgeplant")
        }
    }

    /// Die Regel im Klartext, mit den Standardschwellen.
    var regel: String {
        switch self {
        case .revancheTrade: String(localized: "Eröffnet bis 15 Minuten nach einem Verlust, mit mehr Lots als üblich.")
        case .ueberhandeln: String(localized: "Tage mit mehr als Median plus 2 Trades, ab zehn Handelstagen; darunter nur mit eigener Grenze.")
        case .stopNichtEingehalten: String(localized: "Verlust größer als 1,2 R.")
        case .gewinneZuFrueh: String(localized: "Gewinner, die weniger als die Hälfte des Wegs zum Ziel mitgenommen haben.")
        case .verliererLaufenLassen: String(localized: "Verlierer im Schnitt mehr als 1,5-mal so lange gehalten wie Gewinner.")
        case .verbilligen: String(localized: "Nachkauf in gleicher Richtung zu schlechterem Kurs, während die erste Position offen ist.")
        case .ohneStop: String(localized: "Trade ohne Stop-Loss.")
        case .schwankendeGroesse: String(localized: "Risiko je Trade stark gestreut (Variationskoeffizient über 0,5).")
        case .groesseNachGewinnserie: String(localized: "Nach zwei Gewinnen in Folge mehr als 1,5-mal das übliche Risiko.")
        case .staendigesUmplanen: String(localized: "Mehr als die Hälfte der Pending Orders gelöscht.")
        }
    }
}
