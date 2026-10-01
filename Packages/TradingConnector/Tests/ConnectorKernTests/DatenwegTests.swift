import ConnectorKern
import Foundation
import Testing

@Suite struct DatenwegTests {
    let home = FileManager.default.temporaryDirectory
        .appending(path: "tb-test-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func ohneGruppeMeldetKeineGruppe() {
        #expect(Datenweg.pruefe(gruppe: nil, home: home) == .keineGruppe)
    }

    @Test func fehlendeDateiWirdErkannt() {
        let ergebnis = Datenweg.pruefe(gruppe: "TEAM.journal", home: home)
        guard case .fehlt = ergebnis else {
            Issue.record("erwartet .fehlt, bekommen \(ergebnis)")
            return
        }
    }

    @Test func vorhandeneDateiWirdGelesen() throws {
        let ordner = Datenweg.ordner(gruppe: "TEAM.journal", home: home)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try #"{"wert":42}"#.write(to: ordner.appending(path: Datenweg.dateiname), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: home) }

        let ergebnis = Datenweg.pruefe(gruppe: "TEAM.journal", home: home)
        guard case let .gelesen(_, inhalt) = ergebnis else {
            Issue.record("erwartet .gelesen, bekommen \(ergebnis)")
            return
        }
        #expect(inhalt == #"{"wert":42}"#)
    }
}
