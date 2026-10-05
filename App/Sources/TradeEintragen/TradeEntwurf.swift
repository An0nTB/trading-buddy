import Foundation
import TradingCore

/// Formular „Trade eintragen“ ohne Ansicht (Doc 02 Nr. 63, Vorlage: Browser-Journal): Felder, Prüfung und
/// Vorschau des Ergebnisses. Gerechnet wird nur über `ManuellerTrade`, damit Formular und Import der
/// Journal-Sicherung gleich rechnen. Nur geschlossene Trades; offene kommen später.
struct TradeEntwurf: Equatable {
    /// Stop als Kurs oder als geplantes Risiko in Kontowährung (Vorlage: nur Risiko).
    enum StopArt: String, CaseIterable, Identifiable {
        case kurs, risiko
        var id: String { rawValue }
    }

    /// Konto, in das der Trade geht: ein vorhandenes oder ein neues für Handeinträge.
    enum Kontowahl: Hashable {
        case bestehend(Int64)
        case neu
    }

    /// Zeiteinheiten der Vorlage; leer heißt ohne Angabe.
    static let zeiteinheiten = ["M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1"]
    /// Währungen für ein neues Konto, wie im Import-Blatt.
    static let waehrungen = ["EUR", "USD", "GBP", "CHF"]

    var einstieg: Date
    var ausstiegBekannt = true
    var ausstieg: Date
    var symbol = ""
    var produktart: Produktart = .unbekannt
    var markterwartung: Side = .buy
    /// Abrechnung „Schein gekauft“ (Knock-out, Optionsschein, Zertifikat) statt „direkt gehandelt“.
    var schein = false
    /// Name des Setups aus dem Playbook; leer heißt ohne.
    var setup = ""
    /// Leer heißt ohne Angabe.
    var zeiteinheit = ""
    var groesse: Decimal?
    var einstiegskurs: Decimal?
    var ausstiegskurs: Decimal?
    var stopArt: StopArt = .risiko
    var stopKurs: Decimal?
    var risiko: Decimal?
    var gebuehren: Decimal?
    var planEingehalten = true
    var gedanken = ""
    var kontowahl: Kontowahl = .neu
    var neuerKontoname = ""
    var neueWaehrung = "EUR"

    /// Einstieg jetzt, Ausstieg zur selben Zeit; die Uhrzeit stellt der Nutzer ein.
    init(jetzt: Date = Date()) {
        einstieg = jetzt
        ausstieg = jetzt
    }

    /// Fehlende Pflichtangaben vor der fachlichen Prüfung.
    enum Luecke: Equatable {
        case groesse, einstiegskurs, ausstiegskurs, kontoname
    }

    func luecken() -> [Luecke] {
        var liste: [Luecke] = []
        if groesse == nil { liste.append(.groesse) }
        if einstiegskurs == nil { liste.append(.einstiegskurs) }
        if ausstiegskurs == nil { liste.append(.ausstiegskurs) }
        if kontowahl == .neu, neuerKontoname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            liste.append(.kontoname)
        }
        return liste
    }

    /// Der Trade für Speichern und Vorschau; `nil`, solange Größe oder Kurse fehlen.
    /// Ein Schein ist immer ein Derivat; ohne Wahl bleibt die Produktart `unbekannt`.
    var trade: ManuellerTrade? {
        guard let groesse, let einstiegskurs, let ausstiegskurs else { return nil }
        let symbolGetrimmt = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return ManuellerTrade(symbol: symbolGetrimmt, einstieg: einstieg, ausstieg: ausstiegBekannt ? ausstieg : nil,
                              markterwartung: markterwartung, schein: schein, groesse: groesse,
                              einstiegskurs: einstiegskurs, ausstiegskurs: ausstiegskurs,
                              stopKurs: stopArt == .kurs ? stopKurs : nil,
                              risiko: stopArt == .risiko ? risiko.flatMap { $0 == 0 ? nil : abs($0) } : nil,
                              gebuehren: abs(gebuehren ?? 0),
                              produktart: schein ? .derivat : produktart)
    }

    /// Fachliche Probleme des Trades (leer, wenn er gespeichert werden kann) plus fehlende Angaben.
    var probleme: [ManuellerTrade.Problem] { trade?.pruefe() ?? [] }

    var speicherbar: Bool { luecken().isEmpty && trade != nil && probleme.isEmpty }

    /// Angaben, die keine Spalte der Position sind; leere Texte werden `nil`.
    var angaben: TradeAngaben {
        TradeAngaben(setup: Self.ohneLeere(setup), zeiteinheit: Self.ohneLeere(zeiteinheit),
                     regeltreue: planEingehalten, notiz: Self.ohneLeere(gedanken))
    }

    /// Ergebnis nach Gebühren in Kontowährung; `nil`, solange Größe oder Kurse fehlen.
    var netto: Decimal? {
        guard let trade else { return nil }
        return trade.ergebnis - trade.gebuehren
    }

    /// Risiko des Trades aus Stop oder Betrag: Abstand Einstieg bis Stop mal Größe. `nil` ohne Stop oder
    /// mit Stop auf der Gewinnseite. Wert je Kurspunkt = Größe, wie in `ManuellerTrade.ergebnis`.
    var eigenesRisiko: Decimal? {
        guard let trade, let stop = trade.stop else { return nil }
        let abstand = trade.handelsseite == .buy ? trade.einstiegskurs - stop : stop - trade.einstiegskurs
        guard abstand > 0 else { return nil }
        return abstand * trade.groesse
    }

    /// Ergebnis in R mit eigenem Risiko, sonst mit dem Standard-Risiko aus Setup oder Konto (Nr. 64, „angenommen“).
    func rWert(standardRisiko: Decimal?) -> Decimal? {
        guard let netto, let risiko = eigenesRisiko ?? standardRisiko, risiko > 0 else { return nil }
        return netto / risiko
    }

    /// Hebelprodukt im Namen (Scalable, Trade Republic): stellt Abrechnung und Markterwartung vor.
    /// Gibt das erkannte Produkt zurück, damit die Ansicht es nennen kann.
    @discardableResult
    mutating func uebernimmHebelprodukt() -> Hebelprodukt? {
        guard let erkannt = Hebelprodukt.erkenne(symbol) else { return nil }
        schein = true
        markterwartung = erkannt.markterwartung
        return erkannt
    }

    /// Text des Problems für die Ansicht, in Alltagssprache. Bei Scheinen heißt Einstieg der Kaufkurs des Scheins.
    static func text(_ problem: ManuellerTrade.Problem) -> String {
        switch problem {
        case .symbolLeer: String(localized: "Asset fehlt.")
        case .groesseNichtPositiv: String(localized: "Die Größe muss über 0 liegen.")
        case .kursNichtPositiv: String(localized: "Einstieg muss über 0 liegen, Exit auch (nur ein Schein darf mit 0 enden).")
        case .ausstiegVorEinstieg: String(localized: "Die Ausstiegszeit liegt vor dem Einstieg.")
        case .stopAufFalscherSeite: String(localized: "Der Stop liegt auf der Gewinnseite des Einstiegs.")
        }
    }

    static func text(_ luecke: Luecke) -> String {
        switch luecke {
        case .groesse: String(localized: "Größe fehlt.")
        case .einstiegskurs: String(localized: "Entry fehlt.")
        case .ausstiegskurs: String(localized: "Exit fehlt; offene Trades kommen später.")
        case .kontoname: String(localized: "Name für das neue Konto fehlt.")
        }
    }

    /// Alle Gründe, warum „Trade sichern“ grau ist, in fester Reihenfolge.
    var hinderungsgruende: [String] {
        luecken().map(Self.text) + probleme.map(Self.text)
    }

    private static func ohneLeere(_ text: String) -> String? {
        let getrimmt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return getrimmt.isEmpty ? nil : getrimmt
    }
}

/// Angaben aus dem Formular und aus der Journal-Sicherung, die keine Spalte der Position sind.
struct TradeAngaben: Equatable {
    var setup: String?
    var zeiteinheit: String?
    var regeltreue: Bool?
    var notiz: String?
}
