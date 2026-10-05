import SwiftUI
import TradingCalendar
import TradingCore

/// Ansicht der Kalender-Seite: Wirtschaftstermine oder Ergebnis je Tag (Tim 05.10.2026).
enum Kalenderansicht: String, CaseIterable, Identifiable {
    case termine, ergebnis

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .termine: String(localized: "Termine")
        case .ergebnis: String(localized: "Ergebnis")
        }
    }
}

/// Ergebnis-Kalender (Tim 05.10.2026, Vorbild Monatskalender gängiger Trading-Journale): Netto je Tag nach Schlusstag
/// in der Anzeigewährung, Wochen- und Monatssumme, Markierung für Fehlermuster und Wirtschaftstermine. Ein Klick auf
/// einen Tag öffnet die Tagesseite. Rechnung im Kern (`Monatskalender`), hier nur Anzeige.
struct ErgebnisKalender: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    /// Erster Tag des gezeigten Monats.
    @State private var monat = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()

    var body: some View {
        let kalender = Calendar.current
        let teile = kalender.dateComponents([.year, .month], from: monat)
        let daten = Monatskalender(trades: modell.kalenderTrades, jahr: teile.year ?? 2026, monat: teile.month ?? 1,
                                   kalender: kalender)
        let mitMuster = modell.kalenderTradesMitMuster
        let terminTage = terminTage(kalender)
        let waehrung = modell.summenwaehrung
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            monatsleiste(kalender)
            kacheln(daten, waehrung)
            Karte(verbatim: Format.monat(monat)) {
                raster(daten, waehrung: waehrung, mitMuster: mitMuster, terminTage: terminTage)
            }
            MischwaehrungHinweis()
            Text("Netto nach Kosten, je Tag nach Schlusszeit. ⚠ Fehlermuster an diesem Tag, ● Wirtschaftstermin deiner Währungen. Ein Klick öffnet den Tag; die Tagesseite zeigt die an diesem Tag eröffneten Trades.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    // MARK: Monatsleiste und Kacheln

    private func monatsleiste(_ kalender: Calendar) -> some View {
        HStack(spacing: Abstand.raster * 2) {
            Button { blaettere(-1, kalender) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(Text("Monat davor"))
            Text(verbatim: Format.monat(monat))
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
                .frame(minWidth: 180)
            Button { blaettere(1, kalender) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(Text("Monat danach"))
            Button("Dieser Monat") {
                monat = kalender.date(from: kalender.dateComponents([.year, .month], from: Date())) ?? monat
            }
            Spacer()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(thema.akzent)
    }

    private func blaettere(_ schritt: Int, _ kalender: Calendar) {
        monat = kalender.date(byAdding: .month, value: schritt, to: monat) ?? monat
    }

    private func kacheln(_ daten: Monatskalender, _ waehrung: String) -> some View {
        LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Monat", wert: Format.geld(daten.netto, waehrung),
                   zusatz: String(localized: "\(daten.anzahl) Trades"),
                   farbe: daten.anzahl == 0 ? nil : thema.vorzeichen(daten.netto))
            Kachel(titel: "Gewinn- zu Verlusttagen", wert: "\(daten.gewinnTage) : \(daten.verlustTage)",
                   zusatz: String(localized: "Tage mit Trades: \(daten.tage.filter { $0.anzahl > 0 }.count)"))
            Kachel(titel: "Bester Tag", wert: daten.besterTag.map { Format.geld($0.netto, waehrung) } ?? "–",
                   zusatz: daten.besterTag.map { Format.datum($0.beginn) },
                   farbe: daten.besterTag == nil ? nil : thema.gewinn)
            Kachel(titel: "Schlechtester Tag", wert: daten.schlechtesterTag.map { Format.geld($0.netto, waehrung) } ?? "–",
                   zusatz: daten.schlechtesterTag.map { Format.datum($0.beginn) },
                   farbe: daten.schlechtesterTag == nil ? nil : thema.verlust)
        }
    }

    // MARK: Raster

    private func raster(_ daten: Monatskalender, waehrung: String, mitMuster: Set<String>,
                        terminTage: Set<Date>) -> some View {
        Grid(horizontalSpacing: Abstand.raster, verticalSpacing: Abstand.raster) {
            GridRow {
                ForEach(Self.wochentage, id: \.self) { name in
                    Text(verbatim: name)
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                        .frame(maxWidth: .infinity)
                }
                Text("Woche")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(daten.wochen.enumerated()), id: \.offset) { eintrag in
                GridRow {
                    ForEach(0..<7, id: \.self) { spalte in
                        if let tag = eintrag.element.tage[spalte] {
                            zelle(tag, groesster: daten.groessterBetrag, waehrung: waehrung,
                                  muster: tag.trades.contains(where: mitMuster.contains),
                                  termin: terminTage.contains(tag.beginn))
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: Self.zellenhoehe)
                        }
                    }
                    wochensumme(eintrag.element, waehrung)
                }
            }
        }
    }

    private func zelle(_ tag: Monatskalender.Tag, groesster: Decimal, waehrung: String, muster: Bool,
                       termin: Bool) -> some View {
        let heute = Calendar.current.isDateInToday(tag.beginn)
        return Button {
            modell.tagSprung = Journaltag(tag.beginn, zeitzone: .current)
            modell.bereich = .tag
        } label: {
            VStack(alignment: .leading, spacing: Abstand.raster / 2) {
                HStack(spacing: Abstand.raster) {
                    Text(verbatim: String(tag.tag))
                        .font(Schrift.beschriftung.weight(heute ? .bold : .regular))
                        .foregroundStyle(heute ? thema.akzent : thema.textSchwach)
                    Spacer(minLength: 0)
                    if muster {
                        Text(verbatim: "⚠").font(.caption2).foregroundStyle(thema.warnung)
                    }
                    if termin {
                        Text(verbatim: "●").font(.caption2).foregroundStyle(thema.akzent)
                    }
                }
                Spacer(minLength: 0)
                if tag.anzahl > 0 {
                    Text(verbatim: Self.kurz(tag.netto, waehrung))
                        .font(Schrift.tabelle.weight(.semibold))
                        .foregroundStyle(thema.vorzeichen(tag.netto))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: String(localized: "\(tag.anzahl) Trades"))
                        .font(.caption2)
                        .foregroundStyle(thema.textSchwach)
                        .lineLimit(1)
                }
            }
            .padding(Abstand.raster * 1.5)
            .frame(maxWidth: .infinity, minHeight: Self.zellenhoehe, alignment: .topLeading)
            .background(hintergrund(tag, groesster), in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
            .overlay(RoundedRectangle(cornerRadius: Abstand.radiusKnopf)
                .strokeBorder(heute ? thema.akzent : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: hilfe(tag, waehrung, muster: muster, termin: termin)))
        .accessibilityLabel(Text(verbatim: hilfe(tag, waehrung, muster: muster, termin: termin)))
        .accessibilityHint(Text("Tag öffnen"))
    }

    private func wochensumme(_ woche: Monatskalender.Woche, _ waehrung: String) -> some View {
        VStack(spacing: Abstand.raster / 2) {
            if woche.anzahl > 0 {
                Text(verbatim: Self.kurz(woche.netto, waehrung))
                    .font(Schrift.tabelle.weight(.semibold))
                    .foregroundStyle(thema.vorzeichen(woche.netto))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: String(localized: "\(woche.anzahl) Trades"))
                    .font(.caption2)
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.zellenhoehe)
        .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKnopf))
    }

    /// Grün oder Rot, umso kräftiger, je größer der Betrag im Verhältnis zum größten Tag des Monats.
    private func hintergrund(_ tag: Monatskalender.Tag, _ groesster: Decimal) -> Color {
        guard tag.anzahl > 0, tag.netto != 0, groesster > 0 else { return thema.flaeche2 }
        let anteil = Format.double(abs(tag.netto) / groesster)
        return (tag.netto > 0 ? thema.gewinn : thema.verlust).opacity(0.12 + 0.33 * anteil)
    }

    private func hilfe(_ tag: Monatskalender.Tag, _ waehrung: String, muster: Bool, termin: Bool) -> String {
        var teile = [Format.datum(tag.beginn)]
        teile.append(tag.anzahl == 0
                     ? String(localized: "keine Trades")
                     : String(localized: "\(tag.anzahl) Trades, Netto \(Format.geld(tag.netto, waehrung))"))
        if muster { teile.append(String(localized: "Fehlermuster")) }
        if termin { teile.append(String(localized: "Wirtschaftstermin")) }
        return teile.joined(separator: " · ")
    }

    /// Kalendertage mit einem Termin der eigenen Währungen (ohne erkannte Währung alle Termine).
    private func terminTage(_ kalender: Calendar) -> Set<Date> {
        let meine = modell.meineWaehrungen
        return Set(modell.termine.termine
            .filter { meine.isEmpty || !meine.isDisjoint(with: $0.waehrungen) }
            .map { kalender.startOfDay(for: Terminformat.tagesdatum($0)) })
    }

    // MARK: Texte

    private static let zellenhoehe: CGFloat = 64

    /// Kurze Wochentagsnamen ab Montag in der Sprache des Nutzers.
    private static var wochentage: [String] {
        let namen = Calendar.current.shortWeekdaySymbols
        return Array(namen[1...]) + [namen[0]]
    }

    /// Betrag ohne Nachkommastellen für die Zellen, mit Vorzeichen: „+75 €“, „−50 €“.
    static func kurz(_ wert: Decimal, _ waehrung: String) -> String {
        (wert > 0 ? "+" : "") + wert.formatted(.currency(code: waehrung).precision(.fractionLength(0)))
    }
}
