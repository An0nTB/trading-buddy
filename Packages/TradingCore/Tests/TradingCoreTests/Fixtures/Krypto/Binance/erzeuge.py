"""Erzeugt synthetische Binance-Exporte (keine echten Konten) und rechnet die Sollwerte unabhängig.
Aufbau nach R2 Abschnitt 4 (Spot Trade History, 2021/2026) und CoinTaxman src/book.py (2026, Transaktionsverlauf).
Aufruf: python3 erzeuge.py"""
import csv, io
from decimal import Decimal as D

KOPF = ["Date(UTC)", "Pair", "Side", "Price", "Executed", "Amount", "Fee"]
EINFACH = [
    ["2026-03-02 09:00:01", "BTCEUR", "BUY", "60,000.00", "0.0100000000BTC", "600.00000000EUR", "0.0000100000BTC"],
    ["2026-03-03 10:15:00", "ETHUSDT", "BUY", "3,000.00", "0.5000000000ETH", "1,500.00000000USDT", "1.50000000USDT"],
    ["2026-03-05 13:30:45", "BTCEUR", "SELL", "62,000.00", "0.0099900000BTC", "619.38000000EUR", "0.61938000EUR"],
    ["2026-03-29 01:30:00", "ETHUSDT", "SELL", "3,200.00", "0.5000000000ETH", "1,600.00000000USDT", "1.60000000USDT"],
    ["2026-03-30 10:00:00", "SOLEUR", "BUY", "120.00", "2.5000000000SOL", "300.00000000EUR", "0.30000000EUR"],
    ["2026-03-30 10:00:00", "SOLEUR", "BUY", "120.00", "2.5000000000SOL", "300.00000000EUR", "0.30000000EUR"],
]
SONDER = [
    ["2026-03-06 18:12:00", "ETHBTC", "BUY", "0.0500000", "0.2000000000ETH", "0.01000000BTC", "0.0002000000ETH"],
    ["2026-03-07 13:30:45", "BTCEUR", "SELL", "62,000.00", "0.0099900000BTC", "619.38000000EUR", "0.0011500000BNB"],
    ["2026-03-08 08:00:00", "1INCHUSDT", "BUY", "0.4000", "100.00000000001INCH", "40.00000000USDT", "0.04000000USDT"],
    ["2026-03-09 09:00:00", "BNBUSDT", "BUY", "600.00", "0.1000000000BNB", "60.00000000USDT", "0.0000750000BNB"],
    ["2026-03-10 10:00:00", "XRPEUR", "SELL", "0.5000", "100.0000000000XRP", "50.00000000EUR", "0.1000000000XRP"],
    ["2026-03-11 11:00:00", "BTCEUR", "BUY", "65,000.00", "0.0100000000BTC", "650.00000000USDT", "0.65000000USDT"],
    ["2026-03-12 12:00:00", "ETHEUR", "BUY", "3,000.00", "0.1000000000ETH", "300.00000000EUR", "0.0000000000BNB"],
]
TRANSAKTIONEN = [
    ["User ID", "Time", "Account", "Operation", "Coin", "Change", "Remark"],
    ["10000001", "26-03-02 09:00:01", "Spot", "Transaction Buy", "BTC", "0.01", ""],
    ["10000001", "26-03-02 09:00:01", "Spot", "Transaction Spend", "EUR", "-600", ""],
]

def schreibe(name, zeilen, bom, ende, kopf=True):
    puffer = io.StringIO()
    w = csv.writer(puffer, quoting=csv.QUOTE_MINIMAL, lineterminator=ende)
    if kopf: w.writerow(KOPF)
    w.writerows(zeilen)
    with open(name, "w", encoding="utf-8-sig" if bom else "utf-8", newline="") as f:
        f.write(puffer.getvalue())

schreibe("binance_einfach.csv", EINFACH, bom=False, ende="\n")
schreibe("binance_sonderfaelle.csv", SONDER, bom=True, ende="\r\n")
schreibe("binance_transaktionen.csv", TRANSAKTIONEN, bom=True, ende="\n", kopf=False)

# Sollwerte, unabhängig vom Swift-Code: Gegenwährung = Buchstaben am Ende von Amount, Basis = Paar ohne sie.
GELD = {"EUR", "USD", "CHF", "GBP", "USDT", "USDC", "EURC"}
def teile(text, kuerzel):
    return D(text[: -len(kuerzel)].replace(",", "")) if text.endswith(kuerzel) else None

def soll(zeilen):
    summe, verbucht, hinweise = D(0), [], []
    for n, (zeit, paar, seite, preis, ausg, amount, fee) in enumerate(zeilen, start=2):
        gegen = "".join(c for c in amount if c.isalpha())
        if not paar.endswith(gegen) or gegen not in GELD:
            hinweise.append((n, f"{paar} {seite}")); continue
        basis, preis = paar[: -len(gegen)], D(preis.replace(",", ""))
        menge, amt = teile(ausg, basis), teile(amount, gegen)
        betrag, gebuehr = (-amt if seite == "BUY" else amt), D(0)
        if teile(fee, gegen) is not None:
            gebuehr = -teile(fee, gegen)
        elif teile(fee, basis) is not None and teile(fee, basis) != 0:
            f = teile(fee, basis)
            gebuehr = -(f * preis)
            menge = menge - f if seite == "BUY" else menge + f
            betrag = betrag - gebuehr
        elif D("".join(c for c in fee if not c.isalpha())) != 0:
            hinweise.append((n, f"{paar} {seite} Gebühr {''.join(c for c in fee if c.isalpha())}"))
        summe += betrag + gebuehr
        verbucht.append((f"{basis}/{gegen}", seite, menge, betrag, gebuehr))
    return summe, verbucht, hinweise

for name, zeilen in [("einfach", EINFACH), ("sonderfaelle", SONDER)]:
    summe, verbucht, hinweise = soll(zeilen)
    print(name, "Kassenwirkung", summe)
    for v in verbucht: print("  ", *v)
    for h in hinweise: print("   Hinweis", *h)
btc = D("619.38") - D("0.61938") - (D("600") - D("0.6")) - D("0.6")
eth = D("1600") - D("1.6") - D("1500") - D("1.5")
print("FIFO netto BTC/EUR", btc, "ETH/USDT", eth)
