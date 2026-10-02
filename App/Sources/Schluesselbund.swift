import Foundation
import Security
import TradingQuotes

/// Alpaca-Schlüssel im Schlüsselbund der App (P10, Stand-Doc 20: Schlüssel nie in Dateien, Eingabe in den
/// Einstellungen). Ein Eintrag als generisches Passwort, Dienst und Konto fest. Dazu Textschlüssel anderer
/// Dienste (Marketaux, Doc 26). Die Ablage ist austauschbar (Paket A7): Ohne Angabe der Schlüsselbund des
/// Systems, in den App-Tests `SpeicherSchluesselablage`. Die statischen Kurzformen nutzen immer das System.
struct Schluesselbund: AlpacaSchluesselquelle {
    static let dienst = "de.timbock.journal.alpaca"
    static let konto = "alpaca"
    static let dienstMarketaux = "de.timbock.journal.marketaux"
    static let kontoText = "token"

    let ablage: any Schluesselablage

    init(ablage: any Schluesselablage = SystemSchluesselablage()) {
        self.ablage = ablage
    }

    func alpacaSchluessel() async throws -> AlpacaSchluessel? {
        try lies()
    }

    /// Der gespeicherte Schlüssel; `nil`, wenn keiner eingetragen ist.
    func lies() throws -> AlpacaSchluessel? {
        guard let daten = try ablage.lies(dienst: Self.dienst, konto: Self.konto) else { return nil }
        let eintrag = try JSONDecoder().decode(Eintrag.self, from: daten)
        return AlpacaSchluessel(schluesselID: eintrag.id, geheimnis: eintrag.geheimnis)
    }

    /// Ersetzt den gespeicherten Schlüssel; die Ablage des Systems aktualisiert erst und legt nur ohne Eintrag neu an.
    func speichere(_ schluessel: AlpacaSchluessel) throws {
        let daten = try JSONEncoder().encode(Eintrag(id: schluessel.schluesselID, geheimnis: schluessel.geheimnis))
        try ablage.speichere(daten, dienst: Self.dienst, konto: Self.konto)
    }

    func loesche() throws {
        try ablage.loesche(dienst: Self.dienst, konto: Self.konto)
    }

    func vorhanden() -> Bool {
        ((try? lies()) ?? nil) != nil
    }

    // MARK: Textschlüssel anderer Dienste (Marketaux-Token für die Nachrichten, Doc 26)

    /// Ein einzelner Schlüsseltext je Dienst; `nil`, wenn keiner eingetragen ist.
    func liesText(dienst: String) throws -> String? {
        try ablage.lies(dienst: dienst, konto: Self.kontoText).flatMap { String(data: $0, encoding: .utf8) }
    }

    func speichereText(_ wert: String, dienst: String) throws {
        try ablage.speichere(Data(wert.utf8), dienst: dienst, konto: Self.kontoText)
    }

    func loescheText(dienst: String) throws {
        try ablage.loesche(dienst: dienst, konto: Self.kontoText)
    }

    func textVorhanden(dienst: String) -> Bool {
        ((try? liesText(dienst: dienst)) ?? nil) != nil
    }

    // MARK: Kurzformen für die Ansichten, immer mit dem Schlüsselbund des Systems

    static func lies() throws -> AlpacaSchluessel? { try Schluesselbund().lies() }
    static func speichere(_ schluessel: AlpacaSchluessel) throws { try Schluesselbund().speichere(schluessel) }
    static func loesche() throws { try Schluesselbund().loesche() }
    static func vorhanden() -> Bool { Schluesselbund().vorhanden() }
    static func liesText(dienst: String) throws -> String? { try Schluesselbund().liesText(dienst: dienst) }
    static func speichereText(_ wert: String, dienst: String) throws {
        try Schluesselbund().speichereText(wert, dienst: dienst)
    }
    static func loescheText(dienst: String) throws { try Schluesselbund().loescheText(dienst: dienst) }
    static func textVorhanden(dienst: String) -> Bool { Schluesselbund().textVorhanden(dienst: dienst) }

    private struct Eintrag: Codable {
        var id: String
        var geheimnis: String
    }

    enum Fehler: Error {
        case schluesselbund(OSStatus)

        var text: String {
            switch self {
            case .schluesselbund(let status):
                let grund = (SecCopyErrorMessageString(status, nil) as String?) ?? String(localized: "Fehler \(status)")
                return String(localized: "Schlüsselbund: \(grund)")
            }
        }
    }
}
