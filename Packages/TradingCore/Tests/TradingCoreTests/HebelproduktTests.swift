import Foundation
import Testing
@testable import TradingCore

/// Hebelprodukte am Namen erkennen (Turbos bei Scalable und Trade Republic). Sollwerte von Hand.
private func hebelDez(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

@Test func hebelNasdaqLongTurbo() throws {
    let h = try #require(Hebelprodukt.erkenne("Nasdaq 100 Long 29.209,64 Turbo Open End HSBC"))
    #expect(h.basiswert == "Nasdaq 100")
    #expect(h.markterwartung == .buy)
    #expect(h.art == .knockout)
    #expect(h.schwelle == hebelDez("29209.64"))
    #expect(h.schwellenwaehrung == nil)
}

@Test func hebelDollarSchwelle() throws {
    let h = try #require(Hebelprodukt.erkenne("Iren Long 23,39 $ Turbo Open End HSBC"))
    #expect(h.basiswert == "Iren")
    #expect(h.markterwartung == .buy)
    #expect(h.art == .knockout)
    #expect(h.schwelle == hebelDez("23.39"))
    #expect(h.schwellenwaehrung == "USD")
}

@Test func hebelNasdaqShortClassic() throws {
    let h = try #require(Hebelprodukt.erkenne("Nasdaq 100 Short 31.450,00 Turbo Classic HSBC"))
    #expect(h.basiswert == "Nasdaq 100")
    #expect(h.markterwartung == .sell)
    #expect(h.art == .knockout)
    #expect(h.schwelle == hebelDez("31450"))
    #expect(h.schwellenwaehrung == nil)
}

@Test func hebelDaxShort() throws {
    let h = try #require(Hebelprodukt.erkenne("DAX Short 25.843,30 Turbo Open End HSBC"))
    #expect(h.basiswert == "DAX")
    #expect(h.markterwartung == .sell)
    #expect(h.schwelle == hebelDez("25843.3"))
}

@Test func hebelBasiswertAusMehrerenWoertern() throws {
    let h = try #require(Hebelprodukt.erkenne("Advanced Micro Devices Long 471,02 $ Turbo Open End HSBC"))
    #expect(h.basiswert == "Advanced Micro Devices")
    #expect(h.markterwartung == .buy)
    #expect(h.schwelle == hebelDez("471.02"))
    #expect(h.schwellenwaehrung == "USD")
}

@Test func hebelOptionsscheinCallUndPut() throws {
    let call = try #require(Hebelprodukt.erkenne("Beispielaktie Call 200,00 $ Optionsschein Testbank"))
    #expect(call.basiswert == "Beispielaktie")
    #expect(call.markterwartung == .buy)
    #expect(call.art == .optionsschein)
    #expect(call.schwelle == hebelDez("200"))
    #expect(call.schwellenwaehrung == "USD")
    let put = try #require(Hebelprodukt.erkenne("Beispielindex Put 7.340,90€ Testbank"))
    #expect(put.markterwartung == .sell)
    #expect(put.art == .optionsschein)
    #expect(put.schwelle == hebelDez("7340.9"))
    #expect(put.schwellenwaehrung == "EUR")
}

@Test func hebelKeineFehltreffer() {
    // Aktien, ETFs und unsichere Namen ergeben nil.
    #expect(Hebelprodukt.erkenne("Generac Holdings") == nil)
    #expect(Hebelprodukt.erkenne("iShares Core MSCI World") == nil)
    #expect(Hebelprodukt.erkenne("Optionsschein SYN") == nil)
    #expect(Hebelprodukt.erkenne("Turbo Open End HSBC") == nil)
    #expect(Hebelprodukt.erkenne("DAX Long Turbo Open End HSBC") == nil)
    #expect(Hebelprodukt.erkenne("Faktor Long DAX") == nil)
    #expect(Hebelprodukt.erkenne("Long Term Fonds Long 12,50") == nil)
    #expect(Hebelprodukt.erkenne("Beispielindex Long 1.23,45 Turbo") == nil)
    #expect(Hebelprodukt.erkenne("") == nil)
}

@Test func hebelPositionsbildungShortTurbo() throws {
    let name = "Beispielindex Short 8.000,00 Turbo Open End Testbank"
    let kauf = Ausfuehrung(id: "k1", zeit: Date(timeIntervalSince1970: 1_790_000_000), kennung: "DE000TEST0001",
                           name: name, seite: .buy, menge: 100, preis: hebelDez("3.47"), betrag: -347,
                           waehrung: "EUR")
    let verkauf = Ausfuehrung(id: "v1", zeit: Date(timeIntervalSince1970: 1_790_003_600), kennung: "DE000TEST0001",
                              name: name, seite: .sell, menge: 100, preis: 4, betrag: 400, waehrung: "EUR")
    let ergebnis = Positionsbildung.bilde([kauf, verkauf])
    let trade = try #require(ergebnis.trades.first)
    // Der Schein wird gekauft (side), die Erwartung auf den Basiswert ist Short.
    #expect(trade.side == .buy)
    #expect(trade.markterwartung == .sell)
    #expect(trade.basiswert == "Beispielindex")
    #expect(trade.symbol == name)
    #expect(trade.produktart == .derivat)
    #expect(trade.profit == 53)
}

@Test func hebelPositionsbildungAktieUnveraendert() throws {
    let kauf = Ausfuehrung(id: "k1", zeit: Date(timeIntervalSince1970: 1_790_000_000), kennung: "DE000TEST0002",
                           name: "Beispiel AG", seite: .buy, menge: 1, preis: 10, betrag: -10, waehrung: "EUR")
    let verkauf = Ausfuehrung(id: "v1", zeit: Date(timeIntervalSince1970: 1_790_003_600), kennung: "DE000TEST0002",
                              name: "Beispiel AG", seite: .sell, menge: 1, preis: 12, betrag: 12, waehrung: "EUR")
    let trade = try #require(Positionsbildung.bilde([kauf, verkauf]).trades.first)
    #expect(trade.basiswert == nil)
    #expect(trade.markterwartung == nil)
    #expect(trade.produktart == .unbekannt)
}

@Test func hebelScalableZeileAlsDerivat() throws {
    let text = """
    date;time;status;reference;description;assetType;type;isin;shares;price;amount;fee;tax;currency
    2026-10-01;15:45:50;Executed;"SCALtest0001";"Beispielindex Short 8.000,00 Turbo Open End Testbank";\
    Security;Buy;DE000TEST0001;100;3,47;-347,00;0,00;0,00;EUR
    2026-10-01;16:10:00;Executed;"SCALtest0002";"Beispiel AG";Security;Buy;DE000TEST0002;1;10,00;-10,00;0,00;0,00;EUR
    """
    let k = try ScalableCSV.lies(text)
    #expect(k.ausfuehrungen.map(\.id) == ["SCALtest0001", "SCALtest0002"])
    #expect(k.ausfuehrungen.map(\.produktart) == [.derivat, .unbekannt])
    #expect(k.ausfuehrungen.first?.betrag == -347)
    #expect(k.ausfuehrungen.first?.preis == hebelDez("3.47"))
}
