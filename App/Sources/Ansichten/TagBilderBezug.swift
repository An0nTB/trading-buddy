import Observation
import SwiftUI
import TradingCore
import TradingStore

/// Bilder zu einem Trade oder verpassten Trade (Bildverweis mit Bezug `.trade` oder `.verpassterTrade`).
/// Liest und schreibt direkt im Journal; die Tagesseite selbst nutzt weiter `TagModell`. Lädt erst über
/// `laden()` (in `.task` der Ansicht), damit ein Neuzeichnen des Inspektors keine Abfrage auslöst.
@Observable @MainActor
final class BilderModell {
    let bezug: Bildverweis.Bezug
    private let lesen: () throws -> [Bildverweis]
    private let speichern: (Bildverweis) throws -> Void
    private let entfernenVerweis: (String) throws -> Void
    private(set) var bilder: [Bildverweis] = []
    var fehler: String?

    init(bezug: Bildverweis.Bezug, lesen: @escaping () throws -> [Bildverweis],
         speichern: @escaping (Bildverweis) throws -> Void, entfernen: @escaping (String) throws -> Void) {
        self.bezug = bezug
        self.lesen = lesen
        self.speichern = speichern
        entfernenVerweis = entfernen
    }

    /// Bilder eines Trades im gewählten Konto; der Trade ist über Konto und Ticket bestimmt.
    static func trade(_ trade: Trade, konto: Konto, journal: Journal) -> BilderModell {
        BilderModell(bezug: .trade(trade.id),
                     lesen: { try mitKlartext { try journal.bilder(trade: trade.id, konto: konto) } },
                     speichern: { bild in try mitKlartext { try journal.speichereBild(bild, konto: konto) } },
                     entfernen: { datei in try mitKlartext { try journal.loescheBild(datei: datei) } })
    }

    /// Bilder eines gespeicherten verpassten Trades.
    static func verpasst(_ id: String, journal: Journal) -> BilderModell {
        BilderModell(bezug: .verpassterTrade(id),
                     lesen: { try mitKlartext { try journal.bilder(verpassterTrade: id) } },
                     speichern: { bild in try mitKlartext { try journal.speichereBild(bild) } },
                     entfernen: { datei in try mitKlartext { try journal.loescheBild(datei: datei) } })
    }

    func laden() {
        do {
            bilder = try lesen()
        } catch {
            fehler = error.localizedDescription
        }
    }

    func fuegeHinzu(_ quellen: [Bildquelle]) {
        fehler = Bilderordner.lege(quellen, bezug: bezug, speichern: speichern)
        laden()
    }

    func entferne(_ bild: Bildverweis) {
        do {
            try entfernenVerweis(bild.datei)
            Bilderordner.loesche(bild.datei)
            laden()
        } catch {
            fehler = error.localizedDescription
        }
    }
}

/// `SpeicherFehler` als Klartext, wie in `JournalTagAblage`.
private func mitKlartext<T>(_ aufruf: () throws -> T) throws -> T {
    do {
        return try aufruf()
    } catch let fehler as SpeicherFehler {
        throw TagSpeicherFehler(fehler)
    }
}

/// Karte „Screenshots“ für einen Trade, zum Einhängen im Trade-Inspektor (AP11). Ohne Datenbank oder
/// Konto zeigt sie nichts.
struct TradeBilderKarte: View {
    let trade: Trade
    @Environment(AppModell.self) private var modell

    var body: some View {
        if let journal = modell.journal, let konto = modell.konto {
            BilderKarteInhalt(titel: "Screenshots") {
                BilderModell.trade(trade, konto: konto, journal: journal)
            }
            .id("\(konto.id ?? 0)-\(trade.id)")
        }
    }
}

/// Abschnitt „Screenshots“ im Blatt eines verpassten Trades; erst nach dem ersten Sichern, weil der
/// Verweis den gespeicherten Eintrag braucht.
struct VerpasstBilderAbschnitt: View {
    let id: String
    let gespeichert: Bool
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        Section {
            if gespeichert, let journal = modell.journal {
                BilderAbschnittInhalt(modell: BilderModell.verpasst(id, journal: journal))
            } else {
                Text("Screenshots kannst du nach dem ersten Sichern anhängen.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        } header: {
            Text("Screenshots")
        }
    }
}

/// Hält das Modell über Neuzeichnungen hinweg (State behält das erste Modell je Identität der Ansicht).
private struct BilderKarteInhalt: View {
    let titel: LocalizedStringKey
    @State private var modell: BilderModell

    init(titel: LocalizedStringKey, modell: @escaping () -> BilderModell) {
        self.titel = titel
        _modell = State(initialValue: modell())
    }

    var body: some View {
        Karte(titel) {
            BilderAbschnittInhalt.raster(modell)
        }
        .task { modell.laden() }
        .alert("Fehler", isPresented: fehlerSichtbar) {
            Button("OK") { modell.fehler = nil }
        } message: {
            Text(verbatim: modell.fehler ?? "")
        }
    }

    private var fehlerSichtbar: Binding<Bool> {
        Binding(get: { modell.fehler != nil }, set: { if !$0 { modell.fehler = nil } })
    }
}

/// Raster plus Fehlerzeile für Formulare.
private struct BilderAbschnittInhalt: View {
    @State private var modell: BilderModell
    @Environment(\.thema) private var thema

    init(modell: @autoclosure () -> BilderModell) {
        _modell = State(initialValue: modell())
    }

    var body: some View {
        Group {
            Self.raster(modell)
            if let fehler = modell.fehler {
                Text(verbatim: fehler)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.verlust)
            }
        }
        .task { modell.laden() }
    }

    static func raster(_ modell: BilderModell) -> BilderRaster {
        BilderRaster(bilder: modell.bilder,
                     hinzufuegen: { modell.fuegeHinzu($0) },
                     entfernen: { modell.entferne($0) },
                     meldeFehler: { modell.fehler = $0 })
    }
}
