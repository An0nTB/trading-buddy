#!/usr/bin/env python3
"""Englisch-Abdeckung der App prüfen (Paket 6, Doc 43).

Liest die XLIFF-Datei, die `xcodebuild -exportLocalizations -exportLanguage en` erzeugt, und zählt
je Datei die Texte ohne englische Übersetzung. Mit `--liste` stehen die fehlenden Schlüssel als
JSON-Zeilen zwischen den Markern im Log (Grundlage für die Übersetzung, ohne Xcode in der Cloud).
Mit `--streng` endet das Skript mit Code 1, sobald ein Text fehlt.

Aufruf: python3 scripts/lokalisierung_pruefen.py <Ordner mit .xcloc oder .xliff> [--liste] [--streng]
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


def einheiten(xliff: Path):
    baum = ET.parse(xliff)
    for datei in baum.getroot().findall("x:file", NS):
        name = datei.get("original", "")
        for einheit in datei.iter("{urn:oasis:names:tc:xliff:document:1.2}trans-unit"):
            quelle = einheit.find("x:source", NS)
            ziel = einheit.find("x:target", NS)
            notiz = einheit.find("x:note", NS)
            yield {
                "datei": name,
                "id": einheit.get("id", ""),
                "quelle": quelle.text if quelle is not None else "",
                "ziel": ziel.text if ziel is not None else None,
                "zustand": ziel.get("state") if ziel is not None else None,
                "notiz": notiz.text if notiz is not None else None,
            }


def main() -> int:
    argumente = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not argumente:
        print(__doc__)
        return 2
    ordner = Path(argumente[0])
    dateien = sorted(ordner.rglob("en.xliff"))
    if not dateien:
        print(f"Keine en.xliff unter {ordner}")
        return 2
    fehlend = []
    gesamt = 0
    for xliff in dateien:
        for e in einheiten(xliff):
            gesamt += 1
            if not e["ziel"] or e["zustand"] in ("new", "needs-translation"):
                fehlend.append(e)
    je_datei = {}
    for e in fehlend:
        je_datei[e["datei"]] = je_datei.get(e["datei"], 0) + 1
    print(f"Texte gesamt: {gesamt}, ohne Englisch: {len(fehlend)}")
    for name, zahl in sorted(je_datei.items()):
        print(f"  {name}: {zahl}")
    if "--liste" in sys.argv:
        print("=== FEHLEND ANFANG ===")
        for e in fehlend:
            print(json.dumps({"d": e["datei"], "k": e["id"], "q": e["quelle"], "n": e["notiz"]}, ensure_ascii=False))
        print("=== FEHLEND ENDE ===")
    if "--streng" in sys.argv and fehlend:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
