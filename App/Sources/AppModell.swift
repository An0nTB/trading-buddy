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
    let kurse = Kursdienst()
    /// Wirtschaftstermine (Paket TradingCalendar, Stand-Doc 25): nächste Termine und „über Termin gehalten“ (Doc 18 F9).
    let termine = Termindienst()
    /// Nachrichten und Merkliste (Doc 26); Standard aus, nichts davon läuft beim Start.
    let nachrichten = Nachrichtendienst()

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

    /// EZB-Referenzkurse für die Steuer-Seite (Doc 34). Leer beim Start, damit init keine Datei liest;
    /// `ladeEZBKurse()` liest den Zwischenspeicher und fragt die EZB nur, wenn der Kurs von heute fehlt.
    var ezb: EZBKurse.Stand = .leer

    /// Öffnet das Journal unter `Application Support`; ohne Datenbank bleibt `journal` leer und `fehler` gesetzt.
    convenience init() {
        let geoeffnet = Result { try Journal(pfad: Self.datenbankpfad()) }
        self.init(journal: try? geoeffnet.get())
        if case .failure(let error) = geoeffnet { fehler = error.localizedDescription }
    }

    /// Mit Journal von außen. `nebenwirkungen: false` für Tests (App/Tests): kein Export in den Ordner des
    /// Nutzers und kein EZB-Abruf, sonst überschriebe ein Testlauf am Mac die echte Exportdatei.
    init(journal: Journal?, nebenwirkungen: Bool = true) {
        self.nebenwirkungen = nebenwirkungen
        if nebenwirkungen { anzeigewaehrung = UserDefaults.standard.string(forKey: Self.anzeigewaehrungSchluessel) }
        if let journal {
            self.journal = journal
            nachrichten.verbinde(journal)
            schliesseAbgelaufeneZiele()
            laden()
            exportiere()
        }
        if nebenwirkungen { Task { await ladeEZBKurse() } }
    }

    /// `false` nur in Tests: kein Export, kein EZB-Abruf.
    private let nebenwirkungen: Bool

    /// EZB-Kurse nachladen, wenn der letzte erfolgreiche Abruf älter als einen Tag ist (lange Laufzeit) oder der
    /// Start ohne Netz war; höchstens ein Versuch je Stunde. `EZBKurse.laden()` fragt die EZB nur außerhalb der
    /// Ruhezeit, sonst liest es nur den Zwischenspeicher (Zweiter Gegencheck X6).
    private func ladeEZBKurseFallsVeraltet() {
        guard nebenwirkungen else { return }
        let jetzt = Date()
        if let versuch = ezbVersuch, jetzt.timeIntervalSince(versuch) < 60 * 60 { return }
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
        Task { await kurse.ladeVerlaeufe(fuer: symbole) }
    }

    var konto: Konto? { konten.first { $0.id == kontoId } ?? konten.first }
    var waehrung: String { konto?.waehrung ?? "EUR" }
    /// Wochentag, Stunde und Tagesgrenze in der Zeitzone des Nutzers.
    var zeitzone: TimeZone { .current }

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

    /// Trades nach Zeitraum und Instrument in Kontowährung: Grundlage der Regel-Seite (Grenzen stehen in Kontowährung).
    var kontoTrades: [Trade] { gefiltert(angleich.trades) }

    private func gefiltert(_ trades: [Trade]) -> [Trade] {
        let kalender = self.kalender
        return trades.filter { trade in
            if let instrument, trade.symbol != instrument { return false }
            if case .monat(let monat) = zeitraum, monatsanfang(trade.closeTime, kalender) != monat { return false }
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
        angleich = Waehrungsangleich(alleTrades, kontowaehrung: konto, kurse: ezb.kurse)
        let ziel = summenwaehrung
        guard ziel != konto else { anzeige = angleich; return }
        // Trades ohne eigene Währung stehen in Kontowährung; ausdrücklich setzen, sonst gälten sie als Zielwährung.
        let mitWaehrung = alleTrades.map { trade in
            var t = trade
            t.waehrung = trade.waehrung(kontowaehrung: konto)
            return t
        }
        anzeige = Waehrungsangleich(mitWaehrung, kontowaehrung: ziel, kurse: ezb.kurse)
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
        return Set(alleTrades.map { monatsanfang($0.closeTime, kalender) }).sorted(by: >)
    }

    var symbole: [String] { Set(alleTrades.map(\.symbol)).sorted() }

    var kennzahlen: Kennzahlen { Kennzahlen(trades: angeglicheneTrades) }
    var kapitalverlauf: Kapitalverlauf { Kapitalverlauf(trades: angeglicheneTrades) }
    var befunde: [Befund] {
        Fehlermuster.pruefe(angeglicheneTrades, geloeschteOrders: geloeschteOrders, zeitzone: zeitzone)
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
            } else {
                positionen = []
                kontobewegungen = Kontobewegungen()
                journaleintraege = [:]
                alleGeloeschten = []
                ziele = []
                regeln = Handelsregeln()
                checklisten = [:]
                offenerAuszug = nil
            }
            playbook = try journal.playbook()
            positionsbildung = Positionsbildung.bilde(kontobewegungen.ausfuehrungen,
                                                      kapitalmassnahmen: kontobewegungen.kapitalmassnahmen)
            aktualisiereTrades()
            kurse.beobachte(offenePositionen.map(\.symbol))
            ladeKursverlaeufe()
        } catch {
            fehler = error.localizedDescription
        }
    }

    /// Offene Positionen des Kontos: MT4-Auszug zuerst, dann offene Käufe aus der Positionsbildung
    /// (Trade Republic, Scalable, Krypto). Nur eine Momentaufnahme aus dem letzten Import (Stand-Doc 20).
    var offenePositionen: [OffenePosition] {
        let mt4 = (offenerAuszug?.positionen ?? []).map { OffenePosition(herkunft: .mt4($0)) }
        let kaeufe = positionsbildung.offen.map { OffenePosition(herkunft: .kauf($0)) }
        return mt4 + kaeufe
    }

    /// Baut die Trades aus den Positionen (MetaTrader, XTB) und aus der Positionsbildung (Trade Republic,
    /// Scalable); ein Stop aus dem Journal ersetzt den aus dem Export (Entscheidung 8: der Export kennt
    /// nur den letzten Stand), damit Risiko und R stimmen.
    private func aktualisiereTrades() {
        alleTrades = (positionen.map(Trade.init) + positionsbildung.trades)
            .map { $0.mitJournal(journaleintraege[$0.id]) }
        gleicheWaehrungenAn()
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

    /// Speichert den Eintrag; ein Eintrag ohne Angaben wird gelöscht. Trades und Kennzahlen ziehen sofort mit.
    func speichereJournal(_ eintrag: Journaleintrag) {
        guard let journal, let konto else { return }
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

    /// Legt ein Ziel für das gewählte Konto an; die Speicherung lehnt leeren Text und einen Zeitraum ohne Dauer ab.
    func legeZielAn(_ ziel: Reviewziel) throws {
        guard let journal, let konto else { throw Zielfehler.keinKonto }
        try journal.legeZielAn(ziel, konto: konto)
        ziele = try journal.ziele(konto: konto)
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
    /// den Filter: „Trades je Tag“ und „Tagesverlust“ zählen den ganzen Tag, nicht nur ein Instrument.
    var verstoesse: [Regelverstoss] {
        Regelpruefung.pruefe(angleich.trades, regeln: regeln, zeitzone: zeitzone, manuell: manuellVerletzt)
    }

    /// Der letzte Handelstag im gewählten Zeitraum, Grundlage der Regel-Ampel.
    var letzterTagesstand: Regelpruefung.Tagesstand? {
        let kalender = self.kalender
        let staende = Regelpruefung.tagesstaende(angleich.trades, regeln: regeln, zeitzone: zeitzone, manuell: manuellVerletzt)
        return staende.last { stand in
            if case .monat(let monat) = zeitraum { return monatsanfang(stand.tag, kalender) == monat }
            return true
        }
    }

    /// Trades, die an diesem Kalendertag (Zeitzone des Nutzers) eröffnet wurden.
    func trades(eroeffnetAm tag: Date) -> [Trade] {
        let kalender = self.kalender
        return alleTrades.filter { kalender.startOfDay(for: $0.openTime) == tag }
    }

    /// Disziplin-Kurve der gefilterten Trades; die Verstöße stammen aus der Prüfung über alle Trades,
    /// Prop-Firm-Verstöße zählen mit (TradingCore 0.16.0; ein Trade mit beiden Arten zählt einmal).
    var disziplin: Disziplin {
        Disziplin(trades: kontoTrades, verstoesse: verstoesse, propFirm: propFirmErgebnis?.verstoesse ?? [])
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
        guard nebenwirkungen else { return }
        #if os(macOS)
        exportStand = ExportOrdner.schreibe(journal, zeitzone: zeitzone)
        #endif
    }

    /// `Application Support/Trading Buddy/journal.sqlite`, in der Sandbox im Container der App.
    private static func datenbankpfad() throws -> String {
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
    }

    let herkunft: Herkunft

    var id: String {
        switch herkunft {
        case .mt4(let p): p.ticket
        case .kauf(let k): k.id
        }
    }

    /// Symbol in Journal-Schreibweise, Schlüssel für die Kurszuordnung (wie `Trade.symbol`).
    var symbol: String {
        switch herkunft {
        case .mt4(let p): p.symbol
        case .kauf(let k): k.name.isEmpty ? k.kennung : k.name
        }
    }

    var seite: Side {
        switch herkunft {
        case .mt4(let p): p.side
        case .kauf: .buy
        }
    }

    /// Lots (MetaTrader) oder Stück.
    var menge: Decimal {
        switch herkunft {
        case .mt4(let p): p.lots
        case .kauf(let k): k.menge
        }
    }

    var einstieg: Decimal {
        switch herkunft {
        case .mt4(let p): p.openPrice
        case .kauf(let k): k.menge == 0 ? k.preis : -k.betrag / k.menge
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
        }
    }
}

private func monatsanfang(_ datum: Date, _ kalender: Calendar) -> Date {
    kalender.dateInterval(of: .month, for: datum)?.start ?? datum
}

extension Journaleintrag {
    /// Kein Feld ausgefüllt: so ein Eintrag wird nicht gespeichert, ein vorhandener gelöscht.
    var ohneAngaben: Bool {
        setup == nil && regeltreue == nil && zustand == nil && marktumfeld == nil && grund == nil && stopEinstieg == nil
    }

    /// Dieselben Angaben wie `andere` (ohne Zeitstempel); `nil` zählt wie ein Eintrag ohne Angaben.
    func gleicheAngaben(wie andere: Journaleintrag?) -> Bool {
        guard let andere else { return ohneAngaben }
        return setup == andere.setup && regeltreue == andere.regeltreue && zustand == andere.zustand
            && marktumfeld == andere.marktumfeld && grund == andere.grund && stopEinstieg == andere.stopEinstieg
    }

    /// Leerraum an den Rändern weg, leere Texte werden `nil`.
    var bereinigt: Journaleintrag {
        var kopie = self
        kopie.setup = Self.text(setup)
        kopie.marktumfeld = Self.text(marktumfeld)
        kopie.grund = Self.text(grund)
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
        case .ueberhandeln: String(localized: "Tage mit mehr als Median plus 2 Trades.")
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
