import Foundation

/// Echtgeld- oder Demo-/Paper-Konto (E1, Tim 17.10.2026): XTB-Demo und IBKR-Paper laufen vor Echtgeld, ihre
/// Trades zählen getrennt (Kill-Kriterium, Auswertung). Gespeichert am Konto in TradingStore (Migration v14).
public enum Kontoart: String, Codable, Sendable, CaseIterable {
    case echt
    /// Demo- oder Paper-Konto ohne echtes Geld.
    case demo
}
