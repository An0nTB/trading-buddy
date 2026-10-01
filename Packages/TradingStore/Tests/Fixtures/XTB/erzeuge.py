"""Erzeugt die XTB-Testdateien der TradingStore-Tests (Stand 01.10.2026). Aufruf: python3 erzeuge.py

Nur Standardbibliothek, alle Werte erfunden. Ergänzt die Dateien aus
TradingCore/Tests/TradingCoreTests/Fixtures/XTB um einen Folgezeitraum desselben Kontos (100001),
der sich mit `xtb_sonderfaelle.xlsx` überschneidet, und um Fehlerfälle für die Speicherung.
Aufbau wie `xtb_einfach.xlsx`: Beschriftung links, Wert rechts, Texte inline, Zeiten als Text.
"""
import datetime as dt
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

HIER = Path(__file__).parent
FEST = dt.datetime(2026, 10, 1)  # feste Zeit im ZIP, damit die Datei bei jedem Lauf gleich ist
NS = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
TYP = "application/vnd.openxmlformats-officedocument.spreadsheetml."


def n(wert):
    return ("n", str(wert))


def blatt_xml(zeilen):
    xml = []
    for nr in sorted(zeilen):
        zellen = []
        for i, wert in enumerate(zeilen[nr]):
            ref = f"{chr(65 + i)}{nr}"
            if wert is None:
                continue
            if isinstance(wert, tuple):
                zellen.append(f'<c r="{ref}"><v>{wert[1]}</v></c>')
            else:
                zellen.append(f'<c r="{ref}" t="inlineStr"><is><t>{escape(wert)}</t></is></c>')
        xml.append(f'<row r="{nr}">{"".join(zellen)}</row>')
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<worksheet {NS}><sheetData>{"".join(xml)}</sheetData></worksheet>'


def speichere(datei, blaetter):
    teile = {
        "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8"?>\n<Types '
        'xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" '
        'ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" '
        f'ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="{TYP}sheet.main+xml"/>'
        + "".join(f'<Override PartName="/xl/worksheets/sheet{i + 1}.xml" ContentType="{TYP}worksheet+xml"/>'
                  for i in range(len(blaetter))) + "</Types>",
        "_rels/.rels": '<?xml version="1.0" encoding="UTF-8"?>\n<Relationships '
        'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" '
        f'Type="{REL}/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        "xl/workbook.xml": f'<?xml version="1.0" encoding="UTF-8"?>\n<workbook {NS} xmlns:r="{REL}"><sheets>'
        + "".join(f'<sheet name="{escape(name)}" sheetId="{i + 1}" r:id="rId{i + 1}"/>'
                  for i, (name, _) in enumerate(blaetter)) + "</sheets></workbook>",
        "xl/_rels/workbook.xml.rels": '<?xml version="1.0" encoding="UTF-8"?>\n<Relationships '
        'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + "".join(f'<Relationship Id="rId{i + 1}" Type="{REL}/worksheet" Target="worksheets/sheet{i + 1}.xml"/>'
                  for i in range(len(blaetter))) + "</Relationships>",
    }
    for i, (_, zeilen) in enumerate(blaetter):
        teile[f"xl/worksheets/sheet{i + 1}.xml"] = blatt_xml(zeilen)
    with zipfile.ZipFile(HIER / datei, "w", zipfile.ZIP_DEFLATED) as z:
        for name, inhalt in teile.items():
            z.writestr(zipfile.ZipInfo(name, FEST.timetuple()[:6]), inhalt, zipfile.ZIP_DEFLATED)


KOPF_POS = [None, "Position", "Symbol", "Type", "Volume", "Open time", "Open price", "Close time", "Close price",
            "Purchase value", "Sale value", "SL", "TP", "Margin", "Commission", "Swap", "Rollover", "Gross P/L"]
KOPF_KASSE = [None, "ID", "Type", "Time", "Comment", "Symbol", "Amount"]
KONTO = {1: [None, "Account", "100001"], 2: [None, "Currency", "EUR"]}


def folgezeitraum(datei, ergebnis_910003=40, summe_ergebnis=None):
    """Folgezeitraum zu xtb_sonderfaelle.xlsx: Position 910003 und Auszahlung 800014 stehen in beiden
    Dateien (gleiche Werte, andere Spalten und Zeitformat), 910005 und 800017 sind neu."""
    if summe_ergebnis is None:
        summe_ergebnis = ergebnis_910003 + 10
    speichere(datei, [
        ("CLOSED POSITION HISTORY", {**KONTO, 4: KOPF_POS,
            5: [None, n(910003), "SAP.DE", "BUY", n(2), "02/03/2026 10:00:00", n(200), "09/03/2026 15:00:00",
                n(220), n(400), n(440), n(0), n(0), n(0), n(0), n(0), n(0), n(ergebnis_910003)],
            6: [None, n(910005), "US500", "SELL", n("0.1"), "14/04/2026 15:30:00", n(5600), "14/04/2026 16:00:00",
                n(5590), n(0), n(0), n(5620), n(0), n(280), n(0), n(0), n(0), n(10)],
            7: [None, "Total"] + [None] * 12 + [n(0), n(0), n(0), n(summe_ergebnis)]}),
        ("CASH OPERATION HISTORY", {**KONTO, 4: KOPF_KASSE,
            5: [None, n(800014), "Withdrawal", "10/04/2026 10:00:00", "Withdrawal SYNTHETISCH", None, n(-200)],
            6: [None, n(800016), "Profit/Loss (FX/CFD)", "14/04/2026 16:00:00", "Profit of position #910005",
                "US500", n(10)],
            7: [None, n(800017), "Deposit", "15/04/2026 09:00:00", "SYNTHETISCH deposit", None, n(300)],
            8: [None, "Total", None, None, None, None, n(110)]}),
    ])


folgezeitraum("xtb_folgezeitraum.xlsx")
# Gleiche Position 910003 mit anderem Ergebnis: der Import muss abbrechen.
folgezeitraum("xtb_abweichend.xlsx", ergebnis_910003=41)
# Summenzeile passt nicht zu den Positionen (50): der Import darf nichts speichern.
folgezeitraum("xtb_falsche_summe.xlsx", summe_ergebnis=49)

# Ohne Kontonummer und Währung im Kopf (beides muss die App angeben), ohne Summenzeilen.
speichere("xtb_ohne_kopf.xlsx", [
    ("CLOSED POSITION HISTORY", {1: KOPF_POS,
        2: [None, n(930001), "EURUSD", "BUY", n("0.1"), "05/05/2026 09:00:00", n("1.1"), "05/05/2026 10:00:00",
            n("1.1005"), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(5)]}),
    ("CASH OPERATION HISTORY", {1: KOPF_KASSE,
        2: [None, n(830001), "Deposit", "04/05/2026 12:00:00", "SYNTHETISCH deposit", None, n(100)],
        3: [None, n(830002), "Profit/Loss (FX/CFD)", "05/05/2026 10:00:00", "Profit of position #930001",
            "EURUSD", n(5)]}),
])
