import Foundation
import TradingCore

/// Werkzeug `henry_status` (Beta-Punkte 17 und 18): Tester sehen sofort, ob Claude Henrys Daten bekommt und was
/// zu tun ist, wenn nicht. Antwortet auch ohne lesbare Exportdatei.
public enum Verbindungsstatus {
    /// Version der Erweiterung; dieselbe steht in `Connector/manifest.json` (CI prüft das).
    public static let connectorVersion = "0.21.0"
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
        if let warnung = versionswarnung(export) { t.insert(warnung, at: 1) }
        if export.konten.isEmpty {
            t.append("HINWEIS: Noch kein Konto importiert. In Henry einen Kontoauszug importieren, dann neu fragen.")
        } else {
            t.append("Konten: " + export.konten.map { "\(export.kurzname($0)) \(artname($0))" }.joined(separator: ", ") + ".")
        }
        t.append(contentsOf: pruefstand(export))
        if alter > hoechstesAlter {
            t.append("HINWEIS: Der Export ist älter als 24 Stunden. Henry öffnen: Die App schreibt den Export beim Start, "
                + "nach jedem Import und unter Einstellungen > Claude neu. Neue Trades fehlen bis dahin.")
        }
        t.append("Antwort an den Nutzer: in ein bis zwei Sätzen, ob die Verbindung steht, Stand des Exports und, falls "
            + "es eine Warnung oder einen Hinweis gibt, was zu tun ist; eine Warnung zuerst.")
        return t.joined(separator: "\n")
    }

    /// Warnung, wenn App und Erweiterung mit verschiedenen Rechenkernen rechnen (E9, Tim 17.10.2026): Nach einem
    /// App-Update ohne neue Erweiterung weichen Zahlen und Regeln von der App ab. `nil` bei gleichem Rechenkern.
    /// Steht in `henry_status` vorn und vor der Antwort jedes anderen Werkzeugs.
    public static func versionswarnung(_ export: JournalExport) -> String? {
        let app = export.rechenkern, eigener = TradingCore.version
        guard app != eigener else { return nil }
        if istNeuer(app, als: eigener) {
            return "WARNUNG, ERWEITERUNG VERALTET: Henry rechnet mit Rechenkern \(app), diese Erweiterung "
                + "(\(connectorVersion)) mit \(eigener). Zahlen, Regeln und neue Felder können von der App abweichen. "
                + "Was tun: die Erweiterung aus derselben Lieferung wie die App in Claude Desktop installieren "
                + "(Einstellungen > Erweiterungen, alte ersetzen) und Claude Desktop neu starten. Dem Nutzer zuerst sagen."
        }
        return "WARNUNG, APP ÄLTER ALS ERWEITERUNG: Henry rechnet mit Rechenkern \(app), diese Erweiterung "
            + "(\(connectorVersion)) mit \(eigener). Zahlen können von der App abweichen. Was tun: Henry auf den "
            + "Stand der Erweiterung bringen und einmal öffnen, damit die App den Export neu schreibt. Dem Nutzer "
            + "zuerst sagen."
    }

    /// Antwort eines Werkzeugs mit vorangestellter `versionswarnung`, wenn es eine gibt.
    public static func mitVersionswarnung(_ text: String, export: JournalExport) -> String {
        guard let warnung = versionswarnung(export) else { return text }
        return warnung + "\n\n" + text
    }

    /// Ist Version `a` (wie „0.29.0“) neuer als `b`? Teile als Zahlen verglichen, fehlende als 0; Unlesbares als 0.
    static func istNeuer(_ a: String, als b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    static func artname(_ konto: JournalExport.Kontodaten) -> String {
        konto.istBeispiel ? "Beispielkonto" : konto.art == .demo ? "Demo/Paper" : "Echtgeld"
    }

    /// Stand des Kill-Kriteriums (E7) aller Karten, je Kontoart; fällige Prüfungen zuerst. Leer ohne Prüfstände.
    static func pruefstand(_ export: JournalExport) -> [String] {
        let staende = (export.playbook ?? []).flatMap { $0.pruefung ?? [] }
            .sorted { ($0.faellig ? 1 : 0, $1.kontoart, $1.setup) > ($1.faellig ? 1 : 0, $0.kontoart, $0.setup) }
        guard !staende.isEmpty else { return [] }
        let teile = staende.map { s in
            let art = s.kontoart == Kontoart.demo.rawValue ? "Demo" : "Echtgeld"
            var text = "\(s.setup) (\(art)) \(min(s.anzahl, s.schwelle)) von \(s.schwelle) Trades"
            if s.anzahl > s.schwelle { text += " (insgesamt \(s.anzahl))" }
            if s.faellig {
                text += ", Erwartungswert \(Format.r(s.erwartungswertR)): "
                    + (s.nichtBestanden ? "FÄLLIG, Kill-Kriterium erreicht" : "fällig, bestanden")
            }
            return text
        }
        return ["Prüfung der Setups (Kill-Kriterium nach N Trades, Erwartungswert in R nach Kosten): "
            + teile.joined(separator: "; ") + "."]
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
