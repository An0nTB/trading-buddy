import Foundation
import Testing
@testable import TradingCore

/// Tagesnotizen, verpasste Trades und Handelsregeln in der Exportdatei (AP12, P8).

@Test func notizImExportOhneLeereTexte() throws {
    let tag = try #require(Journaltag("2025-05-05"))
    let erstellt = Date(timeIntervalSince1970: 1_746_428_400)
    let leer = JournalExport.Notiz(Tagesnotiz(tag: tag, plan: " \n", planErstellt: erstellt, rueckblick: "", erstellt: erstellt))
    #expect(leer.plan == nil && leer.planErstellt == nil && leer.istLeer)

    let notiz = JournalExport.Notiz(Tagesnotiz(tag: tag, plan: "Nur Ausbruch", planErstellt: erstellt, verfassung: 4,
                                               erstellt: erstellt))
    #expect(!notiz.istLeer && notiz.modell.hatPlan(vor: erstellt) && !notiz.modell.hatPlan(vor: erstellt - 1))

    let export = JournalExport(konten: [], zeitzone: TimeZone(identifier: "Europe/Berlin")!, erstellt: erstellt,
                               tagesnotizen: [notiz, leer])
    #expect(export.tagesnotizen == [notiz])
    #expect(try JournalExport.lese(try export.json()) == export)
}

@Test func verpassterTradeImExport() throws {
    let zeit = Date(timeIntervalSince1970: 1_746_428_400)
    let original = VerpassterTrade(id: "v1", zeit: zeit, symbol: "DAX", seite: .sell, setup: " ", grund: .zuSpaet,
                                   notiz: "", ergebnisR: 2)
    let export = JournalExport.Verpasst(original)
    #expect(export.seite == "sell" && export.grund == "zuSpaet" && export.setup == nil && export.notiz == nil)
    #expect(export.modell?.grund == .zuSpaet && export.modell?.ergebnisR == 2)
    var unbekannt = export
    unbekannt.grund = "neuerGrund"
    #expect(unbekannt.modell == nil)
}
