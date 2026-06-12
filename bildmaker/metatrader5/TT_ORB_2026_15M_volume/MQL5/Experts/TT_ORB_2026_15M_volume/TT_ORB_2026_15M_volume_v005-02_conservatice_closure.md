# TT_ORB_2026_15M_volume_v005-02_conservatice_closure

Dokumentation fuer:

`TT_ORB_2026_15M_volume_v005-02_conservatice_closure.mq5`

Stand: 2026-06-12

## Kurzbeschreibung

Dieser Expert Advisor handelt eine 15-Minuten Opening-Range-Breakout-Logik. Die Opening Range wird standardmaessig ueber die 09:30 New-York-Kerze gebildet. Danach sucht der EA bis zur konfigurierten Cutoff-Zeit nach einem Ausbruch ueber das Opening-Range-High oder unter das Opening-Range-Low.

Der EA kombiniert die Breakout-Logik mit optionalem Volumenfilter, D1-ATR-Volatilitaetsfilter, Monatsfiltern je Richtung, dynamischer Positionsgroesse, virtuellem Schutzlevel-Handling und konservativer Behandlung von mehrdeutigen SL/TP-Kerzen.

## Aenderungen in v005-02

Diese Version basiert auf `TT_ORB_2026_15M_volume_v005_conservatice_closure.mq5` und erweitert den Daily-Volatility-Filter visuell und diagnostisch.

Neu:

- Das TradeWindow wird in `clrFireBrick` gezeichnet, wenn der aktivierte D1-ATR-Filter den Handel fuer den Tag blockiert.
- Um 09:00 New-York-Zeit wird einmal pro NY-Handelstag eine Print-Meldung ausgegeben, falls wegen des D1-ATR-Filters kein Trade stattfinden wird.
- Eine modulare Chart-Comment-Section wurde eingefuehrt.
- Der Chart-Kommentar zeigt den Status des D1-ATR-Filters als `ERLAUBT`, `BLOCKIERT` oder `AUS`.
- `InpShowChartComments` wurde als neuer Input ergaenzt, um Chart-Kommentare ein- oder auszuschalten.
- Der Default fuer `InpTradeComment` sowie Init/Deinit-Prints wurden auf den neuen Versionsnamen angepasst.

Wichtige neue Routinen:

- `GetDailyVolatilityTradeStatus(...)`: zentrale Statusroutine fuer den D1-ATR-Filter.
- `GetTradeWindowColor()`: entscheidet, ob das TradeWindow normal oder `clrFireBrick` gezeichnet wird.
- `MaybePrintDailyVolatilityNoTradeAtNine(...)`: gibt die einmalige 09:00-NY-Blockademeldung aus.
- `UpdateChartComment()`: zentrale Einstiegsmethode fuer Chart-Kommentare.
- `BuildChartCommentText()`: baut den kompletten Chart-Kommentar zusammen.
- `BuildDailyVolatilityCommentLine()`: baut die D1-ATR-Statuszeile.
- `IsNewYorkBarTime(...)`: wiederverwendbarer Zeitvergleich auf New-York-Barzeit.

## Handelslogik

### Session und Opening Range

- Signal-Zeitrahmen: `PERIOD_M15`.
- Die Opening Range wird aus einer definierten New-York-Kerze gebildet.
- Standardwerte:
  - Opening Range: 09:30 New York.
  - Opening-Range-Dauer: 15 Minuten.
  - No-Trade-After: 11:30 New York.
- Die Broker-Zeit wird ueber die konfigurierbaren UTC-Offsets und DST-Regeln in New-York-Zeit umgerechnet.

### Entry-Regeln

Der EA prueft auf der zuletzt geschlossenen M15-Kerze:

- Long-Signal: Kerze bricht ueber das Opening-Range-High aus.
- Short-Signal: Kerze bricht unter das Opening-Range-Low aus.
- Optional muss der Close ausserhalb der Opening Range liegen.
- Optionaler Tick-Volume-Filter:
  - aktuelles Tick-Volumen muss groesser sein als der Durchschnitt der letzten Bars multipliziert mit `InpVolumeMultiplier`.
- Es wird nur gehandelt, wenn die jeweilige Richtung durch den Monatsfilter erlaubt ist.
- Pro Tag ist die maximale Anzahl Trades ueber `InpMaxTradesPerDay` begrenzt.

### Daily-Volatility-Filter

Der D1-ATR-Filter kann in drei Modi laufen:

- `DAILY_VOLATILITY_FILTER_OFF`: Filter deaktiviert.
- `DAILY_VOLATILITY_FILTER_GREATER_THAN`: Handel nur erlaubt, wenn D1 ATR groesser als die Schwelle ist.
- `DAILY_VOLATILITY_FILTER_LESS_THAN`: Handel nur erlaubt, wenn D1 ATR kleiner als die Schwelle ist.

Wenn der Filter aktiv ist und blockiert:

- es wird kein Entry ausgefuehrt,
- das TradeWindow wird `clrFireBrick`,
- um 09:00 New-York-Zeit wird eine Blockademeldung im Journal ausgegeben,
- der Chart-Kommentar zeigt `D1-ATR Filter: BLOCKIERT`.

### Positionsgroesse

Die Positionsgroesse kann fix oder dynamisch berechnet werden.

- Fix: `InpFixedLotSize`.
- Dynamisch: Risiko in Prozent des Kontostands ueber `InpRiskPercent`.
- Die Risikodistanz ergibt sich aus Entry-Preis und initialem Stop-Level am gegenueberliegenden Opening-Range-Rand.
- Das Volumen wird auf Symbol-Minimum, Maximum und Volume-Step normalisiert.

### Schutzlevel, TP und Break-Even

Nach dem Entry wird das urspruengliche Same-Bar-Hold-Verhalten beibehalten:

- In der Entry-Kerze werden noch keine realen SL/TP-Schutzlevels gesetzt.
- Ab der naechsten M15-Kerze verwaltet der EA SL und TP.

Stop und Take Profit:

- Initialer SL liegt am gegenueberliegenden Opening-Range-Rand.
- TP wird ueber `InpTakeProfitRMultiple` als R-Multiple der Risikodistanz berechnet.

Break-Even:

- Optional aktiv ueber `InpEnableBreakEven`.
- Trigger-Distanz: M15-ATR mal `InpBreakEvenAtrMultiple`.
- Wenn der Trigger erreicht ist, wird der SL in Richtung Break-Even plus/minus `InpBreakEvenOffsetPrice` verschoben.
- SL-Management ist one-way: der Stop wird nicht wieder verschlechtert.

### Konservative Exit-Logik

Wenn `InpUseConservativeAmbiguousBarExit` aktiv ist, behandelt der EA eine M15-Kerze konservativ, wenn SL und TP innerhalb derselben Kerze beruehrt wurden.

In diesem Fall wird die Position geschlossen und optional eine Meldung ausgegeben. Das reduziert optimistische Backtest-Artefakte bei mehrdeutiger Intrabar-Reihenfolge.

## Visualisierung

Der EA zeichnet:

- Opening-Range-Rechteck in `InpOpeningRangeColor`.
- TradeWindow-Rechteck in `InpTradeWindowColor`.
- TradeWindow-Rechteck in `clrFireBrick`, wenn der aktive D1-ATR-Filter den Handel blockiert.
- Entry- und Exit-Marker, wenn `InpDrawTradeMarkers` aktiv ist.
- Chart-Kommentar, wenn `InpShowChartComments` aktiv ist.

Der Chart-Kommentar ist modular aufgebaut und kann spaeter um weitere Statuszeilen erweitert werden.

## Wichtige Inputs

- `InpTradingEnabled`: schaltet Live-/Backtest-Trading ein oder aus.
- `InpMagicNumber`: Magic Number fuer die Zuordnung eigener Trades.
- `InpMaxTradesPerDay`: maximale Trade-Anzahl pro NY-Tag.
- `InpEnableVolumeFilter`: aktiviert den Tick-Volume-Filter.
- `InpDailyVolatilityFilterMode`: Modus des D1-ATR-Filters.
- `InpDailyVolatilityAtrPeriod`: ATR-Periode fuer D1.
- `InpDailyVolatilityThreshold`: Schwelle fuer den D1-ATR-Filter.
- `InpUseDynamicLotSize`: aktiviert risikobasierte Positionsgroesse.
- `InpRiskPercent`: Risiko in Prozent bei dynamischer Positionsgroesse.
- `InpTakeProfitRMultiple`: Take-Profit-Multiple bezogen auf die Risikodistanz.
- `InpEnableBreakEven`: aktiviert ATR-basiertes Break-Even-Management.
- `InpShowChartComments`: aktiviert die Chart-Comment-Section.

## Hinweise

- Die 09:00-Meldung bezieht sich auf New-York-Zeit, passend zur Session-Logik des EAs.
- Wenn der D1-ATR-Wert nicht gelesen werden kann und der Filter aktiv ist, wird der Handel ebenfalls blockiert.
- Der Dateiname enthaelt bewusst die bestehende Schreibweise `conservatice`, damit die Versionslinie konsistent bleibt.
