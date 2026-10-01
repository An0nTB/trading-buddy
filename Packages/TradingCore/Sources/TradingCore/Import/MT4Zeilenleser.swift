import Foundation

/// Geht die Tabellenzeilen eines MetaTrader-Auszugs der Reihe nach durch und
/// ordnet sie dem jeweiligen Abschnitt zu („Closed Transactions:“, „Open Trades:“ …).
struct MT4Zeilenleser {
    let zeitzone: TimeZone
    private(set) var abschnitt: String?
    private(set) var konto: [String: String] = [:]
    private(set) var kopfzeit: String?
    private(set) var geschlossen: [ClosedPosition] = []
    private(set) var geloescht: [CancelledOrder] = []
    private(set) var offen: [OpenPosition] = []
    private(set) var wartend: [WorkingOrder] = []
    /// Summenzeile je Abschnitt (Kommission, Swap, Kursergebnis).
    private(set) var summen: [String: [String]] = [:]
    /// Beschriftete Werte je Abschnitt, zum Beispiel „Closed Trade P/L“.
    private(set) var werte: [String: [String: String]] = [:]

    init(zeitzone: TimeZone) {
        self.zeitzone = zeitzone
    }

    var uebersicht: [String: String] { werte["A/C Summary"] ?? [:] }

    mutating func lies(_ zellen: [String]) throws {
        guard zellen.contains(where: { !$0.isEmpty }) else { return }
        if zellen.count == 1, zellen[0].hasSuffix(":") {
            abschnitt = String(zellen[0].dropLast())
            return
        }
        guard let abschnitt else {
            kopfzeile(zellen)
            return
        }
        if zellen[0] == "Ticket" {
            try Self.pruefeKopf(zellen, abschnitt: abschnitt)
            return
        }
        if zellen[0] == "No transactions" { return }
        if Self.istTicket(zellen[0]) {
            try position(zellen, abschnitt: abschnitt)
        } else if zellen.count == 4, zellen[0].isEmpty {
            summen[abschnitt] = Array(zellen[1...])
        } else {
            werte[abschnitt, default: [:]].merge(Self.beschriftungen(zellen)) { _, neu in neu }
        }
    }

    private mutating func kopfzeile(_ zellen: [String]) {
        for zelle in zellen {
            if zelle.hasPrefix("A/C No:") {
                konto["A/C No"] = String(zelle.dropFirst("A/C No:".count)).trimmingCharacters(in: .whitespaces)
            } else if zelle.hasPrefix("Name:") {
                konto["Name"] = String(zelle.dropFirst("Name:".count)).trimmingCharacters(in: .whitespaces)
            } else if zelle.first?.isNumber == true {
                kopfzeit = zelle
            }
        }
    }

    private mutating func position(_ z: [String], abschnitt: String) throws {
        let unbekannt = MT4ImportFehler.unbekannteZeile(abschnitt: abschnitt, ticket: z[0], zellen: z)
        switch abschnitt {
        case "Closed Transactions" where z.count == 13:
            let art = try MT4Werte.auftragsart(z[2])
            guard art == .buy || art == .sell else { throw unbekannt }
            geschlossen.append(ClosedPosition(
                ticket: z[0], rohzeile: z, side: art.side, lots: try zahl(z[3]), symbol: z[4],
                openTime: try zeit(z[1]), openPrice: try zahl(z[5]),
                stopLoss: try MT4Werte.optionaleZahl(z[6]), takeProfit: try MT4Werte.optionaleZahl(z[7]),
                closeTime: try zeit(z[8]), closePrice: try zahl(z[9]),
                commission: try zahl(z[10]), swap: try zahl(z[11]), profit: try zahl(z[12])
            ))
        case "Closed Transactions" where z.count == 11 && z[10].lowercased() == "cancelled":
            geloescht.append(CancelledOrder(
                ticket: z[0], rohzeile: z, type: try MT4Werte.auftragsart(z[2]), lots: try zahl(z[3]), symbol: z[4],
                placedAt: try zeit(z[1]), orderPrice: try zahl(z[5]),
                stopLoss: try MT4Werte.optionaleZahl(z[6]), takeProfit: try MT4Werte.optionaleZahl(z[7]),
                cancelledAt: try zeit(z[8]), marketPrice: try zahl(z[9])
            ))
        case "Open Trades" where z.count == 13 && z[8].isEmpty:
            let art = try MT4Werte.auftragsart(z[2])
            guard art == .buy || art == .sell else { throw unbekannt }
            offen.append(OpenPosition(
                ticket: z[0], rohzeile: z, side: art.side, lots: try zahl(z[3]), symbol: z[4],
                openTime: try zeit(z[1]), openPrice: try zahl(z[5]),
                stopLoss: try MT4Werte.optionaleZahl(z[6]), takeProfit: try MT4Werte.optionaleZahl(z[7]),
                currentPrice: try zahl(z[9]),
                commission: try zahl(z[10]), swap: try zahl(z[11]), profit: try zahl(z[12])
            ))
        case "Working Orders" where z.count >= 9:
            // Aufbau aus der Kopfzeile abgeleitet, noch ohne echtes Beispiel (ungeprüft).
            wartend.append(WorkingOrder(
                ticket: z[0], rohzeile: z, type: try MT4Werte.auftragsart(z[2]), lots: try zahl(z[3]), symbol: z[4],
                placedAt: try zeit(z[1]), orderPrice: try zahl(z[5]),
                stopLoss: try MT4Werte.optionaleZahl(z[6]), takeProfit: try MT4Werte.optionaleZahl(z[7]),
                marketPrice: try zahl(z[8])
            ))
        default:
            throw unbekannt
        }
    }

    private func zahl(_ text: String) throws -> Decimal { try MT4Werte.zahl(text) }
    private func zeit(_ text: String) throws -> Date { try MT4Werte.zeit(text, zeitzone: zeitzone) }

    /// Die Spalten werden nach Position gelesen, weil „Price“ zweimal vorkommt.
    /// Deshalb muss der Spaltenkopf genau dem belegten Aufbau entsprechen.
    static func pruefeKopf(_ kopf: [String], abschnitt: String) throws {
        let gemeinsam = ["Ticket", "Open Time", "Type", "Lots", "Item", "Price", "S / L", "T / P"]
        let erwartet: [String]
        switch abschnitt {
        case "Closed Transactions": erwartet = gemeinsam + ["Close Time", "Price", "Commission", "R/O Swap", "Trade P/L"]
        case "Open Trades": erwartet = gemeinsam + ["", "Price", "Commission", "R/O Swap", "Trade P/L"]
        case "Working Orders": erwartet = gemeinsam + ["Market Price", ""]
        default: erwartet = kopf
        }
        guard kopf == erwartet else {
            throw MT4ImportFehler.unerwarteteSpalten(abschnitt: abschnitt, gefunden: kopf)
        }
    }

    static func istTicket(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Paare aus „Beschriftung: Wert“. Steht der Wert nicht in derselben Zelle,
    /// gilt die nächste Zelle als Wert.
    static func beschriftungen(_ zellen: [String]) -> [String: String] {
        var ergebnis: [String: String] = [:]
        var i = 0
        while i < zellen.count {
            let zelle = zellen[i]
            guard let doppelpunkt = zelle.firstIndex(of: ":") else { i += 1; continue }
            let name = zelle[..<doppelpunkt].trimmingCharacters(in: .whitespaces)
            let wert = zelle[zelle.index(after: doppelpunkt)...].trimmingCharacters(in: .whitespaces)
            if !wert.isEmpty {
                ergebnis[name] = wert
                i += 1
            } else if i + 1 < zellen.count {
                ergebnis[name] = zellen[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        return ergebnis
    }
}
