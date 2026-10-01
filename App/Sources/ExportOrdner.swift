#if os(macOS)
import Foundation

/// Ordner, in den die App Daten für den Claude-Connector schreibt.
/// Der Nutzer wählt ihn einmal; die App merkt sich den Zugriff als
/// Security-scoped Bookmark, damit er nach einem Neustart erhalten bleibt.
enum ExportOrdner {
    static let schluessel = "exportOrdnerLesezeichen"
    static let testdatei = "connector-test.json"

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

    /// Experiment AP6: schreibt eine Testdatei, die der Connector liest.
    static func schreibeTestdatei() -> String {
        guard let ordner = gemerkterOrdner() else {
            return "Connector-Test: noch kein Export-Ordner gewählt"
        }
        guard ordner.startAccessingSecurityScopedResource() else {
            return "Connector-Test: kein Zugriff auf \(ordner.path)"
        }
        defer { ordner.stopAccessingSecurityScopedResource() }
        let json = #"{"quelle":"Trading Buddy App","wert":42,"geschrieben":"\#(Date.now.ISO8601Format())"}"#
        do {
            try json.write(to: ordner.appending(path: testdatei), atomically: true, encoding: .utf8)
            return "Connector-Test: Datei geschrieben (\(ordner.path))"
        } catch {
            return "Connector-Test: Fehler \(error.localizedDescription)"
        }
    }
}
#endif
