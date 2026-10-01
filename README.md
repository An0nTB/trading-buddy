# Trading Buddy

Mac- und iOS-App für Trader: Trading-Journal mit Broker-Import, Kennzahlen und Auswertung über Claude.

Planung und Entscheidungen liegen im Projektordner des Claude-Projekts „Trading-Buddy“ (später in der Wissensbasis).

## Aufbau

| Ordner | Inhalt |
|---|---|
| `Packages/TradingCore` | Rechenkern: Datenmodell, Broker-Importer, Kennzahlen. Reines Swift-Paket ohne Oberfläche. |
| `App/` | Folgt: Xcode-Projekt für macOS, iPhone und iPad (wird auf dem Mac angelegt). |

## Tests lokal ausführen

```
cd Packages/TradingCore && swift test
```

Jeder Pull Request startet dieselben Tests automatisch auf macOS und Linux (GitHub Actions, `.github/workflows/ci.yml`).
