#!/bin/bash
# Verpackt Henry für Testerinnen und Tester: die App im Release-Modus als DMG und ZIP, dazu den
# Connector als .mcpb für Claude Desktop. Läuft nur auf dem Mac (Xcode 27, XcodeGen, Swift).
# Ergebnis in build/verteilung/. Dasselbe Skript nutzt .github/workflows/release.yml.
#
# Signierung und Notarisierung steuern Umgebungsvariablen; Namen, Team-ID und Schlüssel stehen
# nie im Repository (Doc 51):
#   HENRY_SIGNIERUNG      Identität „Developer ID Application: …“ (Name oder SHA-1, siehe
#                         `security find-identity -v -p codesigning`). Leer: ad-hoc signiert,
#                         dann muss die Testerin die App einmal in den Systemeinstellungen freigeben.
#   HENRY_NOTAR_PROFIL    Profil aus `xcrun notarytool store-credentials`. Leer: keine Notarisierung.
#   HENRY_NOTAR_KEYCHAIN  Schlüsselbund mit dem Profil, nur wenn nicht der Anmelde-Schlüsselbund (CI).
#   HENRY_VERSION         Versionsnummer der App (MARKETING_VERSION), sonst die aus project.yml.
#   HENRY_BUILDNUMMER     Build-Nummer (CURRENT_PROJECT_VERSION), sonst die aus project.yml.
#
# Aufruf: scripts/app_verpacken.sh
# Beispiel signiert: HENRY_SIGNIERUNG="Developer ID Application" HENRY_NOTAR_PROFIL=henry-notar scripts/app_verpacken.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ZIEL=build/verteilung
ABLEITUNG=build/release-derived
IDENT="${HENRY_SIGNIERUNG:-}"
PROFIL="${HENRY_NOTAR_PROFIL:-}"
ENTITLEMENTS=App/TradingBuddy-macOS.entitlements

if [ "$(uname)" != "Darwin" ]; then echo "Läuft nur auf dem Mac."; exit 1; fi
command -v xcodegen >/dev/null || { echo "XcodeGen fehlt: brew install xcodegen"; exit 1; }
if [ -n "$PROFIL" ] && [ -z "$IDENT" ]; then echo "Notarisierung braucht eine Developer-ID-Signierung (HENRY_SIGNIERUNG)."; exit 1; fi

if [ -n "$IDENT" ]; then
    echo "Signierung: Developer ID ($IDENT)"
    SIGNATUR=(--force --options runtime --timestamp --sign "$IDENT")
else
    echo "Signierung: ad-hoc, ohne Developer ID. Tester müssen die App einmal unter Systemeinstellungen › Datenschutz & Sicherheit freigeben."
    SIGNATUR=(--force --options runtime --sign -)
fi
[ -n "$PROFIL" ] && echo "Notarisierung: Profil $PROFIL" || echo "Notarisierung: aus (HENRY_NOTAR_PROFIL leer)"

# Reicht eine Datei bei Apple ein und bricht ab, wenn Apple sie nicht annimmt.
notarisieren() {
    local datei="$1" antwort status kennung
    antwort="$ZIEL/notar-$(basename "$1").json"
    local schluessel=(--keychain-profile "$PROFIL")
    [ -n "${HENRY_NOTAR_KEYCHAIN:-}" ] && schluessel+=(--keychain "$HENRY_NOTAR_KEYCHAIN")
    echo "Notarisierung von $(basename "$datei") läuft, das dauert meist einige Minuten."
    xcrun notarytool submit "$datei" "${schluessel[@]}" --wait --output-format json > "$antwort" || true
    status=$(plutil -extract status raw -o - "$antwort" 2>/dev/null || echo "unbekannt")
    kennung=$(plutil -extract id raw -o - "$antwort" 2>/dev/null || echo "")
    echo "Notarisierung $(basename "$datei"): $status"
    if [ "$status" != "Accepted" ]; then
        cat "$antwort"
        [ -n "$kennung" ] && xcrun notarytool log "$kennung" "${schluessel[@]}" || true
        exit 1
    fi
}

rm -rf "$ZIEL" "$ABLEITUNG"
mkdir -p "$ZIEL"

# 1. App bauen, ohne Signierung durch Xcode; signiert wird unten einheitlich.
xcodegen generate
BAU=(-project TradingBuddy.xcodeproj -scheme TradingBuddy -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$ABLEITUNG" CODE_SIGNING_ALLOWED=NO)
[ -n "${HENRY_VERSION:-}" ] && BAU+=("MARKETING_VERSION=$HENRY_VERSION")
[ -n "${HENRY_BUILDNUMMER:-}" ] && BAU+=("CURRENT_PROJECT_VERSION=$HENRY_BUILDNUMMER")
xcodebuild "${BAU[@]}" build

GEBAUT="$(find "$ABLEITUNG/Build/Products/Release" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$GEBAUT" ] || { echo "Keine App unter $ABLEITUNG/Build/Products/Release gefunden."; exit 1; }
# Für Tester heißt das Paket wie die App; Bundle-ID und Datenordner bleiben „Trading Buddy“.
APP="$ZIEL/Henry.app"
ditto "$GEBAUT" "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
echo "Henry $VERSION ($BUILD)"

# 2. Signieren: erst eingebettete Teile, dann die App mit den Berechtigungen (Sandbox, Netz, Ordnerzugriff).
while IFS= read -r -d '' teil; do
    codesign "${SIGNATUR[@]}" "$teil"
done < <(find "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' -o -name '*.xpc' \) -print0 2>/dev/null)
codesign "${SIGNATUR[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.security.app-sandbox" || { echo "Sandbox-Berechtigung fehlt in der Signatur."; exit 1; }

# 3. App notarisieren und das Ticket anheften, damit sie auch ohne Netz beim ersten Start geprüft ist.
if [ -n "$PROFIL" ]; then
    ditto -c -k --keepParent "$APP" "$ZIEL/notar-app.zip"
    notarisieren "$ZIEL/notar-app.zip"
    rm "$ZIEL/notar-app.zip"
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi

# 4. ZIP und DMG (mit Verknüpfung zum Programme-Ordner zum Hineinziehen).
ditto -c -k --keepParent "$APP" "$ZIEL/Henry-$VERSION.zip"
BUEHNE="$ZIEL/dmg"
mkdir -p "$BUEHNE"
ditto "$APP" "$BUEHNE/Henry.app"
ln -s /Applications "$BUEHNE/Programme"
hdiutil create -volname "Henry $VERSION" -srcfolder "$BUEHNE" -ov -format UDZO "$ZIEL/Henry-$VERSION.dmg"
rm -rf "$BUEHNE"
if [ -n "$IDENT" ]; then
    codesign --force --timestamp --sign "$IDENT" "$ZIEL/Henry-$VERSION.dmg"
fi
if [ -n "$PROFIL" ]; then
    notarisieren "$ZIEL/Henry-$VERSION.dmg"
    xcrun stapler staple "$ZIEL/Henry-$VERSION.dmg"
fi

# 5. Connector wie scripts/connector_bauen.sh, aber mit derselben Signierung wie die App.
PAKET=Packages/TradingConnector
swift build -c release --package-path "$PAKET"
SERVER="$(swift build -c release --package-path "$PAKET" --show-bin-path)/trading-buddy-mcp"
CVERSION=$(plutil -extract version raw -o - Connector/manifest.json)
MCPB="$ZIEL/mcpb"
mkdir -p "$MCPB/server"
cp "$SERVER" "$MCPB/server/"
cp Connector/manifest.json "$MCPB/manifest.json"
codesign "${SIGNATUR[@]}" "$MCPB/server/trading-buddy-mcp"
codesign --verify --strict "$MCPB/server/trading-buddy-mcp"
if [ -n "$PROFIL" ]; then
    # Ein einzelnes Programm lässt sich nicht heften; Gatekeeper fragt das Ticket bei Apple ab.
    ditto -c -k "$MCPB/server/trading-buddy-mcp" "$ZIEL/notar-connector.zip"
    notarisieren "$ZIEL/notar-connector.zip"
    rm "$ZIEL/notar-connector.zip"
fi
(cd "$MCPB" && zip -qr "../Henry-Connector-$CVERSION.mcpb" .)
rm -rf "$MCPB"

# 6. Prüfsummen, damit Tester sehen können, dass die Datei vollständig angekommen ist.
(cd "$ZIEL" && shasum -a 256 Henry-*.dmg Henry-*.zip Henry-Connector-*.mcpb > SHA256SUMS.txt)
rm -f "$ZIEL"/notar-*.json

echo "Fertig in $ZIEL:"
ls -l "$ZIEL"
if [ -z "$IDENT" ]; then echo "Hinweis: ad-hoc signiert, nicht notarisiert. Für Tester gilt Doc 51, Abschnitt Gatekeeper."; fi
