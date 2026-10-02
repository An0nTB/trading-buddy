import SwiftUI
import TradingClock

/// Kompakte Börsenuhr für ein kleines, angeheftetes Fenster (Stand-Doc 27, F5): je Börse ein Punkt für offen
/// oder geschlossen und ein laufender Countdown bis zur nächsten Öffnung oder Schließung. Liest nur aus
/// `modell.boersen` (Boersenverwaltung, AP11); Auswahl und Zeiten verwaltet die große Börsenuhr.
/// Die Ansicht hängt nicht von der Fenstergröße ab, damit kein Layout-Kreislauf entsteht (Startabsturz 02.10.2026).
struct MiniBoersenuhr: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        // Status alle 15 Sekunden neu; die Countdowns zählen dazwischen selbst (Text mit timerInterval).
        TimelineView(.periodic(from: .now, by: 15)) { kontext in
            let jetzt = kontext.date
            VStack(alignment: .leading, spacing: Abstand.raster * 2) {
                Text(verbatim: String(localized: "Deine Zeit \(Format.uhrzeit(jetzt))"))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                if let uhr = modell.boersen.uhr, !uhr.boersen.isEmpty {
                    ForEach(uhr.boersen) { boerse in
                        MiniBoersenZeile(boerse: boerse, status: boerse.status(jetzt), jetzt: jetzt)
                    }
                } else {
                    Text(verbatim: modell.boersen.fehler ?? String(localized: "Keine Börsen gewählt"))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            .padding(Abstand.kachelAbstand)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Eine Börse in einer Zeile: Punkt, Name, „schließt in“ oder „öffnet in“ mit Countdown.
private struct MiniBoersenZeile: View {
    let boerse: Boerse
    let status: Boersenstatus
    let jetzt: Date
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(spacing: Abstand.raster * 2) {
            Circle()
                .fill(status.offen ? thema.gewinn : thema.textSchwach)
                .frame(width: 8, height: 8)
                .accessibilityLabel(status.offen ? Text("offen") : Text("geschlossen"))
            Text(verbatim: boerse.name)
                .lineLimit(1)
            Spacer(minLength: Abstand.raster * 2)
            wechsel
        }
        .font(Schrift.tabelle)
        .help((status.feiertag ?? status.verkuerzt)?.uebersetzt ?? "")
    }

    @ViewBuilder
    private var wechsel: some View {
        if let ziel = status.naechsterWechsel, ziel > jetzt {
            HStack(spacing: Abstand.raster) {
                (status.offen ? Text("schließt in") : Text("öffnet in"))
                    .foregroundStyle(thema.textSchwach)
                Text(timerInterval: jetzt...ziel, countsDown: true)
                    .monospacedDigit()
                    .foregroundStyle(status.offen ? thema.text : thema.textSchwach)
            }
        } else if status.offen {
            Text("rund um die Uhr")
                .foregroundStyle(thema.textSchwach)
        } else {
            Text("geschlossen")
                .foregroundStyle(thema.textSchwach)
        }
    }
}
