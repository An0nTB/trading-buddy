import Foundation
import Testing
@testable import TradingCore

@Suite struct OffeneExportTests {
    private func export(_ offene: [OffenerTrade]?) -> JournalExport {
        JournalExport(konten: [.init(broker: "Test", kontonummer: "1234", waehrung: "EUR", trades: [], offene: offene)],
                      zeitzone: TimeZone(secondsFromGMT: 0)!)
    }

    @Test func offeneRegelgrundlagenUeberstehenDieRundreise() throws {
        let risiko = try #require(Decimal(string: "123.4567890123456789"))
        let offene = [OffenerTrade(id: "A", openTime: Date(timeIntervalSince1970: 1_746_403_200),
                                  nurDatum: true, risiko: risiko)]
        let daten = try export(offene).json()
        let gelesen = try JournalExport.lese(daten)
        #expect(gelesen.format == 3)
        #expect(gelesen.konten[0].offene == offene)
        #expect(gelesen.konten[0].offeneVollstaendig == true)
        #expect(String(decoding: daten, as: UTF8.self).contains("\"risiko\":\"123.4567890123456789\""))
    }

    @Test func alterLeererUndKaputterBestandBleibenUnterscheidbar() throws {
        var alt = export(nil)
        alt.format = 2
        #expect(try JournalExport.lese(alt.json()).konten[0].offene == nil)
        let leer = try export([]).json()
        #expect(try JournalExport.lese(leer).konten[0].offene == [])
        let kaputt = String(decoding: leer, as: UTF8.self)
            .replacingOccurrences(of: "\"offene\":[]", with: "\"offene\":[{\"id\":\"A\"}]")
        #expect(kaputt != String(decoding: leer, as: UTF8.self))
        #expect(try JournalExport.lese(Data(kaputt.utf8)).konten[0].offene == nil)
    }

    @Test func unbekanntesRisikoBleibtUnbekannt() throws {
        let offene = [OffenerTrade(id: "A", openTime: Date(timeIntervalSince1970: 1_746_403_200))]
        #expect(try JournalExport.lese(export(offene).json()).konten[0].offene == offene)
    }

    @Test func unvollstaendigerBestandUndFehlendeKennzeichnungBleibenErkennbar() throws {
        var datei = export([])
        datei.konten[0].offeneVollstaendig = false
        #expect(try JournalExport.lese(datei.json()).konten[0].offeneVollstaendig == false)
        datei.konten[0].offeneVollstaendig = nil
        #expect(try JournalExport.lese(datei.json()).konten[0].offeneVollstaendig == nil)
    }
}
