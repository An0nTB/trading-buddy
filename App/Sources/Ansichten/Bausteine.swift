import SwiftUI
import TradingCore

/// Kennzahl-Kachel: Titel, große Zahl, Zusatzzeile.
struct Kachel: View {
    let titel: LocalizedStringKey
    let wert: String
    var zusatz: String?
    var farbe: Color?
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titel)
                .font(.caption)
                .foregroundStyle(thema.textSchwach)
            Text(wert)
                .font(.title2.weight(.semibold))
                .foregroundStyle(farbe ?? thema.text)
            if let zusatz {
                Text(zusatz)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(thema.flaeche, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Überschrift eines Abschnitts auf einer scrollenden Seite.
struct Abschnitt<Inhalt: View>: View {
    let titel: LocalizedStringKey
    @ViewBuilder var inhalt: () -> Inhalt
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titel)
                .font(.headline)
                .foregroundStyle(thema.text)
            inhalt()
        }
    }
}

/// Hinweis bei zu kleiner Stichprobe (R5, Kapitel 08 Abschnitt 7).
struct StichprobenHinweis: View {
    let anzahl: Int
    @Environment(\.thema) private var thema

    var body: some View {
        if anzahl < Kennzahlen.mindestanzahl {
            Label("Weniger als \(Kennzahlen.mindestanzahl) Trades: Die Zahlen beschreiben nur, sie erlauben noch keine Schlussfolgerung.",
                  systemImage: "info.circle")
                .font(.callout)
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

/// Fehlermuster als kleine Marke in Listen.
struct MusterChip: View {
    let muster: Fehlermuster
    @Environment(\.thema) private var thema

    var body: some View {
        Text(muster.titel)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(thema.flaeche2, in: Capsule())
            .foregroundStyle(thema.text)
    }
}
