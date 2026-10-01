#if os(macOS)
import Foundation
import TradingCore
import TradingStore

/// Ordner, in den die App Daten für den Claude-Connector schreibt.
/// Der Nutzer wählt ihn einmal; die App merkt sich den Zugriff als
/// Security-scoped Bookmark, damit er nach einem Neustart erhalten bleibt.
enum ExportOrdner {
    static let schluessel = "exportOrdnerLesezeichen"

    /// Merkt sich den Ordner aus dem Auswahldialog.
    static func merke(_ url: URL) throws {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        let daten = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(daten, forKey: schluessel)
    }

    static func gemerkterOrdner() -> URL? {
        guard let daten = UserDefaults.standard.data(forKey: schluessel) else { return nil }
        var veraltet = false
        guard let url = try? URL(
            resolvingBookmarkData: daten, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &veraltet)
        else { return nil }
        if veraltet { try? merke(url) }
        return url
    }

    /// Exportdatei für den Connector aus allen Konten des Journals, mit dem Stop aus dem Journal
    /// wie in der App (`Trade.mitJournal`). Ohne Kontonamen, Rohzeilen und übrige Journalfelder;
    /// von der Kontonummer nur die letzten vier Stellen, damit Claude die Konten unterscheiden kann.
    static func export(_ journal: Journal, zeitzone: TimeZone) throws -> JournalExport {
        let konten = try journal.konten().map { konto in
            let eintraege = try journal.journaleintraege(konto: konto)
            return JournalExport.Kontodaten(
                broker: konto.broker, kontonummer: String(konto.kontonummer.suffix(4)), waehrung: konto.waehrung,
                trades: try journal.geschlossenePositionen(konto: konto).map { Trade($0).mitJournal(eintraege[$0.ticket]) },
                geloeschteOrders: try journal.geloeschteOrders(konto: konto).map(\.cancelledAt))
        }
        return JournalExport(konten: konten, zeitzone: zeitzone)
    }

    /// Schreibt `trading-buddy-export.json` in den gewählten Ordner, nach jedem Import und beim Start.
    /// Gibt den Stand als Text für die Einstellungen zurück.
    @discardableResult
    static func schreibe(_ journal: Journal?, zeitzone: TimeZone = .current) -> String {
        guard let journal else { return String(localized: "Export: Journal nicht geöffnet") }
        guard let ordner = gemerkterOrdner() else { return String(localized: "Export: noch kein Ordner gewählt") }
        guard ordner.startAccessingSecurityScopedResource() else {
            return String(localized: "Export: kein Zugriff auf \(ordner.path)")
        }
        defer { ordner.stopAccessingSecurityScopedResource() }
        do {
            let daten = try export(journal, zeitzone: zeitzone)
            try daten.json().write(to: ordner.appending(path: JournalExport.dateiname), options: .atomic)
            let trades = daten.konten.reduce(0) { $0 + $1.trades.count }
            return String(localized: "Export: \(trades) Trades aus \(daten.konten.count) Konten, \(Date.now.formatted(date: .omitted, time: .shortened))")
        } catch {
            return String(localized: "Export: Fehler \(error.localizedDescription)")
        }
    }
}
#endif
