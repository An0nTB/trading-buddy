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
                .fontWeight(thema.flaechenGetoent ? .semibold : .regular)
                .textCase(thema.flaechenGetoent ? .uppercase : nil)
                .foregroundStyle(thema.kachelTitel)
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
        .overlay(RoundedRectangle(cornerRadius: Abstand.radiusKachel).strokeBorder(thema.kachelRand, lineWidth: 1))
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
        .overlay(RoundedRectangle(cornerRadius: Abstand.radiusKachel).strokeBorder(thema.kachelRand, lineWidth: 1))
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
    @AppStorage(Ton.schluessel) private var ton = Ton.bro
    var body: some View {
        ContentUnavailableView(ton.text("Noch keine Trades", bro: "Noch nichts am Start, Alter."), systemImage: "tray",
                               description: Text(verbatim: ton.text("Importiere einen Kontoauszug unter „Import“.",
                                                                    bro: "Zieh einen Kontoauszug unter „Import“ rein, dann reden wir über Zahlen.")))
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

/// Fehlermuster als kleine Marke in Listen: Kurzform, voller Titel als Tooltip; `kurz: false` für den vollen Titel.
struct MusterChip: View {
    let muster: Fehlermuster
    var kurz = true
    @Environment(\.thema) private var thema

    var body: some View {
        Text(verbatim: kurz ? muster.kurz : muster.titel)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, Abstand.raster * 2)
            .padding(.vertical, Abstand.raster / 2)
            .background(thema.flaeche2, in: Capsule())
            .foregroundStyle(thema.text)
            .help(muster.titel)
    }
}

/// Bis zu `maxAnzahl` Chips nebeneinander, der Rest als „+N“; alle Titel im Tooltip.
struct MusterChips: View {
    let muster: [Fehlermuster]
    var maxAnzahl = 2
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(spacing: Abstand.raster) {
            ForEach(Array(muster.prefix(maxAnzahl)), id: \.self) { MusterChip(muster: $0) }
            if muster.count > maxAnzahl {
                Text(verbatim: "+\(muster.count - maxAnzahl)")
                    .font(.caption2)
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .help(muster.map(\.titel).joined(separator: ", "))
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

/// Kleine Kapsel mit Zähler oder Filterwert; `betont` färbt sie im Akzent (Hell-Variante B, 01.10.2026).
struct Kapsel: View {
    let text: String
    var betont = false
    @Environment(\.thema) private var thema

    var body: some View {
        Text(verbatim: text)
            .font(Schrift.beschriftung)
            .padding(.horizontal, Abstand.raster * 2)
            .padding(.vertical, Abstand.raster)
            .background(betont ? thema.akzentTint : thema.flaeche2, in: Capsule())
            .foregroundStyle(betont ? thema.akzent : thema.text)
    }
}

/// Auswahl im Akzent: zeigt den gewählten Wert, ein Klick öffnet die Optionen als Menü mit Häkchen.
/// Ersetzt den Menü-Picker, dessen Schrift am Mac die Systemfarbe trägt und nicht die Farbwelt.
struct Auswahlknopf<Wert: Hashable, Optionen: View>: View {
    let titel: LocalizedStringKey
    let anzeige: String
    @Binding var auswahl: Wert
    let mitHintergrund: Bool
    let optionen: () -> Optionen
    @Environment(\.thema) private var thema

    init(_ titel: LocalizedStringKey, anzeige: String, auswahl: Binding<Wert>, mitHintergrund: Bool = true,
         @ViewBuilder optionen: @escaping () -> Optionen) {
        self.titel = titel
        self.anzeige = anzeige
        self._auswahl = auswahl
        self.mitHintergrund = mitHintergrund
        self.optionen = optionen
    }

    var body: some View {
        Menu {
            Picker(titel, selection: $auswahl, content: optionen)
                .pickerStyle(.inline)
        } label: {
            HStack(spacing: Abstand.raster) {
                Text(verbatim: anzeige)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(mitHintergrund ? Schrift.fliesstext : .callout.weight(.medium))
            .foregroundStyle(thema.akzent)
            .padding(.horizontal, mitHintergrund ? Abstand.raster * 2 : 0)
            .padding(.vertical, mitHintergrund ? Abstand.raster : 0)
            .background(mitHintergrund ? thema.flaeche2 : .clear,
                        in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
            .contentShape(RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(titel))
        .accessibilityValue(Text(verbatim: anzeige))
    }
}


/// Beschriftung über einem Eingabeelement, für schmale Spalten wie den Inspektor.
struct Feldblock<Inhalt: View>: View {
    let titel: LocalizedStringKey
    @ViewBuilder let inhalt: () -> Inhalt
    @Environment(\.thema) private var thema

    init(_ titel: LocalizedStringKey, @ViewBuilder inhalt: @escaping () -> Inhalt) {
        self.titel = titel
        self.inhalt = inhalt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(titel)
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            inhalt()
        }
    }
}
