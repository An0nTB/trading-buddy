import SwiftUI
import TradingAssistant
import TradingCore
import TradingStore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Blatt „Frag Henry“: Vorlage wählen, Frage prüfen, Claude Desktop mit vorbefülltem Eingabefeld öffnen
/// (Entscheidung Tim 02.10.2026, Doc 02 Zeile 44). Gesendet wird erst in Claude; das Gespräch liegt dort im Verlauf.
struct FragBradBlatt: View {
    let anfrage: FragBradAnfrage
    @Environment(AppModell.self) private var modell
    @Environment(\.dismiss) private var schliessen
    /// Ton-Schalter aus den Einstellungen (AP11, `Ton.swift`); nur „Sachlich“ lässt die Tonbitte weg,
    /// jeder andere oder fehlende Wert ist der Standard „Henry“.
    @AppStorage(Ton.schluessel) private var tonWahl = Ton.henry
    @State private var vorlage: FragBradVorlage
    @State private var freieFrage = ""
    @State private var meldung: String?

    init(anfrage: FragBradAnfrage) {
        self.anfrage = anfrage
        _vorlage = State(initialValue: anfrage.vorlage)
    }

    private var vorlagen: [FragBradVorlage] {
        FragBradVorlage.verfuegbar(mitTrade: anfrage.trade != nil, mitTag: anfrage.tag != nil,
                                   mitSymbol: symbol != nil)
    }

    private var ton: FragBradTon { tonWahl == .sachlich ? .sachlich : .henry }

    /// Wert für „Wert analysieren“: ausdrücklich gewählt, sonst Symbol des Trades, sonst Instrument im Filter.
    private var symbol: String? { anfrage.symbol ?? anfrage.trade?.symbol ?? modell.instrument }

    private var kontext: FragBradKontext {
        FragBradKontextAusModell.kontext(modell, trade: anfrage.trade, tag: anfrage.tag, symbol: symbol)
    }

    private var text: String? {
        FragBrad.text(vorlage, kontext: kontext, freieFrage: freieFrage, ton: ton, zeitzone: modell.zeitzone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text("Frag Henry").font(Schrift.titel)
            Text(Self.erklaerung).font(.callout).foregroundStyle(.secondary)
            Picker("Frage", selection: $vorlage) {
                ForEach(vorlagen) { Text(verbatim: $0.titel.uebersetzt).tag($0) }
            }
            if vorlage == .frei {
                TextField("Deine Frage an Henry", text: $freieFrage, axis: .vertical)
                    .lineLimit(3...8)
            }
            if vorlage == .analyse {
                Text(verbatim: FragBrad.inkognitoHinweis(ton).uebersetzt).font(.callout)
                if !kontext.mitKursverlauf {
                    Text(verbatim: FragBrad.ohneKursverlaufHinweis.uebersetzt).font(.callout).foregroundStyle(.secondary)
                }
            }
            vorschau
            if let meldung {
                Text(meldung).font(.callout).foregroundStyle(.secondary)
            }
            knoepfe
        }
        .padding(Abstand.seitenrand)
        #if os(macOS)
        .frame(width: 520)
        #endif
    }

    private var vorschau: some View {
        ScrollView {
            Text(text ?? String(localized: "Schreib zuerst deine Frage."))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 120, maxHeight: 220)
    }

    private var knoepfe: some View {
        HStack {
            Button("Abbrechen", role: .cancel) { schliessen() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Frage kopieren") {
                guard let text else { return }
                FragBradOeffner.kopiere(text)
                meldung = String(localized: "Die Frage liegt in der Zwischenablage.")
            }
            .disabled(text == nil)
            #if os(macOS)
            Button("In Claude öffnen") { oeffne() }
                .keyboardShortcut(.defaultAction)
                .disabled(text == nil)
            #endif
        }
    }

    #if os(macOS)
    private func oeffne() {
        guard let text else { return }
        // Analyse: zusätzlich kopieren, falls der Klick auf Inkognito das vorbefüllte Feld leert (Doc 38).
        if vorlage.kopiertMit { FragBradOeffner.kopiere(text) }
        if FragBradOeffner.oeffneClaude(text) {
            schliessen()
        } else {
            FragBradOeffner.kopiere(text)
            meldung = String(localized: "Claude Desktop ist auf diesem Mac nicht installiert. Die Frage liegt in der Zwischenablage; du kannst sie in Claude im Browser einfügen.")
        }
    }

    private static var erklaerung: LocalizedStringKey { "Henry öffnet Claude Desktop mit deiner Frage. Du schickst sie dort selbst ab, die Zahlen holt sich Claude über den Connector. Im Link stehen nur Konto-Endziffern, Zeitraum und Instrument, keine Beträge und keine Notizen." }
    #else
    private static var erklaerung: LocalizedStringKey { "Henry kopiert deine Frage. Füge sie am Mac in Claude Desktop ein, nur dort liest Claude dein Journal." }
    #endif
}

/// Kontext für die Frage aus dem gemeinsamen Filter: Konto, Monat, Instrument.
@MainActor
enum FragBradKontextAusModell {
    static func kontext(_ modell: AppModell, trade: Trade?, tag: Date?, symbol: String? = nil) -> FragBradKontext {
        var kontext = FragBradKontext(konto: modell.konto.map { kurzname($0, unter: modell.konten) },
                                      instrument: modell.instrument)
        if let symbol {
            kontext.symbol = symbol
            kontext.mitKursverlauf = modell.kurse.verlaeufe.verlaeufe[symbol] != nil
        }
        if case .monat(let anfang) = modell.zeitraum {
            var kalender = Calendar(identifier: .gregorian)
            kalender.timeZone = modell.zeitzone
            kontext.von = anfang
            kontext.bis = kalender.date(byAdding: DateComponents(month: 1, day: -1), to: anfang)
        }
        kontext.tag = tag
        if let trade {
            kontext.trade = FragBradTrade(symbol: trade.symbol, eroeffnet: trade.openTime,
                                          geschlossen: trade.closeTime, nurDatum: trade.nurDatum)
        }
        return kontext
    }

    /// Gleicher Name wie im Export für Claude (`JournalExport.kurzname`), damit der Connector das Konto findet.
    static func kurzname(_ konto: Konto, unter konten: [Konto]) -> String {
        let andere = konten.filter { $0.broker == konto.broker }.map(\.kontonummer)
        let stellen = JournalExport.endziffern(konto.kontonummer, neben: andere)
        return "\(konto.broker) …\(konto.kontonummer.suffix(stellen))"
    }
}

/// Öffnen und Kopieren, je Plattform.
@MainActor
enum FragBradOeffner {
    static func kopiere(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    #if os(macOS)
    /// `false`, wenn kein Programm `claude://` öffnen kann (Claude Desktop fehlt).
    static func oeffneClaude(_ text: String) -> Bool {
        guard let link = FragBrad.link(text), NSWorkspace.shared.urlForApplication(toOpen: link) != nil else {
            return false
        }
        return NSWorkspace.shared.open(link)
    }
    #endif
}
