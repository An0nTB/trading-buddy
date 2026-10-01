# Trading Buddy

Mac- und iOS-App für Trader: Trading-Journal mit Broker-Import, Kennzahlen und Auswertung über Claude.

Planung und Entscheidungen liegen im Projektordner des Claude-Projekts „Trading-Buddy“ (später in der Wissensbasis).

## Aufbau

| Ordner | Inhalt |
|---|---|
| `Packages/TradingCore` | Rechenkern: Datenmodell, Broker-Importer, Kennzahlen. Reines Swift-Paket ohne Oberfläche. |
| `App/` | App für macOS, iPhone und iPad (SwiftUI), Texte Deutsch und Englisch. |
| `project.yml` | Bauplan für das Xcode-Projekt. Daraus erzeugt XcodeGen `TradingBuddy.xcodeproj`. |

## App auf dem Mac öffnen

Einmalig: `brew install xcodegen`

Dann im Repository-Ordner:

```
xcodegen generate
open TradingBuddy.xcodeproj
```

In Xcode oben das Ziel „My Mac“ wählen und auf Start drücken. Zum Signieren unter Target → Signing & Capabilities dein Personal Team auswählen.

## Tests lokal ausführen

```
cd Packages/TradingCore && swift test
```

Jeder Pull Request startet dieselben Tests automatisch auf macOS und Linux und baut die App für macOS und den iOS-Simulator (GitHub Actions, `.github/workflows/ci.yml`).
