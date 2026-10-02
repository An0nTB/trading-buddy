"""Erzeugt synthetische Coinbase-Transaktionsberichte (keine echten Konten) und rechnet die Sollwerte unabhängig.
Köpfe v4, v3 und v1 nach CoinTaxman src/book.py (GitHub, 2026) und R2 Abschnitt 4. Aufruf: python3 erzeuge.py"""
import csv, io
from decimal import Decimal as D

def schreibe(name, vorspann, kopf, zeilen):
    b = io.StringIO()
    w = csv.writer(b, lineterminator="\n")
    for z in vorspann + [kopf] + zeilen:
        w.writerow(z)
    open(name, "w", encoding="utf-8").write(b.getvalue())

NUTZER = ["User", "SYNTHETISCH", "0000"]
KOPF4 = ["ID", "Timestamp", "Transaction Type", "Asset", "Quantity Transacted", "Price Currency", "Price at Transaction",
         "Subtotal", "Total (inclusive of fees and/or spread)", "Fees and/or Spread", "Notes"]
def r(i, t, typ, a, q, p, sub, tot, fee, notiz=""):
    return [f"syn{i:021d}", t + " UTC", typ, a, q, "EUR", p, sub, tot, fee, notiz]
V4 = [
    r(1, "2026-03-02 09:00:00", "Buy", "BTC", "0.008", "€60000.00", "€480.00", "€489.00", "€9.00", "Bought 0.008 BTC for €489.00 EUR"),
    r(2, "2026-03-05 13:00:00", "Sell", "BTC", "-0.008", "€62000.00", "-€496.00", "-€487.00", "€9.00", "Sold 0.008 BTC for €487.00 EUR"),
    r(3, "2026-03-06 08:30:00", "Advanced Trade Buy", "ETH", "0.5", "€2,400.00", "€1,200.00", "€1,204.80", "€4.80", "Bought 0.5 ETH for 1204.80 EUR on ETH-EUR"),
    r(4, "2026-03-07 15:45:00", "Advanced Trade Sell", "ETH", "-0.2", "€2,500.00", "-€500.00", "-€498.00", "€2.00", "Sold 0.2 ETH for 498.00 EUR on ETH-EUR"),
    r(5, "2026-03-08 10:00:00", "Convert", "ETH", "-0.1", "€2500.00", "€250.00", "€250.00", "€3.70", "Converted 0.1 ETH to 246.30 USDC"),
    r(6, "2026-03-09 11:00:00", "Convert", "SOL", "-10", "€150.00", "€1,500.00", "€1,500.00", "€18.50", "Converted 10 SOL to 1,481.5 USDC"),
    r(7, "2026-03-10 12:00:00", "Convert", "ADA", "-100", "€0.50", "€50.00", "€50.00", "€0.75", "Converted 100 ADA to 1,234 XRP"),
    r(8, "2026-03-11 00:00:00", "Staking Income", "ETH", "0.0004", "€2500.00", "€1.00", "€1.00", "€0.00"),
    r(9, "2026-03-12 00:00:00", "Rewards Income", "SOL", "0.05", "€150.00", "€7.50", "€7.50", "€0.00"),
    r(10, "2026-03-13 09:00:00", "Learning Reward", "GRT", "20", "€0.15", "€3.00", "€3.00", "€0.00", "Received 20 GRT from Coinbase Learn"),
    r(11, "2026-03-01 08:00:00", "Deposit", "EUR", "1000", "€1.00", "€1,000.00", "€1,000.00", "€0.00"),
    r(12, "2026-03-20 08:00:00", "Withdrawal", "EUR", "-200", "€1.00", "-€200.00", "-€201.50", "€1.50"),
    r(13, "2026-03-21 08:00:00", "Send", "BTC", "-0.001", "€61000.00", "-€61.00", "-€61.00", "€0.00", "Sent 0.001 BTC to synthetische Adresse"),
    r(14, "2026-03-22 08:00:00", "Receive", "ETH", "0.05", "€2400.00", "€120.00", "€120.00", "€0.00", "Received 0.05 ETH from an external account"),
    r(15, "2026-03-23 08:00:00", "Retail Staking Transfer", "ETH", "-0.1", "€2400.00", "€240.00", "€240.00", "€0.00"),
]
SATZ3 = ("You can use this transaction report to inform your likely tax obligations. For US customers, Sells, Converts, "
         "Rewards Income, Learning Rewards, and Donations are taxable events. For final tax obligations, please consult your tax advisor.")
SATZ1 = ("You can use this transaction report to inform your likely tax obligations. For US customers, Sells, Converts, "
         "and Rewards Income, and Coinbase Earn transactions are taxable events. For final tax obligations, please consult your tax advisor.")
KOPF3 = ["Timestamp", "Transaction Type", "Asset", "Quantity Transacted", "Spot Price Currency", "Spot Price at Transaction",
         "Subtotal", "Total (inclusive of fees and/or spread)", "Fees and/or Spread", "Notes"]
V3 = [
    ["2022-01-10T08:00:00Z", "Buy", "BTC", "0.01", "EUR", "40000.00", "400.00", "405.99", "5.99", "Bought 0.01 BTC for €405.99 EUR"],
    ["2022-02-14T16:20:00Z", "Sell", "BTC", "0.01", "EUR", "38000.00", "380.00", "374.34", "5.66", "Sold 0.01 BTC for €374.34 EUR"],
    ["2022-03-01T00:00:00Z", "Coinbase Earn", "XLM", "10", "EUR", "0.20", "2.00", "2.00", "0.00", "Received 10 XLM from Coinbase Earn"],
    ["2022-03-02T09:00:00Z", "Send", "XLM", "10", "EUR", "0.21", "", "", "", "Sent 10 XLM to synthetische Adresse"],
]
KOPF1 = ["Timestamp", "Transaction Type", "Asset", "Quantity Transacted", "EUR Spot Price at Transaction", "EUR Subtotal",
         "EUR Total (inclusive of fees)", "EUR Fees", "Notes"]
V1 = [
    ["2021-04-01T10:00:00Z", "Buy", "ETH", "0.5", "1500.00", "", "760.00", "10.00", "Bought 0.5 ETH for €760.00 EUR"],
    ["2021-05-01T10:00:00Z", "Sell", "ETH", "0.5", "2400.00", "1200.00", "1185.00", "15.00", "Sold 0.5 ETH for €1,185.00 EUR"],
]
ALT = lambda satz: [[satz], [], [], [], ["Transactions"], NUTZER, []]
schreibe("coinbase_v4.csv", [[], ["Transactions"], NUTZER], KOPF4, V4)
schreibe("coinbase_v3.csv", ALT(SATZ3), KOPF3, V3)
schreibe("coinbase_v1.csv", ALT(SATZ1), KOPF1, V1)

# Sollwerte: eigener Leser, nicht vom Swift-Code abgeleitet.
def zahl(s):
    s = s.strip().replace("€", "").replace(",", "")
    return abs(D(s)) if s not in ("", "-") else D(0)

def soll(name):
    zeilen = list(csv.reader(open(name, encoding="utf-8")))
    h = next(i for i, z in enumerate(zeilen) if z and z[0] in ("ID", "Timestamp"))
    kopf = zeilen[h]
    g = lambda z, *namen: next(z[kopf.index(n)] for n in namen if n in kopf)
    handel, geld, hinweise = [], [], []
    for j, z in enumerate(zeilen[h + 1:]):
        nr, typ, asset = h + 2 + j, g(z, "Transaction Type"), g(z, "Asset")
        q, p = zahl(g(z, "Quantity Transacted")), zahl(g(z, "Price at Transaction", "Spot Price at Transaction", "EUR Spot Price at Transaction"))
        fee, wert = zahl(g(z, "Fees and/or Spread", "Fees", "EUR Fees")), zahl(g(z, "Subtotal", "EUR Subtotal")) or q * p
        if typ in ("Buy", "Advanced Trade Buy"): handel.append((asset, -wert, -fee))
        elif typ in ("Sell", "Advanced Trade Sell"): handel.append((asset, wert, -fee))
        elif typ in ("Staking Income", "Rewards Income", "Learning Reward", "Coinbase Earn"):
            handel.append((asset, -wert, -fee)); geld.append((typ, wert, D(0)))
        elif typ == "Convert":
            w = g(z, "Notes").split()
            if "," in w[4] and "." not in w[4]: hinweise.append(nr); continue
            handel += [(asset, wert, -fee), (w[5], -(wert - fee), D(0))]
        elif typ == "Deposit": geld.append((typ, q, -fee))
        elif typ == "Withdrawal": geld.append((typ, -q, -fee))
        else: hinweise.append(nr)
    kasse = sum(b + f for _, b, f in handel + geld)
    print(f"{name}: {len(handel)} Ausführungen, {len(geld)} Geldbewegungen, Hinweise {hinweise}, Kassenwirkung {kasse}")

for n in ("coinbase_v4.csv", "coinbase_v3.csv", "coinbase_v1.csv"):
    soll(n)
