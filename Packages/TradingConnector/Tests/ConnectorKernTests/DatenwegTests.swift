import ConnectorKern
import Foundation
import Testing

@Suite struct DatenwegTests {
    let ordner = FileManager.default.temporaryDirectory
        .appending(path: "tb-test-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func ohneOrdnerMeldetKeinenOrdner() {
        #expect(Datenweg.pruefe(ordner: nil) == .keinOrdner)
        #expect(Datenweg.pruefe(ordner: "") == .keinOrdner)
    }

    @Test func fehlendeDateiWirdErkannt() {
        let ergebnis = Datenweg.pruefe(ordner: ordner.path)
        guard case .fehlt = ergebnis else {
            Issue.record("erwartet .fehlt, bekommen \(ergebnis)")
            return
        }
    }

    @Test func vorhandeneDateiWirdGelesen() throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        try #"{"wert":42}"#.write(
            to: ordner.appending(path: Datenweg.dateiname), atomically: true, encoding: .utf8)

        let ergebnis = Datenweg.pruefe(ordner: ordner.path)
        guard case let .gelesen(_, inhalt) = ergebnis else {
            Issue.record("erwartet .gelesen, bekommen \(ergebnis)")
            return
        }
        #expect(inhalt == #"{"wert":42}"#)
    }
}
