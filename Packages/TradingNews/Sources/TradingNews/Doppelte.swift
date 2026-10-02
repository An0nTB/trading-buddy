import Foundation

/// Dieselbe Meldung kommt oft über mehrere Feeds. Abgleich über normalisierte Adresse und Überschrift.
public enum Doppelte {
    /// Parameter, die nur der Reichweitenmessung dienen und die Adresse nicht ändern.
    static let messparameter: Set<String> = ["fbclid", "gclid", "ref", "rss", "feed", "src", "source"]

    /// Kleinbuchstaben für Schema und Host, ohne „www.“, ohne Anker, ohne Messparameter (utm_* und Liste oben),
    /// ohne Schrägstrich am Ende.
    public static func schluessel(fuer url: URL) -> String {
        guard var teile = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        teile.scheme = "https"
        if var host = teile.host?.lowercased() {
            if host.hasPrefix("www.") { host.removeFirst(4) }
            teile.host = host
        }
        teile.fragment = nil
        while teile.path.count > 1 && teile.path.hasSuffix("/") { teile.path.removeLast() }
        let behalten = (teile.queryItems ?? []).filter { eintrag in
            let name = eintrag.name.lowercased()
            return !name.hasPrefix("utm_") && !messparameter.contains(name)
        }
        teile.queryItems = behalten.isEmpty ? nil : behalten
        var text = teile.string ?? url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// Überschrift nur mit Buchstaben und Ziffern, klein geschrieben.
    public static func titelSchluessel(_ titel: String) -> String {
        Zuordnung.woerter(titel).joined(separator: " ")
    }

    /// Entfernt Doppelte. Behält die erste Meldung, ergänzt fehlenden Anriss und vereinigt die Symbole.
    /// Ergebnis neueste zuerst.
    public static func entferne(_ meldungen: [Meldung]) -> [Meldung] {
        var ergebnis: [Meldung] = []
        var nachID: [String: Int] = [:]
        var nachTitel: [String: Int] = [:]
        for meldung in meldungen {
            let titel = titelSchluessel(meldung.titel)
            if let stelle = nachID[meldung.id] ?? (titel.isEmpty ? nil : nachTitel[titel]) {
                var vorhanden = ergebnis[stelle]
                if vorhanden.anriss == nil { vorhanden.anriss = meldung.anriss }
                for symbol in meldung.symbole where !vorhanden.symbole.contains(symbol) {
                    vorhanden.symbole.append(symbol)
                }
                ergebnis[stelle] = vorhanden
                continue
            }
            nachID[meldung.id] = ergebnis.count
            if !titel.isEmpty { nachTitel[titel] = ergebnis.count }
            ergebnis.append(meldung)
        }
        return ergebnis.sorted { $0.zeit > $1.zeit }
    }
}
