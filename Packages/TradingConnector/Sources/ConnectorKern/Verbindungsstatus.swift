import Foundation
import TradingCore

/// Werkzeug `henry_status` (Beta-Punkte 17 und 18): Tester sehen sofort, ob Claude Henrys Daten bekommt und was
/// zu tun ist, wenn nicht. Antwortet auch ohne lesbare Exportdatei.
public enum Verbindungsstatus {
    /// Version der Erweiterung; dieselbe steht in `Connector/manifest.json` (CI prüft das).
    public static let connectorVersion = "0.16.1"
    /// Ab diesem Alter gilt der Export als veraltet.
    public static let hoechstesAlter: TimeInterval = 24 * 3_600

    public static func text(_ ergebnis: Exportdatei.Ergebnis, ordner: String?, jetzt: Date = .now) -> String {
        var t = ["# Henry · Status",
                 "Erweiterung \(connectorVersion), liest Exportdateien bis Format \(JournalExport.aktuellesFormat), "
                     + "Rechenkern \(TradingCore.version).",
                 "Export-Ordner in der Erweiterung: \(ordner.flatMap { $0.isEmpty ? nil : $0 } ?? "nicht eingetragen")."]
        guard case let .geladen(export) = ergebnis else {
            t.append("VERBINDUNG FEHLT. " + (Exportdatei.meldung(ergebnis) ?? ""))
            t.append(abhilfe(ergebnis))
            return t.joined(separator: "\n")
        }
        let trades = export.konten.reduce(0) { $0 + $1.trades.count }
        let alter = jetzt.timeIntervalSince(export.erstellt)
        t.append("VERBINDUNG STEHT. Export vom \(Format.datum(export.erstellt, export.nutzerZeitzone)) "
            + "(\(alterstext(alter))), Format \(export.format), Rechenkern der App \(export.rechenkern): "
            + "\(export.konten.count) Konten, \(trades) Trades.")
        if export.konten.isEmpty {
            t.append("HINWEIS: Noch kein Konto importiert. In Henry einen Kontoauszug importieren, dann neu fragen.")
        }
        if alter > hoechstesAlter {
            t.append("HINWEIS: Der Export ist älter als 24 Stunden. Henry öffnen: Die App schreibt den Export beim Start, "
                + "nach jedem Import und unter Einstellungen > Claude neu. Neue Trades fehlen bis dahin.")
        }
        if export.rechenkern != TradingCore.version {
            t.append("HINWEIS: App und Erweiterung haben verschiedene Rechenkerne (App \(export.rechenkern), Erweiterung "
                + "\(TradingCore.version)). Zahlen können von der App abweichen; App und Erweiterung auf denselben "
                + "Stand bringen.")
        }
        t.append("Antwort an den Nutzer: in ein bis zwei Sätzen, ob die Verbindung steht, Stand des Exports und, falls "
            + "es einen Hinweis gibt, was zu tun ist.")
        return t.joined(separator: "\n")
    }

    static func abhilfe(_ ergebnis: Exportdatei.Ergebnis) -> String {
        let ordner = "In Henry unter Einstellungen > Claude einen Export-Ordner wählen und in Claude Desktop unter "
            + "Einstellungen > Erweiterungen > Henry denselben Ordner eintragen, danach Claude Desktop neu starten."
        switch ergebnis {
        case .geladen: return ""
        case .keinOrdner, .fehlt: return "Was tun: " + ordner
        case .keinZugriff: return "Was tun: Den Ordner in den Einstellungen der Erweiterung neu auswählen. Liegt er unter "
            + "Dokumente oder Schreibtisch, beim ersten Zugriff die Erlaubnisfrage von macOS bestätigen."
        case .unlesbar: return "Was tun: Henry öffnen, damit die App den Export neu schreibt; meldet die Erweiterung ein "
            + "neueres Format, die neueste Erweiterung installieren."
        }
    }

    static func alterstext(_ sekunden: TimeInterval) -> String {
        if sekunden < 0 { return "Zeitpunkt liegt in der Zukunft, Uhr prüfen" }
        let minuten = Int(sekunden / 60)
        if minuten < 1 { return "gerade eben" }
        if minuten < 60 { return "vor \(minuten) Minuten" }
        let stunden = minuten / 60
        if stunden < 48 { return "vor \(stunden) Stunden" }
        return "vor \(stunden / 24) Tagen"
    }
}
