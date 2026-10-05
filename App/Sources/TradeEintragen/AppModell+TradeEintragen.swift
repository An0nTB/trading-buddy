import Foundation
import TradingCore
import TradingStore

/// Speichern aus dem Formular „Trade eintragen“ und Import der Journal-Sicherung. Die eine Stelle, an der die
/// Oberfläche die Speicherung (TradingStore, AP9) aufruft.
extension AppModell {
    /// Speichert den Trade samt Angaben im gewählten oder in einem neuen Konto für Handeinträge,
    /// lädt neu und wechselt zum Konto des Trades.
    func speichereManuellenTrade(_ trade: ManuellerTrade, angaben: TradeAngaben, kontowahl: TradeEntwurf.Kontowahl,
                                 neuerKontoname: String, waehrung: String) throws {
        guard journal != nil else { throw TradeEintragenFehler.keinJournal }
        _ = (trade, angaben, kontowahl, neuerKontoname, waehrung)
        // Store-API folgt aus AP9 (speichereManuellenTrade, manuellesKonto); bis dahin nicht speicherbar.
        throw TradeEintragenFehler.speicherungFolgt
    }

    /// Liest und speichert eine Journal-Sicherung in ein Euro-Konto mit diesem Namen.
    func importiereJournalSicherung(daten: Data, dateiname: String, kontoname: String) throws -> ImportErgebnis {
        guard journal != nil else { throw TradeEintragenFehler.keinJournal }
        _ = (daten, dateiname, kontoname)
        // Store-API folgt aus AP9 (importiereJournalSicherung); bis dahin nicht speicherbar.
        throw TradeEintragenFehler.speicherungFolgt
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
    case speicherungFolgt

    var errorDescription: String? {
        switch self {
        case .keinJournal: String(localized: "Die Journal-Datei ist nicht geöffnet.")
        case .speicherungFolgt: String(localized: "Speichern folgt mit dem nächsten Stand der Speicherung.")
        }
    }
}
