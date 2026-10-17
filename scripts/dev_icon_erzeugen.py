#!/usr/bin/env python3
"""Erzeugt das Icon „Henry Dev“ (AppIconDev) aus dem normalen Icon: das H etwas kleiner, daneben „Dev“ in
derselben Goldfarbe (Tim 17.10.2026). Nur nötig, wenn sich AppIcon ändert. Braucht Pillow und Liberation Serif.

Aufruf: python3 scripts/dev_icon_erzeugen.py
"""
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

QUELLE = "App/Resources/Assets.xcassets/AppIcon.appiconset"
ZIEL = "App/Resources/Assets.xcassets/AppIconDev.appiconset"
SCHRIFT = "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf"
SKALIERUNG_H = 0.74
SCHRIFTGROESSE = 0.18


def mit_dev(pfad):
    img = Image.open(pfad).convert("RGBA")
    W, H = img.size
    px = img.load()
    # Kasten der goldenen Pixel des H
    xs, ys = [], []
    for y in range(int(H * .25), int(H * .75)):
        for x in range(int(W * .25), int(W * .75)):
            c = px[x, y]
            if c[0] > 150 and c[2] < 150 and c[3] > 200:
                xs.append(x)
                ys.append(y)
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    gold = px[(x0 + x1) // 2, (y0 + y1) // 2]  # Querbalken des H
    # Hintergrund je Zeile aus einer Spalte im Inneren, links vom H
    spalte = int(W * 0.24)
    leer = img.copy()
    lp = leer.load()
    for y in range(y0 - 4, y1 + 4):
        c = px[spalte, y]
        for x in range(x0 - 4, x1 + 4):
            lp[x, y] = c
    # H freistellen: Alpha aus Abstand zur Zeilenfarbe
    hbild = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    hp = hbild.load()
    for y in range(y0, y1):
        bg = px[spalte, y]
        for x in range(x0, x1):
            c = px[x, y]
            d = max(abs(c[i] - bg[i]) for i in range(3))
            dmax = max(abs(gold[i] - bg[i]) for i in range(3))
            a = max(0, min(255, int(255 * d / dmax)))
            hp[x - x0, y - y0] = (gold[0], gold[1], gold[2], a)
    skal = SKALIERUNG_H
    hb = hbild.resize((int(hbild.width * skal), int(hbild.height * skal)), Image.LANCZOS)
    schrift = ImageFont.truetype(SCHRIFT, int(H * SCHRIFTGROESSE))
    text = "Dev"
    zeichnen = ImageDraw.Draw(leer)
    tb = zeichnen.textbbox((0, 0), text, font=schrift)
    tw = tb[2] - tb[0]
    luecke = int(W * 0.025)
    gesamt = hb.width + luecke + tw
    start = (W - gesamt) // 2
    oben = (H - hb.height) // 2
    leer.alpha_composite(hb, (start, oben))
    grund = oben + hb.height  # Grundlinie = Unterkante H
    zeichnen.text((start + hb.width + luecke - tb[0], grund - tb[3]), text, font=schrift, fill=gold)
    return leer


def main():
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    os.makedirs(ZIEL, exist_ok=True)
    shutil.copy(os.path.join(QUELLE, "Contents.json"), os.path.join(ZIEL, "Contents.json"))
    mac = mit_dev(os.path.join(QUELLE, "icon_512x512@2x.png"))
    with open(os.path.join(QUELLE, "Contents.json"), encoding="utf-8") as f:
        bilder = [b["filename"] for b in json.load(f)["images"] if "filename" in b]
    for name in bilder:
        original = Image.open(os.path.join(QUELLE, name))
        if name == "icon_1024_ios.png":
            bild = mit_dev(os.path.join(QUELLE, name))
        else:
            bild = mac.resize(original.size, Image.LANCZOS)
        bild.convert(original.mode).save(os.path.join(ZIEL, name), optimize=True)
        print(name, original.size[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
