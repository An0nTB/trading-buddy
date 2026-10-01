#!/bin/bash
# Baut den MCP-Server, signiert ihn mit deinem Apple-Development-Zertifikat und
# verpackt ihn als build/TradingBuddy.mcpb für Claude Desktop. Läuft nur auf dem Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITAET=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -z "$IDENTITAET" ]; then echo "Kein Apple-Development-Zertifikat gefunden. Die App einmal in Xcode starten."; exit 1; fi

PAKET=Packages/TradingConnector
swift build -c release --package-path "$PAKET"
BIN="$(swift build -c release --package-path "$PAKET" --show-bin-path)/trading-buddy-mcp"

ZIEL=build/mcpb
rm -rf "$ZIEL" build/TradingBuddy.mcpb
mkdir -p "$ZIEL/server"
cp "$BIN" "$ZIEL/server/"
cp Connector/manifest.json "$ZIEL/manifest.json"

codesign --force --options runtime --sign "$IDENTITAET" "$ZIEL/server/trading-buddy-mcp"
(cd "$ZIEL" && zip -qr ../TradingBuddy.mcpb .)

echo "Signatur:"
codesign -dv "$ZIEL/server/trading-buddy-mcp" 2>&1 | grep -E "TeamIdentifier" || true
echo "Fertig: build/TradingBuddy.mcpb"
