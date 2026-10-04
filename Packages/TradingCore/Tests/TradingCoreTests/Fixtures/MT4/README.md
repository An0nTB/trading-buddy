# MT4-Beispielauszüge

Herkunft: vollständig erfunden, erzeugt mit `erzeugen.py` am 04.10.2026.

Konto `12345678`, Name „Max Muster“, Broker „Beispiel Broker Ltd.“, alle Tickets, Zeiten (Mai und
Juni 2026, Serverzeit UTC+3), Kurse, Mengen und Beträge sind ausgedacht. Nachgebildet ist nur der
HTML-Aufbau der Auszüge, die ein MetaTrader-4-Server per Mail verschickt. Das Skript braucht nur die
Python-Standardbibliothek und hat einen festen Seed; ein neuer Lauf schreibt dieselben Dateien:

```
python3 erzeugen.py
```

Wer die Dateien neu erzeugt oder ändert, muss die Sollwerte in den Tests neu rechnen (unabhängig vom
Swift-Code, etwa mit einem eigenen Python-Skript).

| Datei | Art | Inhalt |
|---|---|---|
| `beispiel-2026-05-13-daily.html` | Tagesauszug | 4 geschlossene Positionen (eine über Nacht mit Swap), 4 gelöschte Stop-Orders ohne Ziel |
| `beispiel-2026-05-17-daily.html` | Tagesauszug (Sonntag) | keine Bewegung, 1 offene Position im Minus |
| `beispiel-2026-05-21-daily.html` | Tagesauszug | 1 geschlossene Position über mehrere Tage, 1 offene Position |
| `beispiel-2026-05-24-daily.html` | Tagesauszug (Sonntag) | keine Bewegung, dieselbe offene Position im Plus |
| `beispiel-2026-05-31-monthly.html` | Monatsauszug | 110 geschlossene Positionen, 68 gelöschte Orders, ohne Vortagesstand |
| `beispiel-2026-06-01-daily.html` | Tagesauszug | 8 geschlossene Positionen, 6 gelöschte Orders |
| `beispiel-2026-06-03-daily.html` | Tagesauszug | genau 1 geschlossene Position |
| `beispiel-2026-06-04-daily.html` | Tagesauszug | 6 geschlossene Positionen, 14 gelöschte Orders, 1 offene Position |
| `beispiel-2026-06-05-daily.html` | Tagesauszug | 2 geschlossene Positionen, 1 offene Position |
| `beispiel-2026-06-06-daily.html` | Tagesauszug (Samstag) | keine Bewegung, 1 offene Position |

Abgedeckte Formatfälle: Abschnitte „Closed Transactions“, „Open Trades“, „Working Orders“ (leer,
„No transactions“) und „A/C Summary“; gelöschte Pending-Orders (buy stop, sell stop)
mit „cancelled“ und T/P 0.00; Summenzeilen je Abschnitt; Zeile „Deposit/Withdrawal: 0.00“;
Monatsauszug mit leerer Zeile statt „Previous Ledger Balance“; Name mit doppeltem Leerzeichen;
Tickets, die in Tages- und Monatsauszug doppelt vorkommen; Positionen über Nacht mit Swap und
dreifachem Swap am Mittwoch; Devisen, Indizes, Gold und Öl mit zwei bis fünf Nachkommastellen.
