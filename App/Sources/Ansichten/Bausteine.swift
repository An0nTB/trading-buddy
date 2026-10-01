import SwiftUI
import TradingCore

/// Titelzeile einer Seite: großer Titel, Untertitel daneben, rechts Filter oder Knöpfe.
struct Kopfzeile<Rechts: View>: View {
    let titel: LocalizedStringKey
    var untertitel: String?
    let rechts: () -> Rechts
    @Environment(\.thema) private var thema

    init(_ titel: LocalizedStringKey, untertitel: String? = nil, @ViewBuilder rechts: @escaping () -> Rechts) {
        self.titel = titel
        self.untertitel = untertitel
        self.rechts = rechts
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.kachelAbstand) {
            Text(titel)
                .font(Schrift.grosserTitel)
                .foregroundStyle(thema.text)
            if let untertitel {
                Text(verbatim: untertitel)
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            }
            Spacer()
            rechts()
        }
        .frame(minHeight: Abstand.kopfzeile)
    }
}

extension Kopfzeile where Rechts == EmptyView {
    init(_ titel: LocalizedStringKey, untertitel: String? = nil) {
        self.init(titel, untertitel: untertitel) { EmptyView() }
    }
}

/// Kennzahl-Kachel: Beschriftung, große Zahl, Unterzeile (Doc 10, Komponenten).
struct Kachel: View {
    let titel: LocalizedStringKey
    let wert: String
    var zusatz: String?
    var farbe: Color?
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(titel)
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            Text(verbatim: wert)
                .font(Schrift.zahlGross)
                .foregroundStyle(farbe ?? thema.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let zusatz {
                Text(verbatim: zusatz)
                    .font(Schrift.beschriftung)
                    .monospacedDigit()
                    .foregroundStyle(thema.textSchwach)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Abstand.kachelInnen)
        .background(thema.flaeche, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
    }
}

/// Karte mit Überschrift, rechts wahlweise ein Knopf „Alle“.
struct Karte<Inhalt: View>: View {
    private let titel: Text
    private let aktion: (() -> Void)?
    private let inhalt: () -> Inhalt
    @Environment(\.thema) private var thema

    init(_ titel: LocalizedStringKey, aktion: (() -> Void)? = nil, @ViewBuilder inhalt: @escaping () -> Inhalt) {
        self.titel = Text(titel)
        self.aktion = aktion
        self.inhalt = inhalt
    }

    init(verbatim titel: String, aktion: (() -> Void)? = nil, @ViewBuilder inhalt: @escaping () -> Inhalt) {
        self.titel = Text(verbatim: titel)
        self.aktion = aktion
        self.inhalt = inhalt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            HStack {
                titel
                    .font(.headline)
                    .foregroundStyle(thema.text)
                Spacer()
                if let aktion {
                    Button("Alle", action: aktion)
                        .buttonStyle(.plain)
                        .foregroundStyle(thema.akzent)
                }
            }
            inhalt()
        }
        .padding(Abstand.kachelInnen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(thema.flaeche, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
    }
}

/// Hinweis bei zu kleiner Stichprobe (R5, Kapitel 08 Abschnitt 7).
struct StichprobenHinweis: View {
    let anzahl: Int
    @Environment(\.thema) private var thema

    var body: some View {
        if anzahl < Kennzahlen.mindestanzahl {
            Label("Unter \(Kennzahlen.mindestanzahl) Trades: Die Zahlen beschreiben nur, sie belegen noch kein Muster.",
                  systemImage: "info.circle")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }
}

/// Leerer Zustand, solange nichts importiert ist.
struct KeineTrades: View {
    var body: some View {
        ContentUnavailableView("Noch keine Trades", systemImage: "tray",
                               description: Text("Importiere einen Kontoauszug unter „Import“."))
    }
}

/// Platzhalter für Bereiche, die nach dem ersten Entwurf kommen.
struct Platzhalter: View {
    let titel: LocalizedStringKey
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        ContentUnavailableView(titel, systemImage: symbol, description: Text(text))
    }
}

/// Fehlermuster als kleine Marke in Listen.
struct MusterChip: View {
    let muster: Fehlermuster
    @Environment(\.thema) private var thema

    var body: some View {
        Text(verbatim: muster.titel)
            .font(.caption2)
            .padding(.horizontal, Abstand.raster * 2)
            .padding(.vertical, Abstand.raster / 2)
            .background(thema.flaeche2, in: Capsule())
            .foregroundStyle(thema.text)
    }
}

/// Pflichthinweis unter Übersicht und Kennzahlen (R5 Kapitel 13 Abschnitt 6).
struct Pflichthinweis: View {
    @Environment(\.thema) private var thema

    var body: some View {
        Text("Keine Anlageberatung. Die Zahlen beschreiben dein eigenes Handeln; Steuerwerte sind eine Orientierung.")
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }
}
