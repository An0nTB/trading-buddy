import Foundation
import TradingCore

/// Aufteilung nach eigenen Journalangaben (Setup, Regeltreue, Zustand). Liegt im Connector,
/// weil der Rechenkern die Angaben nicht am Trade führt; gerechnet wird mit `Kennzahlen`.
public enum Journalgruppe: String, Sendable, CaseIterable {
    case setup, regeltreue, zustand

    var name: String {
        switch self {
        case .setup: "Setup"
        case .regeltreue: "Regeltreue"
        case .zustand: "Zustand"
        }
    }

    /// Gruppenname eines Trades; Trades ohne Angabe landen in „ohne Angabe“.
    func schluessel(_ angaben: Journalangaben?) -> String {
        switch self {
        case .setup: angaben?.setup ?? Journalgruppe.ohneAngabe
        case .regeltreue: angaben?.regeltreue.map { $0 ? "nach Regeln" : "Regel gebrochen" } ?? Journalgruppe.ohneAngabe
        case .zustand: angaben?.zustand.map { "\($0) von 5" } ?? Journalgruppe.ohneAngabe
        }
    }

    static let ohneAngabe = "ohne Angabe"
}

/// Was `hole_aufschluesselung` als `dimension` annimmt: Merkmale des Rechenkerns oder des Journals.
public enum Aufschluesselung: Sendable, Equatable {
    case kern(Aufteilung)
    case journal(Journalgruppe)

    public init?(rawValue: String) {
        if let a = Aufteilung(rawValue: rawValue) {
            self = .kern(a)
        } else if let j = Journalgruppe(rawValue: rawValue) {
            self = .journal(j)
        } else {
            return nil
        }
    }

    public static var alleWerte: [String] {
        Aufteilung.allCases.map(\.rawValue) + Journalgruppe.allCases.map(\.rawValue)
    }
}

extension Anfrage {
    /// Journalangaben eines Trades dieses Kontos.
    public func journal(_ trade: Trade) -> Journalangaben? { konto.journal[trade.id] }

    /// Kennzahlen je Gruppe; „ohne Angabe“ zuletzt, sonst alphabetisch.
    func gruppen(_ trades: [Trade], nach gruppe: Journalgruppe) -> [(name: String, kennzahlen: Kennzahlen)] {
        Dictionary(grouping: trades) { gruppe.schluessel(journal($0)) }
            .map { (name: $0.key, kennzahlen: Kennzahlen(trades: $0.value)) }
            .sorted { a, b in
                if (a.name == Journalgruppe.ohneAngabe) != (b.name == Journalgruppe.ohneAngabe) {
                    return b.name == Journalgruppe.ohneAngabe
                }
                return a.name < b.name
            }
    }

    /// Wie viele Trades eine Angabe haben: (Setup, Regeltreue, Zustand, Grund).
    func journalabdeckung(_ trades: [Trade]) -> (setup: Int, regeltreue: Int, zustand: Int, grund: Int) {
        let angaben = trades.compactMap { journal($0) }
        return (angaben.filter { $0.setup != nil }.count, angaben.filter { $0.regeltreue != nil }.count,
                angaben.filter { $0.zustand != nil }.count, angaben.filter { $0.grund != nil }.count)
    }
}
