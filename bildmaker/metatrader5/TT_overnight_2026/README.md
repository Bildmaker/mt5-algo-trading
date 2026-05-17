# TT_overnight_2026

Ein einfacher zeitbasierter MetaTrader-5-EA fuer Overnight- und Intraday-Haltefenster.

## Idee

Der EA kann zwei voneinander getrennte Zeitmodelle handeln:

- abends eroefnen, morgens schliessen
- morgens eroefnen, abends schliessen

Die Zeiten werden in Berlin-Zeit gepflegt. Fuer US-Indizes gibt es einen Schalter, der die US/EU-DST-Uebergangswochen automatisch um eine Stunde kompensiert.

## Datei

- `MQL5/Experts/TT_overnight_2026/TT_overnight_2026_v001.mq5`

