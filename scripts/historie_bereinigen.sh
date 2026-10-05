#!/bin/bash
# Entfernt die alten MT4-Originalauszüge (gbe-2025-*.html) aus der gesamten Git-Historie von
# An0nTB/trading-buddy und ersetzt ihre Ticketnummern in alten Fassungen der Testdateien.
# Läuft auf Tims Mac (05.10.2026). Voraussetzung: git-filter-repo (brew install git-filter-repo)
# und auf GitHub ist „Allow force pushes“ für main eingeschaltet.
# Aufruf: bash historie_bereinigen.sh          (nur vorbereiten und prüfen)
#         bash historie_bereinigen.sh --push   (danach überschreiben)
set -euo pipefail

URL=https://github.com/An0nTB/trading-buddy.git
ORDNER=Packages/TradingCore/Tests/TradingCoreTests/Fixtures/MT4
ERSTER=2e9a8b2   # Commit, der die Auszüge am 01.10.2026 hinzugefügt hat
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
command -v git-filter-repo >/dev/null || { echo "git-filter-repo fehlt: brew install git-filter-repo"; exit 1; }

cd "$W"
GIT_LFS_SKIP_SMUDGE=1 git clone -q --mirror "$URL" alt.git
cp -a alt.git neu.git

# Ticketnummern (7+ Ziffern) aus den Original-Auszügen sammeln; die Liste bleibt im Temp-Ordner.
for f in $(git -C alt.git ls-tree --name-only "$ERSTER" "$ORDNER/" | grep 'gbe-2025-'); do
  git -C alt.git show "$ERSTER:$f"
done | grep -oE '[0-9]{7,}' | sort -u > nummern.txt
echo "Gefundene Nummern: $(wc -l < nummern.txt)"
awk '{printf "%s==>%08d\n", $1, 90000000+NR-1}' nummern.txt > ersetzen.txt

cd neu.git
git filter-repo --force --invert-paths --path-glob "$ORDNER/gbe-2025-*" --replace-text ../ersetzen.txt

# Prüfen: Inhalt von main gleich, keine Auszüge, keine Nummern mehr.
A=$(git -C ../alt.git rev-parse 'refs/heads/main^{tree}'); N=$(git rev-parse 'refs/heads/main^{tree}')
[ "$A" = "$N" ] || { echo "ABBRUCH: Inhalt von main weicht ab"; exit 1; }
[ "$(git rev-list --all --objects | grep -c 'gbe-2025' || true)" = "0" ] || { echo "ABBRUCH: Auszüge noch da"; exit 1; }
REST=$(git rev-list --all --objects | awk 'NF==2{print $1}' | sort -u | git cat-file --batch 2>/dev/null \
  | grep -aoE '[0-9]{7,}' | sort -u | comm -12 - ../nummern.txt | wc -l | tr -d ' ')
[ "$REST" = "0" ] || { echo "ABBRUCH: $REST Nummern noch da"; exit 1; }
echo "Geprüft: main-Inhalt gleich ($N), keine Auszüge, keine Nummern. Branches: $(git for-each-ref refs/heads | wc -l | tr -d ' ')"

if [ "${1:-}" = "--push" ]; then
  # Fernstand darf sich seit dem Klonen nicht geändert haben.
  git ls-remote --heads "$URL" | sort > ../jetzt.txt
  git -C ../alt.git for-each-ref --format='%(objectname)%09%(refname)' refs/heads | sort > ../vorher.txt
  diff -q ../jetzt.txt ../vorher.txt >/dev/null || { echo "ABBRUCH: GitHub hat sich seit dem Klonen geändert, neu starten"; exit 1; }
  git remote add ziel "$URL"
  git push --force ziel 'refs/heads/*:refs/heads/*'
  echo "Gepusht. Jetzt „Allow force pushes“ wieder ausschalten."
else
  echo "Nur geprüft. Zum Überschreiben: bash historie_bereinigen.sh --push"
fi
