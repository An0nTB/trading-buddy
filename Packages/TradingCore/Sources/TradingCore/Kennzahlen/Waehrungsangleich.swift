import Foundation

/// Bringt die Beträge aller Trades eines Kontos in die Kontowährung (Doc 40, W1–W3), bevor Kennzahlen,
/// Regeln, Kapitalverlauf oder Monatsbericht summieren. Umgerechnet wird mit den Referenzkursen am Schlusstag
/// wie in der Steuer-Orientierung (Näherung). Kurse (Einstieg, Ausstieg, Stop) bleiben in der Kurswährung;
/// der Wert je Kurspunkt und damit `risk` und R folgen dem umgerechneten Ergebnis. `geplantesRisiko` steht schon
/// in Kontowährung und bleibt, wie es ist; R aus dem geplanten Risiko daher nur auf angeglichenen Trades rechnen.
public struct Waehrungsangleich: Sendable, Equatable {
    /// Alle Trades in Kontowährung, Reihenfolge wie übergeben, ohne `ohneKurs`.
    public var trades: [Trade]
    /// IDs der umgerechneten Trades.
    public var umgerechnet: Set<String>
    /// Trades in fremder Währung ohne Kurs am Schlusstag: nicht in `trades`, damit keine Summe sie
    /// als Kontowährung zählt.
    public var ohneKurs: [Trade]
    /// Fremde Währungen in den übergebenen Trades, sortiert.
    public var fremdwaehrungen: [String]

    /// IDs aus `ohneKurs`. Die Regelprüfung zählt diese Trades mit, rechnet aber nicht mit ihren Beträgen
    /// (Dritter Gegencheck G1, Doc 49).
    public var ohneKursIDs: Set<String> { Set(ohneKurs.map(\.id)) }

    /// - Parameter zeitzone: bestimmt den Kurstag. Vorgabe deutsche Zeit wie bei der EZB und der
    ///   Steuer-Orientierung; App, Bericht und Connector übergeben keine andere, damit derselbe Trade überall
    ///   denselben Kurs bekommt (Dritter Gegencheck G6, Doc 49).
    public init(_ trades: [Trade], kontowaehrung: String, kurse: Referenzkurse?,
                zeitzone: TimeZone = Steuerorientierung.deutscheZeit) {
        let konto = kontowaehrung.uppercased()
        var angeglichen: [Trade] = []
        var umgerechnet: Set<String> = []
        var ohneKurs: [Trade] = []
        var fremd: Set<String> = []
        for t in trades {
            let waehrung = t.waehrung(kontowaehrung: konto)
            guard waehrung != konto else { angeglichen.append(t); continue }
            fremd.insert(waehrung)
            // Ohne Kurse rechnet ein leerer Satz: Gleichgesetztes (USDT wie USD) bleibt so umrechenbar (G5).
            let satz = kurse ?? Referenzkurse(kurse: [:])
            guard let faktor = satz.umrechnen(1, von: waehrung, nach: konto, am: t.closeTime, zeitzone: zeitzone)
            else { ohneKurs.append(t); continue }
            var u = t
            u.profit = t.profit * faktor
            u.commission = t.commission * faktor
            u.swap = t.swap * faktor
            u.taxes = t.taxes * faktor
            u.waehrung = nil
            angeglichen.append(u)
            umgerechnet.insert(t.id)
        }
        self.trades = angeglichen
        self.umgerechnet = umgerechnet
        self.ohneKurs = ohneKurs
        fremdwaehrungen = fremd.sorted()
    }
}
