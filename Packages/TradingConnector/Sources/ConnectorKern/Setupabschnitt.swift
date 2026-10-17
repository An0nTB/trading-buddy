import Foundation
import TradingCore

extension Anfrage {
    /// Stand des Kill-Kriteriums je Setup (E7) für die Kontoart dieses Kontos, aus den Karten der Datei. Die App
    /// zählt über alle Konten derselben Art und alle Zeiträume; Demo und Echtgeld getrennt (E1). Leer ohne Karte mit
    /// „Prüfung nach N Trades“ oder ohne Trades dazu.
    func setuppruefungAbschnitt() -> [String] {
        let art = konto.art
        let staende = (export.playbook ?? []).flatMap { $0.pruefung ?? [] }
            .filter { $0.kontoart == art.rawValue }
            .sorted { (Self.rang($0), $1.setup) > (Self.rang($1), $0.setup) }
        guard !staende.isEmpty else { return [] }
        let welche = art == .demo ? "Demo-Konten" : "Echtgeld-Konten"
        var t = ["\n## Prüfung der Setups (Kill-Kriterium; alle \(welche), alle Zeiträume, gezählt in der App)"]
        t.append(Format.tabelle(["Setup", "Trades", "Prüfung nach", "Erw. R nach Kosten (Trades mit R)", "Stand"],
                                staende.map(Self.pruefzeile)))
        t.append("Regel: Nach N Trades zählt der Erwartungswert in R nach Kosten; ist er nicht positiv, ist das "
            + "Kill-Kriterium erreicht" + (art == .demo ? " und das Setup geht nach der eigenen Regel nicht auf Echtgeld." : "."))
        if staende.contains(where: \.faellig) {
            t.append("Antwort: Fällige Prüfungen im Review mit Anzahl und Erwartungswert in R nennen.")
        }
        return t
    }

    /// Nicht bestanden vor fällig vor offen.
    static func rang(_ s: Setuppruefung) -> Int { s.nichtBestanden ? 2 : s.faellig ? 1 : 0 }

    static func pruefzeile(_ s: Setuppruefung) -> [String] {
        let angenommen = s.anzahlRAngenommen > 0 ? ", davon \(s.anzahlRAngenommen) angenommen" : ""
        let stand: String
        if s.nichtBestanden {
            stand = "FÄLLIG, Kill-Kriterium erreicht"
        } else if s.faellig {
            stand = "fällig, bestanden"
        } else {
            stand = "noch \(s.schwelle - s.anzahl) Trades bis zur Prüfung"
        }
        return [s.setup, "\(s.anzahl)", "\(s.schwelle)", "\(Format.r(s.erwartungswertR)) (\(s.anzahlMitR)\(angenommen))",
                stand]
    }
}
