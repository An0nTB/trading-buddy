import Foundation
import TradingCore
import TradingStore

/// Speichern aus dem Formular „Trade eintragen“ und Import der Journal-Sicherung. Die eine Stelle, an der die
/// Oberfläche die Speicherung (TradingStore, AP9 #276) aufruft.
extension AppModell {
    /// Broker neuer Konten für Handeinträge; Konten heißen nach ihrer Bezeichnung (Broker + Nummer = Name).
    static let handBroker = "Von Hand"

    /// Speichert den Trade samt Angaben im gewählten oder in einem neuen Konto für Handeinträge,
    /// lädt neu und wechselt zum Konto des Trades. Gibt das Ticket zurück.
    @discardableResult
    func speichereManuellenTrade(_ trade: ManuellerTrade, angaben: TradeAngaben, kontowahl: TradeEntwurf.Kontowahl,
                                 neuerKontoname: String, waehrung: String) throws -> String {
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
        // Konto und Ticket setzt die Speicherung; der Stop steht in der Position, das Risiko im Eintrag.
        let eintrag = Journaleintrag(kontoId: kontoId, ticket: "", setup: angaben.setup,
                                     regeltreue: angaben.regeltreue, grund: angaben.notiz,
                                     risikoEinstieg: trade.risiko.map { abs($0) },
                                     zeiteinheit: angaben.zeiteinheit)
        let position = try journal.speichereManuellenTrade(trade, konto: konto, eintrag: eintrag)
        nachHandeintrag(kontoId: kontoId)
        return position.ticket
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
