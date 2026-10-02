# TradingQuotes

Kurse für offene Trades (Entscheidung 1, Option 1 gratis; R1). Ohne Oberfläche und ohne Abhängigkeiten;
die Kachel in der Übersicht baut die App. Der Buchgewinn je Position steht in TradingCore
(`OffeneBewertung`), dieses Paket liefert nur Kurse.

```swift
let beobachter = Kursbeobachter(quellen: [
    Kursquellen.kraken(),
    Kursquellen.coinbase(),
    Kursquellen.binance(),
    Kursquellen.alpaca(schluessel: schluesselbund)   // AlpacaSchluesselquelle der App
])
let zuordnungen = symbole.compactMap {
    if case .zuordnung(let z) = Kurszuordner.vorschlag(fuer: $0) { return z } else { return nil }
}
var stand = Kursstand()
for await ereignis in beobachter.beobachte(zuordnungen) {
    stand.uebernimm(ereignis)       // stand.kurse, stand.ohneQuelle, stand.verbindungen, stand.veraltet(jetzt:)
}
```

| Quelle | Markt | Takt | Schlüssel | Grenze |
|---|---|---|---|---|
| Kraken (`wss://ws.kraken.com/v2`) | Krypto | Echtzeit | nein | keine bekannt |
| Coinbase (`wss://advanced-trade-ws.coinbase.com`) | Krypto | Echtzeit | nein | keine bekannt |
| Binance (`wss://data-stream.binance.vision`) | Krypto | Echtzeit | nein | 1.024 Ströme, 24 h je Verbindung |
| Alpaca (`wss://stream.data.alpaca.markets/v2/iex`) | US-Aktien, nur IEX | Echtzeit | ja, eigener | 30 Symbole, 1 Verbindung |

CFDs und Devisen des Brokers (MetaTrader) bekommen keinen Vorschlag: Ein neutraler Kurs fehlt (R1).
Eine eigene Zuordnung auf einen Basiswert ist möglich und trägt den Hinweis `naeherung`.
Deutsche Kurse (15 Minuten verzögert) sind noch nicht angebunden; Kandidat und offene Punkte im Stand-Doc 20.

Die App braucht in der Sandbox `com.apple.security.network.client`. Der Alpaca-Schlüssel kommt aus dem
Schlüsselbund über `AlpacaSchluesselquelle`, nie aus Dateien.
