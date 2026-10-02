# TradingRates

EZB-Referenzkurse für die Steuer-Orientierung: Krypto-Trades in USD oder USDT erscheinen damit in Euro
(Doc 02 Entscheidung 47, Doc 22, Doc 34). Das Paket lädt nur und liefert `Referenzkurse` aus TradingCore;
umgerechnet wird im Kern.

```swift
let ezb = EZBKurse()                       // Datei: Application Support/Trading Buddy/ezb-referenzkurse.json
var stand = ezb.zwischenspeicher()         // sofort, ohne Netz
stand = await ezb.laden()                  // lädt nur, wenn nötig; ohne Netz gilt die Datei
let summen = Steuerorientierung.toepfe(trades, kontowaehrung: "USD", jahr: 2026, kurse: stand.kurse)
// stand.quelle (.netz, .zwischenspeicher, .keine), stand.letzterTag, stand.fehler
// EZBKurse.istNaeherung("USDT") == true: Beträge als Näherung kennzeichnen
```

Quelle: `https://www.ecb.europa.eu/stats/eurofxref/` mit `eurofxref-daily.xml` (letzter Arbeitstag),
`eurofxref-hist-90d.xml` (90 Tage) und `eurofxref-hist.xml` (seit 1999). Einheit: Fremdwährung je 1 Euro.
Kein Schlüssel. Abruf höchstens alle sechs Stunden, und nur, wenn der Kurs von heute fehlt.
