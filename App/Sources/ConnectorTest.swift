#if os(macOS)
import Foundation
import Security

/// Experiment AP6: Die App legt eine Testdatei in ihre App Group,
/// der MCP-Server in Claude Desktop versucht sie zu lesen.
/// Wird nach dem Experiment durch den echten Datenexport ersetzt.
enum ConnectorTest {
    static let dateiname = "connector-test.json"

    /// App-Group-ID aus den eigenen Entitlements, z. B. "ABCDE12345.journal".
    static func gruppe() -> String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let wert = SecTaskCopyValueForEntitlement(
                  task, "com.apple.security.application-groups" as CFString, nil)
        else { return nil }
        return (wert as? [String])?.first
    }

    static func schreibe() -> String {
        guard let gruppe = gruppe(),
              let ordner = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: gruppe)
        else { return "Connector-Test: keine App Group (App unsigniert?)" }
        let json = #"{"quelle":"Trading Buddy App","wert":42,"geschrieben":"\#(Date.now.ISO8601Format())"}"#
        do {
            try json.write(to: ordner.appending(path: dateiname), atomically: true, encoding: .utf8)
            return "Connector-Test: Datei geschrieben (\(gruppe))"
        } catch {
            return "Connector-Test: Fehler \(error.localizedDescription)"
        }
    }
}
#endif
