import Foundation

extension JournalExport {
    /// Ausstiegsanalyse eines Trades aus der App (Doc 39, Paket B4): MAE, MFE und die Bewegung nach dem Ausstieg,
    /// gerechnet aus den Kerzen auf dem Mac. Die Kerzen selbst bleiben in der App. Kurspunkte in der Kurswährung
    /// des Trades, Werte als Text wie die Beträge der Trades. Nur beschreibend, keine Aussage über künftige Kurse.
    ///
    /// `liegengelassen` steht nicht in der Datei: Der Connector rechnet es mit `analyse(_:)` aus dem Trade, den er
    /// gerade auswertet, damit es nach dem Währungsangleich in Kontowährung lautet wie in der App.
    public struct Ausstieg: Sendable, Equatable, Codable {
        public var tradeID: String
        public var kerzenDauer: Int
        public var anzahlKerzen: Int
        public var abdeckung: Decimal
        public var unscharf: Bool
        public var mae: Decimal
        public var mfe: Decimal
        public var erzielt: Decimal
        public var maeAnteil: Decimal
        public var mfeAnteil: Decimal
        public var maeR: Decimal?
        public var mfeR: Decimal?
        public var effizienz: Decimal?
        public var zeitMAE: Date?
        public var zeitMFE: Date?
        public var nachAusstiegFuer: Decimal?
        public var nachAusstiegGegen: Decimal?

        public init(_ a: Ausstiegsanalyse) {
            tradeID = a.tradeID
            kerzenDauer = a.kerzenDauer
            anzahlKerzen = a.anzahlKerzen
            abdeckung = a.abdeckung
            unscharf = a.unscharf
            mae = a.mae
            mfe = a.mfe
            erzielt = a.erzielt
            maeAnteil = a.maeAnteil
            mfeAnteil = a.mfeAnteil
            maeR = a.maeR
            mfeR = a.mfeR
            effizienz = a.effizienz
            zeitMAE = a.zeitMAE
            zeitMFE = a.zeitMFE
            nachAusstiegFuer = a.nachAusstiegFuer
            nachAusstiegGegen = a.nachAusstiegGegen
        }

        /// Zurück zur Analyse des Rechenkerns, für `Ausstiegsauswertung` im Connector. `trade` ist der Trade mit
        /// dieser ID; er liefert das Ergebnis und den Wert je Kurspunkt. Mit dem angeglichenen Trade aus
        /// `Waehrungsangleich` lautet `liegengelassen` in Kontowährung, mit dem ursprünglichen in Tradewährung.
        public func analyse(_ trade: Trade) -> Ausstiegsanalyse {
            Ausstiegsanalyse(export: self, trade: trade)
        }

        private enum CodingKeys: String, CodingKey {
            case tradeID, kerzenDauer, anzahlKerzen, abdeckung, unscharf, mae, mfe, erzielt, maeAnteil, mfeAnteil
            case maeR, mfeR, effizienz, zeitMAE, zeitMFE, nachAusstiegFuer, nachAusstiegGegen
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func zahl(_ key: CodingKeys) throws -> Decimal? {
                guard let text = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
                guard let wert = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                    throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Keine Zahl: \(text)")
                }
                return wert
            }
            func wert(_ key: CodingKeys) throws -> Decimal {
                guard let gelesen = try zahl(key) else {
                    throw DecodingError.keyNotFound(key, .init(codingPath: c.codingPath, debugDescription: "Fehlt"))
                }
                return gelesen
            }
            tradeID = try c.decode(String.self, forKey: .tradeID)
            kerzenDauer = try c.decode(Int.self, forKey: .kerzenDauer)
            anzahlKerzen = try c.decode(Int.self, forKey: .anzahlKerzen)
            abdeckung = try wert(.abdeckung)
            unscharf = try c.decode(Bool.self, forKey: .unscharf)
            mae = try wert(.mae)
            mfe = try wert(.mfe)
            erzielt = try wert(.erzielt)
            maeAnteil = try wert(.maeAnteil)
            mfeAnteil = try wert(.mfeAnteil)
            maeR = try zahl(.maeR)
            mfeR = try zahl(.mfeR)
            effizienz = try zahl(.effizienz)
            zeitMAE = try c.decodeIfPresent(Date.self, forKey: .zeitMAE)
            zeitMFE = try c.decodeIfPresent(Date.self, forKey: .zeitMFE)
            nachAusstiegFuer = try zahl(.nachAusstiegFuer)
            nachAusstiegGegen = try zahl(.nachAusstiegGegen)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(tradeID, forKey: .tradeID)
            try c.encode(kerzenDauer, forKey: .kerzenDauer)
            try c.encode(anzahlKerzen, forKey: .anzahlKerzen)
            try c.encode(abdeckung.description, forKey: .abdeckung)
            try c.encode(unscharf, forKey: .unscharf)
            try c.encode(mae.description, forKey: .mae)
            try c.encode(mfe.description, forKey: .mfe)
            try c.encode(erzielt.description, forKey: .erzielt)
            try c.encode(maeAnteil.description, forKey: .maeAnteil)
            try c.encode(mfeAnteil.description, forKey: .mfeAnteil)
            try c.encodeIfPresent(maeR?.description, forKey: .maeR)
            try c.encodeIfPresent(mfeR?.description, forKey: .mfeR)
            try c.encodeIfPresent(effizienz?.description, forKey: .effizienz)
            try c.encodeIfPresent(zeitMAE, forKey: .zeitMAE)
            try c.encodeIfPresent(zeitMFE, forKey: .zeitMFE)
            try c.encodeIfPresent(nachAusstiegFuer?.description, forKey: .nachAusstiegFuer)
            try c.encodeIfPresent(nachAusstiegGegen?.description, forKey: .nachAusstiegGegen)
        }
    }
}

extension Ausstiegsanalyse {
    /// Aus dem Export zurück; `liegengelassen` wie in `init?(trade:kerzen:nachlauf:)` aus dem Gewinn von `trade`.
    init(export a: JournalExport.Ausstieg, trade: Trade) {
        tradeID = a.tradeID
        ergebnis = trade.outcome
        kerzenDauer = a.kerzenDauer
        anzahlKerzen = a.anzahlKerzen
        abdeckung = a.abdeckung
        unscharf = a.unscharf
        mae = a.mae
        mfe = a.mfe
        erzielt = a.erzielt
        maeAnteil = a.maeAnteil
        mfeAnteil = a.mfeAnteil
        maeR = a.maeR
        mfeR = a.mfeR
        effizienz = a.effizienz
        let wertJePunkt = a.erzielt != 0 ? trade.profit / a.erzielt : 0
        liegengelassen = wertJePunkt > 0 ? (a.mfe - a.erzielt) * wertJePunkt : nil
        zeitMAE = a.zeitMAE
        zeitMFE = a.zeitMFE
        nachAusstiegFuer = a.nachAusstiegFuer
        nachAusstiegGegen = a.nachAusstiegGegen
    }
}
