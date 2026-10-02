"""Erzeugt synthetische Bitpanda-Transaktionsverläufe (keine echten Konten) und rechnet die Sollwerte unabhängig.
Aufbau nach CoinTaxman src/book.py und BittyTax parsers/bitpanda.py (beide GitHub, Abruf 01.10.2026)
und R2 Abschnitt 4. Aufruf: python3 erzeuge.py"""
import csv, io
from decimal import Decimal as D

KOPF_ALT = ["Transaction ID", "Timestamp", "Transaction Type", "In/Out", "Amount Fiat", "Fiat", "Amount Asset",
            "Asset", "Asset market price", "Asset market price currency", "Asset class", "Product ID", "Fee",
            "Fee asset", "Spread", "Spread Currency"]
KOPF_NEU = KOPF_ALT + ["Tax Fiat"]
VORSPANN = [["SYNTHETISCH Disclaimer"], ["SYNTHETISCH User ID: 0000"], ["SYNTHETISCH Name"],
            ["SYNTHETISCH Adresse, Ort"], ["SYNTHETISCH Zeitraum"], ["SYNTHETISCH Erstellt am"]]

def z(tid, zeit, typ, inout, af, fiat, aa, asset, preis, preiswg, klasse, pid, fee, feeasset, spread, spreadwg,
      tax="0.00"):
    return [tid, zeit, typ, inout, af, fiat, aa, asset, preis, preiswg, klasse, pid, fee, feeasset, spread, spreadwg, tax]

NEU = [
    z("SYN-BP-0001", "2026-03-02T09:00:00+01:00", "deposit", "incoming", "1000.00", "EUR", "-", "EUR", "-", "-", "Fiat", "-", "0.00", "EUR", "-", "-"),
    z("SYN-BP-0002", "2026-03-02T10:00:00+01:00", "buy", "incoming", "500.00", "EUR", "0.00825083", "BTC", "60000.00", "EUR", "Cryptocurrency", "1", "4.95", "EUR", "0.50", "EUR"),
    z("SYN-BP-0003", "2026-03-05T14:30:00+01:00", "buy", "incoming", "300.00", "EUR", "0.15000000", "ETH", "2000.00", "EUR", "Cryptocurrency", "5", "1.20", "BEST", "0.30", "EUR"),
    z("SYN-BP-0004", "2026-03-20T00:14:13+01:00", "rewards", "incoming", "2.10", "EUR", "0.00105000", "ETH", "2000.00", "EUR", "Cryptocurrency", "5", "0.00", "ETH", "-", "-"),
    z("SYN-BP-0005", "2026-03-30T10:00:00+02:00", "sell", "outgoing", "514.65", "EUR", "0.00825083", "BTC", "63000.00", "EUR", "Cryptocurrency", "1", "5.15", "EUR", "0.52", "EUR"),
    z("SYN-BP-0006", "2026-03-31T10:00:00+02:00", "transfer(stake)", "outgoing", "-", "EUR", "0.10000000", "ETH", "-", "-", "Cryptocurrency", "5", "0.00", "ETH", "-", "-", "-"),
    z("SYN-BP-0007", "2026-04-02T08:00:00+02:00", "withdrawal", "outgoing", "-", "EUR", "0.01000000", "ETH", "-", "-", "Cryptocurrency", "5", "0.00", "ETH", "-", "-", "-"),
    z("SYN-BP-0008", "2026-04-10T11:00:00+02:00", "sell", "outgoing", "74.00", "EUR", "0.03000000", "ETH", "2500.00", "EUR", "Cryptocurrency", "5", "1.00", "EUR", "0.10", "EUR", "0.20"),
    z("SYN-BP-0009", "2026-04-15T09:00:00+02:00", "withdrawal", "outgoing", "200.00", "EUR", "-", "EUR", "-", "-", "Fiat", "-", "1.00", "EUR", "-", "-"),
    z("SYN-BP-0010", "2026-04-21T10:00:00+02:00", "transfer", "incoming", "5.00", "EUR", "2.00000000", "SNX", "2.50", "EUR", "Cryptocurrency", "77", "0.00", "SNX", "-", "-"),
    z("SYN-BP-0011", "2026-04-22T10:00:00+02:00", "buy", "incoming", "1000.00", "TRY", "0.00050000", "BTC", "2000000.00", "TRY", "Cryptocurrency", "1", "0.00", "TRY", "-", "-"),
]
ALT = [r[:16] for r in NEU[:2]] + [
    ["SYN-BP-0102", "2026-03-30T10:00:00+02:00", "sell", "outgoing", "514.65", "EUR", "0.00825083", "BTC", "63000.00", "EUR", "Cryptocurrency", "1", "5.15", "EUR", "0.52", "EUR"],
]

def schreibe(name, kopf, zeilen, bom, ende, quoting):
    puffer = io.StringIO()
    w = csv.writer(puffer, quoting=quoting, lineterminator=ende)
    w.writerows(VORSPANN)
    w.writerow(kopf)
    w.writerows([r[:len(kopf)] for r in zeilen])
    with open(name, "w", encoding="utf-8-sig" if bom else "utf-8", newline="") as f:
        f.write(puffer.getvalue())

schreibe("bitpanda_neu.csv", KOPF_NEU, NEU, bom=False, ende="\r\n", quoting=csv.QUOTE_MINIMAL)
schreibe("bitpanda_alt.csv", KOPF_ALT, ALT, bom=True, ende="\n", quoting=csv.QUOTE_ALL)

# Sollwerte, unabhängig vom Swift-Code. Annahme: Amount Fiat ist die Kassenwirkung samt Gebühr in Fiat.
def zahl(t): return D(0) if t in ("", "-") else D(t)
GELD = {"EUR", "USD", "CHF", "GBP", "USDT", "USDC", "EURC"}
def soll(zeilen):
    kasse, verbucht, geld, hinweise = D(0), [], [], []
    for n, r in enumerate(zeilen, start=len(VORSPANN) + 2):
        tid, typ, af, fiat, aa, asset, klasse = r[0], r[2], zahl(r[4]), r[5], zahl(r[6]), r[7], r[10]
        fee, feeasset, tax = zahl(r[12]), r[13], zahl(r[16]) if len(r) > 16 else D(0)
        if typ in ("deposit", "withdrawal") and klasse == "Fiat":
            betrag = af + fee if typ == "deposit" else -af
            geld.append((tid, typ, betrag, -fee)); kasse += betrag - fee
        elif typ in ("buy", "sell") and fiat in GELD:
            gebuehr = -fee if feeasset == fiat else D(0)
            if fee != 0 and feeasset != fiat: hinweise.append((n, f"{asset}/{fiat} {typ} Gebühr {feeasset}"))
            betrag = -(af + gebuehr) if typ == "buy" else af - gebuehr
            verbucht.append((tid, f"{asset}/{fiat}", typ, betrag, gebuehr)); kasse += betrag + gebuehr
            if tax != 0: hinweise.append((n, f"{asset}/{fiat} {typ} Steuer {r[16]} {fiat}"))
        elif typ in ("reward", "rewards") and fiat in GELD and af > 0:
            verbucht.append((tid, f"{asset}/{fiat}", "buy", -af, D(0))); geld.append((tid, "zinsen", af, D(0)))
        else:
            hinweise.append((n, f"{asset}/{fiat} {typ}" if typ in ("buy", "sell") else f"{typ} {asset}"))
    return kasse, verbucht, geld, hinweise

for name, zeilen in [("neu", NEU), ("alt", ALT)]:
    kasse, verbucht, geld, hinweise = soll(zeilen)
    print(name, "Kassenwirkung", kasse)
    for v in verbucht: print("  ", *v)
    for g in geld: print("   Geld", *g)
    for h in hinweise: print("   Hinweis", *h)
# FIFO: BTC-Runde; ETH-Verkauf 0.03 aus dem Kauf über 0.15 (Einstand 300, Gebühr in BEST nicht verbucht).
btc = D("519.80") - D("495.05") - D("4.95") - D("5.15")
eth = D("75.00") - D("300") * D("0.03") / D("0.15") - D("1.00")
print("FIFO netto BTC/EUR", btc, "ETH/EUR", eth)
