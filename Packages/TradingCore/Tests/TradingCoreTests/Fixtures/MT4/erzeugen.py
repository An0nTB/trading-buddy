"""Erzeugt die erfundenen MT4-Beispielauszüge (Stand 04.10.2026). Aufruf: python3 erzeugen.py

Nur Standardbibliothek, fester Seed: Jeder Lauf schreibt dieselben zehn Dateien. Konto, Name, Broker,
Tickets, Zeiten, Kurse, Mengen und Beträge sind erfunden. Nachgebildet ist nur der HTML-Aufbau der
Auszüge, die ein MetaTrader-4-Server per Mail verschickt (Daily Confirmation, Monthly Statement), siehe README.md.

Ablauf: Erst entsteht ein Handelsverlauf (Mai und erste Juniwoche 2026, Serverzeit UTC+3), danach
schneidet `auszug` daraus je Stichtag die Abschnitte heraus. Kontostände, Summenzeilen und
Übersicht werden aus denselben Zeilen gerechnet, damit jeder Auszug mit sich selbst und mit den
anderen Auszügen zusammenpasst.
"""
import datetime as dt
import math
import random
from decimal import ROUND_HALF_UP, Decimal as D
from pathlib import Path

HIER = Path(__file__).parent
ZUFALL = random.Random(20260514)

KONTO = "12345678"
NAME = "Max  Muster"  # zwei Leerzeichen wie im MetaTrader-Kopf; der Leser fasst sie zusammen
BROKER = "Beispiel Broker Ltd."
STARTSTAND = D("1187.40")  # Kontostand am 30.04.2026, 23:59 Serverzeit

# Umrechnung der Gewinnwährung in die Kontowährung EUR (feste, erfundene Kurse).
NACH_EUR = {"EUR": D("1"), "USD": D("0.86"), "GBP": D("1.155"), "CHF": D("1.07"), "JPY": D("0.0058"),
            "CAD": D("0.63"), "AUD": D("0.57"), "NZD": D("0.52")}


class Wert:
    def __init__(self, name, kurs, stellen, kontrakt, waehrung, kommission, swap_kauf, swap_verkauf, basis="EUR"):
        self.name = name
        self.kurs = D(kurs)
        self.stellen = stellen
        self.tick = D(1).scaleb(-stellen)
        self.kontrakt = D(kontrakt)          # Gewinn je Lot und Kurspunkt in `waehrung`
        self.waehrung = waehrung
        self.kommission = D(kommission)      # je Lot, nur Devisen
        self.swap = {"buy": D(swap_kauf), "sell": D(swap_verkauf)}  # je Lot und Nacht in EUR
        self.basis = basis

    def text(self, kurs):
        return f"{kurs:.{self.stellen}f}"


DEVISEN = [
    Wert("eurusd", "1.16420", 5, 100000, "USD", "-6", "-6.10", "1.80"),
    Wert("gbpusd", "1.34870", 5, 100000, "USD", "-6", "-4.20", "0.90", "GBP"),
    Wert("audusd", "0.65930", 5, 100000, "USD", "-6", "-1.60", "-2.40", "AUD"),
    Wert("usdcad", "1.37160", 5, 100000, "CAD", "-6", "1.10", "-5.30", "USD"),
    Wert("usdchf", "0.80240", 5, 100000, "CHF", "-6", "3.20", "-9.80", "USD"),
    Wert("eurjpy", "171.840", 3, 100000, "JPY", "-6", "2.10", "-11.40"),
    Wert("gbpjpy", "198.315", 3, 100000, "JPY", "-6", "3.60", "-14.10", "GBP"),
    Wert("eurgbp", "0.86370", 5, 100000, "GBP", "-6", "-5.40", "2.30"),
    Wert("euraud", "1.76580", 5, 100000, "AUD", "-6", "-8.70", "3.10"),
    Wert("audcad", "0.90410", 5, 100000, "CAD", "-6", "-2.20", "-1.90", "AUD"),
    Wert("gbpchf", "1.08260", 5, 100000, "CHF", "-6", "2.80", "-10.20", "GBP"),
    Wert("audnzd", "1.09870", 5, 100000, "NZD", "-6", "-3.30", "0.70", "AUD"),
    Wert("cadjpy", "108.420", 3, 100000, "JPY", "-6", "1.90", "-8.60", "CAD"),
]
WERTE = {w.name: w for w in DEVISEN}
for w in [
    Wert("ger40.cash", "24486.30", 2, 1, "EUR", "0", "-2.60", "-0.40"),
    Wert("nas100.cash", "22874.60", 2, 1, "USD", "0", "-2.30", "-0.50"),
    Wert("us30.cash", "44562.10", 2, 1, "USD", "0", "-4.10", "-0.80"),
    Wert("uk100.cash", "9146.40", 2, 1, "GBP", "0", "-1.10", "-0.30"),
    Wert("jp225.cash", "41270.00", 2, D("0.1"), "JPY", "0", "-0.02", "-0.01"),
    Wert("eu50.cash", "5418.70", 2, 1, "EUR", "0", "-0.60", "-0.20"),
    Wert("xauusd", "3412.40", 2, 100, "USD", "0", "-22.00", "6.00"),
    Wert("usoil.cash", "64.512", 3, 100, "USD", "0", "-1.40", "-0.90"),
]:
    WERTE[w.name] = w


def kurs_um(wert, zeit):
    """Erfundener, glatter Kursverlauf je Wert: zwei Wellen um den Ausgangskurs. Gleichzeitige Orders
    im selben Wert liegen so beim selben Kurs."""
    tage = (zeit - dt.datetime(2026, 5, 1)).total_seconds() / 86400
    phase = sum(map(ord, wert.name)) % 17
    welle = 0.011 * math.sin(tage / 4.3 + phase) + 0.003 * math.sin(tage * 5.1 + phase / 3)
    return wert.kurs * D(str(round(1 + welle, 6)))


def q2(x):
    return x.quantize(D("0.01"), rounding=ROUND_HALF_UP) + 0


def runde(w, kurs):
    return kurs.quantize(w.tick, rounding=ROUND_HALF_UP)


def zz(a, b):
    """Zufallszahl zwischen a und b als Decimal mit vier Stellen."""
    return D(str(round(ZUFALL.uniform(float(a), float(b)), 4)))


def sek(a, b):
    return dt.timedelta(seconds=ZUFALL.randint(a, b))


class Order:
    """Eine Zeile im Auszug: Position (buy/sell) oder Pending Order (buy stop, sell stop)."""

    def __init__(self, wert, art, lots, platziert, kurs, sl, tp):
        self.wert = wert
        self.art = art
        self.lots = D(lots)
        self.platziert = platziert   # Zeitpunkt, an dem das Ticket vergeben wurde
        self.eroeffnet = platziert   # bei ausgelösten Stops später
        self.kurs = runde(wert, kurs)
        self.sl = runde(wert, sl)
        self.tp = runde(wert, tp) if tp else D(0)
        self.geschlossen = None
        self.schlusskurs = None
        self.geloescht = None
        self.marktkurs = None
        self.ticket = None

    @property
    def seite(self):
        return "buy" if self.art.startswith("buy") else "sell"

    def ausloesen(self, zeit, kurs):
        self.art = self.seite
        self.eroeffnet = zeit
        self.kurs = runde(self.wert, kurs)

    def schliessen(self, zeit, kurs):
        self.geschlossen = zeit
        self.schlusskurs = runde(self.wert, kurs)
        # Jede Position bringt mindestens einen Cent Kursergebnis, damit R immer bestimmt ist:
        # sonst den Schlusskurs in seiner Richtung um einen Tick weiter schieben.
        aufwaerts = self.schlusskurs > self.kurs or (self.schlusskurs == self.kurs and self.seite == "buy")
        while self.gewinn(self.schlusskurs) == 0:
            self.schlusskurs += self.wert.tick if aufwaerts else -self.wert.tick

    def loeschen(self, zeit, kurs):
        self.geloescht = zeit
        self.marktkurs = runde(self.wert, kurs)

    def gewinn(self, kurs):
        bewegung = kurs - self.kurs if self.seite == "buy" else self.kurs - kurs
        return q2(bewegung * self.lots * self.wert.kontrakt * NACH_EUR[self.wert.waehrung])

    def kommission(self):
        return q2(self.lots * self.wert.kommission)

    def swap(self, bis):
        """Swap je Nacht Montag bis Freitag, mittwochs dreifach (Wochenende), bis zum Zeitpunkt `bis`."""
        naechte = 0
        tag = self.eroeffnet.date()
        while dt.datetime.combine(tag + dt.timedelta(days=1), dt.time()) <= bis:
            naechte += {0: 1, 1: 1, 2: 3, 3: 1, 4: 1}.get(tag.weekday(), 0)
            tag += dt.timedelta(days=1)
        return q2(self.lots * self.wert.swap[self.seite] * naechte)


ORDERS = []


def neu(*args):
    o = Order(*args)
    ORDERS.append(o)
    return o


# --- Handelsmuster -------------------------------------------------------------------------------

def position(wert, seite, lots, zeit, sl_pips=None, tp_pips=None, kurs=None):
    """Devisenposition mit Stop und Ziel (Abstände in Pips)."""
    pip = wert.tick * 10
    kurs = kurs if kurs is not None else kurs_um(wert, zeit)
    sl_pips = D(sl_pips if sl_pips is not None else ZUFALL.randint(45, 160))
    tp_pips = D(tp_pips if tp_pips is not None else ZUFALL.randint(12, 34))
    r = 1 if seite == "buy" else -1
    return neu(wert, seite, lots, zeit, kurs, kurs - r * sl_pips * pip, kurs + r * tp_pips * pip)


def plan_trade(wert, seite, lots, zeit, ausgang, dauer, sl_pips=None, tp_pips=None):
    """`ausgang`: ziel, frueh (vor der Hälfte des Ziels geschlossen), verlust (vor dem Stop), stop."""
    o = position(wert, seite, lots, zeit, sl_pips, tp_pips)
    r = 1 if seite == "buy" else -1
    if ausgang == "ziel":
        schluss = o.tp + r * wert.tick * D(ZUFALL.choice([0, 0, 0, 0, 1, 2]))
    elif ausgang == "frueh":
        schluss = o.kurs + (o.tp - o.kurs) * zz("0.22", "0.46")
    elif ausgang == "verlust":
        schluss = o.kurs + (o.sl - o.kurs) * zz("0.25", "0.85")
    else:  # stop
        schluss = o.sl
    o.schliessen(zeit + dauer, schluss)
    return o


def straddle_leer(wert, zeit, abstand):
    """Buy Stop und Sell Stop um den Kurs, beide nach kurzer Zeit wieder gelöscht."""
    mitte = kurs_um(wert, zeit)
    sl = abstand * zz("3.4", "4.2")
    kauf = neu(wert, "buy stop", "0.03", zeit, mitte + abstand / 2, mitte + abstand / 2 - sl, 0)
    verkauf = neu(wert, "sell stop", "0.03", zeit, mitte - abstand / 2, mitte - abstand / 2 + sl, 0)
    ende = zeit + sek(40, 240)
    kauf.loeschen(ende, mitte + abstand * zz("-0.3", "0.3"))
    verkauf.loeschen(ende, kauf.marktkurs - wert.tick * 10)
    return ende


def zone(wert, zeit, abstand, lots0, stufen_max, ausloeser=None):
    """Buy Stop und Sell Stop um den Kurs; nach jeder Auslösung kommt eine Gegenorder mit mehr Lots.
    Am Ziel werden alle Positionen zugleich geschlossen und die letzte Gegenorder gelöscht."""
    mitte = kurs_um(wert, zeit)
    oben, unten = runde(wert, mitte + abstand / 2), runde(wert, mitte - abstand / 2)
    sl = runde(wert, abstand * zz("3.4", "4.0"))
    lots = [D(lots0)]
    for i in range(stufen_max + 1):
        faktor = D("2.6") if i == 0 else D("1.5")
        lots.append(max(q2(lots[-1] * faktor), lots[-1] + D("0.01")))
    kauf = neu(wert, "buy stop", lots[0], zeit, oben, oben - sl, 0)
    verkauf = neu(wert, "sell stop", lots[0], zeit + sek(0, 1), unten, unten + sl, 0)
    seite = ausloeser or ZUFALL.choice(["buy", "sell"])
    t = zeit + sek(6, 400)
    offen = []
    warten = kauf if seite == "sell" else verkauf
    ausgeloest = verkauf if seite == "sell" else kauf
    rutsch = wert.tick * 10 * D(ZUFALL.choice([0, 1, 1, 2, 3]))
    ausgeloest.ausloesen(t, (oben + rutsch) if seite == "buy" else (unten - rutsch))
    warten.loeschen(t, ausgeloest.kurs - (wert.tick * 10 if seite == "buy" else -wert.tick * 10))
    offen.append(ausgeloest)
    stufe = 1
    while True:
        gegen = "sell" if seite == "buy" else "buy"
        preis = unten if gegen == "sell" else oben
        t += sek(1, 3)
        stop = neu(wert, gegen + " stop", lots[stufe], t, preis, preis + (sl if gegen == "sell" else -sl), 0)
        if stufe >= stufen_max or ZUFALL.random() < 0.45:
            # Ziel jenseits der zuletzt ausgelösten Seite: alle schließen, Gegenorder löschen.
            weite = abstand * zz("0.9", "1.9")
            schluss = (oben + weite) if seite == "buy" else (unten - weite)
            t += sek(30, 700)
            for o in offen:
                spanne = wert.tick * 10 * D(ZUFALL.choice([0, 1, 2]))
                o.schliessen(t + sek(0, 1), schluss - spanne if o.seite == "buy" else schluss + spanne)
            stop.loeschen(t + sek(0, 1), schluss)
            return t + sek(0, 2)
        t += sek(20, 500)
        rutsch = wert.tick * 10 * D(ZUFALL.choice([-1, 0, 1, 1, 2]))
        stop.ausloesen(t, preis + rutsch if gegen == "buy" else preis - rutsch)
        offen.append(stop)
        seite = gegen
        stufe += 1


def am(tag, uhr):
    h, m = uhr
    return dt.datetime.combine(tag, dt.time(h, m, ZUFALL.randint(0, 59)))


def handelstag(tag, art="normal"):
    """Zufälliger Tagesablauf: Devisen mit Stop und Ziel, Ausbruchsserien in Indizes und Gold."""
    if art == "ruhig":
        anzahl_devisen, serien = ZUFALL.randint(1, 3), 0
    else:
        anzahl_devisen, serien = ZUFALL.randint(1, 4), ZUFALL.choice([0, 1, 1, 2, 3, 4])
    for _ in range(anzahl_devisen):
        wert = ZUFALL.choice(DEVISEN)
        start = am(tag, (ZUFALL.choice([9, 10, 12, 13, 16, 19]), ZUFALL.randint(0, 50)))
        ausgang = ZUFALL.choices(["ziel", "frueh", "verlust", "stop"], [62, 10, 24, 4])[0]
        if ausgang in ("ziel", "frueh"):
            dauer = sek(300, 3 * 3600)
        else:
            dauer = sek(3 * 3600, 6 * 3600)
        # Alles schließt am selben Tag vor 22:30, damit kein Zufallstrade über einen Stichtag offen bleibt.
        dauer = min(dauer, dt.datetime.combine(tag, dt.time(22, 30)) - start)
        plan_trade(wert, ZUFALL.choice(["buy", "sell"]), ZUFALL.choice(["0.01", "0.01", "0.02", "0.03", "0.04"]),
                   start, ausgang, dauer)
    t = am(tag, (ZUFALL.choice([10, 11, 16, 17]), ZUFALL.randint(0, 30)))
    for _ in range(serien):
        wert = WERTE[ZUFALL.choice(["ger40.cash", "ger40.cash", "nas100.cash", "xauusd"])]
        abstand = {"ger40.cash": zz(12, 18), "nas100.cash": zz(17, 24), "xauusd": zz("1.3", "1.9")}[wert.name]
        if ZUFALL.random() < 0.2:
            t = straddle_leer(wert, t, abstand) + sek(5, 120)
        else:
            lots0 = "0.01" if wert.name == "xauusd" else ZUFALL.choice(["0.02", "0.03", "0.04"])
            t = zone(wert, t, abstand, lots0, ZUFALL.randint(1, 5))
            t += sek(4, 900)


def weite_stops(tag):
    """Mehrere Indizes mit weitem Stop und nahem Ziel, gemeinsam eröffnet (große Lots beim Nikkei)."""
    start = am(tag, (9, 10))
    for name, lots in [("jp225.cash", "8.00"), ("eu50.cash", "0.02"), ("us30.cash", "0.01")]:
        w = WERTE[name]
        kurs = kurs_um(w, start)
        o = neu(w, "buy", lots, start + sek(5, 40), kurs, kurs * zz("0.82", "0.88"), kurs * zz("1.006", "1.012"))
        o.schliessen(o.platziert + sek(2400, 4000), o.tp + w.tick * 10 * D(ZUFALL.randint(0, 6)))


# --- Mai 2026 ------------------------------------------------------------------------------------

def tag(m, t):
    return dt.date(2026, m, t)


# Mehrtägige Positionen außerhalb der Stichtage der Tagesauszüge.
plan_trade(WERTE["gbpjpy"], "sell", "0.01", am(tag(5, 4), (11, 40)), "ziel", sek(13 * 3600, 14 * 3600))
plan_trade(WERTE["usdchf"], "sell", "0.03", am(tag(5, 5), (16, 5)), "verlust", sek(40 * 3600, 42 * 3600))
plan_trade(WERTE["euraud"], "buy", "0.01", am(tag(5, 7), (16, 3)), "verlust", sek(97 * 3600, 98 * 3600))
plan_trade(WERTE["audcad"], "sell", "0.02", am(tag(5, 26), (12, 20)), "ziel", sek(26 * 3600, 27 * 3600))
plan_trade(WERTE["eurusd"], "buy", "0.02", am(tag(5, 27), (9, 15)), "verlust", sek(30 * 3600, 31 * 3600))

# 13. und 21.05. sind fest vorgegeben (Tagesauszüge mit genau bekanntem Inhalt).
for t in [tag(5, 1), tag(5, 4), tag(5, 5), tag(5, 6), tag(5, 7), tag(5, 8), tag(5, 11), tag(5, 12),
          tag(5, 14), tag(5, 15), tag(5, 18), tag(5, 19), tag(5, 20), tag(5, 22),
          tag(5, 25), tag(5, 26), tag(5, 27), tag(5, 28), tag(5, 29)]:
    handelstag(t, "ruhig" if t.day in (1, 22, 29) else "normal")
weite_stops(tag(5, 11))
weite_stops(tag(5, 19))


def nachkauf(wert, seite, zeit, schritt_pips, ergebnis_pips):
    """Zweite Position in gleicher Richtung zu schlechterem Kurs, während die erste noch läuft;
    beide schließen zusammen."""
    r = 1 if seite == "buy" else -1
    pip = wert.tick * 10
    erste = position(wert, seite, "0.01", zeit, sl_pips=150, tp_pips=40)
    zweite = position(wert, seite, "0.02", zeit + sek(4000, 6000), sl_pips=110, tp_pips=50,
                      kurs=erste.kurs - r * D(schritt_pips) * pip)
    ende = zweite.platziert + sek(3000, 7000)
    for o in (erste, zweite):
        o.schliessen(ende + sek(0, 2), erste.kurs + r * D(ergebnis_pips) * pip)


nachkauf(WERTE["eurusd"], "buy", am(tag(5, 7), (10, 5)), 31, -12)
nachkauf(WERTE["gbpjpy"], "sell", am(tag(5, 27), (13, 10)), 24, 9)

# 12./13.05.: Verlierer über Nacht (mit Swap) und zwei gelöschte Ausbruchspaare.
plan_trade(WERTE["audusd"], "buy", "0.01", am(tag(5, 12), (8, 47)), "verlust", sek(28 * 3600, 28 * 3600 + 900),
           sl_pips=190, tp_pips=21)
plan_trade(WERTE["eurusd"], "buy", "0.01", am(tag(5, 13), (12, 0)), "ziel", sek(700, 1500))
plan_trade(WERTE["usdcad"], "buy", "0.01", am(tag(5, 13), (12, 0)), "ziel", sek(900, 1800))
straddle_leer(WERTE["nas100.cash"], am(tag(5, 13), (18, 31)), D(20))
straddle_leer(WERTE["nas100.cash"], am(tag(5, 13), (18, 41)), D(20))
plan_trade(WERTE["cadjpy"], "sell", "0.01", am(tag(5, 13), (20, 6)), "ziel", sek(500, 900))

# Offene Positionen über die Stichtage 17., 21. und 24.05.
P1 = position(WERTE["gbpusd"], "sell", "0.01", am(tag(5, 15), (12, 0)), sl_pips=170, tp_pips=19)
P1.schliessen(am(tag(5, 18), (8, 21)), P1.kurs + D("0.00742"))
P2 = position(WERTE["eurjpy"], "sell", "0.01", am(tag(5, 18), (8, 32)), sl_pips=260, tp_pips=29)
P2.schliessen(am(tag(5, 21), (10, 44)), P2.tp - D("0.006"))
P3 = position(WERTE["eurgbp"], "sell", "0.01", am(tag(5, 18), (8, 33)), sl_pips=310, tp_pips=33)
P3.schliessen(am(tag(5, 26), (14, 2)), P3.tp)

# --- Juni 2026 -----------------------------------------------------------------------------------

J1, J3, J4, J5 = tag(6, 1), tag(6, 3), tag(6, 4), tag(6, 5)
plan_trade(WERTE["gbpchf"], "sell", "0.01", am(J1, (8, 41)), "ziel", sek(5000, 8000))
o = neu(WERTE["jp225.cash"], "sell", "6.00", am(J1, (8, 44)), D("41420.00"), D("42310.00"), D("41315.50"))
o.schliessen(o.platziert + sek(4000, 6000), D("41314.00"))
o = neu(WERTE["usoil.cash"], "buy", "0.10", am(J1, (8, 45)), D("63.874"), D("61.402"), D("64.168"))
o.schliessen(o.platziert + sek(6000, 9000), D("64.171"))
plan_trade(WERTE["audusd"], "buy", "0.02", am(J1, (12, 0)), "ziel", sek(1200, 1800))
straddle_leer(WERTE["nas100.cash"], am(J1, (17, 52)), D(20))
straddle_leer(WERTE["ger40.cash"], am(J1, (17, 56)), D(15))
zone(WERTE["nas100.cash"], am(J1, (18, 6)), D(20), "0.03", 6, ausloeser="buy")
plan_trade(WERTE["audcad"], "buy", "0.03", am(J1, (20, 0)), "ziel", sek(4000, 6500))
o = neu(WERTE["us30.cash"], "sell", "0.02", am(J1, (20, 1)), D("44610.30"), D("45190.80"), D("44551.10"))
o.schliessen(o.platziert + sek(1500, 1800), D("44551.00"))
o = neu(WERTE["uk100.cash"], "sell", "0.40", am(J1, (20, 1)), D("9171.20"), D("9199.60"), D("9168.10"))
o.schliessen(o.platziert + sek(1100, 1300), D("9167.90"))

plan_trade(WERTE["euraud"], "sell", "0.01", am(J3, (16, 1)), "ziel", sek(1200, 1700))

straddle_leer(WERTE["ger40.cash"], am(J4, (11, 12)), D(20))
zone(WERTE["ger40.cash"], am(J4, (11, 13)), D(20), "0.02", 2, ausloeser="sell")
straddle_leer(WERTE["ger40.cash"], am(J4, (20, 8)), D(20))
zone(WERTE["nas100.cash"], am(J4, (20, 8)), D(19), "0.03", 2, ausloeser="buy")
straddle_leer(WERTE["nas100.cash"], am(J4, (20, 13)), D(20))
straddle_leer(WERTE["nas100.cash"], am(J4, (20, 14)), D(20))
zone(WERTE["nas100.cash"], am(J4, (20, 14)), D(21), "0.03", 2, ausloeser="buy")
# Über Nacht offen (Stichtag 04.06.), am 05.06. am Ziel geschlossen.
OFFEN_J4 = neu(WERTE["audnzd"], "buy", "0.05", am(J4, (20, 1)), D("1.09912"), D("1.09381"), D("1.09948"))
OFFEN_J4.schliessen(am(J5, (16, 4)), OFFEN_J4.tp)

o = neu(WERTE["eurusd"], "sell", "0.01", am(J5, (16, 0)), D("1.16733"), D("1.17702"), D("1.16637"))
o.schliessen(o.platziert + sek(380, 420), D("1.16634"))
OFFEN_J5 = neu(WERTE["eurgbp"], "sell", "0.03", am(J5, (16, 0)), D("0.86512"), D("0.86828"), D("0.86481"))

# Momentaufnahmen der offenen Positionen: aktueller Kurs je Stichtag.
AKTUELL = {
    (P1, tag(5, 17)): P1.kurs + D("0.00648"),
    (P3, tag(5, 21)): P3.kurs + D("0.00004"),
    (P3, tag(5, 24)): P3.kurs - D("0.00083"),
    (OFFEN_J4, J4): OFFEN_J4.kurs - D("0.00025"),
    (OFFEN_J5, J5): OFFEN_J5.kurs + D("0.00129"),
    (OFFEN_J5, tag(6, 6)): OFFEN_J5.kurs + D("0.00129"),
}

# Tickets nach Zeitpunkt der Order, mit Lücken wie bei einem Server mit vielen Konten.
nummer = 51_734_200
for o in sorted(ORDERS, key=lambda o: o.platziert):
    nummer += 1 + ZUFALL.randint(0, 900)
    o.ticket = str(nummer)


# --- HTML ----------------------------------------------------------------------------------------

def zeit(t):
    return t.strftime("%Y.%m.%d %H:%M:%S")


def betrag(x):
    return f"{q2(x):.2f}"


def zeile_geschlossen(o):
    w = o.wert
    if o.geloescht:
        return (f'<td>{o.ticket}</td><td nowrap="">&nbsp;{zeit(o.platziert)}</td><td>{o.art}</td><td>{o.lots}</td>'
                f'<td>{w.name}</td><td>{w.text(o.kurs)}</td><td>{w.text(o.sl)}</td><td>{w.text(o.tp)}</td>'
                f'<td nowrap="">&nbsp;{zeit(o.geloescht)}</td><td>{w.text(o.marktkurs)}</td>'
                f'<td colspan="4">cancelled</td></tr>')
    return (f'<td>{o.ticket}</td><td nowrap="">&nbsp;{zeit(o.eroeffnet)}</td><td>{o.art}</td><td>{o.lots}</td>'
            f'<td>{w.name}</td><td>{w.text(o.kurs)}</td><td>{w.text(o.sl)}</td><td>{w.text(o.tp)}</td>'
            f'<td nowrap="">&nbsp;{zeit(o.geschlossen)}</td><td>{w.text(o.schlusskurs)}</td>'
            f'<td>{betrag(o.kommission())}</td><td>{betrag(o.swap(o.geschlossen))}</td>'
            f'<td>{betrag(o.gewinn(o.schlusskurs))}</td></tr>')


KOPF_SPALTEN = ('<td>Ticket</td><td nowrap="">Open Time</td><td>Type</td><td>Lots</td><td>Item</td>{l}'
                '<td nowrap="">Price</td><td>S / L</td><td>T / P</td>')
STIL = ('<style type="text/css" media="screen"> <!-- td { font: 8pt Tahoma,Arial; } //--> </style> '
        '<style type="text/css" media="print"> <!-- td { font: 7pt Tahoma,Arial; } //--> </style>')
FUSS = ('<tr><td colspan="13" style="font: 8pt arial">Best Regards<br>Accounts Department</td></tr> </tbody></table>  '
        '<font face="arial,tahoma" size="1"><div style="font: 8pt arial,tahoma"> <br>Every effort has been made, '
        f'from {BROKER}, to ensure the accuracy of this statement and all information hereunder. <br>Please check '
        'this statement carefully and with full attention. If any errors or omissions have occured please send an '
        'email to <br>backoffice@beispiel-broker.example or contact us on P: +00 000 000 000 within 24 hours to '
        'inform us about your objection. Otherwise <br>this statement will be considered to be confirmed by you.'
        '</div></font>  </div></font>')
LEER = '<tr align="right"><td colspan="13" nowrap="" align="center">No transactions</td></tr>'
ABSTAND = '<tr><td colspan="13" style="font: 1pt arial">&nbsp;</td></tr>'
MONATE = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December"]


def zeilen(liste):
    teile = []
    for i, z in enumerate(liste):
        farbe = ' bgcolor="E0E0E0"' if i % 2 else ""
        teile.append(f'<tr{farbe} align="right">' + z)
    return " ".join(teile)


def summe(werte):
    return sum(werte, D(0))


def auszug(stichtag, monat):
    """Auszug zum Stichtag (23:59 Serverzeit). `monat`: Monatsauszug über den Kalendermonat des Stichtags."""
    ende = dt.datetime.combine(stichtag, dt.time(23, 59, 59))
    beginn = dt.datetime.combine(stichtag.replace(day=1) if monat else stichtag, dt.time())
    vortag = beginn

    def gebucht(o, bis):
        return o.geschlossen is not None and o.geschlossen < bis

    geschlossen = [o for o in ORDERS if o.geschlossen and beginn <= o.geschlossen <= ende]
    geloescht = [o for o in ORDERS if o.geloescht and beginn <= o.geloescht <= ende]
    offen = [o for o in ORDERS if o.art in ("buy", "sell") and o.eroeffnet <= ende
             and (o.geschlossen is None or o.geschlossen > ende)]
    abschnitt = sorted(geschlossen + geloescht, key=lambda o: int(o.ticket))

    kommission = summe(o.kommission() for o in geschlossen)
    swap = summe(o.swap(o.geschlossen) for o in geschlossen)
    gewinn = summe(o.gewinn(o.schlusskurs) for o in geschlossen)
    ergebnis = kommission + swap + gewinn
    vorher = STARTSTAND + summe(o.kommission() + o.swap(o.geschlossen) + o.gewinn(o.schlusskurs)
                                for o in ORDERS if gebucht(o, vortag))
    stand = vorher + ergebnis

    offen_zeilen, o_kom, o_swap, o_gew, marge = [], D(0), D(0), D(0), D(0)
    for o in offen:
        w = o.wert
        aktuell = runde(w, AKTUELL[(o, stichtag)])
        k, s, g = o.kommission(), o.swap(ende), o.gewinn(aktuell)
        o_kom, o_swap, o_gew = o_kom + k, o_swap + s, o_gew + g
        marge += q2(o.lots * 100000 * NACH_EUR[w.basis] / 30)
        offen_zeilen.append(
            f'<tr align="right"><td>{o.ticket}</td><td nowrap="">&nbsp;{zeit(o.eroeffnet)}</td><td>{o.art}</td>'
            f'<td>{o.lots}</td><td>{w.name}</td><td>{w.text(o.kurs)}</td><td>{w.text(o.sl)}</td>'
            f'<td>{w.text(o.tp)}</td><td nowrap="">&nbsp;&nbsp;</td><td>{w.text(aktuell)}</td><td>{betrag(k)}</td>'
            f'<td>{betrag(s)}</td><td>{betrag(g)}</td>   </tr>')
    schwebend = o_kom + o_swap + o_gew
    equity = stand + schwebend

    titel = "Monthly Statement" if monat else "Daily Confirmation"
    stich = f"{stichtag.year} {MONATE[stichtag.month - 1]} {stichtag.day}, 23:59"
    l1, l2 = ("     ", "     ") if monat else ("    ", "    ")
    t = [f'<title>{KONTO}: {titel}</title> {STIL}   <font face="tahoma,arial" size="1"> <div align="center">'
         + (" " if monat else "  ") + f'<div style="font: 20pt Times New Roman"><b>{BROKER}</b></div>'
         + ("    " if monat else "   ") + '<table cellspacing="1" cellpadding="3" border="0"> <tbody><tr><td colspan="2">'
         f'A/C No: <b>{KONTO}</b></td>     <td colspan="6">Name: <b>{NAME}</b></td><td colspan="3">&nbsp;</td>'
         f'<td colspan="2" align="right">{stich}</td></tr> <tr><td colspan="13"><b>Closed Transactions:</b></td></tr> '
         f'<tr align="center" bgcolor="C0C0C0">{l1}' + KOPF_SPALTEN.format(l=l2)
         + '<td nowrap="">Close Time</td>' + l2 + '<td nowrap="">Price</td><td>Commission</td><td>R/O Swap</td>'
         '<td>Trade P/L</td></tr>  ']
    t.append((zeilen([zeile_geschlossen(o) for o in abschnitt]) if abschnitt else LEER) + "   ")
    t.append(f'<tr align="right"><td colspan="10">&nbsp;</td><td>{betrag(kommission)}</td><td>{betrag(swap)}</td>'
             f'<td>{betrag(gewinn)}</td></tr> <tr><td colspan="4"><b>Deposit/Withdrawal: 0.00</b></td>     '
             '<td colspan="5"><b>Credit Facility: 0.00</b></td>     <td colspan="2"><b>Closed Trade P/L: </b></td>     '
             f'<td colspan="2" align="right"><b>{betrag(ergebnis)}</b></td>' + ("" if monat else " ") + "</tr> "
             + ABSTAND + (" " if monat else "") + ' <tr><td colspan="13"><b>Open Trades:</b></td></tr> '
             '<tr align="center" bgcolor="C0C0C0">     ' + KOPF_SPALTEN.format(l="     ")
             + '<td nowrap="">&nbsp;</td>     <td nowrap="">Price</td><td>Commission</td><td>R/O Swap</td>'
             '<td>Trade P/L</td></tr>  ')
    t.append("".join(offen_zeilen) if offen_zeilen else LEER + "   ")
    t.append(f'<tr align="right"><td colspan="10">&nbsp;</td><td>{betrag(o_kom)}</td><td>{betrag(o_swap)}</td>'
             f'<td>{betrag(o_gew)}</td></tr> <tr><td colspan="9">&nbsp;</td><td colspan="2"><b>Floating P/L:</b></td>     '
             f'<td colspan="2" align="right"><b>{betrag(schwebend)}</b></td></tr> ' + ABSTAND
             + (" " if monat else "") + ' <tr><td colspan="13"><b>Working Orders:</b></td></tr> '
             '<tr align="center" bgcolor="C0C0C0">     ' + KOPF_SPALTEN.format(l="     ")
             + '<td colspan="2">Market Price</td><td colspan="3">&nbsp;</td></tr>  ' + LEER + "   ")
    # Der Monatsauszug hat keinen Vortag: leere Zeile und keine Beschriftung (wie MetaTrader ihn druckt).
    if monat:
        t.append('<tr><td colspan="13"><b>A/C Summary:</b></td></tr> <tr></tr><tr><td colspan="7">&nbsp;</td>     ')
    else:
        t.append(ABSTAND + '  <tr><td colspan="13"><b>A/C Summary:</b></td></tr> <tr><td colspan="3" nowrap="">'
                 f'Previous Ledger Balance:</td>     <td colspan="2" align="right" nowrap="">{betrag(vorher)}</td>'
                 '<td colspan="2">&nbsp;</td>     ')
    t.append(f'<td align="right" colspan="3">Floating P/L:</td>     <td colspan="3" align="right">{betrag(schwebend)}'
             '</td></tr> <tr><td colspan="3" nowrap="">Closed Trade P/L:</td>     <td align="right" colspan="2">'
             f'{betrag(ergebnis)}</td><td colspan="2">&nbsp;</td>     <td align="right" colspan="3" nowrap="">'
             'Total Credit Facility:</td>     <td colspan="3" align="right">0.00</td></tr> <tr><td colspan="3" '
             'nowrap="">Deposit/Withdrawal:</td>     <td align="right" colspan="2">0.00</td><td colspan="2">&nbsp;'
             '</td>     <td align="right" colspan="3" nowrap="">Equity:</td>     <td colspan="3" align="right">'
             f'{betrag(equity)}</td></tr> <tr><td colspan="3" nowrap="">Balance:</td>     <td align="right" '
             f'colspan="2">{betrag(stand)}</td><td colspan="2">&nbsp;</td>     <td align="right" colspan="3" '
             'nowrap="">Margin Requirement:</td>     <td colspan="3" align="right">'
             f'{betrag(marge)}</td></tr> <tr><td colspan="10" align="right">Available Margin:</td>     '
             f'<td colspan="3" align="right">{betrag(equity - marge)}</td></tr> ' + FUSS)
    return "".join(t)


AUSZUEGE = [(tag(5, 13), False), (tag(5, 17), False), (tag(5, 21), False), (tag(5, 24), False),
            (tag(5, 31), True), (J1, False), (J3, False), (J4, False), (J5, False), (tag(6, 6), False)]

if __name__ == "__main__":
    for stichtag, monat in AUSZUEGE:
        name = f"beispiel-{stichtag.isoformat()}-{'monthly' if monat else 'daily'}.html"
        (HIER / name).write_text(auszug(stichtag, monat), encoding="utf-8")
        print(name)
