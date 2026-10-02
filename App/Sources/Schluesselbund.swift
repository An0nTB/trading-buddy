import Foundation
import Security
import TradingQuotes

/// Alpaca-Schlüssel im Schlüsselbund der App (P10, Stand-Doc 20: Schlüssel nie in Dateien, Eingabe in den
/// Einstellungen). Ein Eintrag als generisches Passwort, Dienst und Konto fest; am Mac im Anmelde-Schlüsselbund,
/// am iPhone im geschützten Schlüsselbund der App. Dazu Textschlüssel anderer Dienste (Marketaux, Doc 26).
struct Schluesselbund: AlpacaSchluesselquelle {
    static let dienst = "de.timbock.journal.alpaca"
    static let konto = "alpaca"

    func alpacaSchluessel() async throws -> AlpacaSchluessel? {
        try Self.lies()
    }

    /// Der gespeicherte Schlüssel; `nil`, wenn keiner eingetragen ist.
    static func lies() throws -> AlpacaSchluessel? {
        var abfrage = grundabfrage()
        abfrage[kSecReturnData as String] = true
        abfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        let status = SecItemCopyMatching(abfrage as CFDictionary, &ergebnis)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let daten = ergebnis as? Data else { throw Fehler.schluesselbund(status) }
        let eintrag = try JSONDecoder().decode(Eintrag.self, from: daten)
        return AlpacaSchluessel(schluesselID: eintrag.id, geheimnis: eintrag.geheimnis)
    }

    /// Ersetzt den gespeicherten Schlüssel.
    static func speichere(_ schluessel: AlpacaSchluessel) throws {
        let daten = try JSONEncoder().encode(Eintrag(id: schluessel.schluesselID, geheimnis: schluessel.geheimnis))
        try loesche()
        var eintrag = grundabfrage()
        eintrag[kSecValueData as String] = daten
        let status = SecItemAdd(eintrag as CFDictionary, nil)
        guard status == errSecSuccess else { throw Fehler.schluesselbund(status) }
    }

    static func loesche() throws {
        let status = SecItemDelete(grundabfrage() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Fehler.schluesselbund(status) }
    }

    static func vorhanden() -> Bool {
        ((try? lies()) ?? nil) != nil
    }

    // MARK: Textschlüssel anderer Dienste (Marketaux-Token für die Nachrichten, Doc 26)

    static let dienstMarketaux = "de.timbock.journal.marketaux"
    private static let kontoText = "token"

    /// Ein einzelner Schlüsseltext je Dienst; `nil`, wenn keiner eingetragen ist.
    static func liesText(dienst: String) throws -> String? {
        var abfrage = grundabfrage(dienst: dienst, konto: kontoText)
        abfrage[kSecReturnData as String] = true
        abfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        let status = SecItemCopyMatching(abfrage as CFDictionary, &ergebnis)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let daten = ergebnis as? Data else { throw Fehler.schluesselbund(status) }
        return String(data: daten, encoding: .utf8)
    }

    static func speichereText(_ wert: String, dienst: String) throws {
        try loescheText(dienst: dienst)
        var eintrag = grundabfrage(dienst: dienst, konto: kontoText)
        eintrag[kSecValueData as String] = Data(wert.utf8)
        let status = SecItemAdd(eintrag as CFDictionary, nil)
        guard status == errSecSuccess else { throw Fehler.schluesselbund(status) }
    }

    static func loescheText(dienst: String) throws {
        let status = SecItemDelete(grundabfrage(dienst: dienst, konto: kontoText) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Fehler.schluesselbund(status) }
    }

    static func textVorhanden(dienst: String) -> Bool {
        ((try? liesText(dienst: dienst)) ?? nil) != nil
    }

    private static func grundabfrage(dienst: String = Schluesselbund.dienst,
                                     konto: String = Schluesselbund.konto) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: dienst,
         kSecAttrAccount as String: konto]
    }

    private struct Eintrag: Codable {
        var id: String
        var geheimnis: String
    }

    enum Fehler: Error {
        case schluesselbund(OSStatus)

        var text: String {
            switch self {
            case .schluesselbund(let status):
                let grund = (SecCopyErrorMessageString(status, nil) as String?) ?? "Fehler \(status)"
                return String(localized: "Schlüsselbund: \(grund)")
            }
        }
    }
}
