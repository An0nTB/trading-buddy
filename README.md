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

In Xcode oben das Ziel „My Mac“ wählen und auf Start drücken.

Signieren, einmalig: `cp Config/Local.xcconfig.example Config/Local.xcconfig`, darin die eigene Team-ID eintragen, dann `xcodegen generate`. Die Team-ID steht in Xcode unter Target → Build Settings → „Development Team“, nachdem man dort einmal das Personal Team gewählt hat. `Local.xcconfig` wird nicht eingecheckt, so bleibt das Team auch nach jedem `xcodegen generate` gesetzt.

## Tests lokal ausführen

```
cd Packages/TradingCore && swift test
```

Jeder Pull Request startet dieselben Tests automatisch auf macOS und Linux und baut die App für macOS und den iOS-Simulator (GitHub Actions, `.github/workflows/ci.yml`).

## Connector für Claude Desktop (Experiment AP6)

Der lokale MCP-Server liegt in `Packages/TradingConnector`. Er liest die Daten der App aus einem Export-Ordner, den man in der App und in den Einstellungen der Erweiterung gleich wählt. Bauen und verpacken auf dem Mac:

```
scripts/connector_bauen.sh
```

Ergebnis ist `build/TradingBuddy.mcpb`. Installation in Claude Desktop: Settings → Extensions → Advanced settings → „Install Extension…“.
