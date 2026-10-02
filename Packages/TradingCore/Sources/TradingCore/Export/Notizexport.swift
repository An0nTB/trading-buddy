import Foundation

extension JournalExport {
    /// Tagesnotiz im Export (Doc 18 F4): Plan vor dem Handel, Rückblick, Verfassung.
    /// Eigene Exportform statt `Tagesnotiz` selbst, damit der Aufbau der Datei unabhängig vom Modell bleibt.
    public struct Notiz: Sendable, Equatable, Codable {
        public var tag: Journaltag
        public var plan: String?
        /// Wann der Plan zuerst gespeichert wurde; zeigt, ob er vor dem ersten Trade stand.
        public var planErstellt: Date?
        public var rueckblick: String?
        /// 1 (schlecht) bis 5 (sehr gut).
        public var verfassung: Int?

        public init(tag: Journaltag, plan: String? = nil, planErstellt: Date? = nil, rueckblick: String? = nil,
                    verfassung: Int? = nil) {
            self.tag = tag
            self.plan = Self.text(plan)
            self.planErstellt = self.plan == nil ? nil : planErstellt
            self.rueckblick = Self.text(rueckblick)
            self.verfassung = verfassung
        }

        public init(_ notiz: Tagesnotiz) {
            self.init(tag: notiz.tag, plan: notiz.plan, planErstellt: notiz.planErstellt,
                      rueckblick: notiz.rueckblick, verfassung: notiz.verfassung)
        }

        public var istLeer: Bool { plan == nil && rueckblick == nil && verfassung == nil }

        /// Zurück ins Modell, damit der Connector mit denselben Regeln rechnet wie die App (`Planwirkung`).
        /// `erstellt` steht nicht in der Datei und spielt dort keine Rolle.
        public var modell: Tagesnotiz {
            Tagesnotiz(tag: tag, plan: plan ?? "", planErstellt: planErstellt, rueckblick: rueckblick ?? "",
                       verfassung: verfassung, erstellt: planErstellt ?? tag.beginn(in: TimeZone(secondsFromGMT: 0)!))
        }

        private static func text(_ wert: String?) -> String? {
            guard let wert, !wert.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return wert
        }
    }

    /// Verpasster Trade im Export: Setup gesehen, nicht gehandelt, mit Grund.
    public struct Verpasst: Sendable, Equatable, Codable {
        public var id: String
        public var zeit: Date
        public var symbol: String
        /// „buy“ oder „sell“.
        public var seite: String
        public var setup: String?
        /// Rohwert von `VerpassterTrade.Grund`, z. B. „zoegern“.
        public var grund: String
        public var notiz: String?
        /// Geschätztes Ergebnis in R; eigene Schätzung.
        public var ergebnisR: Decimal?

        public init(id: String, zeit: Date, symbol: String, seite: String, setup: String? = nil, grund: String,
                    notiz: String? = nil, ergebnisR: Decimal? = nil) {
            self.id = id
            self.zeit = zeit
            self.symbol = symbol
            self.seite = seite
            self.setup = setup.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            self.grund = grund
            self.notiz = notiz.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            self.ergebnisR = ergebnisR
        }

        public init(_ t: VerpassterTrade) {
            self.init(id: t.id, zeit: t.zeit, symbol: t.symbol, seite: t.seite.rawValue, setup: t.setup,
                      grund: t.grund.rawValue, notiz: t.notiz, ergebnisR: t.ergebnisR)
        }

        /// Zurück ins Modell für `VerpassteAuswertung`; `nil` bei Seite oder Grund, die dieser Rechenkern nicht kennt.
        public var modell: VerpassterTrade? {
            guard let s = Side(rawValue: seite), let g = VerpassterTrade.Grund(rawValue: grund) else { return nil }
            return VerpassterTrade(id: id, zeit: zeit, symbol: symbol, seite: s, setup: setup, grund: g,
                                   notiz: notiz ?? "", ergebnisR: ergebnisR)
        }
    }
}
