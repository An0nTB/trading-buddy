import SwiftUI
import TradingCore
import TradingRates
import TradingStore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Steuer-Orientierung je Konto und Kalenderjahr (Doc 22 Abschnitt 5; Entscheidungen E2, S1, S2 vom 02.10.2026):
/// Summen je Verlusttopf, Krypto-Haltefrist mit Freigrenze, Lücken in den Daten und ein Hinweis zum Broker.
/// Orientierung, keine Steuerberechnung; gerechnet wird in TradingCore (`Steuerorientierung`, `KryptoHaltefrist`).
struct SteuerView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    /// Gewähltes Jahr; ohne Wahl das jüngste Jahr mit Verkäufen.
    @State private var jahrAuswahl: Int?

    private var jahre: [Int] { modell.steuerjahre }
    private var jahr: Int { jahrAuswahl ?? jahre.first ?? Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Steuer-Orientierung", untertitel: untertitel) {
                    if !jahre.isEmpty {
                        Auswahlknopf("Jahr", anzeige: String(jahr), auswahl: jahrBinding) {
                            ForEach(jahre, id: \.self) { j in
                                Text(verbatim: String(j)).tag(j)
                            }
                        }
                    }
                }
                Text("Orientierung, keine Steuerberechnung: ohne Steuersatz, Sparer-Pauschbetrag, Verlustvorträge und Teilfreistellung. Was zu melden ist, klärt die Steuerberatung.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                if modell.konto == nil {
                    Text("Importiere zuerst einen Kontoauszug unter „Import“.")
                        .font(Schrift.fliesstext)
                        .foregroundStyle(thema.textSchwach)
                } else if jahre.isEmpty {
                    Text("Noch keine Verkäufe in diesem Konto.")
                        .font(Schrift.fliesstext)
                        .foregroundStyle(thema.textSchwach)
                } else {
                    inhalt
                }
            }
            .padding(Abstand.seitenrand)
        }
    }

    private var untertitel: String? {
        guard let konto = modell.konto else { return nil }
        return konto.broker + " · " + modell.waehrung + " · " + String(localized: "Verkaufsjahr nach deutscher Zeit")
    }

    /// Stand der EZB-Referenzkurse (Paket TradingRates, Doc 34): bis wann Kurse vorliegen, USDT als Näherung.
    private var ezbHinweis: String {
        var teile: [String] = []
        if let tag = modell.ezb.letzterTag {
            teile.append(String(localized: "EZB-Referenzkurse bis \(String(format: "%02d.%02d.%d", tag.tag, tag.monat, tag.jahr))"))
        } else {
            teile.append(String(localized: "EZB-Referenzkurse noch nicht geladen; Beträge in Fremdwährung bleiben Lücke"))
        }
        if modell.hatKrypto, EZBKurse.istNaeherung("USDT") {
            teile.append(String(localized: "USDT wie USD umgerechnet (Näherung)"))
        }
        if let fehler = modell.ezb.fehler {
            teile.append(String(localized: "Abruf: \(fehler)"))
        }
        return teile.joined(separator: " · ")
    }

    private var jahrBinding: Binding<Int> {
        Binding(get: { jahr }, set: { jahrAuswahl = $0 })
    }

    @ViewBuilder private var inhalt: some View {
        Text(verbatim: ezbHinweis)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
        let toepfe = modell.topfsummen(jahr: jahr)
        let krypto = modell.hatKrypto ? modell.kryptoJahr(jahr) : nil
        let luecken = Steuerluecken(toepfe: toepfe, krypto: krypto)
        LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
            topfKachel("Aktien-Topf", .aktien, toepfe, hinweis: String(localized: "Verluste nur gegen Aktiengewinne"))
            topfKachel("Allgemeiner Topf", .allgemein, toepfe, hinweis: nil)
            kryptoKachel(krypto)
            Kachel(titel: "Lücken", wert: String(luecken.anzahl), zusatz: luecken.kurz)
        }
        ToepfeKarte(toepfe: toepfe, jahr: jahr)
        if let krypto {
            KryptoKarte(jahr: krypto)
        }
        let produktartLuecken = modell.produktartLuecken()
        if !produktartLuecken.isEmpty {
            ProduktartKarte(luecken: produktartLuecken)
        }
        Kurvenpaar {
            LueckenKarte(luecken: luecken)
        } rechts: {
            BrokerKarte(jahr: jahr, toepfe: toepfe, krypto: krypto, luecken: luecken)
        }
    }

    private func topfKachel(_ titel: LocalizedStringKey, _ topf: Verlusttopf, _ toepfe: [Topfsumme],
                            hinweis: String?) -> some View {
        guard let summe = toepfe.first(where: { $0.topf == topf }) else {
            return Kachel(titel: titel, wert: "–", zusatz: String(localized: "keine Trades"), farbe: nil)
        }
        if summe.ohneEuro == summe.anzahl {
            return Kachel(titel: titel, wert: "–", zusatz: String(localized: "\(summe.anzahl) Trades ohne Euro"), farbe: nil)
        }
        var zusatz = String(localized: "\(summe.anzahl) Trades")
        if topf == .allgemein, summe.davonCFD != 0 {
            zusatz += " · " + String(localized: "davon CFDs \(Format.geld(summe.davonCFD, "EUR"))")
        } else if let hinweis {
            zusatz += " · " + hinweis
        }
        return Kachel(titel: titel, wert: Format.geld(summe.saldo, "EUR"), zusatz: zusatz,
                      farbe: thema.vorzeichen(summe.saldo))
    }

    private func kryptoKachel(_ krypto: KryptoHaltefrist.Jahr?) -> some View {
        guard let krypto, !krypto.lose.isEmpty else {
            return Kachel(titel: "Krypto steuerpflichtig", wert: "–",
                          zusatz: String(localized: "keine Krypto-Verkäufe"), farbe: nil)
        }
        let frei = krypto.unterFreigrenze
            ? String(localized: "unter Freigrenze 1.000 €")
            : String(localized: "über Freigrenze 1.000 €")
        let steuerfrei = String(localized: "steuerfrei \(Format.geld(krypto.steuerfrei, "EUR"))")
        return Kachel(titel: "Krypto steuerpflichtig", wert: Format.geld(krypto.steuerpflichtig, "EUR"),
                      zusatz: frei + " · " + steuerfrei, farbe: thema.vorzeichen(krypto.steuerpflichtig))
    }
}

/// Was in den Summen fehlt (Doc 22 Abschnitt 5 „Lücken mit Anzahl“). Erst ohne Lücken sind die Summen vollständig.
struct Steuerluecken {
    var ohneProduktart = 0
    var tradesOhneEuro = 0
    var kryptoOhneEuro = 0
    var ohneAnschaffung: [Ausfuehrung] = []
    var importhinweise = 0

    init(toepfe: [Topfsumme], krypto: KryptoHaltefrist.Jahr?) {
        ohneProduktart = toepfe.first { $0.topf == .nichtZugeordnet }?.anzahl ?? 0
        tradesOhneEuro = toepfe.reduce(0) { $0 + $1.ohneEuro }
        if let krypto {
            kryptoOhneEuro = krypto.ohneEuro
            ohneAnschaffung = krypto.ohneAnschaffung
            importhinweise = krypto.importhinweise
        }
    }

    var anzahl: Int { ohneProduktart + tradesOhneEuro + kryptoOhneEuro + ohneAnschaffung.count + importhinweise }

    /// Kurzform für die Kachel.
    var kurz: String {
        if anzahl == 0 { return String(localized: "Summen vollständig") }
        var teile: [String] = []
        if ohneProduktart > 0 { teile.append(String(localized: "\(ohneProduktart) ohne Produktart")) }
        if tradesOhneEuro > 0 { teile.append(String(localized: "\(tradesOhneEuro) ohne Euro")) }
        if kryptoOhneEuro > 0 { teile.append(String(localized: "\(kryptoOhneEuro) Krypto-Lose ohne Euro")) }
        if !ohneAnschaffung.isEmpty { teile.append(String(localized: "\(ohneAnschaffung.count) ohne Kauf")) }
        if importhinweise > 0 { teile.append(String(localized: "\(importhinweise) nicht verbucht")) }
        return teile.joined(separator: " · ")
    }

    /// Eine Zeile je Lücke: Zahl, Grund, Folge.
    var zeilen: [String] {
        var z: [String] = []
        if ohneProduktart > 0 {
            z.append(String(localized: "\(ohneProduktart) Trades ohne Produktart (Scalable, XTB): bis zur Zuordnung im Topf „nicht zugeordnet“; nachtragen in der Karte „Produktart nachtragen“."))
        }
        if tradesOhneEuro > 0 {
            z.append(String(localized: "\(tradesOhneEuro) Trades in einem Konto ohne Euro: fehlen in den Topf-Summen."))
        }
        if kryptoOhneEuro > 0 {
            z.append(String(localized: "\(kryptoOhneEuro) Krypto-Lose ohne Euro-Wert (Kauf oder Verkauf in USD, USDT): fehlen in den Haltefrist-Summen (Entscheidung S2)."))
        }
        if !ohneAnschaffung.isEmpty {
            z.append(String(localized: "\(ohneAnschaffung.count) Verkäufe ohne Kauf in den Daten (\(coins)): Übertrag von einer anderen Börse? Anschaffung fehlt."))
        }
        if importhinweise > 0 {
            z.append(String(localized: "\(importhinweise) Importzeilen nicht verbucht (Krypto gegen Krypto, Gebühr in BNB): Jahr und Betrag unbekannt."))
        }
        return z
    }

    private var coins: String {
        let namen = Set(ohneAnschaffung.map { $0.name.isEmpty ? $0.kennung : $0.name })
        return namen.sorted().prefix(3).joined(separator: ", ")
    }
}

/// Tabelle der Verlusttöpfe eines Jahres; am iPhone eine Liste mit zwei Zeilen je Topf.
struct ToepfeKarte: View {
    let toepfe: [Topfsumme]
    let jahr: Int
    @Environment(\.thema) private var thema

    var body: some View {
        Karte(verbatim: String(localized: "Verlusttöpfe \(String(jahr))")) {
            if toepfe.isEmpty {
                Text("Keine Verkäufe in diesem Jahr.")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                tabelle
            }
            Text("Ergebnis je Trade = Kursergebnis + Kommission + Swap, ohne abgeführte Steuern; Verkaufsjahr nach deutscher Zeit. Seit dem Jahressteuergesetz 2024 gibt es keinen eigenen Topf für Termingeschäfte (BMF-Schreiben 14.05.2025). Aktienverluste sind nur mit Aktiengewinnen verrechenbar (§ 20 Abs. 6 Satz 4 EStG, BVerfG 2 BvL 3/21 anhängig).")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    #if os(macOS)
    private var tabelle: some View {
        Grid(alignment: .trailing, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                kopf("Topf").gridColumnAlignment(.leading)
                kopf("Gewinne")
                kopf("Verluste")
                kopf("Saldo")
                kopf("Trades")
            }
            Divider()
            ForEach(toepfe, id: \.topf) { summe in
                zeile(summe)
                if summe.topf == .allgemein, summe.davonCFD != 0 {
                    cfdZeile(summe)
                }
            }
        }
    }

    private func zeile(_ s: Topfsumme) -> some View {
        let leer = s.ohneEuro == s.anzahl
        return GridRow {
            HStack(spacing: Abstand.raster * 2) {
                Text(verbatim: s.topf.titel)
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                if s.topf == .nichtZugeordnet {
                    Kapsel(text: String(localized: "Produktart fehlt"), betont: true)
                }
            }
            .gridColumnAlignment(.leading)
            zelle(leer ? nil : s.gewinne)
            zelle(leer ? nil : s.verluste)
            zelle(leer ? nil : s.saldo)
            Text(verbatim: String(s.anzahl))
                .font(Schrift.tabelle)
                .foregroundStyle(thema.text)
        }
    }

    private func cfdZeile(_ s: Topfsumme) -> some View {
        GridRow {
            Text("davon CFDs (Termingeschäfte, nur zur Information)")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                .padding(.leading, Abstand.kachelInnen)
                .gridColumnAlignment(.leading)
            Text(verbatim: "")
            Text(verbatim: "")
            Text(verbatim: Format.geld(s.davonCFD, "EUR"))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            Text(verbatim: "")
        }
    }

    private func kopf(_ titel: LocalizedStringKey) -> some View {
        Text(titel)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }
    #else
    private var tabelle: some View {
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            ForEach(toepfe, id: \.topf) { s in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Abstand.raster) {
                        Text(verbatim: s.topf.titel)
                            .font(Schrift.fliesstext)
                            .foregroundStyle(thema.text)
                        Text(verbatim: untertitel(s))
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                    Spacer()
                    zelle(s.ohneEuro == s.anzahl ? nil : s.saldo)
                }
                Divider()
            }
        }
    }

    private func untertitel(_ s: Topfsumme) -> String {
        if s.ohneEuro == s.anzahl { return String(localized: "\(s.anzahl) Trades ohne Euro") }
        let gewinne = Format.geld(s.gewinne, "EUR")
        let verluste = Format.geld(s.verluste, "EUR")
        var t = String(localized: "\(s.anzahl) Trades · Gewinne \(gewinne) · Verluste \(verluste)")
        if s.topf == .allgemein, s.davonCFD != 0 {
            t += " · " + String(localized: "davon CFDs \(Format.geld(s.davonCFD, "EUR"))")
        }
        if s.topf == .nichtZugeordnet {
            t += " · " + String(localized: "Produktart fehlt")
        }
        return t
    }
    #endif

    private func zelle(_ wert: Decimal?) -> some View {
        Text(verbatim: wert.map { Format.geld($0, "EUR") } ?? "–")
            .font(Schrift.tabelle)
            .foregroundStyle(wert.map { thema.vorzeichen($0) } ?? thema.textSchwach)
    }
}

/// Krypto-Haltefrist eines Jahres: Lose der Verkäufe, Bestand mit erstem steuerfreiem Verkaufstag.
struct KryptoKarte: View {
    let jahr: KryptoHaltefrist.Jahr
    @State private var alleLose = false
    @Environment(\.thema) private var thema
    private static let vorschau = 6

    var body: some View {
        Karte(verbatim: String(localized: "Krypto-Haltefrist \(String(jahr.jahr))")) {
            kapseln
            if jahr.lose.isEmpty {
                Text("Keine Krypto-Verkäufe in diesem Jahr.")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                lose
                if jahr.lose.count > Self.vorschau {
                    Button(action: { alleLose.toggle() }) {
                        Text(verbatim: alleLose
                             ? String(localized: "Weniger zeigen")
                             : String(localized: "Alle \(jahr.lose.count) Lose zeigen"))
                    }
                    .buttonStyle(.plain)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.akzent)
                }
            }
            if !jahr.offen.isEmpty {
                bestand
            }
            Text("Verkauf innerhalb eines Jahres nach Anschaffung ist steuerpflichtig, danach frei; Gewinne eines Jahres unter 1.000 € bleiben frei (Freigrenze, kein Freibetrag; § 23 EStG, Rechtsstand 2026). FIFO je Konto und Coin. Fristende: Tag nach dem Jahrestag in deutscher Zeit (Einschätzung). Lose in USD oder USDT ohne Tageskurs zählen nur als Lücke (Entscheidung S2).")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private var sichtbareLose: [KryptoHaltefrist.Los] {
        alleLose ? jahr.lose : Array(jahr.lose.prefix(Self.vorschau))
    }

    private var kapseln: some View {
        HStack(spacing: Abstand.raster * 2) {
            Farbkapsel(text: String(localized: "Steuerpflichtig \(Format.geld(jahr.steuerpflichtig, "EUR"))"),
                       farbe: jahr.steuerpflichtig > 0 ? thema.verlust : thema.textSchwach)
            Farbkapsel(text: String(localized: "Steuerfrei \(Format.geld(jahr.steuerfrei, "EUR"))"), farbe: thema.gewinn)
            Kapsel(text: jahr.unterFreigrenze
                   ? String(localized: "Unter Freigrenze 1.000 €")
                   : String(localized: "Über Freigrenze 1.000 €"), betont: true)
            if jahr.ohneEuro > 0 {
                Kapsel(text: String(localized: "\(jahr.ohneEuro) Lose ohne Euro-Wert"))
            }
        }
    }

    #if os(macOS)
    private var lose: some View {
        Grid(alignment: .trailing, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster * 2) {
            GridRow {
                kopf("Coin").gridColumnAlignment(.leading)
                kopf("Menge")
                kopf("Kauf")
                kopf("Verkauf")
                kopf("Haltedauer")
                kopf("Gewinn")
                kopf("Status")
            }
            Divider()
            ForEach(Array(sichtbareLose.enumerated()), id: \.offset) { _, los in
                GridRow {
                    Text(verbatim: los.coin)
                        .font(Schrift.fliesstext)
                        .foregroundStyle(thema.text)
                        .gridColumnAlignment(.leading)
                    tabellentext(Format.zahl(los.menge, stellen: 4))
                    tabellentext(Format.datum(los.kaufzeit))
                    tabellentext(Format.datum(los.verkaufzeit))
                    tabellentext(Steuertext.tage(von: los.kaufzeit, bis: los.verkaufzeit))
                    gewinn(los)
                    status(los)
                }
            }
        }
    }

    private func kopf(_ titel: LocalizedStringKey) -> some View {
        Text(titel)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func tabellentext(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Schrift.tabelle)
            .foregroundStyle(thema.text)
    }
    #else
    private var lose: some View {
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            ForEach(Array(sichtbareLose.enumerated()), id: \.offset) { _, los in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Abstand.raster) {
                        Text(verbatim: los.coin + " " + Format.zahl(los.menge, stellen: 4))
                            .font(Schrift.fliesstext)
                            .foregroundStyle(thema.text)
                        Text(verbatim: Format.datum(los.kaufzeit) + " bis " + Format.datum(los.verkaufzeit)
                             + " · " + Steuertext.tage(von: los.kaufzeit, bis: los.verkaufzeit))
                            .font(Schrift.beschriftung)
                            .foregroundStyle(thema.textSchwach)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Abstand.raster) {
                        gewinn(los)
                        status(los)
                    }
                }
                Divider()
            }
        }
    }
    #endif

    private func gewinn(_ los: KryptoHaltefrist.Los) -> some View {
        Text(verbatim: los.gewinn.map { Format.geld($0, "EUR") } ?? "–")
            .font(Schrift.tabelle)
            .foregroundStyle(los.gewinn.map { thema.vorzeichen($0) } ?? thema.textSchwach)
    }

    private func status(_ los: KryptoHaltefrist.Los) -> some View {
        if los.gewinn == nil {
            return Farbkapsel(text: String(localized: "ohne Euro"), farbe: thema.textSchwach)
        }
        return los.steuerfrei
            ? Farbkapsel(text: String(localized: "steuerfrei"), farbe: thema.gewinn)
            : Farbkapsel(text: String(localized: "steuerpflichtig"), farbe: thema.verlust)
    }

    @ViewBuilder private var bestand: some View {
        Text("Bestand und erster steuerfreier Verkaufstag")
            .font(.headline)
            .foregroundStyle(thema.text)
        ForEach(Array(jahr.offen.prefix(8).enumerated()), id: \.offset) { _, b in
            HStack(spacing: Abstand.raster * 2) {
                Text(verbatim: b.coin + " " + Format.zahl(b.menge, stellen: 4))
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                Text(verbatim: String(localized: "gekauft \(Format.datum(b.kaufzeit))"))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                Spacer()
                Text(verbatim: String(localized: "steuerfrei ab \(Format.datum(b.steuerfreiAb))"))
                    .font(Schrift.tabelle)
                    .foregroundStyle(thema.text)
                bestandKapsel(b)
            }
        }
        if jahr.offen.count > 8 {
            Text("\(jahr.offen.count - 8) weitere Bestände")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private func bestandKapsel(_ b: KryptoHaltefrist.Bestand) -> some View {
        let tage = Steuertext.tageBis(b.steuerfreiAb)
        return tage <= 0
            ? Farbkapsel(text: String(localized: "frei seit \(-tage) Tagen"), farbe: thema.gewinn)
            : Farbkapsel(text: String(localized: "noch \(tage) Tage"), farbe: thema.textSchwach)
    }
}

/// Liste der Lücken (Doc 22 Abschnitt 5).
struct LueckenKarte: View {
    let luecken: Steuerluecken
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Lücken in den Daten") {
            if luecken.anzahl == 0 {
                Text("Keine Lücken: Produktart, Euro-Werte und Anschaffungen sind vollständig.")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                ForEach(luecken.zeilen, id: \.self) { zeile in
                    HStack(alignment: .top, spacing: Abstand.raster * 2) {
                        Text(verbatim: "•")
                            .foregroundStyle(thema.textSchwach)
                        Text(verbatim: zeile)
                            .font(Schrift.fliesstext)
                            .foregroundStyle(thema.text)
                    }
                }
                Text("Erst wenn hier nichts mehr steht, sind die Summen vollständig.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }
}

/// Hinweis, ob der Broker die Steuer abführt, plus Bericht als Text in die Zwischenablage.
struct BrokerKarte: View {
    let jahr: Int
    let toepfe: [Topfsumme]
    let krypto: KryptoHaltefrist.Jahr?
    let luecken: Steuerluecken
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var kopiert = false

    var body: some View {
        Karte("Konto und Broker") {
            HStack(spacing: Abstand.raster * 2) {
                Farbkapsel(text: status.text, farbe: status.farbe)
                if let konto = modell.konto {
                    Kapsel(text: konto.broker)
                }
            }
            Text(verbatim: erklaerung)
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            Text("Diese Seite zeigt ein Konto. Eine Summe über alle Konten folgt, wenn die App mehrere Konten gleichzeitig lädt.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            HStack {
                Spacer()
                Button(action: kopieren) {
                    Text(verbatim: kopiert ? String(localized: "Kopiert") : String(localized: "Als Text kopieren"))
                }
            }
        }
    }

    private var status: (text: String, farbe: Color) {
        switch modell.brokerFuehrtSteuerAb {
        case .some(true): (String(localized: "Broker führt Steuer ab"), thema.gewinn)
        case .some(false): (String(localized: "Broker führt keine Steuer ab"), thema.verlust)
        case .none: (String(localized: "Steuerabzug unbekannt"), thema.textSchwach)
        }
    }

    private var erklaerung: String {
        switch modell.brokerFuehrtSteuerAb {
        case .some(true):
            String(localized: "Trade Republic und Scalable Capital führen die Steuer ab; maßgeblich ist die Steuerbescheinigung des Brokers (Recherche R5, 2026). Diese Seite dient dem Abgleich.")
        case .some(false):
            String(localized: "Ohne Abzug durch den Broker kommen die Zahlen erst über die Steuererklärung zum Finanzamt; dafür ist diese Seite gedacht (Recherche R5, 2026).")
        case .none:
            String(localized: "Ob dieser Broker Steuer abführt, weiß die App nicht. Trade Republic und Scalable Capital führen ab; MetaTrader, XTB und Krypto-Börsen nicht (Recherche R5, 2026).")
        }
    }

    private func kopieren() {
        let text = Steuertext.bericht(jahr: jahr, konto: modell.konto, waehrung: modell.waehrung,
                                      toepfe: toepfe, krypto: krypto, luecken: luecken)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        kopiert = true
    }
}

/// Kapsel in einer Farbe der Farbwelt (Gewinn, Verlust, schwach), für Status wie steuerfrei oder steuerpflichtig.
struct Farbkapsel: View {
    let text: String
    let farbe: Color

    var body: some View {
        Text(verbatim: text)
            .font(Schrift.beschriftung)
            .padding(.horizontal, Abstand.raster * 2)
            .padding(.vertical, Abstand.raster)
            .background(farbe.opacity(0.18), in: Capsule())
            .foregroundStyle(farbe)
    }
}

/// Texte und Tagesrechnung für die Steuerseite, in deutscher Zeit wie der Rechenkern.
enum Steuertext {
    private static var kalender: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = Steuerorientierung.deutscheZeit
        return kalender
    }

    /// Haltedauer in Kalendertagen.
    static func tage(von: Date, bis: Date) -> String {
        let k = kalender
        let n = k.dateComponents([.day], from: k.startOfDay(for: von), to: k.startOfDay(for: bis)).day ?? 0
        return n == 1 ? String(localized: "1 Tag") : String(localized: "\(n) Tage")
    }

    /// Tage von heute bis zu einem Datum; negativ, wenn es vorbei ist.
    static func tageBis(_ datum: Date, jetzt: Date = Date()) -> Int {
        let k = kalender
        return k.dateComponents([.day], from: k.startOfDay(for: jetzt), to: k.startOfDay(for: datum)).day ?? 0
    }

    /// Bericht für die Zwischenablage: Töpfe, Krypto, Lücken, je eine Zeile.
    static func bericht(jahr: Int, konto: Konto?, waehrung: String, toepfe: [Topfsumme],
                        krypto: KryptoHaltefrist.Jahr?, luecken: Steuerluecken) -> String {
        var zeilen: [String] = []
        var kopf = String(localized: "Steuer-Orientierung \(String(jahr))")
        if let konto { kopf += " · " + konto.broker + " " + konto.kontoname + " · " + waehrung }
        zeilen.append(kopf)
        zeilen.append(String(localized: "Orientierung, keine Steuerberechnung. Ergebnis je Trade = Kursergebnis + Kommission + Swap, ohne abgeführte Steuern."))
        zeilen.append(String(localized: "Verlusttöpfe:"))
        for s in toepfe {
            if s.ohneEuro == s.anzahl {
                zeilen.append("- " + s.topf.titel + ": " + String(localized: "\(s.anzahl) Trades ohne Euro"))
                continue
            }
            let gewinne = Format.geld(s.gewinne, "EUR")
            let verluste = Format.geld(s.verluste, "EUR")
            let saldo = Format.geld(s.saldo, "EUR")
            var t = "- " + s.topf.titel + ": "
            t += String(localized: "Gewinne \(gewinne), Verluste \(verluste), Saldo \(saldo), \(s.anzahl) Trades")
            if s.topf == .allgemein, s.davonCFD != 0 {
                t += ", " + String(localized: "davon CFDs \(Format.geld(s.davonCFD, "EUR"))")
            }
            zeilen.append(t)
        }
        if let krypto {
            let pflichtig = Format.geld(krypto.steuerpflichtig, "EUR")
            let frei = Format.geld(krypto.steuerfrei, "EUR")
            let grenze = krypto.unterFreigrenze
                ? String(localized: "unter Freigrenze 1.000 €")
                : String(localized: "über Freigrenze 1.000 €")
            zeilen.append(String(localized: "Krypto-Haltefrist: steuerpflichtig \(pflichtig), steuerfrei \(frei), \(grenze), \(krypto.lose.count) Lose"))
        }
        if luecken.anzahl > 0 {
            zeilen.append(String(localized: "Lücken:"))
            zeilen.append(contentsOf: luecken.zeilen.map { "- " + $0 })
        }
        return zeilen.joined(separator: "\n")
    }
}

extension Verlusttopf {
    /// Name in der Oberfläche.
    var titel: String {
        switch self {
        case .aktien: String(localized: "Aktien")
        case .allgemein: String(localized: "Allgemein (Fonds, Anleihen, Derivate, CFDs)")
        case .krypto: String(localized: "Krypto (Haltefrist unten)")
        case .nichtZugeordnet: String(localized: "Nicht zugeordnet")
        }
    }
}
