import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Zahlen der Seite „Ziele“ (`Zielbilanz`). A2 (Doc 36): `bis` ist ausschließlich; ein Ziel darf nicht
/// in zwei Monaten zählen.
@Suite struct ZielbilanzTests {
    private typealias T = AppTestdaten
    private let kalender = AppTestdaten.utcKalender

    private func ziel(_ von: Date, _ bis: Date, _ status: Reviewziel.Status = .offen, ergebnis: String? = nil,
                      text: String = "Stop vor dem Einstieg setzen") -> Reviewziel {
        Reviewziel(text: text, von: von, bis: bis, status: status, ergebnis: ergebnis, erstellt: von)
    }

    @Test func letzterTagIstDerTagVorBis() {
        let z = ziel(T.zeit(2026, 9, 1), T.zeit(2026, 10, 1))
        #expect(Zielbilanz.letzterTag(z, kalender: kalender) == T.zeit(2026, 9, 30))
    }

    @Test func zielMitLetztemTagAmMonatserstenZaehltNurEinmal() {
        // Letzter Tag 01.09. 00:00: gehört zum September, nicht auch zum August.
        let z = ziel(T.zeit(2026, 8, 25), T.zeit(2026, 9, 2), .erreicht)
        let werte = Zielbilanz.jeMonat([z], monate: 3, jetzt: T.zeit(2026, 9, 15), kalender: kalender)
        let erreicht = werte.filter { $0.status == .erreicht }
        #expect(erreicht.reduce(0) { $0 + $1.anzahl } == 1)
        #expect(erreicht.first { $0.monat == T.zeit(2026, 9, 1) }?.anzahl == 1)
        #expect(erreicht.first { $0.monat == T.zeit(2026, 8, 1) }?.anzahl == 0)
    }

    @Test func jeMonatLiefertJedenMonatAuchOhneZiele() {
        let werte = Zielbilanz.jeMonat([], monate: 6, jetzt: T.zeit(2026, 9, 15), kalender: kalender)
        #expect(Set(werte.map(\.monat)).count == 6)
        #expect(werte.allSatisfy { $0.anzahl == 0 })
    }

    @Test func zielZumJahreswechselGehoertInsAlteJahr() {
        let z = ziel(T.zeit(2026, 12, 1), T.zeit(2027, 1, 1), .verfehlt)
        #expect(Zielbilanz.imJahr([z], 2026, kalender: kalender).count == 1)
        #expect(Zielbilanz.imJahr([z], 2027, kalender: kalender).isEmpty)
    }

    @Test func automatischVerfehlteWartenAufEinUrteil() {
        let auto = ziel(T.zeit(2026, 8, 1), T.zeit(2026, 9, 1), .verfehlt, ergebnis: Journal.fristAbgelaufen)
        let vonHand = ziel(T.zeit(2026, 7, 1), T.zeit(2026, 8, 1), .verfehlt, ergebnis: "Zweimal ohne Stop")
        let erreicht = ziel(T.zeit(2026, 6, 1), T.zeit(2026, 7, 1), .erreicht)
        let offen = ziel(T.zeit(2026, 9, 1), T.zeit(2026, 10, 1))
        let alle = [erreicht, vonHand, auto, offen]
        #expect(Zielbilanz.zuBeurteilen(alle) == [auto])
        #expect(Zielbilanz.offen(alle) == [offen])
        // Beurteilt: ohne die automatisch verfehlten, spätestes Ende zuerst.
        #expect(Zielbilanz.beurteilt(alle) == [vonHand, erreicht])
    }

    @Test func zieleInFolgeZaehlenBisZurErstenLuecke() {
        let a = ziel(T.zeit(2026, 9, 1), T.zeit(2026, 9, 8), .erreicht)
        let b = ziel(T.zeit(2026, 9, 8), T.zeit(2026, 9, 15), .verfehlt)
        let c = ziel(T.zeit(2026, 9, 16), T.zeit(2026, 9, 22))
        let folge = Zielbilanz.inFolge([c, a, b], kalender: kalender)
        #expect(folge.anzahl == 3)
        #expect(folge.seit == T.zeit(2026, 9, 1))

        let spaet = ziel(T.zeit(2026, 9, 25), T.zeit(2026, 10, 1))
        #expect(Zielbilanz.inFolge([a, b, c, spaet], kalender: kalender).anzahl == 1)
        #expect(Zielbilanz.inFolge([], kalender: kalender).anzahl == 0)
    }

    @Test func verworfeneZieleZaehlenNichtInDerFolge() {
        let a = ziel(T.zeit(2026, 9, 1), T.zeit(2026, 9, 8), .erreicht)
        let verworfen = ziel(T.zeit(2026, 9, 8), T.zeit(2026, 9, 15), .verworfen)
        #expect(Zielbilanz.inFolge([a, verworfen], kalender: kalender).anzahl == 1)
        #expect(Zielbilanz.inFolge([a, verworfen], kalender: kalender).seit == T.zeit(2026, 9, 1))
    }

    @Test func gruppenNachMonatInEingabereihenfolge() {
        let sep = ziel(T.zeit(2026, 9, 1), T.zeit(2026, 9, 10))
        let aug = ziel(T.zeit(2026, 8, 1), T.zeit(2026, 8, 10))
        let sep2 = ziel(T.zeit(2026, 9, 10), T.zeit(2026, 9, 20))
        let gruppen = Zielbilanz.nachMonat([sep, aug, sep2], kalender: kalender)
        #expect(gruppen.map(\.monat) == [T.zeit(2026, 9, 1), T.zeit(2026, 8, 1)])
        #expect(gruppen.first?.ziele == [sep, sep2])
    }
}
