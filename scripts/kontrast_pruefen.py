#!/usr/bin/env python3
"""Rechnet den WCAG-Kontrast (2.x, Erfolgskriterium 1.4.3) für die Paare, die die App wirklich zeichnet,
aus Design/tokens.json. Ende mit Fehlercode 1, wenn ein Paar unter 4,5:1 liegt (Doc 10, Doc 55 J22/J23).

Geprüfte Paare je Farbwelt, Hell und Dunkel, Flächen neutral und getönt:
- Text und schwacher Text auf Grund, Fläche, Fläche 2
- Akzent, Gewinn, Verlust, Warnung auf Fläche und Fläche 2 (Zahlen, Beschriftungen, Ampel)
- Text auf Kapselgrund: Farbe mit 18 % Deckkraft über Fläche und Fläche 2 (Kapsel, Farbkapsel, Statuskapsel)
- Text auf Akzent (Knöpfe)

Aufruf im Repository-Ordner: python3 scripts/kontrast_pruefen.py [--alle]  (--alle druckt jedes Paar)
"""
import json
import sys
from pathlib import Path

WURZEL = Path(__file__).resolve().parent.parent
TOKENS = WURZEL / "Design" / "tokens.json"
MINDESTENS = 4.5
KAPSEL_DECKKRAFT = 0.18


def rgb(wert: str) -> tuple[float, float, float]:
    h = wert.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def leuchtdichte(wert: str) -> float:
    def linear(c: float) -> float:
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (linear(c) for c in rgb(wert))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def kontrast(vorne: str, hinten: str) -> float:
    a, b = leuchtdichte(vorne), leuchtdichte(hinten)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def mischen(farbe: str, deckkraft: float, grund: str) -> str:
    """Farbe mit Deckkraft über Grund, wie SwiftUI `.opacity` sie zeichnet (sRGB, ohne Gamma-Korrektur)."""
    f, g = rgb(farbe), rgb(grund)
    return "#" + "".join(f"{round((fc * deckkraft + gc * (1 - deckkraft)) * 255):02x}" for fc, gc in zip(f, g))


def paare(tokens: dict):
    neutral = tokens["neutral"]
    for name, welt in tokens["farbwelten"].items():
        for modus in ("dunkel", "hell"):
            farben = welt[modus]
            text, schwach = neutral[modus]["text"], neutral[modus]["textSchwach"]
            flaechen = {"neutral": neutral[modus], "getönt": welt["getoent"][modus]}
            for art, fl in flaechen.items():
                ort = f"{welt['name']} {modus} {art}"
                for grund in ("grund", "flaeche", "flaeche2"):
                    yield ort, f"text auf {grund}", text, fl[grund]
                    yield ort, f"textSchwach auf {grund}", schwach, fl[grund]
                for farbe in ("akzent", "gewinn", "verlust", "warnung"):
                    if farbe not in farben:
                        continue
                    for grund in ("flaeche", "flaeche2"):
                        yield ort, f"{farbe} auf {grund}", farben[farbe], fl[grund]
                        kapsel = mischen(farben[farbe], KAPSEL_DECKKRAFT, fl[grund])
                        yield ort, f"text auf Kapsel {farbe} 18 % über {grund}", text, kapsel
                for grund in ("flaeche", "flaeche2"):
                    kapsel = mischen(schwach, KAPSEL_DECKKRAFT, fl[grund])
                    yield ort, f"text auf Kapsel textSchwach 18 % über {grund}", text, kapsel
            yield f"{welt['name']} {modus}", "textAufAkzent auf akzent", farben["textAufAkzent"], farben["akzent"]


def main() -> int:
    tokens = json.loads(TOKENS.read_text(encoding="utf-8"))
    alle = "--alle" in sys.argv
    fehler, anzahl, kleinstes = [], 0, (99.0, "")
    for ort, was, vorne, hinten in paare(tokens):
        wert = kontrast(vorne, hinten)
        anzahl += 1
        if wert < kleinstes[0]:
            kleinstes = (wert, f"{ort}: {was}")
        zeile = f"{wert:5.2f}:1  {ort}: {was} ({vorne} auf {hinten})"
        if wert < MINDESTENS:
            fehler.append(zeile)
        elif alle:
            print(zeile)
    if fehler:
        print("\n".join(fehler))
        print(f"FEHLER: {len(fehler)} von {anzahl} Paaren unter {MINDESTENS}:1")
        return 1
    print(f"ALLE OK: {anzahl} Paare mindestens {MINDESTENS}:1, kleinstes {kleinstes[0]:.2f}:1 ({kleinstes[1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
