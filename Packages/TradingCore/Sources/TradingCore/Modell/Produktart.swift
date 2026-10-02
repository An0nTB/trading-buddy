import Foundation

/// Art des gehandelten Produkts. Beschreibt das Produkt, nicht den Steuertopf:
/// Welche Art in welchen Verlusttopf fällt, entscheidet die Steuer-Orientierung (P3).
/// Kommt aus dem Export, wo der Broker sie nennt; sonst `unbekannt`, damit die App fragen kann.
public enum Produktart: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case aktie
    /// ETF und andere Investmentfonds.
    case fonds
    case anleihe
    /// Börsengehandelte Derivate: Optionsscheine, Knock-outs, Zertifikate, Futures, Optionen.
    case derivat
    /// CFD und Forex beim Broker (MetaTrader, XTB-CFD).
    case cfd
    case krypto
    /// Vom Broker genannt, aber keiner Art oben zuzuordnen.
    case sonstiges
    /// Export nennt keine Art.
    case unbekannt

    /// Bezeichnung in Trade-Republic-Exporten (Spalte `asset_class`).
    /// Werte laut R2-Recherche, an echten Exporten ungeprüft. Leer ergibt `unbekannt`.
    public init(tradeRepublic wert: String) {
        switch wert.uppercased() {
        case "STOCK": self = .aktie
        case "FUND": self = .fonds
        case "BOND": self = .anleihe
        case "DERIVATIVE": self = .derivat
        case "CRYPTO": self = .krypto
        case "": self = .unbekannt
        default: self = .sonstiges
        }
    }
}
