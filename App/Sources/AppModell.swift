import Foundation
import Observation
import TradingCore
import TradingStore

/// Zustand der App: das Journal auf der Festplatte und die Trades des gewählten Kontos.
/// Kennzahlen und Fehlermuster rechnet der Rechenkern bei Bedarf neu.
@Observable @MainActor
final class AppModell {
    private(set) var journal: Journal?
    private(set) var konten: [Konto] = []
    private(set) var trades: [Trade] = []
    private(set) var geloeschteOrders = 0
    var kontoId: Int64?
    var fehler: String?

    init() {
        do {
            journal = try Journal(pfad: Self.datenbankpfad())
            laden()
        } catch {
            fehler = error.localizedDescription
        }
    }

    var konto: Konto? { konten.first { $0.id == kontoId } ?? konten.first }
    var waehrung: String { konto?.waehrung ?? "EUR" }
    /// Wochentag, Stunde und Tagesgrenze in der Zeitzone des Nutzers.
    var zeitzone: TimeZone { .current }

    var kennzahlen: Kennzahlen { Kennzahlen(trades: trades) }
    var kapitalverlauf: Kapitalverlauf { Kapitalverlauf(trades: trades) }
    var befunde: [Befund] {
        Fehlermuster.pruefe(trades, geloeschteOrders: geloeschteOrders, zeitzone: zeitzone)
    }

    /// Trades nach Schlusszeit, neueste zuerst.
    var tradesNeuesteZuerst: [Trade] {
        trades.sorted { ($0.closeTime, $0.id) > ($1.closeTime, $1.id) }
    }

    /// Welche Fehlermuster bei welchem Trade angeschlagen haben.
    var musterJeTrade: [String: [Fehlermuster]] {
        var ergebnis: [String: [Fehlermuster]] = [:]
        for befund in befunde {
            for id in befund.trades { ergebnis[id, default: []].append(befund.muster) }
        }
        return ergebnis
    }

    func laden() {
        guard let journal else { return }
        do {
            konten = try journal.konten()
            if let konto {
                trades = try journal.geschlossenePositionen(konto: konto).map { Trade($0) }
                geloeschteOrders = try journal.geloeschteOrders(konto: konto).count
            } else {
                trades = []
                geloeschteOrders = 0
            }
        } catch {
            fehler = error.localizedDescription
        }
    }

    func importiere(daten: Data, dateiname: String, serverZeitzone: TimeZone,
                    waehrung: String) throws -> ImportErgebnis {
        guard let journal else { throw CocoaError(.fileNoSuchFile) }
        let ergebnis = try journal.importiereMT4(datei: daten, dateiname: dateiname,
                                                 serverZeitzone: serverZeitzone, kontowaehrung: waehrung)
        laden()
        return ergebnis
    }

    /// `Application Support/Trading Buddy/journal.sqlite`, in der Sandbox im Container der App.
    private static func datenbankpfad() throws -> String {
        let ordner = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Trading Buddy", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner.appendingPathComponent("journal.sqlite").path
    }
}

extension Fehlermuster {
    var titel: String {
        switch self {
        case .revancheTrade: String(localized: "Revanche-Trade")
        case .ueberhandeln: String(localized: "Überhandeln")
        case .stopNichtEingehalten: String(localized: "Stop nicht eingehalten")
        case .gewinneZuFrueh: String(localized: "Gewinne zu früh")
        case .verliererLaufenLassen: String(localized: "Verlierer laufen lassen")
        case .verbilligen: String(localized: "Verbilligen")
        case .ohneStop: String(localized: "Ohne Stop")
        case .schwankendeGroesse: String(localized: "Schwankende Größe")
        case .groesseNachGewinnserie: String(localized: "Größe nach Gewinnserie")
        case .staendigesUmplanen: String(localized: "Ständiges Umplanen")
        }
    }

    /// Die Regel im Klartext, mit den Standardschwellen.
    var regel: String {
        switch self {
        case .revancheTrade: String(localized: "Eröffnet bis 15 Minuten nach einem Verlust, mit mehr Lots als üblich.")
        case .ueberhandeln: String(localized: "Tage mit mehr als Median plus 2 Trades.")
        case .stopNichtEingehalten: String(localized: "Verlust größer als 1,2 R.")
        case .gewinneZuFrueh: String(localized: "Gewinner, die weniger als die Hälfte des Wegs zum Ziel mitgenommen haben.")
        case .verliererLaufenLassen: String(localized: "Verlierer im Schnitt mehr als 1,5-mal so lange gehalten wie Gewinner.")
        case .verbilligen: String(localized: "Nachkauf in gleicher Richtung zu schlechterem Kurs, während die erste Position offen ist.")
        case .ohneStop: String(localized: "Trade ohne Stop-Loss.")
        case .schwankendeGroesse: String(localized: "Risiko je Trade stark gestreut (Variationskoeffizient über 0,5).")
        case .groesseNachGewinnserie: String(localized: "Nach zwei Gewinnen in Folge mehr als 1,5-mal das übliche Risiko.")
        case .staendigesUmplanen: String(localized: "Mehr als die Hälfte der Pending Orders gelöscht.")
        }
    }
}
