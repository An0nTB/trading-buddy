import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

@Suite struct ExportdateiTests {
    let ordner = FileManager.default.temporaryDirectory
        .appending(path: "tb-test-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func ohneOrdnerOderDatei() {
        #expect(Exportdatei.lade(ordner: nil) == .keinOrdner)
        #expect(Exportdatei.lade(ordner: "") == .keinOrdner)
        guard case .fehlt = Exportdatei.lade(ordner: ordner.path) else {
            Issue.record("erwartet .fehlt")
            return
        }
        #expect(Exportdatei.meldung(.keinOrdner)?.hasPrefix("KEIN ORDNER") == true)
    }

    @Test func dateiWirdGelesen() throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let export = JournalExport(konten: [], zeitzone: TimeZone(identifier: "Europe/Berlin")!,
                                   erstellt: Date(timeIntervalSince1970: 1_790_000_000))
        try export.json().write(to: ordner.appending(path: JournalExport.dateiname))
        #expect(Exportdatei.lade(ordner: ordner.path) == .geladen(export))
        #expect(Exportdatei.meldung(.geladen(export)) == nil)
    }

    @Test func kaputteDateiWirdGemeldet() throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        try Data("kein json".utf8).write(to: ordner.appending(path: JournalExport.dateiname))
        guard case .unlesbar = Exportdatei.lade(ordner: ordner.path) else {
            Issue.record("erwartet .unlesbar")
            return
        }
    }
}
