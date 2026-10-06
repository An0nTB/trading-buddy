import Foundation

extension JournalExport {
    /// Best-Exit eines Trades aus der App (`BestExit`): wie feste Ziele in R gegenüber dem tatsächlichen Ausstieg
    /// ausgegangen wären, gerechnet aus den Minutenkerzen auf dem Mac. Die Kerzen bleiben in der App; der Connector
    /// fasst die Trades eines Zeitraums mit `BestExitAuswertung` zusammen. Werte als Text wie die Beträge der Trades.
    public struct BestAusstieg: Sendable, Equatable, Codable {
        public struct Stufe: Sendable, Equatable, Codable {
            public var ziel: Decimal
            /// „ziel“, „stop“ oder „tatsaechlich“ (`BestExit.Ausgang`).
            public var ausgang: String
            public var r: Decimal
            public var differenz: Decimal
            public var differenzBetrag: Decimal
            public var unscharf: Bool

            private enum CodingKeys: String, CodingKey { case ziel, ausgang, r, differenz, differenzBetrag, unscharf }

            public init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                ziel = try c.exportzahl(.ziel)
                ausgang = try c.decode(String.self, forKey: .ausgang)
                r = try c.exportzahl(.r)
                differenz = try c.exportzahl(.differenz)
                differenzBetrag = try c.exportzahl(.differenzBetrag)
                unscharf = try c.decode(Bool.self, forKey: .unscharf)
            }

            public func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(ziel.description, forKey: .ziel)
                try c.encode(ausgang, forKey: .ausgang)
                try c.encode(r.description, forKey: .r)
                try c.encode(differenz.description, forKey: .differenz)
                try c.encode(differenzBetrag.description, forKey: .differenzBetrag)
                try c.encode(unscharf, forKey: .unscharf)
            }

            init(_ s: BestExit.Stufe) {
                ziel = s.ziel
                ausgang = switch s.ausgang {
                case .ziel: "ziel"
                case .stop: "stop"
                case .tatsaechlich: "tatsaechlich"
                }
                r = s.r
                differenz = s.differenz
                differenzBetrag = s.differenzBetrag
                unscharf = s.unscharf
            }
        }

        public var risiko: Decimal
        public var tatsaechlichR: Decimal
        public var kostenR: Decimal
        public var theoretischesMaximumR: Decimal
        public var kerzenUnscharf: Bool
        public var abdeckung: Decimal
        public var stufen: [Stufe]
        /// 1 R aus dem geplanten Risiko statt aus einem Stop (`BestExit.risikoAngenommen`); fehlt in älteren Dateien.
        public var risikoAngenommen: Bool

        public init(_ b: BestExit) {
            risiko = b.risiko
            tatsaechlichR = b.tatsaechlichR
            kostenR = b.kostenR
            theoretischesMaximumR = b.theoretischesMaximumR
            kerzenUnscharf = b.kerzenUnscharf
            abdeckung = b.abdeckung
            stufen = b.stufen.map { Stufe($0) }
            risikoAngenommen = b.risikoAngenommen
        }

        /// Zurück zur Analyse des Rechenkerns; `nil`, wenn eine Stufe einen unbekannten Ausgang trägt.
        public func bestExit(tradeID: String) -> BestExit? {
            BestExit(export: self, tradeID: tradeID)
        }

        private enum CodingKeys: String, CodingKey {
            case risiko, tatsaechlichR, kostenR, theoretischesMaximumR, kerzenUnscharf, abdeckung, stufen
            case risikoAngenommen
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            risiko = try c.exportzahl(.risiko)
            tatsaechlichR = try c.exportzahl(.tatsaechlichR)
            kostenR = try c.exportzahl(.kostenR)
            theoretischesMaximumR = try c.exportzahl(.theoretischesMaximumR)
            kerzenUnscharf = try c.decode(Bool.self, forKey: .kerzenUnscharf)
            abdeckung = try c.exportzahl(.abdeckung)
            stufen = try c.decode([Stufe].self, forKey: .stufen)
            risikoAngenommen = (try? c.decodeIfPresent(Bool.self, forKey: .risikoAngenommen)) ?? false
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(risiko.description, forKey: .risiko)
            try c.encode(tatsaechlichR.description, forKey: .tatsaechlichR)
            try c.encode(kostenR.description, forKey: .kostenR)
            try c.encode(theoretischesMaximumR.description, forKey: .theoretischesMaximumR)
            try c.encode(kerzenUnscharf, forKey: .kerzenUnscharf)
            try c.encode(abdeckung.description, forKey: .abdeckung)
            try c.encode(stufen, forKey: .stufen)
            if risikoAngenommen { try c.encode(true, forKey: .risikoAngenommen) }
        }
    }
}

extension BestExit {
    /// Aus dem Export zurück, mit allen Werten wie in der App gerechnet.
    init?(export b: JournalExport.BestAusstieg, tradeID: String) {
        var stufen: [Stufe] = []
        for s in b.stufen {
            let ausgang: Ausgang
            switch s.ausgang {
            case "ziel": ausgang = .ziel
            case "stop": ausgang = .stop
            case "tatsaechlich": ausgang = .tatsaechlich
            default: return nil
            }
            stufen.append(Stufe(ziel: s.ziel, ausgang: ausgang, r: s.r, differenz: s.differenz,
                                differenzBetrag: s.differenzBetrag, unscharf: s.unscharf))
        }
        self.tradeID = tradeID
        risiko = b.risiko
        tatsaechlichR = b.tatsaechlichR
        kostenR = b.kostenR
        self.stufen = stufen
        theoretischesMaximumR = b.theoretischesMaximumR
        differenzTheoretischesMaximum = max(0, b.theoretischesMaximumR - b.tatsaechlichR)
        kerzenUnscharf = b.kerzenUnscharf
        abdeckung = b.abdeckung
        risikoAngenommen = b.risikoAngenommen
    }
}

extension KeyedDecodingContainer {
    /// Zahl, die als Text im Export steht („-0.07“).
    fileprivate func exportzahl(_ key: Key) throws -> Decimal {
        let text = try decode(String.self, forKey: key)
        guard let wert = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Keine Zahl: \(text)")
        }
        return wert
    }
}
