import Foundation
import TradingCore
import TradingStore

/// Speichern aus dem Formular „Trade eintragen“ und Import der Journal-Sicherung. Die eine Stelle, an der die
/// Oberfläche die Speicherung (TradingStore, AP9 #276) aufruft.
extension AppModell {
    /// Broker neuer Konten für Handeinträge; Konten heißen nach ihrer Bezeichnung (Broker + Nummer = Name).
    static let handBroker = "Von Hand"

    /// Speichert den Trade samt Angaben im gewählten oder in einem neuen Konto für Handeinträge,
    /// lädt neu und wechselt zum Konto des Trades. Mit `ticket` ersetzt er den von Hand eingetragenen Trade
    /// dieses Tickets; übrige Felder seines Journaleintrags (Zustand, Marktumfeld …) bleiben. Ein offener
    /// Trade (`trade.offen`) geht in die offenen Positionen; mit Exit gespeichert, ist er geschlossen.
    /// Gibt das Ticket zurück.
    @discardableResult
    func speichereManuellenTrade(_ trade: ManuellerTrade, angaben: TradeAngaben, kontowahl: TradeEntwurf.Kontowahl,
                                 neuerKontoname: String, waehrung: String, ticket: String? = nil) throws -> String {
        guard let journal else { throw TradeEintragenFehler.keinJournal }
        let konto: Konto
        switch kontowahl {
        case .bestehend(let id):
            guard let gefunden = konten.first(where: { $0.id == id }) else { throw TradeEintragenFehler.kontoFehlt }
            konto = gefunden
        case .neu:
            let name = neuerKontoname.trimmingCharacters(in: .whitespacesAndNewlines)
            konto = try journal.legeKontoAn(broker: Self.handBroker, kontonummer: name, kontoname: name,
                                            waehrung: waehrung)
        }
        guard let kontoId = konto.id else { throw TradeEintragenFehler.kontoFehlt }
        // Konto und Ticket setzt die Speicherung; Position und Journal bekommen denselben Stop.
        var eintrag = ticket.flatMap { bisherigerEintrag(konto: konto, ticket: $0) }
            ?? Journaleintrag(kontoId: kontoId, ticket: "")
        eintrag.setup = angaben.setup
        eintrag.regeltreue = angaben.regeltreue
        eintrag.grund = angaben.notiz
        eintrag.stopEinstieg = trade.stop
        eintrag.risikoEinstieg = angaben.risikoEinstieg.map { abs($0) }
        eintrag.zeiteinheit = angaben.zeiteinheit
        eintrag.geaendertAm = Date()
        let gespeichert = try journal.speichereHandtrade(trade, konto: konto, ticket: ticket, eintrag: eintrag)
        nachHandeintrag(kontoId: kontoId)
        return gespeichert
    }

    /// Journaleintrag eines Tickets: aus dem geladenen Konto, sonst aus der Speicherung.
    private func bisherigerEintrag(konto: Konto, ticket: String) -> Journaleintrag? {
        if konto.id == self.konto?.id, let eintrag = journaleintraege[ticket] { return eintrag }
        return (try? journal?.journaleintraege(konto: konto))?[ticket]
    }

    /// Ob der Trade im gewählten Konto von Hand eingetragen ist (nur solche lassen sich bearbeiten und löschen).
    func istHandtrade(_ trade: Trade) -> Bool {
        guard let journal, let konto else { return false }
        return (try? journal.manuelleTickets(konto: konto))?.contains(trade.id) ?? false
    }

    /// Entwurf zum Bearbeiten eines von Hand eingetragenen Trades im gewählten Konto; `nil` bei importierten.
    func handEntwurf(_ trade: Trade) -> TradeEntwurf? {
        handEntwurf(ticket: trade.id)
    }

    /// Entwurf zum Bearbeiten oder Schließen eines Hand-Trades (offen oder geschlossen) im gewählten Konto.
    func handEntwurf(ticket: String) -> TradeEntwurf? {
        guard let journal, let konto, let kontoId = konto.id,
              let gespeichert = try? journal.manuellerTrade(konto: konto, ticket: ticket)
        else { return nil }
        return TradeEntwurf(bearbeite: gespeichert, eintrag: journaleintraege[ticket], kontoId: kontoId,
                            ticket: ticket)
    }

    /// Offene Hand-Trades des gewählten Kontos, nach Einstieg.
    var offeneHandtrades: [OffenerHandtrade] {
        guard let journal, let konto else { return [] }
        return (try? journal.offeneManuelleTrades(konto: konto)) ?? []
    }

    /// Löscht einen von Hand eingetragenen Trade samt Journaleintrag, Tags und Bildern.
    func loescheHandtrade(_ trade: Trade) throws {
        try loescheHandtrade(ticket: trade.id)
    }

    /// Löscht einen von Hand eingetragenen Trade (offen oder geschlossen) samt Journaleintrag, Tags und Bildern.
    func loescheHandtrade(ticket: String) throws {
        guard let journal else { throw TradeEintragenFehler.keinJournal }
        guard let konto else { throw TradeEintragenFehler.kontoFehlt }
        let bilder = try journal.loescheManuellenTrade(konto: konto, ticket: ticket)
        bilder.forEach(Bilderordner.loesche)
        nachHandeintrag(kontoId: konto.id)
    }

    /// Liest und speichert eine Journal-Sicherung in ein Euro-Konto mit dieser Bezeichnung.
    func importiereJournalSicherung(daten: Data, dateiname: String, kontoname: String) throws -> ImportErgebnis {
        guard let journal else { throw TradeEintragenFehler.keinJournal }
        let ergebnis = try journal.importiereJournalSicherung(datei: daten, dateiname: dateiname,
                                                              kontonummer: kontoname, kontoname: kontoname,
                                                              zeitzone: JournalSicherungVorschau.zeitzone)
        laden() // erst danach kennt `importe` den neuen Lauf und sein Konto
        nachHandeintrag(kontoId: importe.first(where: { $0.lauf.id == ergebnis.importlaufId })?.konto.id)
        return ergebnis
    }

    /// Standard-Risiko für einen neuen Trade (Nr. 64): Setup vor Konto; `nil` ohne Angabe oder bei neuem Konto.
    func standardRisiko(setup: String, kontowahl: TradeEntwurf.Kontowahl) -> (betrag: Decimal, herkunft: Risikoherkunft)? {
        guard let journal else { return nil }
        let name = setup.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let betrag = (try? journal.standardRisikoJeSetup())?[name] {
            return (betrag, .setup)
        }
        guard case .bestehend(let id) = kontowahl, let konto = konten.first(where: { $0.id == id }),
              let betrag = try? journal.standardRisiko(konto: konto)
        else { return nil }
        return (betrag, .konto)
    }

    /// Symbole bisheriger Trades des gewählten Kontos, für die Vorschläge im Feld „Asset“.
    var bekannteSymbole: [String] {
        Array(Set(alleTrades.map(\.symbol))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Wie nach jedem Import: neu laden, zum Konto wechseln, Export für den Connector schreiben.
    func nachHandeintrag(kontoId: Int64?) {
        laden()
        if let kontoId, kontoId != konto?.id {
            waehleKonto(kontoId)
        }
        exportiere()
    }
}

/// Fehler beim Speichern aus dem Formular oder der Journal-Sicherung.
enum TradeEintragenFehler: LocalizedError, Equatable {
    case keinJournal
    case kontoFehlt

    var errorDescription: String? {
        switch self {
        case .keinJournal: String(localized: "Die Journal-Datei ist nicht geöffnet.")
        case .kontoFehlt: String(localized: "Das gewählte Konto gibt es nicht mehr.")
        }
    }
}
