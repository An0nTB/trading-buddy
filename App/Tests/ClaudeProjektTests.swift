import Foundation
import Testing
import TradingAssistant
@testable import Trading_Buddy

/// Frag Henry im Claude-Projekt (Tim 17.10.2026). Die Paket-Tests von TradingAssistant laufen nicht in der CI,
/// darum prüft die App beide Projektarten und Fehleingaben hier mit. Erfundene Kennungen; der Eintrag wird danach
/// zurückgesetzt.
@MainActor @Suite(.serialized) struct ClaudeProjektTests {
    private let code = "chan_01TESTPROJEKT00000000000"
    private let chat = "00000000-0000-4000-8000-000000000000"

    @Test func beideProjektartenOhneFrageImLink() throws {
        let vorher = UserDefaults.standard.string(forKey: ClaudeProjekt.schluessel)
        defer { UserDefaults.standard.set(vorher, forKey: ClaudeProjekt.schluessel) }

        UserDefaults.standard.set(code, forKey: ClaudeProjekt.schluessel)
        #expect(ClaudeProjekt.fuer(.monat) == .code(code))
        #expect(ClaudeProjekt.fuer(.analyse) == nil)
        #expect(ClaudeProjekt.fuer(.woche)?.link?.absoluteString == "claude://claude.ai/code/project/\(code)")

        let eingabe = "https://claude.ai/project/\(chat.uppercased())"
        let ziel = try #require(FragBrad.projekt(eingabe))
        UserDefaults.standard.set(ziel.kennung, forKey: ClaudeProjekt.schluessel)
        #expect(ClaudeProjekt.fuer(.trade) == .chat(chat))
        #expect(ClaudeProjekt.fuer(.trade)?.link?.absoluteString == "claude://claude.ai/project/\(chat)")

        UserDefaults.standard.removeObject(forKey: ClaudeProjekt.schluessel)
        #expect(ClaudeProjekt.fuer(.monat) == nil)
    }

    @Test func fehleingabenErgebenKeinProjekt() {
        for eingabe in ["", "kein Projekt", "https://claude.ai/code/project/", "chan_"] {
            #expect(FragBrad.projekt(eingabe) == nil)
        }
    }
}
