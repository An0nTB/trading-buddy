import TradingCore

/// Feste Gliederung der Wochen- und Monatsauswertung (R5, Kapitel 10 Abschnitt 5 und Kapitel 13 Abschnitt 4).
/// Steht am Ende jeder Auswertung, damit Claude ohne eigenen Prompt danach schreibt.
public enum Rezept {
    public static let text = """
        ## Rezept für die Antwort (Trading Buddy)
        Schreibe die Auswertung genau in dieser Gliederung:
        1. Ergebnis: Netto, Erwartungswert in R, Profitfaktor, Drawdown, verglichen mit dem Vorzeitraum.
        2. Was trug, was kostete: nach Setup, wenn im Journal erfasst, sonst nach Symbol.
        3. Fehlermuster: welche, wie oft, was sie gekostet haben (Netto und R); dazu Regeltreue und Zustand
           aus dem Journal, wenn erfasst (Regel gebrochen gegen nach Regeln).
        4. Kosten: Anteil der Kosten und Steuern; hat ein Kostenblock das Ergebnis gedreht?
        5. Ohne Regelbrüche: Ergebnis ohne die Trades eines Musters (Zeile „Ohne diese Trades“).
        6. Ziel aus dem letzten Review: danach fragen, die App speichert es noch nicht.
        7. Genau ein messbares Ziel für den nächsten Zeitraum.
        Regeln:
        - Jede Aussage nennt Zahl und Stichprobe. Unter 30 Trades nur beschreiben, nicht folgern.
        - Zeitraum und Gesamtbestand nicht verwechseln: „Gespeichert insgesamt“ gilt für alle Zeiträume.
        - Journalangaben sind eigene Einschätzungen; wenige ausgefüllte Trades so benennen.
        - Ton: kritischer Coach, Prozess vor Ergebnis, kein Lob ohne Zahl.
        - Keine Kursprognosen, keine Zielkurse, keine Kauf- oder Produktempfehlungen.
        - Nur Zahlen aus den Trading-Buddy-Werkzeugen verwenden; fehlt etwas, das sagen statt schätzen.
        - Details bei Bedarf: hole_trades (Trades je Muster, beste und schlechteste, mit Journal und Grund) und
          hole_aufschluesselung (Setup, Regeltreue, Zustand, Wochentag, Stunde, Haltedauer, Trade-Nummer am Tag,
          nach vorherigem Ergebnis).
        - Schluss: „Keine Anlageberatung. Die Auswertung beschreibt vergangene Trades.“
        """

    /// Vorlage „Monatsauswertung“ in Claude Desktop; das Rezept selbst kommt mit `hole_auswertung`.
    public static func monatsvorlage(monat: String?) -> String {
        let wahl = monat.map { "mit monat=\($0)" } ?? "ohne Zeitraum (dann gilt der letzte Monat mit Trades)"
        return "Erstelle meine Monatsauswertung\(monat.map { " für \($0)" } ?? ""). "
            + "Rufe dazu hole_auswertung \(wahl) auf und folge dem Rezept am Ende der Werkzeugantwort."
    }

    /// Vorlage „Wochenauswertung“; `datum` ist ein beliebiger Tag der Woche.
    public static func wochenvorlage(datum: String) -> String {
        "Erstelle meine Wochenauswertung für die Woche mit dem \(datum). "
            + "Rufe dazu hole_auswertung mit woche=\(datum) auf und folge dem Rezept am Ende der Werkzeugantwort."
    }
}

extension Fehlermuster {
    /// Gleiche Wortwahl wie in der App (AP11).
    var bezeichnung: String {
        switch self {
        case .revancheTrade: "Revanche-Trade"
        case .ueberhandeln: "Überhandeln"
        case .stopNichtEingehalten: "Stop nicht eingehalten"
        case .gewinneZuFrueh: "Gewinne zu früh"
        case .verliererLaufenLassen: "Verlierer laufen lassen"
        case .verbilligen: "Verbilligen"
        case .ohneStop: "Ohne Stop"
        case .schwankendeGroesse: "Schwankende Größe"
        case .groesseNachGewinnserie: "Größe nach Gewinnserie"
        case .staendigesUmplanen: "Ständiges Umplanen"
        }
    }

    /// Die Regel mit den Standardschwellen.
    var regeltext: String {
        switch self {
        case .revancheTrade: "eröffnet bis 15 Minuten nach einem Verlust, mit mehr Lots als üblich"
        case .ueberhandeln: "Tage mit mehr als Median plus 2 Trades"
        case .stopNichtEingehalten: "Verlust größer als 1,2 R"
        case .gewinneZuFrueh: "Gewinner, die weniger als die Hälfte des Wegs zum Ziel mitgenommen haben"
        case .verliererLaufenLassen: "Verlierer im Schnitt mehr als 1,5-mal so lange gehalten wie Gewinner"
        case .verbilligen: "Nachkauf in gleicher Richtung zu schlechterem Kurs, während die erste Position offen ist"
        case .ohneStop: "Trade ohne Stop-Loss"
        case .schwankendeGroesse: "Risiko je Trade stark gestreut (Variationskoeffizient über 0,5)"
        case .groesseNachGewinnserie: "nach zwei Gewinnen in Folge mehr als 1,5-mal das übliche Risiko"
        case .staendigesUmplanen: "mehr als die Hälfte der Pending Orders gelöscht"
        }
    }
}
