import SwiftUI
import TradingCore
import TradingStore

/// Texte zur Produktart (Doc 23): beschreibt das Produkt, nicht den Steuertopf.
enum Produktartformat {
    /// Arten, die der Nutzer selbst vergeben kann (`unbekannt` nicht).
    static let waehlbar: [Produktart] = [.aktie, .fonds, .anleihe, .derivat, .cfd, .krypto, .sonstiges]

    static func titel(_ art: Produktart) -> String {
        switch art {
        case .aktie: String(localized: "Aktie")
        case .fonds: String(localized: "Fonds oder ETF")
        case .anleihe: String(localized: "Anleihe")
        case .derivat: String(localized: "Derivat (Optionsschein, Knock-out, Zertifikat)")
        case .cfd: String(localized: "CFD oder Forex")
        case .krypto: String(localized: "Krypto")
        case .sonstiges: String(localized: "Sonstiges")
        case .unbekannt: String(localized: "unbekannt")
        }
    }
}

/// Produktart je Wertpapier nachtragen (Steuer-Seite; TradingStore #96 `symboleOhneProduktart`, `setzeProduktart`):
/// Scalable und XTB nennen die Art nicht, bis zur Zuordnung zählen die Trades im Topf „nicht zugeordnet“.
struct ProduktartKarte: View {
    let luecken: [ProduktartLuecke]
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var meldung: String?
    @State private var meldungIstFehler = false

    var body: some View {
        Karte("Produktart nachtragen") {
            Text("Diese Wertpapiere kamen ohne Produktart aus der Datei (Scalable, XTB). Wähle die Art je Wertpapier; sie gilt für alle Zeilen des Kontos mit diesem Symbol und ordnet die Trades dem Steuertopf zu.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            ForEach(luecken, id: \.symbol) { luecke in
                HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
                    VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                        Text(verbatim: luecke.name)
                            .foregroundStyle(thema.text)
                        Text(verbatim: luecke.symbol == luecke.name
                             ? String(localized: "\(luecke.anzahl) Zeilen")
                             : "\(luecke.symbol) · " + String(localized: "\(luecke.anzahl) Zeilen"))
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                    Spacer()
                    Menu {
                        ForEach(Produktartformat.waehlbar, id: \.self) { art in
                            Button(action: { setze(luecke, art) }) { Text(verbatim: Produktartformat.titel(art)) }
                        }
                    } label: {
                        Text("Art wählen")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
            }
            if let meldung {
                Text(verbatim: meldung)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(meldungIstFehler ? thema.verlust : thema.textSchwach)
            }
        }
    }

    private func setze(_ luecke: ProduktartLuecke, _ art: Produktart) {
        do {
            let anzahl = try modell.setzeProduktart(symbol: luecke.symbol, art)
            meldung = String(localized: "\(luecke.name): \(anzahl) Zeilen als \(Produktartformat.titel(art)) gespeichert.")
            meldungIstFehler = false
        } catch {
            meldung = Regelfehler.text(error)
            meldungIstFehler = true
        }
    }
}

/// Produktart im Trade-Inspektor nachfragen, wenn der Auszug sie nicht nennt (Doc 23, Paket A1 c): gleiche Speicherung
/// wie `ProduktartKarte`, die Wahl gilt für alle Zeilen des Kontos mit diesem Symbol.
struct ProduktartFrage: View {
    let trade: Trade
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var fehler: String?

    var body: some View {
        Karte("Produktart") {
            Text("Der Auszug nennt die Produktart nicht. Bis du sie wählst, zählt der Trade in der Steuer als „nicht zugeordnet“. Die Wahl gilt für alle Trades dieses Kontos mit demselben Symbol.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            Menu {
                ForEach(Produktartformat.waehlbar, id: \.self) { art in
                    Button(action: { setze(art) }) { Text(verbatim: Produktartformat.titel(art)) }
                }
            } label: {
                Text("Art wählen")
            }
            .menuStyle(.button)
            .fixedSize()
            if let fehler {
                Text(verbatim: fehler)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.verlust)
            }
        }
    }

    private func setze(_ art: Produktart) {
        do {
            _ = try modell.setzeProduktart(symbol: trade.symbol, art)
            fehler = nil
        } catch {
            fehler = Regelfehler.text(error)
        }
    }
}
