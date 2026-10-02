import Foundation
import Security
import Synchronization

/// Wo der Schlüsselbund seine Einträge ablegt (Paket A7, Doc 44): am Gerät der Schlüsselbund des Systems,
/// in den App-Tests ein Speicher im Arbeitsspeicher. Ein Eintrag ist ein generisches Passwort mit Dienst und Konto.
protocol Schluesselablage: Sendable {
    /// Die gespeicherten Daten; `nil`, wenn es keinen Eintrag gibt.
    func lies(dienst: String, konto: String) throws -> Data?
    /// Ersetzt den Eintrag oder legt ihn an.
    func speichere(_ daten: Data, dienst: String, konto: String) throws
    /// Entfernt den Eintrag; ohne Eintrag kein Fehler.
    func loesche(dienst: String, konto: String) throws
}

/// Der Schlüsselbund des Systems: am Mac der Anmelde-Schlüsselbund, am iPhone der geschützte Schlüsselbund der App.
struct SystemSchluesselablage: Schluesselablage {
    func lies(dienst: String, konto: String) throws -> Data? {
        var abfrage = Self.abfrage(dienst: dienst, konto: konto)
        abfrage[kSecReturnData as String] = true
        abfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: CFTypeRef?
        let status = SecItemCopyMatching(abfrage as CFDictionary, &ergebnis)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let daten = ergebnis as? Data else { throw Schluesselbund.Fehler.schluesselbund(status) }
        return daten
    }

    /// Erst aktualisieren, nur ohne Eintrag neu anlegen: Scheitert das Schreiben, bleibt der alte Schlüssel
    /// erhalten (Codex-Review und Gesamt-Gegencheck 02.10.2026).
    func speichere(_ daten: Data, dienst: String, konto: String) throws {
        let abfrage = Self.abfrage(dienst: dienst, konto: konto)
        var status = SecItemUpdate(abfrage as CFDictionary, [kSecValueData as String: daten] as CFDictionary)
        if status == errSecItemNotFound {
            var eintrag = abfrage
            eintrag[kSecValueData as String] = daten
            status = SecItemAdd(eintrag as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Schluesselbund.Fehler.schluesselbund(status) }
    }

    func loesche(dienst: String, konto: String) throws {
        let status = SecItemDelete(Self.abfrage(dienst: dienst, konto: konto) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Schluesselbund.Fehler.schluesselbund(status)
        }
    }

    private static func abfrage(dienst: String, konto: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: dienst,
         kSecAttrAccount as String: konto]
    }
}

/// Fake für die App-Tests: Einträge nur im Arbeitsspeicher, nichts erreicht den echten Schlüsselbund.
/// `fehler` lässt jeden Zugriff mit diesem Status scheitern, etwa `errSecAuthFailed`.
final class SpeicherSchluesselablage: Schluesselablage {
    private let zustand = Mutex<(eintraege: [String: Data], fehler: OSStatus?)>(([:], nil))

    init(_ eintraege: [String: Data] = [:]) {
        zustand.withLock { $0.eintraege = eintraege }
    }

    /// Schlüssel der Einträge: „Dienst|Konto“.
    static func schluessel(dienst: String, konto: String) -> String { dienst + "|" + konto }

    var eintraege: [String: Data] { zustand.withLock { $0.eintraege } }

    func setzeFehler(_ status: OSStatus?) { zustand.withLock { $0.fehler = status } }

    func lies(dienst: String, konto: String) throws -> Data? {
        try zustand.withLock { z in
            if let fehler = z.fehler { throw Schluesselbund.Fehler.schluesselbund(fehler) }
            return z.eintraege[Self.schluessel(dienst: dienst, konto: konto)]
        }
    }

    func speichere(_ daten: Data, dienst: String, konto: String) throws {
        try zustand.withLock { z in
            if let fehler = z.fehler { throw Schluesselbund.Fehler.schluesselbund(fehler) }
            z.eintraege[Self.schluessel(dienst: dienst, konto: konto)] = daten
        }
    }

    func loesche(dienst: String, konto: String) throws {
        try zustand.withLock { z in
            if let fehler = z.fehler { throw Schluesselbund.Fehler.schluesselbund(fehler) }
            z.eintraege[Self.schluessel(dienst: dienst, konto: konto)] = nil
        }
    }
}
