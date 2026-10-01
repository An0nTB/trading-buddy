"""Erzeugt die synthetischen XTB-Testdateien (Stand 01.10.2026). Aufruf: python3 erzeuge.py

Nur Standardbibliothek. Alle Werte sind erfunden; der Aufbau folgt xtb-xlsx-cleaner (2025)
und dem Beispielexport von Export-To-Ghostfolio (2026), siehe 00_LIESMICH.md.
"""
import datetime as dt
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

HIER = Path(__file__).parent
FEST = dt.datetime(2026, 10, 1)  # feste Zeit im ZIP, damit die Datei bei jedem Lauf gleich ist


def serie(text):
    """Excel-Seriennummer einer Ortszeit „2026-03-02 09:10:00“."""
    t = dt.datetime.fromisoformat(text)
    return repr((t - dt.datetime(1899, 12, 30)).total_seconds() / 86400)


def spalte(i):
    name = ""
    i += 1
    while i:
        i, rest = divmod(i - 1, 26)
        name = chr(65 + rest) + name
    return name


class Mappe:
    def __init__(self, gemeinsam):
        self.gemeinsam = gemeinsam  # True: Texte in sharedStrings.xml, sonst inline
        self.texte, self.blaetter = [], []

    def text(self, wert):
        if wert not in self.texte:
            self.texte.append(wert)
        return self.texte.index(wert)

    def blatt(self, name, zeilen):
        """zeilen: {Zeilennummer: [Zellwert, ...]} ab Spalte A; None = leere Zelle,
        ("n", "1.5") = Zahl wie gespeichert, ("x", "<si>…</si>") = Rohtext für sharedStrings."""
        xml = []
        for nr in sorted(zeilen):
            zellen = []
            for i, wert in enumerate(zeilen[nr]):
                ref = f"{spalte(i)}{nr}"
                if wert is None:
                    continue
                if isinstance(wert, tuple) and wert[0] == "n":
                    zellen.append(f'<c r="{ref}"><v>{wert[1]}</v></c>')
                elif isinstance(wert, tuple) and wert[0] == "x":
                    self.texte.append(wert[1])
                    zellen.append(f'<c r="{ref}" t="s"><v>{len(self.texte) - 1}</v></c>')
                elif self.gemeinsam:
                    zellen.append(f'<c r="{ref}" t="s"><v>{self.text(wert)}</v></c>')
                else:
                    zellen.append(f'<c r="{ref}" t="inlineStr"><is><t>{escape(wert)}</t></is></c>')
            xml.append(f'<row r="{nr}" spans="1:21">{"".join(zellen)}</row>')
        self.blaetter.append((name, "".join(xml)))

    def speichere(self, datei):
        ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        rel = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
        typ = "application/vnd.openxmlformats-officedocument.spreadsheetml."
        rel_typ = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        teile = {
            "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types '
            'xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" '
            'ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" '
            f'ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="{typ}sheet.main+xml"/>'
            + "".join(f'<Override PartName="/xl/worksheets/sheet{i + 1}.xml" ContentType="{typ}worksheet+xml"/>'
                      for i in range(len(self.blaetter)))
            + (f'<Override PartName="/xl/sharedStrings.xml" ContentType="{typ}sharedStrings+xml"/>'
               if self.gemeinsam else "") + "</Types>",
            "_rels/.rels": '<?xml version="1.0" encoding="UTF-8"?>\n<Relationships '
            'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="xl/workbook.xml"/></Relationships>',
            "xl/workbook.xml": f'<?xml version="1.0" encoding="UTF-8"?>\n<workbook {ns} {rel}><sheets>'
            + "".join(f'<sheet name="{escape(n)}" sheetId="{i + 1}" r:id="rId{i + 1}"/>'
                      for i, (n, _) in enumerate(self.blaetter)) + "</sheets></workbook>",
            "xl/_rels/workbook.xml.rels": '<?xml version="1.0" encoding="UTF-8"?>\n<Relationships '
            'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + "".join(f'<Relationship Id="rId{i + 1}" Type="{rel_typ}/worksheet" Target="worksheets/sheet{i + 1}.xml"/>'
                      for i in range(len(self.blaetter)))
            + (f'<Relationship Id="rIdS" Type="{rel_typ}/sharedStrings" Target="sharedStrings.xml"/>'
               if self.gemeinsam else "") + "</Relationships>",
        }
        for i, (_, daten) in enumerate(self.blaetter):
            teile[f"xl/worksheets/sheet{i + 1}.xml"] = (f'<?xml version="1.0" encoding="UTF-8"?>\n<worksheet {ns}>'
                                                       f"<sheetData>{daten}</sheetData></worksheet>")
        if self.gemeinsam:
            si = "".join(t if t.startswith("<si>") else f"<si><t>{escape(t)}</t></si>" for t in self.texte)
            teile["xl/sharedStrings.xml"] = (f'<?xml version="1.0" encoding="UTF-8"?>\n<sst {ns} '
                                             f'count="{len(self.texte)}">{si}</sst>')
        with zipfile.ZipFile(HIER / datei, "w", zipfile.ZIP_DEFLATED) as z:
            for name, inhalt in teile.items():
                z.writestr(zipfile.ZipInfo(name, FEST.timetuple()[:6]), inhalt, zipfile.ZIP_DEFLATED)


def n(wert):
    return ("n", wert)


# 1. Einfacher Aufbau: Beschriftung links, Wert rechts, Texte inline, Zeiten als Text TT/MM/JJJJ.
m = Mappe(gemeinsam=False)
kopf_pos = ["Position", "Symbol", "Type", "Volume", "Open time", "Open price", "Close time", "Close price",
            "Purchase value", "Sale value", "SL", "TP", "Margin", "Commission", "Swap", "Rollover",
            "Gross P/L", "Comment"]
m.blatt("CLOSED POSITION HISTORY", {
    1: [None, "Account", "00000001"],
    2: [None, "Currency", "EUR"],
    4: [None] + kopf_pos,
    5: [None, n(920001), "US100", "SELL", n("0.2"), "10/03/2026 15:30:00", n(18500), "10/03/2026 16:05:10",
        n(18450), n(0), n(0), n(18560), n(0), n(95), n(0), n(0), n(0), n(200), None],
    6: [None, n(920002), "ALV.DE", "BUY", n(1), "11/03/2026 09:05:00", n(300), "12/03/2026 17:20:00", n(290),
        n(300), n(290), n(0), n(0), n(0), n("-1.5"), n(0), n(0), n(-10), None],
    7: [None, "Total", None, None, None, None, None, None, None, None, None, None, None, None, n("-1.5"),
        n(0), n(0), n(190)],
})
m.blatt("CASH OPERATION HISTORY", {
    1: [None, "Account", "00000001"],
    3: [None, "ID", "Type", "Time", "Comment", "Symbol", "Amount"],
    4: [None, n(810001), "deposit", "09/03/2026 10:00:00", "SYNTHETISCH", None, n(500)],
    5: [None, n(810002), "close trade", "10/03/2026 16:05:10", "Close trade 920001", "US100", n(200)],
    6: [None, n(810003), "Stocks/ETF purchase", "11/03/2026 09:05:00", "OPEN BUY 1 @ 300.00", "ALV.DE", n(-300)],
    7: [None, n(810004), "commission", "11/03/2026 09:05:00", "Commission 920002", "ALV.DE", n("-1.5")],
    8: [None, n(810005), "Stocks/ETF sale", "12/03/2026 17:20:00", "CLOSE BUY 1 @ 290.00", "ALV.DE", n(290)],
    9: [None, "Total", None, None, None, None, n("688.5")],
})
m.speichere("xtb_einfach.xlsx")

# 2. Aufbau wie xStation: Beschriftungen in Zeile 6, Werte in Zeile 7, Kopf in Zeile 13,
# gemeinsame Texte (mit Formatierung und Lautschrift), Excel-Datumswerte, Gleitkomma-Reste.
m = Mappe(gemeinsam=True)
konto = {6: [None] * 5 + ["Name and surname", None, None, "Account", None, None, "Currency"],
         7: [None] * 5 + ["SYNTHETISCH", None, None, n(100001), None, None, "EUR"]}
m.blatt("OPEN POSITION 01102026", {**konto, 13: [None, "Position", "Symbol", "Type", "Volume"]})
kopf_pos = kopf_pos[:8] + ["Open origin", "Close origin"] + kopf_pos[8:]
m.blatt("CLOSED POSITION HISTORY", {**konto, 13: [None] + kopf_pos,
    14: [None, n(910001), "DE40", "BUY", n("0.1"), n(serie("2026-03-02 09:10:00")), n("22000.5"),
         n(serie("2026-03-02 11:45:30")), n("22100.5"), "xStation5", "xStation5", n(0), n(0), n(21950), n(0),
         n(110), n(0), n(0), n(0), n(250), None],
    15: [None, n(910002), "EURUSD", "SELL", n("0.05"), n(serie("2026-03-27 20:00:00")), n("1.085"),
         n(serie("2026-03-30 08:00:00")), n("1.0800000000000001"), "xStation5", "xStation5", n(0), n(0), n(0),
         n(0), n(180), n(0), n("-0.85"), n("-0.1"), n("23.050000000000001"), None],
    16: [None, n(910003), "SAP.DE", "BUY", n(2), n(serie("2026-03-02 10:00:00")), n(200),
         n(serie("2026-03-09 15:00:00")), n(220), "xStation5", "xStation5", n(400), n(440), n(0), n(0), n(0),
         n(0), n(0), n(0), n(40), None],
    17: [None, n(910004), "GOLD", "BUY LIMIT", n(1), n(serie("2026-03-05 10:00:00")), n(2900),
         n(serie("2026-03-05 10:00:00")), n(2900), None, None, n(0), n(0), n(0), n(0), n(0), n(0), n(0), n(0),
         n(0), None],
    18: [None, "Total", None, None, None, None, None, None, None, None, None, None, None, None, None, None,
         n(0), n("-0.85"), n("-0.1"), n("313.05")],
})
m.blatt("CASH OPERATION HISTORY", {**konto, 13: [None, "ID", "Type", "Time", "Comment", "Symbol", "Amount"],
    14: [None, n(800001), ("x", "<si><t>Deposit</t><rPh sb=\"0\" eb=\"7\"><t>デポジット</t></rPh></si>"),
         "01.03.2026 12:00:00", "SYNTHETISCH deposit", None, n(1000)],
    15: [None, n(800002), "Profit/Loss (FX/CFD)", n(serie("2026-03-02 11:45:30")), "Profit of position #910001",
         "DE40", n(250)],
    16: [None, n(800003), "Stocks/ETF purchase", n(serie("2026-03-02 10:00:00")), "OPEN BUY 2 @ 200.00",
         "SAP.DE", n(-400)],
    17: [None, n(800004), "Stocks/ETF sale", n(serie("2026-03-09 15:00:00")), "CLOSE BUY 2 @ 220.00", "SAP.DE",
         n(440)],
    18: [None, n(800005), "DIVIDENT", n(serie("2026-03-20 00:00:00")), "SAP.DE EUR 2.2000/ SHR", "SAP.DE",
         n("4.4000000000000004")],
    19: [None, n(800006), ("x", '<si><r><t xml:space="preserve">Withholding </t></r><r><rPr><b/></rPr>'
                                 "<t>tax</t></r></si>"),
         n(serie("2026-03-20 00:00:00")), "SAP.DE EUR WHT", "SAP.DE", n("-1.16")],
    21: [None, n(800007), "Profit/Loss (FX/CFD)", n(serie("2026-03-30 08:00:00")), "Profit of position #910002",
         "EURUSD", n("23.050000000000001")],
    22: [None, n(800008), "Swap", n(serie("2026-03-30 08:00:00")), "Swap of position #910002", "EURUSD",
         n("-0.85")],
    23: [None, n(800009), "Rollover", n(serie("2026-03-30 08:00:00")), "Rollover of position #910002", "EURUSD",
         n("-0.1")],
    24: [None, n(800010), "Free funds interests", n(serie("2026-04-01 13:42:58")), "Free-funds Interest 2026-03",
         None, n("0.12")],
    25: [None, n(800011), "Free funds interests tax", n(serie("2026-04-01 13:42:58")),
         "Free-funds Interest Tax 2026-03", None, n("-0.03")],
    26: [None, n(800012), "SEC fee", n(serie("2026-04-02 16:00:00")), "SEC fee", "SYN.US", n("-0.01")],
    27: [None, n(800013), "Spin off", n(serie("2026-04-03 09:00:00")), "SYN&CO.US spin off", "SYN&CO.US",
         n("2.5")],
    28: [None, n(800014), "Withdrawal", n(serie("2026-04-10 10:00:00")), "Withdrawal SYNTHETISCH", None, n(-200)],
    29: [None, n(800015), "Subaccount Transfer", n(serie("2026-04-11 10:00:00")), "Transfer SYN1 to SYN2", None,
         n(-50)],
    30: [None, "Total", None, None, None, None, n("1067.92")],
})
m.speichere("xtb_sonderfaelle.xlsx")
