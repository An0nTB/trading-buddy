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
#   HENRY_VERSION         Versionsnummer der App (MARKETING_VERSION), etwa 0.2.0. Pflicht, sobald signiert
#                         wird, und nie kleiner als das höchste Tag v*: Tester ersetzen ihre App nur
#                         durch eine neuere, und der Update-Hinweis vergleicht nur diese Nummer.
#                         Ohne Signierung (Probebau) gilt die aus project.yml.
#   HENRY_BUILDNUMMER     Build-Nummer (CURRENT_PROJECT_VERSION). Leer: Zahl der Commits auf HEAD
#                         (git rev-list --count), die mit jedem Commit auf main steigt.
#
# Aufruf: scripts/app_verpacken.sh
# Beispiel signiert: HENRY_VERSION=0.2.0 HENRY_SIGNIERUNG="Developer ID Application" HENRY_NOTAR_PROFIL=henry-notar scripts/app_verpacken.sh
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

# Version und Build-Nummer müssen bei jeder Fassung für Tester steigen (Doc 51, Abschnitt 6).
VORGABE="${HENRY_VERSION:-}"
if [ -n "$IDENT" ] && [ -z "$VORGABE" ]; then echo "Signierter Bau ohne HENRY_VERSION. Bitte eine neue Versionsnummer setzen, etwa HENRY_VERSION=0.2.0."; exit 1; fi
if [ -n "$VORGABE" ]; then
    [[ "$VORGABE" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "HENRY_VERSION ${VORGABE} ist keine Nummer wie 0.2.0."; exit 1; }
    # Als Zahl mit drei Stellen je Teil vergleichen (0.10.0 > 0.9.0); sort -V gibt es nicht überall.
    zahl() { local a b c; IFS=. read -r a b c <<< "$1"; echo $(( 10#$a * 1000000 + 10#${b:-0} * 1000 + 10#${c:-0} )); }
    HOECHSTE=""
    while read -r tag; do
        [[ "$tag" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || continue
        if [ -z "$HOECHSTE" ] || [ "$(zahl "$tag")" -gt "$(zahl "$HOECHSTE")" ]; then HOECHSTE="$tag"; fi
    done < <(git tag -l 'v*' | sed 's/^v//')
    if [ -n "$HOECHSTE" ] && [ "$(zahl "$VORGABE")" -lt "$(zahl "$HOECHSTE")" ]; then
        echo "HENRY_VERSION ${VORGABE} ist kleiner als das höchste Tag v${HOECHSTE}. Tester können keine ältere Version über eine neuere installieren."
        exit 1
    fi
fi
BUILDNUMMER="${HENRY_BUILDNUMMER:-}"
if [ -z "$BUILDNUMMER" ]; then
    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then echo "Flacher Klon: Die Build-Nummer aus der Commit-Zahl wäre falsch. Bitte mit voller Historie auschecken oder HENRY_BUILDNUMMER setzen."; exit 1; fi
    BUILDNUMMER=$(git rev-list --count HEAD)
fi
[[ "$BUILDNUMMER" =~ ^[0-9]+$ ]] || { echo "Build-Nummer ${BUILDNUMMER} ist keine ganze Zahl."; exit 1; }

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
[ -n "$VORGABE" ] && BAU+=("MARKETING_VERSION=$VORGABE")
BAU+=("CURRENT_PROJECT_VERSION=$BUILDNUMMER")
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
# Universal (Apple Silicon und Intel) wie connector_bauen.sh, damit die Erweiterung auf jedem Tester-Mac startet.
ARCH=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH[@]}" --package-path "$PAKET"
SERVER="$(swift build -c release "${ARCH[@]}" --package-path "$PAKET" --show-bin-path)/trading-buddy-mcp"
ARCHS=$(lipo -archs "$SERVER")
case "$ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) echo "Connector-Architekturen: $ARCHS" ;;
    *) echo "Connector ist nicht universal ($ARCHS)."; exit 1 ;;
esac
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
