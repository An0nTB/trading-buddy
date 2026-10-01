#!/bin/bash
# Baut den MCP-Server, signiert ihn mit deinem Personal Team und verpackt ihn
# als build/TradingBuddy.mcpb für Claude Desktop. Läuft nur auf dem Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Config/Local.xcconfig 2>/dev/null || true)
if [ -z "$TEAM" ]; then echo "Team-ID fehlt in Config/Local.xcconfig (siehe README)."; exit 1; fi

IDENTITAET=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -z "$IDENTITAET" ]; then echo "Kein Apple-Development-Zertifikat gefunden. Die App einmal in Xcode starten."; exit 1; fi

PAKET=Packages/TradingConnector
swift build -c release --package-path "$PAKET"
BIN="$(swift build -c release --package-path "$PAKET" --show-bin-path)/trading-buddy-mcp"

ZIEL=build/mcpb
rm -rf "$ZIEL" build/TradingBuddy.mcpb
mkdir -p "$ZIEL/server"
cp "$BIN" "$ZIEL/server/"
sed "s/__TEAM__/$TEAM/" Connector/trading-buddy-mcp.entitlements > build/trading-buddy-mcp.entitlements
sed "s/__TEAM__/$TEAM/" Connector/manifest.json > "$ZIEL/manifest.json"

codesign --force --options runtime --sign "$IDENTITAET" --entitlements build/trading-buddy-mcp.entitlements "$ZIEL/server/trading-buddy-mcp"
(cd "$ZIEL" && zip -qr ../TradingBuddy.mcpb .)

echo "Signatur:"
codesign -dv --entitlements - "$ZIEL/server/trading-buddy-mcp" 2>&1 | grep -E "TeamIdentifier|journal" || true
echo "Fertig: build/TradingBuddy.mcpb"
