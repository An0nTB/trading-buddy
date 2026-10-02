import Foundation
import Testing
@testable import TradingNews

// MARK: Zuordnung zur Merkliste

@Test func symbolUeberSymboleDerMeldung() {
    let m = meldung("Quartalszahlen", symbole: ["SAP.DE"])
    #expect(Zuordnung.trifft(m, Merkbegriff(art: .symbol, text: "SAP")))
    #expect(Zuordnung.trifft(m, Merkbegriff(art: .symbol, text: "sap.de")))
    #expect(!Zuordnung.trifft(m, Merkbegriff(art: .symbol, text: "BMW")))
}

@Test func symbolImTextNurGrossUndAbDreiZeichen() {
    #expect(Zuordnung.trifft(meldung("SAP hebt Prognose"), Merkbegriff(art: .symbol, text: "SAP.DE")))
    #expect(Zuordnung.trifft(meldung("Prognose", anriss: "Auch NVDA. legte zu"), Merkbegriff(art: .symbol, text: "NVDA")))
    #expect(!Zuordnung.trifft(meldung("sap hebt Prognose"), Merkbegriff(art: .symbol, text: "SAP")))
    #expect(!Zuordnung.trifft(meldung("SAPPHIRE steigt"), Merkbegriff(art: .symbol, text: "SAP")))
    // Kurze Symbole nur über die Symbole der Meldung, sonst Zufallstreffer.
    #expect(!Zuordnung.trifft(meldung("T-Aktie im Plus"), Merkbegriff(art: .symbol, text: "T")))
    #expect(Zuordnung.trifft(meldung("Telekom", symbole: ["T"]), Merkbegriff(art: .symbol, text: "T")))
}

@Test func isinImAnriss() {
    let m = meldung("Ad-hoc", anriss: "ISIN: DE0007164600, WKN 716460")
    #expect(Zuordnung.trifft(m, Merkbegriff(art: .isin, text: "de0007164600")))
    #expect(!Zuordnung.trifft(m, Merkbegriff(art: .isin, text: "DE000716460")))
}

@Test func nameAlsWortfolge() {
    let begriff = Merkbegriff(art: .name, text: "Deutsche Bank")
    #expect(Zuordnung.trifft(meldung("Deutsche Bank erhöht Dividende"), begriff))
    #expect(Zuordnung.trifft(meldung("Analyse", anriss: "Bei der deutsche-bank-Aktie …"), begriff))
    #expect(!Zuordnung.trifft(meldung("Aktie der Deutschen Bank fällt"), begriff))
    #expect(!Zuordnung.trifft(meldung("Bank in Deutsche Hand"), begriff))
}

@Test func stichwortAlleWoerterEgalWelcheReihenfolge() {
    let begriff = Merkbegriff(art: .stichwort, text: "Nvidia Zölle")
    #expect(Zuordnung.trifft(meldung("Neue Zölle treffen NVIDIA"), begriff))
    #expect(!Zuordnung.trifft(meldung("Nvidia steigt"), begriff))
    #expect(!Zuordnung.trifft(meldung("Nvidia"), Merkbegriff(art: .stichwort, text: "   ")))
}

@Test func gruppiertJeBegriff() {
    let sap = Merkbegriff(art: .symbol, text: "SAP")
    let gold = Merkbegriff(art: .stichwort, text: "Gold")
    let a = meldung("SAP hebt Prognose", link: "https://example.org/1")
    let b = meldung("Alles auf Gold", link: "https://example.org/2")
    let gruppen = Zuordnung.gruppiert([a, b], nach: [sap, gold])
    #expect(gruppen[sap] == [a])
    #expect(gruppen[gold] == [b])
}

// MARK: Doppelte

@Test func adresseNormalisiert() {
    let url = URL(string: "http://www.Finanzen.net/nachricht/x/?utm_source=rss&id=5&fbclid=abc#oben")!
    #expect(Doppelte.schluessel(fuer: url) == "https://finanzen.net/nachricht/x?id=5")
    #expect(Doppelte.schluessel(fuer: URL(string: "https://example.org/")!) == "https://example.org")
}

@Test func doppelteZusammengefuehrt() {
    let erste = meldung("DAX steigt etwas", link: "https://www.finanzen.net/a?utm_medium=feed",
                        zeit: zeit("2026-10-01T08:00:00Z"))
    let gleicheAdresse = meldung("DAX steigt etwas (Update)", anriss: "Mehr dazu", link: "https://finanzen.net/a",
                                 zeit: zeit("2026-10-01T08:05:00Z"), symbole: ["DAX"])
    let gleicherTitel = meldung("DAX steigt etwas!", link: "https://andere.de/b",
                                zeit: zeit("2026-10-01T08:10:00Z"), symbole: ["SAP"])
    let neuer = meldung("Gold fällt", link: "https://andere.de/c", zeit: zeit("2026-10-01T09:00:00Z"))
    let ergebnis = Doppelte.entferne([erste, gleicheAdresse, gleicherTitel, neuer])
    #expect(ergebnis.map(\.titel) == ["Gold fällt", "DAX steigt etwas"])
    #expect(ergebnis[1].anriss == "Mehr dazu")
    #expect(ergebnis[1].symbole == ["DAX", "SAP"])
}

// MARK: Budget und Feeds

@Test func budgetJeTag() {
    var budget = Abrufbudget(grenzeJeTag: 2, jetzt: zeit("2026-10-02T22:00:00Z"))
    #expect(budget.buche(jetzt: zeit("2026-10-02T22:00:00Z")))
    #expect(budget.buche(jetzt: zeit("2026-10-02T23:00:00Z")))
    #expect(!budget.buche(jetzt: zeit("2026-10-02T23:59:59Z")))
    #expect(budget.rest(jetzt: zeit("2026-10-02T23:59:59Z")) == 0)
    // Neuer Tag in UTC.
    #expect(budget.rest(jetzt: zeit("2026-10-03T00:00:00Z")) == 2)
    #expect(budget.buche(jetzt: zeit("2026-10-03T00:00:00Z")))
    #expect(budget.verbraucht == 1)
}

@Test func feedlisteNurHTTPSOhneDoppelte() {
    let adressen = Feedliste.standard.map(\.adresse)
    #expect(adressen.allSatisfy { $0.scheme == "https" })
    #expect(Set(adressen).count == adressen.count)
    #expect(Set(Feedliste.standard.map(\.bereich)) == Set(Feed.Bereich.allCases))
}
