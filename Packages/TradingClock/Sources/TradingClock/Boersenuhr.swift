import Foundation

/// Sammlung der Börsen, die die Uhr kennt. Mitgeliefert sind Xetra, NYSE, Nasdaq, LSE,
/// Forex und Krypto; eigene Börsen kommen als weitere JSON-Datei dazu (R1 Abschnitt 6).
public struct Boersenuhr: Sendable {
    /// Reihenfolge der mitgelieferten Börsen in der Anzeige; unbekannte folgen nach Name.
    public static let standardReihenfolge = ["xetra", "nyse", "nasdaq", "lse", "forex", "krypto"]

    public let boersen: [Boerse]

    /// Prüft jede Börse und lehnt doppelte Kennungen ab.
    public init(boersen: [Boerse]) throws {
        var gesehen = Set<String>()
        for boerse in boersen {
            try boerse.pruefe()
            guard gesehen.insert(boerse.id).inserted else { throw BoersenuhrFehler.doppelteBoerse(id: boerse.id) }
        }
        self.boersen = boersen.sorted { a, b in
            let ia = Boersenuhr.standardReihenfolge.firstIndex(of: a.id) ?? Int.max
            let ib = Boersenuhr.standardReihenfolge.firstIndex(of: b.id) ?? Int.max
            return ia != ib ? ia < ib : a.name < b.name
        }
    }

    /// Die im Paket mitgelieferten Börsen, plus optional eigene.
    public static func mitgeliefert(zusaetzlich: [Boerse] = []) throws -> Boersenuhr {
        try Boersenuhr(boersen: mitgelieferteBoersen() + zusaetzlich)
    }

    /// Liest alle JSON-Dateien aus dem Ordner `Boersen` im Paket.
    public static func mitgelieferteBoersen() throws -> [Boerse] {
        guard let ordner = Bundle.module.url(forResource: "Boersen", withExtension: nil) else {
            throw BoersenuhrFehler.mitgelieferteDatenFehlen
        }
        let dateien = try FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try dateien.map { try Boerse.lade(json: Data(contentsOf: $0)) }
    }

    public subscript(id: String) -> Boerse? { boersen.first { $0.id == id } }

    /// Status aller Börsen zu einem Zeitpunkt, in Anzeigereihenfolge.
    public func status(_ zeitpunkt: Date) -> [(boerse: Boerse, status: Boersenstatus)] {
        boersen.map { ($0, $0.status(zeitpunkt)) }
    }
}
