import SwiftUI
import TradingCore

// Steuer-Orientierung als eigenes PDF je Kalenderjahr (Koordinator 03.10.2026, Doc 22). Rechnet nichts neu:
// Töpfe aus `Steuerorientierung.toepfe`, Krypto aus `KryptoHaltefrist.jahr`, beide mit EZB-Kursen wie die
// Steuer-Seite der App. Beträge in Euro, Verkaufsjahr nach deutscher Zeit.

/// Inhalt des Steuer-PDFs für ein Kalenderjahr.
struct SteuerAnlage {
    let jahr: Int
    let toepfe: [Topfsumme]
    /// `nil`, wenn das Konto keine Krypto-Ausführungen hat; dann entfällt Seite 2.
    let krypto: KryptoHaltefrist.Jahr?
    let kontext: BerichtKontext

    /// Trades ohne Euro-Wert, die in keiner Topfsumme stehen. Nur die Töpfe: ein Krypto-Trade ohne Kurs steht dort
    /// und als Los auf Seite 2 unter „Lücken“, zusammengezählt wäre er doppelt.
    var ohneKurs: Int { toepfe.reduce(0) { $0 + $1.ohneEuro } }

    static var fusshinweis: String {
        String(localized: "Orientierung, keine Steuerberatung und kein Steuerbescheid.")
    }

    @MainActor
    func daten(thema: Thema) -> Data? {
        let anzahl = krypto == nil ? 1 : 2
        var seiten = [AnyView(BerichtRahmen(kontext: kontext, seitentitel: String(localized: "Verlusttöpfe"),
                                            nummer: 1, anzahl: anzahl, fusshinweis: Self.fusshinweis) {
            SteuerToepfeSeite(anlage: self)
        })]
        if let krypto {
            seiten.append(AnyView(BerichtRahmen(kontext: kontext, seitentitel: String(localized: "Krypto-Haltefrist"),
                                                nummer: 2, anzahl: anzahl, fusshinweis: Self.fusshinweis) {
                SteuerKryptoSeite(krypto: krypto)
            }))
        }
        return BerichtPDF.daten(seiten: seiten, titel: kontext.titel, thema: thema)
    }
}

extension AppModell {
    /// Steuer-Orientierung für das Kalenderjahr `jahr` in deutscher Zeit, über alle Trades des Kontos.
    func steuerAnlage(_ jahr: Int, jetzt: Date = Date()) -> SteuerAnlage? {
        let zeitzone = Steuerorientierung.deutscheZeit
        guard let zeitraum = Zeitspanne.tage(von: DateComponents(year: jahr, month: 1, day: 1),
                                             bis: DateComponents(year: jahr, month: 12, day: 31), zeitzone: zeitzone)
        else { return nil }
        var kontext = berichtKontext(zeitraum, art: .steuer(jahr),
                                     titel: String(localized: "Steuer-Orientierung \(String(jahr))"),
                                     zeitzone: zeitzone, jetzt: jetzt)
        // Die Töpfe lauten auf Euro, auch bei einem Konto in anderer Währung.
        kontext.waehrung = "EUR"
        return SteuerAnlage(jahr: jahr, toepfe: topfsummen(jahr: jahr), krypto: hatKrypto ? kryptoJahr(jahr) : nil,
                            kontext: kontext)
    }
}

/// Deutlicher Kasten oben auf jeder Seite.
struct SteuerBanner: View {
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Orientierung, keine Steuerberatung")
                .font(BerichtSchrift.abschnitt)
                .foregroundStyle(thema.text)
            BerichtHinweis(String(localized: "Kein Steuerbescheid. Ohne Steuersatz, Sparer-Pauschbetrag, Verlustvorträge und Teilfreistellung. Maßgeblich sind Steuerbescheinigung, Erklärung und Bescheid."))
        }
        .frame(width: BerichtMass.breite - Abstand.raster * 6, alignment: .leading)
        .padding(Abstand.raster * 3)
        .background(thema.grund, in: RoundedRectangle(cornerRadius: BerichtMass.radius))
    }
}

// MARK: Seite 1: Verlusttöpfe

struct SteuerToepfeSeite: View {
    let anlage: SteuerAnlage
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: BerichtMass.abschnittAbstand) {
            SteuerBanner()
            BerichtAbschnitt(titel: "Verlusttöpfe",
                             untertitel: String(localized: "1. Januar bis 31. Dezember \(String(anlage.jahr)), Beträge in Euro, Verkaufsjahr nach deutscher Zeit. Ergebnis je Trade = Kursergebnis + Kommission + Swap.")) {
                if anlage.toepfe.isEmpty {
                    BerichtHinweis(String(localized: "Keine Verkäufe in diesem Jahr."))
                }
                ForEach(anlage.toepfe, id: \.topf) { summe in
                    VStack(alignment: .leading, spacing: 1) {
                        BerichtZeile(titel: summe.topf.berichtTitel, wert: wert(summe),
                                     farbe: summe.ohneEuro == summe.anzahl ? nil : thema.vorzeichen(summe.saldo))
                        BerichtHinweis(zusatz(summe))
                        BerichtHinweis(summe.topf.steuerErklaerung)
                    }
                }
            }
            BerichtAbschnitt(titel: "Hinweise zu den Daten") {
                if anlage.ohneKurs > 0 {
                    BerichtZeile(titel: String(localized: "Ohne Euro-Kurs, in keiner Summe enthalten"),
                                 wert: String(anlage.ohneKurs), farbe: thema.verlust)
                    BerichtHinweis(String(localized: "Diese Trades lauten auf eine fremde Währung, für deren Schlusstag kein EZB-Referenzkurs vorliegt. Nach dem nächsten Kursabruf in der App den Bericht neu erstellen."))
                }
                BerichtHinweis(ezbText)
                if let abzug = abzugText {
                    BerichtHinweis(abzug)
                }
                BerichtHinweis(String(localized: "Grundlage sind alle Trades des Kontos, unabhängig vom Filter in der App."))
            }
        }
    }

    private func wert(_ summe: Topfsumme) -> String {
        summe.ohneEuro == summe.anzahl ? "–" : String(localized: "Saldo \(Format.geld(summe.saldo, "EUR"))")
    }

    private func zusatz(_ summe: Topfsumme) -> String {
        var teile = [String(localized: "\(summe.anzahl) Trades"),
                     String(localized: "Gewinne \(Format.geld(summe.gewinne, "EUR"))"),
                     String(localized: "Verluste \(Format.geld(summe.verluste, "EUR"))")]
        if summe.topf == .allgemein, summe.davonCFD != 0 {
            teile.append(String(localized: "davon CFDs \(Format.geld(summe.davonCFD, "EUR"))"))
        }
        if summe.ohneEuro > 0 {
            teile.append(String(localized: "\(summe.ohneEuro) Trades ohne Euro-Wert nicht enthalten"))
        }
        return teile.joined(separator: " · ")
    }

    private var ezbText: String {
        guard let tag = anlage.kontext.ezbBis else {
            return String(localized: "EZB-Referenzkurse noch nicht geladen; Trades in Fremdwährung fehlen in den Euro-Summen.")
        }
        let bis = BerichtKontext.datum(tag)
        return String(localized: "Fremdwährung zum EZB-Referenzkurs am Schlusstag umgerechnet (Näherung, USDT wie USD), Kurse bis \(bis).")
    }

    private var abzugText: String? {
        switch anlage.kontext.brokerFuehrtSteuerAb {
        case true?: String(localized: "Der Broker führt die Steuer selbst ab; maßgeblich ist seine Steuerbescheinigung.")
        case false?: String(localized: "Der Broker führt keine Steuer ab; Gewinne gehören in die Steuererklärung.")
        case nil: nil
        }
    }
}

extension Verlusttopf {
    /// Ein Satz zur Verrechnung je Topf, Rechtsstand 2026 laut Doc 22.
    var steuerErklaerung: String {
        switch self {
        case .aktien:
            String(localized: "Aktienverluste sind nur mit Aktiengewinnen verrechenbar.")
        case .allgemein:
            String(localized: "Termingeschäfte und CFDs laufen seit dem Jahressteuergesetz 2024 im allgemeinen Topf mit.")
        case .krypto:
            String(localized: "Private Veräußerungsgeschäfte; nach über einem Jahr Haltedauer steuerfrei, Aufteilung auf Seite 2.")
        case .nichtZugeordnet:
            String(localized: "Produktart unbekannt; in der App auf der Seite Trades zuordnen.")
        }
    }
}

// MARK: Seite 2: Krypto-Haltefrist

struct SteuerKryptoSeite: View {
    /// Mehr Zeilen passen nicht sicher auf die Seite.
    static let hoechstensBestand = 12
    let krypto: KryptoHaltefrist.Jahr
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: BerichtMass.abschnittAbstand) {
            SteuerBanner()
            BerichtAbschnitt(titel: "Verkäufe im Jahr",
                             untertitel: String(localized: "Verkäufe nach FIFO je Coin über alle Ausführungen des Kontos, Haltefrist ein Jahr in deutscher Zeit, Beträge in Euro.")) {
                BerichtZeile(titel: String(localized: "Steuerpflichtig (bis ein Jahr gehalten)"),
                             wert: Format.geld(krypto.steuerpflichtig, "EUR"), farbe: thema.vorzeichen(krypto.steuerpflichtig))
                BerichtZeile(titel: String(localized: "Steuerfrei (über ein Jahr gehalten)"),
                             wert: Format.geld(krypto.steuerfrei, "EUR"), farbe: thema.vorzeichen(krypto.steuerfrei))
                BerichtZeile(titel: String(localized: "Verkaufte Lose"),
                             wert: String(localized: "\(krypto.lose.count), davon \(krypto.lose.filter(\.steuerfrei).count) steuerfrei"))
                BerichtHinweis(freigrenzeText)
            }
            BerichtAbschnitt(titel: "Lücken") {
                if krypto.vollstaendig {
                    BerichtHinweis(String(localized: "Keine Lücken: alle Lose mit Euro-Wert und Kauf in den Daten."))
                }
                if krypto.ohneEuro > 0 {
                    BerichtZeile(titel: String(localized: "Lose ohne Euro-Wert, nicht in den Summen"),
                                 wert: String(krypto.ohneEuro), farbe: thema.verlust)
                }
                if !krypto.ohneAnschaffung.isEmpty {
                    BerichtZeile(titel: String(localized: "Verkäufe ohne Kauf in den Daten"),
                                 wert: String(krypto.ohneAnschaffung.count), farbe: thema.verlust)
                    BerichtHinweis(String(localized: "Etwa von einer anderen Börse übertragen. Ohne Kaufdatum lassen sich Haltedauer und Gewinn nicht bestimmen."))
                }
                if krypto.importhinweise > 0 {
                    BerichtZeile(titel: String(localized: "Nicht verbuchte Importzeilen"),
                                 wert: String(krypto.importhinweise), farbe: thema.verlust)
                    BerichtHinweis(String(localized: "Krypto gegen Krypto oder Gebühren in einem Coin; das Jahr ist unbekannt, sie können dieses Jahr betreffen."))
                }
            }
            BerichtAbschnitt(titel: "Bestand am Ende der Daten",
                             untertitel: String(localized: "Ab dem genannten Tag wäre ein Verkauf nach der Haltefrist steuerfrei.")) {
                if krypto.offen.isEmpty {
                    BerichtHinweis(String(localized: "Kein offener Bestand."))
                }
                ForEach(Array(krypto.offen.prefix(Self.hoechstensBestand).enumerated()), id: \.offset) { eintrag in
                    let bestand = eintrag.element
                    BerichtZeile(titel: "\(bestand.coin) \(Format.zahl(bestand.menge, stellen: 6))",
                                 wert: String(localized: "steuerfrei ab \(tag(bestand.steuerfreiAb))"))
                }
                if krypto.offen.count > Self.hoechstensBestand {
                    BerichtHinweis(String(localized: "Dazu \(krypto.offen.count - Self.hoechstensBestand) weitere auf der Steuer-Seite der App."))
                }
            }
        }
    }

    private var freigrenzeText: String {
        let grenze = Format.geld(KryptoHaltefrist.freigrenze, "EUR")
        return krypto.unterFreigrenze
            ? String(localized: "Steuerpflichtiger Saldo unter der Freigrenze von \(grenze) für private Veräußerungsgeschäfte. Die Grenze gilt für alle solchen Geschäfte zusammen, nicht je Konto.")
            : String(localized: "Steuerpflichtiger Saldo erreicht die Freigrenze von \(grenze) für private Veräußerungsgeschäfte. Die Grenze gilt für alle solchen Geschäfte zusammen, nicht je Konto.")
    }

    private func tag(_ datum: Date) -> String {
        BerichtKontext.datum(Journaltag(datum, zeitzone: Steuerorientierung.deutscheZeit))
    }
}
