import Foundation

/// Fertige Quellen. Jede Quelle steht in einer eigenen Datei unter Anbieter/.
public enum Kursquellen {
    static let schlafe: @Sendable (Duration) async -> Void = { dauer in
        try? await Task.sleep(for: dauer)
    }
}

/// Was die App aus dem Beobachter bekommt, immer bezogen auf das Symbol im Journal.
public enum Kursereignis: Sendable, Equatable {
    case kurs(journalSymbol: String, kurs: Kurs, naeherung: String?)
    case status(quelle: String, Verbindungsstatus)
    /// Für dieses Symbol kommt kein Kurs, mit Grund für die Anzeige.
    case ohneQuelle(journalSymbol: String, grund: String)
}

/// Beobachtet die Kurse zu einer Liste von Zuordnungen über alle nötigen Quellen gleichzeitig.
/// Je Quelle eine Verbindung; mehrere Journal-Symbole auf dasselbe Quellsymbol teilen sich den Kurs.
public struct Kursbeobachter: Sendable {
    public let quellen: [String: any Kursquelle]

    public init(quellen: [any Kursquelle]) {
        var nachID: [String: any Kursquelle] = [:]
        for quelle in quellen { nachID[quelle.id] = quelle }
        self.quellen = nachID
    }

    /// Plan: was je Quelle abonniert wird und was ohne Quelle bleibt. Getrennt, damit es ohne Netz testbar ist.
    struct Plan: Sendable, Equatable {
        /// Quell-ID → Quellsymbol → Zuordnungen.
        var abos: [String: [String: [Kurszuordnung]]] = [:]
        var ohneQuelle: [(journalSymbol: String, grund: String)] = []

        static func == (a: Plan, b: Plan) -> Bool {
            a.abos == b.abos && a.ohneQuelle.map(\.journalSymbol) == b.ohneQuelle.map(\.journalSymbol)
                && a.ohneQuelle.map(\.grund) == b.ohneQuelle.map(\.grund)
        }
    }

    func plane(_ zuordnungen: [Kurszuordnung]) -> Plan {
        var plan = Plan()
        for z in zuordnungen {
            guard let quelle = quellen[z.quelle] else {
                plan.ohneQuelle.append((journalSymbol: z.journalSymbol, grund: "Quelle „\(z.quelle)“ ist nicht eingerichtet."))
                continue
            }
            var abo = plan.abos[z.quelle, default: [:]]
            if abo[z.quellSymbol] == nil, let grenze = quelle.hoechstzahlSymbole, abo.count >= grenze {
                plan.ohneQuelle.append((journalSymbol: z.journalSymbol, grund: "\(quelle.name) liefert höchstens \(grenze) Symbole gleichzeitig."))
                continue
            }
            abo[z.quellSymbol, default: []].append(z)
            plan.abos[z.quelle] = abo
        }
        return plan
    }

    /// Startet alle Quellen. Der Strom endet, wenn die App ihn nicht mehr liest oder alle Quellen beendet sind.
    public func beobachte(_ zuordnungen: [Kurszuordnung]) -> AsyncStream<Kursereignis> {
        let plan = plane(zuordnungen)
        let quellen = self.quellen
        return AsyncStream { fortsetzung in
            for (symbol, grund) in plan.ohneQuelle {
                fortsetzung.yield(.ohneQuelle(journalSymbol: symbol, grund: grund))
            }
            let aufgabe = Task {
                await withTaskGroup(of: Void.self) { gruppe in
                    for (id, abo) in plan.abos {
                        guard let quelle = quellen[id] else { continue }
                        gruppe.addTask {
                            for await ereignis in quelle.beobachte(abo.keys.sorted()) {
                                switch ereignis {
                                case .status(let status):
                                    fortsetzung.yield(.status(quelle: id, status))
                                case .kurs(let kurs):
                                    for z in abo[kurs.symbol] ?? [] {
                                        fortsetzung.yield(.kurs(journalSymbol: z.journalSymbol, kurs: kurs, naeherung: z.naeherung))
                                    }
                                }
                            }
                        }
                    }
                }
                fortsetzung.finish()
            }
            fortsetzung.onTermination = { _ in aufgabe.cancel() }
        }
    }
}

/// Letzter Stand je Journal-Symbol, für die Kachel in der Übersicht.
public struct Kursstand: Sendable, Equatable {
    public struct Eintrag: Sendable, Equatable {
        public var kurs: Kurs
        public var naeherung: String?
    }

    public private(set) var kurse: [String: Eintrag] = [:]
    public private(set) var ohneQuelle: [String: String] = [:]
    public private(set) var verbindungen: [String: Verbindungsstatus] = [:]

    public init() {}

    public mutating func uebernimm(_ ereignis: Kursereignis) {
        switch ereignis {
        case .kurs(let symbol, let kurs, let naeherung):
            kurse[symbol] = Eintrag(kurs: kurs, naeherung: naeherung)
        case .status(let quelle, let status):
            verbindungen[quelle] = status
        case .ohneQuelle(let symbol, let grund):
            ohneQuelle[symbol] = grund
        }
    }

    /// Symbole, deren Kurs älter ist als erlaubt (R1: 30 s, bei verzögerten Quellen plus Verzug).
    public func veraltet(jetzt: Date, grenze: TimeInterval = 30) -> [String] {
        kurse.filter { $0.value.kurs.istVeraltet(jetzt: jetzt, grenze: grenze) }.map { $0.key }.sorted()
    }
}
