#!/bin/bash
# Ersetzt Tims private E-Mail-Adresse in Autor und Committer aller Commits von An0nTB/trading-buddy
# durch seine GitHub-noreply-Adresse (Tim 07.10.2026 22:28 UTC: „meine adresse muss raus“).
# Läuft auf Tims Mac. Voraussetzung: git-filter-repo (brew install git-filter-repo); für --push ist auf
# GitHub kurz „Allow force pushes“ an und „Do not allow bypassing“ aus (danach beides zurück).
# Die alte Adresse wird beim Start abgefragt und steht in keiner Datei.
# Aufruf: bash adresse_ersetzen.sh          (nur umschreiben und prüfen)
#         bash adresse_ersetzen.sh --push   (danach überschreiben)
set -euo pipefail

URL=https://github.com/An0nTB/trading-buddy.git
NEU="335100243+An0nTB@users.noreply.github.com"   # öffentliche noreply-Adresse des Kontos An0nTB
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
command -v git-filter-repo >/dev/null || { echo "git-filter-repo fehlt: brew install git-filter-repo"; exit 1; }

read -r -p "Alte Adresse, die raus soll: " ALT
[ -n "$ALT" ] || { echo "ABBRUCH: keine Adresse"; exit 1; }

cd "$W"
GIT_LFS_SKIP_SMUDGE=1 git clone -q --mirror "$URL" alt.git
cp -a alt.git neu.git
VORHER=$(git -C alt.git log --all --format='%ae%n%ce' | grep -ciF "$ALT" || true)
echo "Vorkommen vorher: $VORHER"

printf '<%s> <%s>\n' "$NEU" "$ALT" > mailmap.txt
cd neu.git
git filter-repo --force --mailmap ../mailmap.txt

# Prüfen: Inhalt von main gleich, gleiche Zahl Branches, Adresse nirgends mehr in Commits.
A=$(git -C ../alt.git rev-parse 'refs/heads/main^{tree}'); N=$(git rev-parse 'refs/heads/main^{tree}')
[ "$A" = "$N" ] || { echo "ABBRUCH: Inhalt von main weicht ab"; exit 1; }
BA=$(git -C ../alt.git for-each-ref refs/heads | wc -l | tr -d ' '); BN=$(git for-each-ref refs/heads | wc -l | tr -d ' ')
[ "$BA" = "$BN" ] || { echo "ABBRUCH: Branches $BA vorher, $BN nachher"; exit 1; }
REST=$(git log --all --format='%ae%n%ce%n%B' | grep -ciF "$ALT" || true)
[ "$REST" = "0" ] || { echo "ABBRUCH: Adresse noch $REST-mal da"; exit 1; }
echo "Geprüft: main-Inhalt gleich ($N), $BN Branches, Adresse in 0 Commits (vorher $VORHER)."

if [ "${1:-}" = "--push" ]; then
  # Fernstand darf sich seit dem Klonen nicht geändert haben.
  git ls-remote --heads "$URL" | sort > ../jetzt.txt
  git -C ../alt.git for-each-ref --format='%(objectname)%09%(refname)' refs/heads | sort > ../vorher.txt
  diff -q ../jetzt.txt ../vorher.txt >/dev/null || { echo "ABBRUCH: GitHub hat sich seit dem Klonen geändert, neu starten"; exit 1; }
  git remote add ziel "$URL"
  git push --force ziel 'refs/heads/*:refs/heads/*'
  echo "Gepusht. Jetzt auf GitHub „Allow force pushes“ aus und „Do not allow bypassing“ wieder an."
else
  echo "Nur geprüft. Zum Überschreiben: bash adresse_ersetzen.sh --push"
fi
