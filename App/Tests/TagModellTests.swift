import Foundation
import Testing
import TradingCore
@testable import Trading_Buddy

/// Ablage für Tests: wie die flüchtige Ablage der App, nur kann das Speichern auf Wunsch scheitern.
@MainActor
private final class TestTagAblage: TagAblage {
    struct Fehler: Error {}
    let innen = FluechtigeTagAblage()
    var speichernScheitert = false

    var dauerhaft: Bool { false }
    func tagesnotiz(_ tag: Journaltag) throws -> Tagesnotiz? { try innen.tagesnotiz(tag) }
    func tagesnotizen(von: Journaltag, bis: Journaltag) throws -> [Tagesnotiz] { try innen.tagesnotizen(von: von, bis: bis) }
    func speichereTagesnotiz(_ notiz: Tagesnotiz, jetzt: Date) throws -> Tagesnotiz? {
        if speichernScheitert { throw Fehler() }
        return try innen.speichereTagesnotiz(notiz, jetzt: jetzt)
    }
    func verpassteTrades(von: Date, bis: Date) throws -> [VerpassterTrade] { try innen.verpassteTrades(von: von, bis: bis) }
    func speichereVerpasstenTrade(_ verpasst: VerpassterTrade) throws { try innen.speichereVerpasstenTrade(verpasst) }
    func loescheVerpasstenTrade(id: String) throws { try innen.loescheVerpasstenTrade(id: id) }
    func bilder(tag: Journaltag) throws -> [Bildverweis] { try innen.bilder(tag: tag) }
    func speichereBild(_ bild: Bildverweis) throws { try innen.speichereBild(bild) }
    func loescheBild(datei: String) throws { try innen.loescheBild(datei: datei) }
}

/// Zustand der Tagesseite (`TagModell`). T1 (Doc 36): Neu laden nach einer Änderung darf den
/// ungesicherten Entwurf nicht überschreiben.
@Suite @MainActor struct TagModellTests {
    private typealias T = AppTestdaten
    private let ersterOktober = AppTestdaten.tag(2026, 10, 1)

    private func modell(_ ablage: TestTagAblage) -> TagModell {
        TagModell(ablage: ablage, zeitzone: T.berlin, tag: ersterOktober, jetzt: T.zeit(2026, 10, 1, 6))
    }

    private func modell() -> TagModell { modell(TestTagAblage()) }

    private func verpasst(_ id: String) -> VerpassterTrade {
        VerpassterTrade(id: id, zeit: T.zeit(2026, 10, 1, 10), symbol: "DE40", seite: .buy, grund: .zoegern)
    }

    @Test func verpassterTradeLaesstDenEntwurfStehen() throws {
        let tag = modell()
        tag.entwurf.plan = "Nur Ausbrüche über das Vortageshoch"
        try tag.speichere(verpasst("APPT-V1"))
        #expect(tag.entwurf.plan == "Nur Ausbrüche über das Vortageshoch")
        #expect(tag.verpasst.map(\.id) == ["APPT-V1"])
        #expect(tag.ungesichert)
    }

    @Test func loeschenLaesstDenEntwurfStehen() throws {
        let tag = modell()
        try tag.speichere(verpasst("APPT-V1"))
        tag.entwurf.rueckblick = "Zu früh raus"
        tag.loesche(verpasst("APPT-V1"))
        #expect(tag.entwurf.rueckblick == "Zu früh raus")
        #expect(tag.verpasst.isEmpty)
    }

    /// Jede gespeicherte Änderung zählt; daran hängt der neue Export für Claude (X4, Doc 40).
    @Test func gespeicherteAenderungenWerdenGezaehlt() throws {
        let tag = modell()
        #expect(tag.aenderungen == 0)
        try tag.speichere(verpasst("APPT-V1"))
        tag.entwurf.plan = "Plan"
        #expect(tag.sichere(jetzt: T.zeit(2026, 10, 1, 7)))
        tag.loesche(verpasst("APPT-V1"))
        #expect(tag.aenderungen == 3)
        // Ohne Änderung wird nichts gespeichert und nichts gezählt.
        #expect(tag.sichere(jetzt: T.zeit(2026, 10, 1, 8)))
        #expect(tag.aenderungen == 3)
    }

    @Test func gescheitertesSpeichernHaeltDenTagFest() {
        let ablage = TestTagAblage()
        let tag = modell(ablage)
        tag.entwurf.plan = "Plan, der nicht verloren gehen darf"
        ablage.speichernScheitert = true
        tag.wechsle(zu: T.tag(2026, 10, 2))
        #expect(tag.tag == ersterOktober)
        #expect(tag.entwurf.plan == "Plan, der nicht verloren gehen darf")
        #expect(tag.fehler != nil)
    }

    @Test func tageswechselSpeichertUndLaedtDenAnderenTag() {
        let tag = modell()
        tag.entwurf.plan = "Plan für den Ersten"
        tag.wechsle(zu: T.tag(2026, 10, 2))
        #expect(tag.tag == T.tag(2026, 10, 2))
        #expect(tag.entwurf.plan.isEmpty)
        tag.wechsle(zu: ersterOktober)
        #expect(tag.entwurf.plan == "Plan für den Ersten")
        #expect(!tag.ungesichert)
    }

    @Test func neuerVerpassterAnEinemFruehenTagStehtAufMittag() {
        let tag = modell()
        let neu = tag.neuerVerpasster(jetzt: T.zeit(2026, 10, 5, 9))
        // 1. Oktober 12:00 in Berlin (Sommerzeit, UTC+2) ist 10:00 UTC.
        #expect(neu.zeit == T.zeit(2026, 10, 1, 10))
    }

    @Test func planwirkungOhneTradesGibtNil() {
        #expect(modell().planwirkung([]) == nil)
    }
}

/// Tagesrechnung der Tagesseite über die Zeitumstellung (`Journaltag.verschoben`, `spanne`).
@Suite struct JournaltagRechnungTests {
    private typealias T = AppTestdaten

    @Test func tagMitZeitumstellungHatFuenfundzwanzigStunden() {
        // 25.10.2026: Ende der Sommerzeit in Berlin.
        let spanne = T.tag(2026, 10, 25).spanne(in: T.berlin)
        #expect(spanne.bis.timeIntervalSince(spanne.von) == 25 * 3600)
    }

    @Test func verschiebenUeberDieZeitumstellungTrifftDenKalendertag() {
        #expect(T.tag(2026, 10, 24).verschoben(um: 2, zeitzone: T.berlin) == T.tag(2026, 10, 26))
        #expect(T.tag(2026, 3, 30).verschoben(um: -2, zeitzone: T.berlin) == T.tag(2026, 3, 28))
        #expect(T.tag(2026, 3, 1).verschoben(um: -1, zeitzone: T.utc) == T.tag(2026, 2, 28))
    }
}
