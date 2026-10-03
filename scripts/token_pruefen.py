#!/usr/bin/env python3
"""Prüft die Design-Token der App gegen Design/tokens.json (Doc 10, Abschnitt 9).

1. Jede Farbwelt in App/Sources/Design/Farbwelt.swift trägt genau die Werte aus tokens.json
   (Akzent, Gewinn, Verlust, Warnung, je dunkel und hell), ebenso die Neutralfarben und die getönten Flächen.
2. In den Ansichten (App/Sources/Ansichten, App/Sources/*.swift) steht kein Hex-Farbwert.

Aufruf im Repository-Ordner: python3 scripts/token_pruefen.py
Ende mit Fehlercode 1, wenn etwas nicht stimmt.
"""
import json
import re
import sys
from pathlib import Path

WURZEL = Path(__file__).resolve().parent.parent
TOKENS = WURZEL / "Design" / "tokens.json"
FARBWELT = WURZEL / "App" / "Sources" / "Design" / "Farbwelt.swift"
ANSICHTEN = [WURZEL / "App" / "Sources" / "Ansichten", WURZEL / "App" / "Sources"]

HEX_SWIFT = re.compile(r"0x([0-9a-fA-F]{6})")
HEX_CSS = re.compile(r"#([0-9a-fA-F]{6})\b")


def hex_json(wert: str) -> str:
    return wert.lstrip("#").lower()


def pruefe_farbwelten(tokens: dict, quelle: str) -> list[str]:
    fehler = []
    for name, welt in tokens["farbwelten"].items():
        treffer = re.search(r"case \." + name + r":\s*\[(.*?)\]\s*$", quelle, re.MULTILINE)
        if not treffer:
            fehler.append(f"Farbwelt {name}: keine Zeile `case .{name}: [...]` in Farbwelt.swift")
            continue
        paare = re.findall(r"\(0x([0-9a-fA-F]{6}),\s*0x([0-9a-fA-F]{6})\)", treffer.group(1))
        soll = [(hex_json(welt["dunkel"][k]), hex_json(welt["hell"][k])) for k in ("akzent", "gewinn", "verlust", "warnung")]
        ist = [(d.lower(), h.lower()) for d, h in paare]
        if ist != soll:
            fehler.append(f"Farbwelt {name}: Swift {ist} ≠ tokens.json {soll}")
    return fehler


FLAECHEN = ("grund", "flaeche", "flaeche2", "linie")


def paare_in(zeile: str) -> dict[str, tuple[str, str]]:
    """Liest `name: (0xDUNKEL, 0xHELL)` aus einer Flaechen(...)-Zeile."""
    return {name: (d.lower(), h.lower())
            for name, d, h in re.findall(r"(\w+):\s*\(0x([0-9a-fA-F]{6}),\s*0x([0-9a-fA-F]{6})\)", zeile)}


def pruefe_neutral(tokens: dict, quelle: str) -> list[str]:
    fehler = []
    neutral_zeile = next((z for z in quelle.splitlines() if "static let neutral = Flaechen(" in z), "")
    neutral = paare_in(neutral_zeile)
    for name in FLAECHEN + ("text", "textSchwach"):
        dunkel = hex_json(tokens["neutral"]["dunkel"][name])
        hell = hex_json(tokens["neutral"]["hell"][name])
        if name in FLAECHEN:
            ist = neutral.get(name)
            if ist is None:
                fehler.append(f"Neutralfarbe {name}: fehlt in `static let neutral = Flaechen(...)` in Farbwelt.swift")
            elif ist != (dunkel, hell):
                fehler.append(f"Neutralfarbe {name}: Swift {ist} ≠ tokens.json ({dunkel}, {hell})")
            continue
        muster = re.compile(name + r":\s*waehle\(\(0x([0-9a-fA-F]{6}),\s*0x([0-9a-fA-F]{6})\)\)")
        treffer = muster.search(quelle)
        if not treffer:
            fehler.append(f"Neutralfarbe {name}: keine Zeile `{name}: waehle((0x…, 0x…))` in Farbwelt.swift")
        elif (treffer.group(1).lower(), treffer.group(2).lower()) != (dunkel, hell):
            fehler.append(f"Neutralfarbe {name}: Swift ({treffer.group(1)}, {treffer.group(2)}) ≠ tokens.json ({dunkel}, {hell})")
    return fehler


def pruefe_getoent(tokens: dict, quelle: str) -> list[str]:
    """Getönte Flächen je Farbwelt: `case .name: Flaechen(grund: (0x…, 0x…), …)` gegen farbwelten.*.getoent."""
    fehler = []
    for name, welt in tokens["farbwelten"].items():
        zeile = next((z for z in quelle.splitlines() if re.search(r"case \." + name + r":\s*Flaechen\(", z)), "")
        if not zeile:
            fehler.append(f"Getönte Flächen {name}: keine Zeile `case .{name}: Flaechen(...)` in Farbwelt.swift")
            continue
        ist = paare_in(zeile)
        for flaeche in FLAECHEN:
            soll = (hex_json(welt["getoent"]["dunkel"][flaeche]), hex_json(welt["getoent"]["hell"][flaeche]))
            if ist.get(flaeche) != soll:
                fehler.append(f"Getönte Flächen {name}.{flaeche}: Swift {ist.get(flaeche)} ≠ tokens.json {soll}")
    return fehler


def pruefe_ansichten() -> list[str]:
    fehler = []
    gesehen = set()
    for ordner in ANSICHTEN:
        for datei in sorted(ordner.glob("*.swift")):
            if datei in gesehen or datei.parent.name == "Design":
                continue
            gesehen.add(datei)
            for nummer, zeile in enumerate(datei.read_text(encoding="utf-8").splitlines(), 1):
                if HEX_SWIFT.search(zeile) or HEX_CSS.search(zeile) or "Color(red:" in zeile:
                    fehler.append(f"{datei.relative_to(WURZEL)}:{nummer}: Farbwert außerhalb der Token: {zeile.strip()}")
    return fehler


def main() -> int:
    tokens = json.loads(TOKENS.read_text(encoding="utf-8"))
    quelle = FARBWELT.read_text(encoding="utf-8")
    fehler = (pruefe_farbwelten(tokens, quelle) + pruefe_neutral(tokens, quelle)
              + pruefe_getoent(tokens, quelle) + pruefe_ansichten())
    anzahl_welten = len(tokens["farbwelten"])
    if fehler:
        print("\n".join(fehler))
        print(f"FEHLER: {len(fehler)} Abweichungen")
        return 1
    print(f"ALLE OK: {anzahl_welten} Farbwelten, 6 Neutralfarben und {anzahl_welten * 4} getönte Flächen "
          f"stimmen mit tokens.json überein, kein Hex-Wert in den Ansichten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
