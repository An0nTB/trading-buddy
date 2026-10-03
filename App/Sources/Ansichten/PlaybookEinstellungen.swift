import SwiftUI
import TradingCore
import TradingStore

/// Reiter „Playbook“ der Einstellungen (Doc 18 F3, Doc 23; Migration v7 aus AP9 #59): eine Karte je Setup mit
/// Kriterien, Stop- und Zielregel, Marktumfeld, Notiz und Status (Test, Aktiv, Pausiert). Karten gelten für alle
/// Konten; die Häkchen je Trade setzt du im Inspektor der Trade-Liste. Entwurf mit Speichern und Verwerfen wie
/// bei „Regeln“, weil die Karten in der Datenbank liegen und die Speicherung Namen und Kriterien prüft.
struct PlaybookEinstellungen: View {
    @AppStorage(Ton.schluessel) private var ton = Ton.henry
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    /// Gewählte Karte (Datenbank-ID) oder `nil` für eine neue Karte.
    @State private var auswahl: Int64?
    @State private var entwurf = Setup(name: "")
    /// Stand der Karte beim Laden; der Vergleich damit schaltet Speichern und Verwerfen frei.
    @State private var basis = Setup(name: "")
    @State private var meldung: String?
    @State private var meldungIstFehler = false
    @State private var loeschenBestaetigen = false

    var body: some View {
        Group {
            Section {
                Picker("Karte", selection: $auswahl) {
                    Text("Neue Karte").tag(Int64?.none)
                    ForEach(modell.playbook, id: \.id) { karte in
                        Text(verbatim: karte.name).tag(karte.id)
                    }
                }
                hinweis("Eine Karte je Setup: Bedingungen für den Einstieg, Stop- und Zielregel. Der Name verbindet die Karte mit dem Feld „Setup“ im Journal; im Inspektor der Trade-Liste hakst du die Kriterien je Trade ab.")
            }
            Section("Setup") {
                TextField("Name", text: $entwurf.name, prompt: Text("z. B. Ausbruch"))
                Picker("Status", selection: $entwurf.status) {
                    ForEach(Setup.Status.allCases, id: \.self) { status in
                        Text(verbatim: Setupformat.status(status)).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                hinweis(verbatim: statusHinweis)
            }
            kriterienAbschnitt
            Section("Regeln der Karte") {
                textfeld("Stop-Regel", optional(\.stopRegel), prompt: "z. B. unter das Tief der Signalkerze")
                textfeld("Ziel-Regel", optional(\.zielRegel), prompt: "z. B. 2 R oder das Vortageshoch")
                textfeld("Marktumfeld", optional(\.marktumfeld), prompt: "z. B. nur im Trend, nicht vor Zahlen")
                textfeld("Notiz", optional(\.notiz), prompt: "Beispiele, Beobachtungen")
            }
            knopfzeile
        }
        .onAppear(perform: laden)
        .onChange(of: auswahl) { laden() }
        .onChange(of: modell.playbook) {
            // Karte von anderer Stelle gelöscht: zurück auf „Neue Karte“.
            if let auswahl, !modell.playbook.contains(where: { $0.id == auswahl }) { self.auswahl = nil }
        }
    }

    private var kriterienAbschnitt: some View {
        Section("Kriterien") {
            ForEach($entwurf.kriterien, id: \.id) { $kriterium in
                HStack {
                    TextField("Bedingung", text: $kriterium.text, prompt: Text("z. B. Kurs über dem Tageshoch"))
                        .labelsHidden()
                    Button {
                        entwurf.kriterien.removeAll { $0.id == kriterium.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Kriterium entfernen")
                    .accessibilityLabel(Text("Kriterium entfernen")) // Doc 55 J15
                }
            }
            Button("Kriterium hinzufügen") { entwurf.kriterien.append(Kriterium(text: "")) }
            hinweis("Jedes Kriterium wird im Inspektor ein Häkchen je Trade. Umformulieren ist unschädlich; Entfernen und neu Anlegen verliert die alten Häkchen dieses Kriteriums.")
        }
    }

    private var knopfzeile: some View {
        Section {
            HStack {
                Button("Verwerfen") {
                    laden()
                    meldung = nil
                }
                .disabled(!geaendert)
                if auswahl != nil {
                    Button("Karte löschen", role: .destructive) { loeschenBestaetigen = true }
                }
                Spacer()
                Button("Speichern", action: speichern)
                    .buttonStyle(.borderedProminent)
                    .disabled(!geaendert)
            }
            if let meldung {
                Text(verbatim: meldung)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(meldungIstFehler ? thema.verlust : thema.textSchwach)
            }
        }
        .confirmationDialog("Karte „\(basis.name)“ löschen?", isPresented: $loeschenBestaetigen, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: loeschen)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(verbatim: loeschenText)
        }
    }

    private var geaendert: Bool { entwurf != basis }

    private var statusHinweis: String {
        let erklaerung = String(localized: "Test: in der Probephase, noch nicht fest im Plan. Aktiv: im Einsatz. Pausiert: ausgesetzt, Karte bleibt.")
        guard auswahl != nil else { return erklaerung }
        return erklaerung + " " + String(localized: "Status seit \(Format.datum(basis.statusSeit)).")
    }

    private var loeschenText: String {
        let anzahl = modell.anzahlTrades(setup: basis.name)
        if anzahl == 0 {
            return String(localized: "Kein Trade dieses Kontos trägt das Setup. Die Karte und ihre Kriterien verschwinden.")
        }
        return String(localized: "\(anzahl) Trades dieses Kontos tragen das Setup; sie behalten den Namen im Journal, nur die Karte und ihre Kriterien verschwinden.")
    }

    // MARK: Felder

    private func textfeld(_ titel: LocalizedStringKey, _ text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        TextField(titel, text: text, prompt: Text(prompt), axis: .vertical)
            .lineLimit(1...3)
    }

    /// Textfeld auf ein freiwilliges Feld: leer heißt `nil`.
    private func optional(_ feld: WritableKeyPath<Setup, String?>) -> Binding<String> {
        Binding(
            get: { entwurf[keyPath: feld] ?? "" },
            set: { entwurf[keyPath: feld] = $0.isEmpty ? nil : $0 }
        )
    }

    private func hinweis(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    private func hinweis(verbatim text: String) -> some View {
        Text(verbatim: text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
    }

    // MARK: Laden, Speichern, Löschen

    private func laden() {
        let karte = modell.playbook.first { $0.id == auswahl } ?? Setup(name: "")
        entwurf = karte
        basis = karte
        meldung = nil
    }

    private func speichern() {
        var karte = entwurf
        karte.name = karte.name.trimmingCharacters(in: .whitespacesAndNewlines)
        karte.kriterien = karte.kriterien
            .map { Kriterium(id: $0.id, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
        let felder: [WritableKeyPath<Setup, String?>] = [\.stopRegel, \.zielRegel, \.marktumfeld, \.notiz]
        for feld in felder {
            let wert = karte[keyPath: feld]?.trimmingCharacters(in: .whitespacesAndNewlines)
            karte[keyPath: feld] = wert.flatMap { $0.isEmpty ? nil : $0 }
        }
        // Wechsel des Status zählt ab heute (R5: Wechsel mit Datum); eine neue Karte beginnt heute.
        if auswahl == nil || karte.status != basis.status { karte.statusSeit = Date() }
        do {
            let gespeichert = try modell.speichereSetup(karte)
            entwurf = gespeichert
            basis = gespeichert
            if auswahl != gespeichert.id {
                auswahl = gespeichert.id
            }
            meldung = ton.text("Gespeichert. Die Kriterien stehen jetzt im Inspektor der Trade-Liste.",
                               henry: "Festgehalten. Die Kriterien stehen jetzt im Inspektor der Trade-Liste.")
            meldungIstFehler = false
        } catch {
            meldung = Regelfehler.text(error)
            meldungIstFehler = true
        }
    }

    private func loeschen() {
        do {
            try modell.loescheSetup(basis)
            auswahl = nil
            laden()
        } catch {
            meldung = Regelfehler.text(error)
            meldungIstFehler = true
        }
    }
}

/// Texte zum Setup-Status, in Einstellungen und Inspektor gleich.
enum Setupformat {
    static func status(_ status: Setup.Status) -> String {
        switch status {
        case .test: String(localized: "Test")
        case .aktiv: String(localized: "Aktiv")
        case .pausiert: String(localized: "Pausiert")
        }
    }
}
