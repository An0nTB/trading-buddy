#if os(macOS)
import Foundation
import TradingCore
import TradingNews
import TradingQuotes
import TradingRates
import TradingStore

/// Ordner, in den die App Daten für den Claude-Connector schreibt.
/// Der Nutzer wählt ihn einmal; die App merkt sich den Zugriff als
/// Security-scoped Bookmark, damit er nach einem Neustart erhalten bleibt.
enum ExportOrdner {
    static let schluessel = "exportOrdnerLesezeichen"

    /// Merkt sich den Ordner aus dem Auswahldialog.
    static func merke(_ url: URL) throws {
        let zugriff = url.startAccessingSecurityScopedResource()
        defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
        let daten = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(daten, forKey: schluessel)
    }

    static func gemerkterOrdner() -> URL? {
        guard let daten = UserDefaults.standard.data(forKey: schluessel) else { return nil }
        var veraltet = false
        guard let url = try? URL(
            resolvingBookmarkData: daten, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &veraltet)
        else { return nil }
        if veraltet { try? merke(url) }
        return url
    }

    /// Exportdatei für den Connector aus allen Konten des Journals, mit dem Stop aus dem Journal
    /// wie in der App (`Trade.mitJournal`), den übrigen Journalangaben, den Review-Zielen, den Handelsregeln,
    /// den Tagesnotizen, den verpassten Trades, den Tageskerzen geladener Kurse, den EZB-Kursen für Trades in
    /// fremder Währung und den Ausstiegsanalysen aus `ausstieg` (Konto nach `ausstiegskonto` → Trade-ID → Analyse,
    /// damit gleiche Tickets in zwei Konten nicht dieselbe Analyse bekommen). Ohne Kontonamen und Rohzeilen;
    /// von der Kontonummer nur die letzten vier Stellen, damit Claude die Konten unterscheiden kann
    /// (mehr nur, wenn zwei Konten desselben Brokers auf dieselben vier Stellen enden).
    static func export(_ journal: Journal, zeitzone: TimeZone,
                       ausstieg: [String: [String: Ausstiegsanalyse]] = [:]) throws -> JournalExport {
        let alle = try journal.konten()
        let konten = try alle.map { konto in
            let eintraege = try journal.journaleintraege(konto: konto)
            let andere = alle.filter { $0.broker == konto.broker }.map(\.kontonummer)
            let stellen = JournalExport.endziffern(konto.kontonummer, neben: andere)
            let trades = try Self.trades(journal, konto).map { $0.mitJournal(eintraege[$0.id]) }
            let nummer = String(konto.kontonummer.suffix(stellen))
            let analysen = ausstieg[ausstiegskonto(konto.broker, nummer)] ?? [:]
            return JournalExport.Kontodaten(
                broker: konto.broker, kontonummer: nummer, waehrung: konto.waehrung,
                trades: trades,
                geloeschteOrders: try journal.geloeschteOrders(konto: konto).map(\.cancelledAt),
                journal: eintraege.mapValues(\.angaben),
                ziele: try journal.ziele(konto: konto),
                regeln: try journal.handelsregeln(konto: konto),
                ausstieg: trades.compactMap { analysen[$0.id].map { JournalExport.Ausstieg($0) } })
        }
        // Tonfall aus den Einstellungen (AP11, `Ton`); ohne Wahl gilt in der App „bro“.
        let ton = Ton.aktuell.rawValue
        // Tagesnotizen und verpasste Trades gelten für alle Konten; Bilder bleiben auf dem Mac.
        let notizen = try journal.tagesnotizen(von: Journaltag(jahr: 1970, monat: 1, tag: 1)!,
                                               bis: Journaltag(jahr: 2999, monat: 12, tag: 31)!)
        let verpasst = try journal.verpassteTrades(von: .distantPast, bis: .distantFuture)
        return JournalExport(konten: konten, zeitzone: zeitzone, ton: ton,
                             tagesnotizen: notizen.map(JournalExport.Notiz.init),
                             verpassteTrades: verpasst.map(JournalExport.Verpasst.init),
                             nachrichten: nachrichten(journal), kursverlauf: kursverlauf(),
                             referenzkurse: referenzkurse(konten))
    }

    /// EZB-Referenzkurse aus dem Zwischenspeicher von TradingRates, nur für die Tage und Währungen der Trades in
    /// fremder Währung; der Connector rechnet damit wie die App in die Kontowährung um. Ohne Speicher keine Kurse.
    private static func referenzkurse(_ konten: [JournalExport.Kontodaten]) -> [JournalExport.Tageskurse] {
        guard let inhalt = Kursspeicher(datei: Kursspeicher.standardDatei()).lies() else { return [] }
        return JournalExport.referenzkursauszug(Referenzkurse(kurse: inhalt.kurse), fuer: konten)
    }

    /// Tageskerzen aus dem Zwischenspeicher der Kurse (TradingQuotes, A1) unter dem Journal-Symbol, für
    /// `hole_kursanalyse` im Connector. Die laufende Kerze kommt mit `laufend` mit. Ohne Speicher keine Reihen.
    private static func kursverlauf() -> [JournalExport.Kursreihe] {
        guard let stand = Verlaufsspeicher(datei: Verlaufsspeicher.standardDatei()).lies() else { return [] }
        return stand.verlaeufe.values.map { v in
            JournalExport.Kursreihe(
                symbol: v.journalSymbol, quelle: v.quelle, waehrung: v.waehrung ?? "unbekannt", stand: v.geladen,
                kerzen: v.kerzen.compactMap { k in
                    Journaltag(k.handelstag).map {
                        Kerze(tag: $0, open: k.eroeffnung, high: k.hoch, low: k.tief, close: k.schluss,
                              volumen: k.volumen, laufend: !k.abgeschlossen)
                    }
                })
        }
    }

    /// Meldungen der letzten Tage aus dem Zwischenspeicher der Nachrichtenseite, mit den passenden Begriffen der
    /// Merkliste (gleiche Zuordnung wie die Seite). Nur wenn die Nachrichten eingeschaltet sind; ohne Zwischenspeicher
    /// keine Meldungen. Der Nachrichtendienst schreibt den Export nach jedem Abruf neu.
    private static func nachrichten(_ journal: Journal, jetzt: Date = .now) -> [JournalExport.Meldung] {
        guard UserDefaults.standard.bool(forKey: Nachrichtendienst.schluesselAktiv) else { return [] }
        let seit = jetzt.addingTimeInterval(-Double(JournalExport.nachrichtenTage) * 86_400)
        let meldungen = Zwischenspeicher(datei: Nachrichtendienst.zwischenspeicherDatei).lies(jetzt: jetzt)
            .filter { $0.zeit >= seit }
        let eintraege = ((try? journal.merkliste()) ?? []).filter { $0.status == .aktiv }
        let gruppen = Zuordnung.gruppiert(meldungen, nach: eintraege.map(Nachrichtendienst.begriff))
        var begriffe: [String: [String]] = [:]
        for eintrag in eintraege {
            let name = eintrag.anzeigename.isEmpty ? eintrag.begriff : eintrag.anzeigename
            for m in gruppen[Nachrichtendienst.begriff(eintrag)] ?? [] { begriffe[m.id, default: []].append(name) }
        }
        return meldungen.map { m in
            JournalExport.Meldung(titel: m.titel, anriss: m.anriss, quelle: m.quelle, link: m.link.absoluteString,
                                  zeit: m.zeit, symbole: m.symbole, merkliste: begriffe[m.id] ?? [])
        }
    }

    /// Abgeschlossene Trades eines Kontos wie in der App: Positionen aus MetaTrader und XTB,
    /// dazu aus Käufen und Verkäufen gebildete Trades (Trade Republic, Scalable).
    private static func trades(_ journal: Journal, _ konto: Konto) throws -> [Trade] {
        let bewegungen = try journal.kontobewegungen(konto: konto)
        let gebildet = Positionsbildung.bilde(bewegungen.ausfuehrungen, kapitalmassnahmen: bewegungen.kapitalmassnahmen)
        return try journal.geschlossenePositionen(konto: konto).map { Trade($0) } + gebildet.trades
    }

    /// Schreibt `trading-buddy-export.json` in den gewählten Ordner, nach jedem Import und beim Start.
    /// Gibt den Stand als Text für die Einstellungen zurück.
    /// Die Ausstiegsanalysen kommen aus dem letzten Lauf von `aktualisiereAusstieg`; ändern sie sich, schreibt
    /// dieser Lauf die Datei ein zweites Mal.
    @discardableResult @MainActor
    static func schreibe(_ journal: Journal?, zeitzone: TimeZone = .current) -> String {
        guard let journal else { return String(localized: "Export: Journal nicht geöffnet") }
        guard let ordner = gemerkterOrdner() else {
            return UserDefaults.standard.data(forKey: schluessel) == nil
                ? String(localized: "Export: noch kein Ordner gewählt")
                : String(localized: "Export: Ordner nicht erreichbar, bitte neu wählen")
        }
        guard ordner.startAccessingSecurityScopedResource() else {
            return String(localized: "Export: kein Zugriff auf \(ordner.path)")
        }
        defer { ordner.stopAccessingSecurityScopedResource() }
        do {
            let daten = try export(journal, zeitzone: zeitzone, ausstieg: ausstieg)
            try daten.json().write(to: ordner.appending(path: JournalExport.dateiname), options: .atomic)
            let jeKonto = Dictionary(daten.konten.map { (ausstiegskonto($0.broker, $0.kontonummer), $0.trades) },
                                     uniquingKeysWith: { erste, _ in erste })
            aktualisiereAusstieg(jeKonto, journal: journal, zeitzone: zeitzone)
            let trades = daten.konten.reduce(0) { $0 + $1.trades.count }
            return String(localized: "Export: \(trades) Trades aus \(daten.konten.count) Konten, \(Date.now.formatted(date: .omitted, time: .shortened))")
        } catch {
            return String(localized: "Export: Fehler \(error.localizedDescription)")
        }
    }

    /// Ausstiegsanalysen (Doc 39, B4) zum Stand `ausstiegStand`, für den nächsten Export; je Konto, weil
    /// Tickets nur innerhalb eines Kontos eindeutig sind (Befund G25, Doc 49).
    @MainActor private static var ausstieg: [String: [String: Ausstiegsanalyse]] = [:]

    /// Schlüssel eines Kontos im Export: Broker und die exportierten Endziffern (`JournalExport.endziffern`
    /// macht sie je Broker eindeutig).
    static func ausstiegskonto(_ broker: String, _ nummer: String) -> String { broker + "\u{1F}" + nummer }
    @MainActor private static var ausstiegStand: Ausstiegsstand?
    @MainActor private static var ausstiegLaeuft = false
    /// Während eines Laufs kam ein neuer Export: danach noch einmal mit dessen Trades rechnen.
    @MainActor private static var ausstiegNachlauf = false

    /// Wozu die Analysen passen: Kerzenspeicher und Trades. Gleich bleibt gleich, dann rechnet nichts neu.
    private struct Ausstiegsstand: Equatable {
        var kerzen: Int
        var bestand: [Kerzenbestand]
        var trades: [String: [Trade]]
    }

    /// Rechnet die Ausstiegsanalysen im Hintergrund wie die Seite „Ausstieg“ (`Ausstiegsdienst`, Minutenkerzen
    /// auf dem Mac) und schreibt den Export neu, wenn sich etwas geändert hat. Liest die Kerzen nur, wenn sich
    /// Speicher oder Trades seit dem letzten Lauf geändert haben, nicht bei jedem Nachrichtenabruf.
    @MainActor
    private static func aktualisiereAusstieg(_ trades: [String: [Trade]], journal: Journal, zeitzone: TimeZone) {
        guard !ausstiegLaeuft else {
            ausstiegNachlauf = true
            return
        }
        ausstiegLaeuft = true
        ausstiegNachlauf = false
        Task { @MainActor in
            let dienst = Ausstiegsdienst.geteilt
            await dienst.ladeBestand()
            let stand = Ausstiegsstand(kerzen: dienst.stand, bestand: dienst.bestand, trades: trades)
            guard stand != ausstiegStand else {
                ausstiegLaeuft = false
                if ausstiegNachlauf { schreibe(journal, zeitzone: zeitzone) }
                return
            }
            var neu: [String: [String: Ausstiegsanalyse]] = [:]
            for (konto, liste) in trades {
                let analysen = await dienst.analysen(liste)
                if !analysen.isEmpty { neu[konto] = analysen }
            }
            ausstiegStand = stand
            ausstiegLaeuft = false
            if neu != ausstieg || ausstiegNachlauf {
                ausstieg = neu
                schreibe(journal, zeitzone: zeitzone)
            }
        }
    }
}
#endif
