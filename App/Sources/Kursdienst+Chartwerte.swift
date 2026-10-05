import Foundation

/// Eigene Werte für den Kurschart (Tim 05.10.2026); Prüfung der Eingabe in `Chartwerteingabe`.
extension Kursdienst {
    /// Prüft die Eingabe aus dem Kurschart und merkt sich den Wert dauerhaft; doppelte Werte zählen einmal.
    func fuegeChartwertHinzu(_ eingabe: String) -> Chartwerteingabe {
        let ergebnis = Chartwerteingabe.pruefe(eingabe, alpacaSchluessel: schluesselbund.vorhanden())
        if case .wert(let symbol) = ergebnis, !chartwerte.contains(symbol) {
            chartwerte.append(symbol)
            speicher.set(chartwerte, forKey: Self.schluesselChartwerte)
        }
        return ergebnis
    }

    func entferneChartwert(_ symbol: String) {
        chartwerte.removeAll { $0 == symbol }
        speicher.set(chartwerte, forKey: Self.schluesselChartwerte)
    }
}
