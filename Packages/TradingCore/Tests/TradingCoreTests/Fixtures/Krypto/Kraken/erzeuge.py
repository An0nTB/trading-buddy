"""Erzeugt synthetische Kraken-Trade-Exporte (keine echten Konten) und rechnet die Sollwerte unabhängig.
Aufbau nach Kraken Support 2025/2026 (Trades-Export) und R2 Abschnitt 4. Aufruf: python3 erzeuge.py"""
import csv, io
from decimal import Decimal as D

KOPF = ["txid", "ordertxid", "pair", "aclass", "subclass", "time", "type", "ordertype", "price", "cost", "fee",
        "vol", "margin", "misc", "ledgers", "posttxid", "posstatuscode", "cprice", "ccost", "cfee", "cvol",
        "cmargin", "net", "trades"]

def zeile(txid, pair, time, typ, price, cost, fee, vol, margin="0.00000"):
    return {"txid": txid, "ordertxid": "O" + txid[1:], "pair": pair, "aclass": "forex", "subclass": "crypto",
            "time": time, "type": typ, "ordertype": "limit", "price": price, "cost": cost, "fee": fee,
            "vol": vol, "margin": margin, "misc": "", "ledgers": "L" + txid[1:]}

EINFACH = [
    zeile("TKR001-AAAAA-000001", "XXBTZEUR", "2026-03-02 09:05:00.1234", "buy", "60000.0", "600.00000", "1.56000", "0.01000000"),
    zeile("TKR001-AAAAA-000002", "SOL/EUR", "2026-03-03 12:00:00.0001", "buy", "120.50", "602.50000", "1.56650", "5.00000000"),
    zeile("TKR001-AAAAA-000003", "XXBTZEUR", "2026-03-10 14:30:12.5", "sell", "62500.0", "625.00000", "1.62500", "0.01000000"),
    zeile("TKR001-AAAAA-000004", "SOL/EUR", "2026-03-29 01:30:00.0000", "sell", "130.00", "650.00000", "1.69000", "5.00000000"),
    zeile("TKR001-AAAAA-000005", "XETHZUSD", "2026-03-30 10:00:00.0000", "buy", "3000.00", "1500.00000", "3.90000", "0.50000000"),
]
SONDER = [
    zeile("TKR002-BBBBB-000001", "XETHXXBT", "2026-04-01 08:00:00.0000", "buy", "0.05", "0.02500000", "0.00006500", "0.50000000"),
    zeile("TKR002-BBBBB-000002", "XXBTZEUR", "2026-04-01 09:00:00.0000", "buy", "61000.0", "610.00000", "1.58600", "0.01000000", "122.00000"),
    zeile("TKR002-BBBBB-000003", "XXDGZUSD", "2026-04-02 10:00:00.0000", "buy", "0.2000000", "100.00000", "0.26000", "500.00000000"),
    zeile("TKR002-BBBBB-000004", "ADAEUR", "2026-04-02 11:00:00.0000", "buy", "0.500000", "250.00000", "0.65000", "500.00000000"),
    zeile("TKR002-BBBBB-000005", "XBTUSDT", "2026-04-03 12:00:00.0000", "sell", "65000.0", "650.00000", "1.69000", "0.01000000"),
    zeile("TKR002-BBBBB-000006", "XXBTZEUR", "2026-04-04 13:00:00.0000", "settle", "61000.0", "0.00000", "0.00000", "0.01000000"),
]

def schreibe(name, zeilen, bom, ende):
    puffer = io.StringIO()
    w = csv.DictWriter(puffer, KOPF, quoting=csv.QUOTE_ALL, lineterminator=ende, restval="")
    w.writeheader()
    w.writerows(zeilen)
    with open(name, "w", encoding="utf-8-sig" if bom else "utf-8", newline="") as f:
        f.write(puffer.getvalue())

schreibe("kraken_einfach.csv", EINFACH, bom=False, ende="\r\n")
schreibe("kraken_sonderfaelle.csv", SONDER, bom=True, ende="\n")

# Sollwerte, unabhängig vom Swift-Code: Kassenwirkung = Σ(±cost - fee) der verbuchten Zeilen.
def soll(zeilen):
    geld = {"EUR", "USD", "USDT"}
    alt = {"XXBT": "BTC", "XBT": "BTC", "XETH": "ETH", "XXDG": "DOGE", "ZEUR": "EUR", "ZUSD": "USD"}
    summe, verbucht, hinweise = D(0), [], []
    for n, z in enumerate(zeilen, start=2):
        p = z["pair"]
        if "/" in p:
            b, g = p.split("/")
        else:
            g = next(s for s in ["ZEUR", "ZUSD", "USDT", "XXBT", "EUR", "USD"] if p.endswith(s))
            b = p[: -len(g)]
        b, g = alt.get(b, b), alt.get(g, g)
        if z["type"] not in ("buy", "sell") or g not in geld or D(z["margin"]) != 0:
            hinweise.append((n, f"{p} {z['type']}"))
            continue
        betrag = -D(z["cost"]) if z["type"] == "buy" else D(z["cost"])
        summe += betrag - D(z["fee"])
        verbucht.append((f"{b}/{g}", z["type"], betrag, -D(z["fee"])))
    return summe, verbucht, hinweise

for name, zeilen in [("einfach", EINFACH), ("sonderfaelle", SONDER)]:
    summe, verbucht, hinweise = soll(zeilen)
    print(name, "Kassenwirkung", summe)
    for v in verbucht: print("  ", *v)
    for h in hinweise: print("   Hinweis", *h)
btc = D("625") - D("600") - D("1.56") - D("1.625")
sol = D("650") - D("602.50") - D("1.5665") - D("1.69")
print("FIFO netto BTC/EUR", btc, "SOL/EUR", sol)
