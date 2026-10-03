import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.15.0: Werkzeug `henry_status` (Beta-Punkte 17 und 18).

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

private func export(erstellt: Date, trades: Int = 2) -> JournalExport {
    let liste = (0..<trades).map { i in
        Trade(id: "\(i)", symbol: "SAP", side: .buy, lots: 1, openTime: zeit("2025-05-05T08:00:00"),
              closeTime: zeit("2025-05-05T09:00:00"), openPrice: 100, closePrice: 101, profit: 1)
    }
    return JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: liste)],
                         zeitzone: berlin, erstellt: erstellt)
}

@Test func statusMitFrischemExport() {
    let jetzt = zeit("2026-10-03T12:00:00")
    let text = Verbindungsstatus.text(.geladen(export(erstellt: zeit("2026-10-03T09:30:00"))), ordner: "/Nutzer/x/Export",
                                      jetzt: jetzt)
    #expect(text.contains("Erweiterung \(Verbindungsstatus.connectorVersion), liest Exportdateien bis Format 2"))
    #expect(text.contains("Export-Ordner in der Erweiterung: /Nutzer/x/Export."))
    #expect(text.contains("VERBINDUNG STEHT. Export vom 03.10.2026 11:30 (vor 2 Stunden)"))
    #expect(text.contains("1 Konten, 2 Trades.") && !text.contains("HINWEIS"))
}

@Test func statusMitHinweisen() {
    let jetzt = zeit("2026-10-03T12:00:00")
    var alt = export(erstellt: zeit("2026-09-30T12:00:00"), trades: 0)
    alt.konten = []
    alt.rechenkern = "0.1.0"
    let text = Verbindungsstatus.text(.geladen(alt), ordner: "/x", jetzt: jetzt)
    #expect(text.contains("(vor 3 Tagen)") && text.contains("0 Konten, 0 Trades."))
    #expect(text.contains("HINWEIS: Noch kein Konto importiert."))
    #expect(text.contains("HINWEIS: Der Export ist älter als 24 Stunden."))
    #expect(text.contains("verschiedene Rechenkerne (App 0.1.0, Erweiterung \(TradingCore.version))"))
}

@Test func statusOhneVerbindung() {
    let ohne = Verbindungsstatus.text(.keinOrdner, ordner: nil)
    #expect(ohne.contains("Export-Ordner in der Erweiterung: nicht eingetragen."))
    #expect(ohne.contains("VERBINDUNG FEHLT. KEIN ORDNER:") && ohne.contains("Einstellungen > Erweiterungen > Henry"))
    let fehlt = Verbindungsstatus.text(.fehlt(pfad: "/x/trading-buddy-export.json"), ordner: "/x")
    #expect(fehlt.contains("KEINE DATEN: /x/trading-buddy-export.json fehlt.") && fehlt.contains("Was tun: In Henry"))
    let zugriff = Verbindungsstatus.text(.keinZugriff(pfad: "/x", fehler: "verboten"), ordner: "/x")
    #expect(zugriff.contains("Erlaubnisfrage von macOS"))
    let unlesbar = Verbindungsstatus.text(.unlesbar(pfad: "/x", fehler: "kaputt"), ordner: "/x")
    #expect(unlesbar.contains("DATEI UNLESBAR") && unlesbar.contains("neueste Erweiterung"))
}

@Test func alterstexte() {
    #expect(Verbindungsstatus.alterstext(30) == "gerade eben")
    #expect(Verbindungsstatus.alterstext(5 * 60) == "vor 5 Minuten")
    #expect(Verbindungsstatus.alterstext(47 * 3_600) == "vor 47 Stunden")
    #expect(Verbindungsstatus.alterstext(-60).contains("Uhr prüfen"))
}
