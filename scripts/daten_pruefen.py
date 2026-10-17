#!/usr/bin/env python3
"""Keine echten Daten im öffentlichen Repo (Tim 17.10.2026, Lehre 05.10.2026 MT4-Auszüge).

Prüft alle eingecheckten Dateien:
1. Dateien, wie Broker sie liefern (CSV, Excel, HTML, PDF …), liegen nur in einem Testordner
   `Packages/<Paket>/Tests/…/Fixtures/`. Echte Exporte gehören in einen Ordner außerhalb des Repos.
2. In diesen Testdateien stehen keine echten E-Mail-Adressen (nur Domains wie .example) und keine IBAN.
3. Nirgends stehen Kennungen von Claude-Projekten (chan_…, claude.ai/project/<ID>); sie gehören in die
   Einstellungen des Nutzers, nie in den Code. Erfundene Kennungen für Tests tragen TEST, BEISPIEL,
   XXXX oder 0000 im Namen (etwa chan_01TESTPROJEKT00000000000).
Läuft im Pflicht-Check „Design-Token“ und lokal mit `python3 scripts/daten_pruefen.py`.
"""
import re
import subprocess
import sys
import zipfile

BROKERTYPEN = (".csv", ".tsv", ".xlsx", ".xlsm", ".xls", ".ods", ".numbers", ".htm", ".html",
               ".ofx", ".qif", ".pdf", ".sqlite", ".sqlite3", ".db")
TESTORDNER = re.compile(r"^Packages/[^/]+/Tests/(?:.+/)?Fixtures/")
MAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})")
ERLAUBTE_DOMAINS = re.compile(r"(?:^|\.)(?:example|invalid|test|localhost|example\.(?:com|org|net))$", re.I)
IBAN = re.compile(r"\b[A-Z]{2}\d{2}(?: ?[0-9A-Z]{4}){4,7}\b")
PROJEKT = re.compile(r"chan_[A-Za-z0-9]{16,}|claude\.ai/(?:code/)?project/(?:chan_)?[0-9A-Za-z-]{20,}")
ERFUNDEN = re.compile(r"test|beispiel|example|xxxx|0000", re.I)
DIESE_DATEI = "scripts/daten_pruefen.py"


def dateien():
    aus = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout
    return [d for d in aus.decode("utf-8").split("\0") if d]


def text(pfad):
    if pfad.lower().endswith((".xlsx", ".xlsm")):
        try:
            with zipfile.ZipFile(pfad) as z:
                return " ".join(z.read(n).decode("utf-8", "ignore") for n in z.namelist() if n.endswith(".xml"))
        except (zipfile.BadZipFile, OSError):
            return ""
    try:
        with open(pfad, "rb") as f:
            roh = f.read()
    except OSError:
        return ""
    if b"\0" in roh[:8000]:
        return ""
    return roh.decode("utf-8", "ignore")


def pruefe(liste):
    fehler = []
    for pfad in liste:
        klein = pfad.lower()
        imTestordner = bool(TESTORDNER.match(pfad))
        if klein.endswith(BROKERTYPEN) and not imTestordner:
            fehler.append(f"{pfad}: Datei wie aus einem Broker-Export, aber nicht unter Packages/<Paket>/Tests/…/Fixtures/")
        inhalt = text(pfad)
        if imTestordner:
            for domain in sorted({m.group(1) for m in MAIL.finditer(inhalt)}):
                if not ERLAUBTE_DOMAINS.search(domain):
                    fehler.append(f"{pfad}: E-Mail-Adresse mit echter Domain ({domain}); bitte durch …@beispiel.example ersetzen")
            if IBAN.search(inhalt):
                fehler.append(f"{pfad}: sieht nach einer IBAN aus")
        if pfad != DIESE_DATEI and any(not ERFUNDEN.search(m.group(0)) for m in PROJEKT.finditer(inhalt)):
            fehler.append(f"{pfad}: enthält die Kennung eines Claude-Projekts; die gehört in die Einstellungen, nicht ins Repo")
    return fehler


def main():
    fehler = pruefe(dateien())
    for f in fehler:
        print(f)
    if fehler:
        print(f"{len(fehler)} Fund(e). Echte Exporte und Links gehören nicht ins öffentliche Repo.")
        return 1
    print("Keine echten Daten gefunden.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
