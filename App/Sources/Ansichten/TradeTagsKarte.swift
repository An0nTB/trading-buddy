import SwiftUI
import TradingCore

/// Karte „Tags“ im Trade-Inspektor: freie Schlagworte je Trade mit Vorschlägen aus dem Konto
/// (Doc 02 Nr. 65). Auf macOS bearbeitbar, auf dem iPhone nur zum Lesen; ohne Konto zeigt sie nichts.
struct TradeTagsKarte: View {
    let trade: Trade
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var neu = ""

    var body: some View {
        if modell.konto != nil {
            Karte("Tags") {
                if tags.isEmpty {
                    Text("Noch keine Tags.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    reihe(tags, entfernen: true)
                }
                #if os(macOS)
                TextField("Tag hinzufügen", text: $neu)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { fuegeHinzu(neu) }
                if !vorschlaege.isEmpty {
                    reihe(vorschlaege, entfernen: false)
                }
                #endif
            }
        }
    }

    private var tags: [String] { modell.tradeTags[trade.id] ?? [] }

    /// Bekannte Tags des Kontos, die dieser Trade noch nicht trägt, passend zur Eingabe.
    private var vorschlaege: [String] {
        let gesetzt = Set(tags.map { $0.lowercased() })
        let suche = neu.trimmingCharacters(in: .whitespaces).lowercased()
        return Array(modell.tagVorschlaege
            .filter { !gesetzt.contains($0.lowercased()) && (suche.isEmpty || $0.lowercased().contains(suche)) }
            .prefix(8))
    }

    private func reihe(_ liste: [String], entfernen: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Abstand.raster) {
                ForEach(liste, id: \.self) { tag in
                    chip(tag, entfernen: entfernen)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ tag: String, entfernen: Bool) -> some View {
        #if os(macOS)
        Button {
            if entfernen {
                modell.setzeTags(tags.filter { $0 != tag }, trade: trade)
            } else {
                fuegeHinzu(tag)
            }
        } label: {
            HStack(spacing: Abstand.raster / 2) {
                Text(verbatim: tag)
                Image(systemName: entfernen ? "xmark" : "plus")
                    .font(.caption2)
            }
            .chipStil(thema, schwach: !entfernen)
        }
        .buttonStyle(.plain)
        .help(entfernen ? String(localized: "Tag entfernen") : String(localized: "Tag hinzufügen"))
        #else
        Text(verbatim: tag)
            .chipStil(thema, schwach: false)
        #endif
    }

    private func fuegeHinzu(_ text: String) {
        let tag = text.trimmingCharacters(in: .whitespacesAndNewlines)
        neu = ""
        guard !tag.isEmpty else { return }
        modell.setzeTags(tags + [tag], trade: trade)
    }
}

private extension View {
    func chipStil(_ thema: Thema, schwach: Bool) -> some View {
        self
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, Abstand.raster * 2)
            .padding(.vertical, Abstand.raster / 2)
            .background(thema.flaeche2, in: Capsule())
            .foregroundStyle(schwach ? thema.textSchwach : thema.text)
    }
}
