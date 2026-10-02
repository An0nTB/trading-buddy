import Foundation

/// Feste deutsche Texte aus den Paketen (Feiertage, Termine, Hinweise) über den Textkatalog der App
/// übersetzen. Die Pakete bleiben unverändert; ihre festen Texte stehen im Katalog als Schlüssel mit
/// `extractionState: manual`. Unbekannte Texte (eigene Kalender, Broker- oder API-Texte) bleiben, wie sie sind.
extension String {
    var uebersetzt: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }
}
