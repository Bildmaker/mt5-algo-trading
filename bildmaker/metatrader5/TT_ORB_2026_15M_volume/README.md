# TT_ORB_2026_15M_volume

MetaTrader-5 Expert Advisor fuer eine 15-Minuten-Opening-Range-Breakout-Idee mit Volumenfilter.

## Ziel

Der EA soll schrittweise entwickelt und versioniert werden. Der erste Stand enthaelt nur das technische Grundgeruest:

- EA-Datei unter `MQL5/Experts/TT_ORB_2026_15M_volume/`
- eigener Include-Bereich unter `MQL5/Include/TT_ORB_2026_15M_volume/`
- Ordner fuer Setfiles, Backtests, Doku und Hilfsskripte
- GitHub-Workflow fuer Branches, Commits und Pull Requests

## Projektstruktur

```text
TT_ORB_2026_15M_volume/
  MQL5/
    Experts/
      TT_ORB_2026_15M_volume/
        TT_ORB_2026_15M_volume.mq5
    Include/
      TT_ORB_2026_15M_volume/
  backtests/
  docs/
  scripts/
  setfiles/
```

## Naechste Entwicklungsschritte

1. Strategie-Regeln exakt definieren: OR-Zeit, Session, Instrumente, Breakout-Bedingungen.
2. Risikomodell festlegen: feste Lots, Prozent-Risiko, Stop/Take-Profit, Tageslimit.
3. Volumenfilter definieren: Tick-Volume, Durchschnitt, Mindestmultiplikator.
4. Backtest-Protokoll standardisieren.
5. EA in kleinen Git-Commits implementieren.

