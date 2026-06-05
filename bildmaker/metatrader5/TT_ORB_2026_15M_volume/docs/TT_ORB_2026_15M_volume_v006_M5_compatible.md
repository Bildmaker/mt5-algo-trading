# TT_ORB_2026_15M_volume_v006_M5_compatible

Ausfuehrliches README fuer die M5-kompatible Version des Opening-Range-Breakout Expert Advisors.

## Kurzfassung

`TT_ORB_2026_15M_volume_v006_M5_compatible.mq5` ist eine Abwandlung des bisherigen 15-Minuten-ORB-EAs fuer den Einsatz auf einem M5-Chart. Die Opening Range wird nicht mehr aus einer einzelnen M15-Kerze gelesen, sondern aus einer konfigurierbaren Anzahl geschlossener M5-Kerzen ab New-York-Zeit 09:30 zusammengesetzt.

Default:

- Chart-Timeframe: M5
- Opening Range Start: 09:30 New-York-Zeit
- Opening Range Laenge: `InpOpeningRangeM5Bars = 3`
- Effektive Opening Range bei Default: 09:30 bis 09:45 New-York-Zeit
- Entry-Suche: nach abgeschlossener Opening Range bis `InpNoEntryTradeAfterHour/Minute`
- Erster handelbarer Breakout bei Default: Kerze 09:45-09:50, geprueft auf der neuen 09:50-M5-Kerze
- Positionsverwaltung: offene Positionen werden weiter verwaltet, auch wenn keine neuen Entries mehr erlaubt sind

## Dateien

| Datei | Zweck |
| --- | --- |
| `MQL5/Experts/TT_ORB_2026_15M_volume/TT_ORB_2026_15M_volume_v006_M5_compatible.mq5` | Quellcode der v006 |
| `MQL5/Experts/TT_ORB_2026_15M_volume/TT_ORB_2026_15M_volume_v006_M5_compatible.ex5` | Lokal kompilierter EA, wird gemaess Repo-Workflow nicht committed |
| `docs/TT_ORB_2026_15M_volume_v006_M5_compatible.md` | Diese Dokumentation |

## Strategieidee

Der EA handelt eine Opening-Range-Breakout-Idee fuer USTec/Nasdaq100 CFD-artige Symbole. Der Marktstart wird auf New-York-Zeit bezogen. Aus den ersten M5-Kerzen nach 09:30 wird eine Range gebildet:

- `OR High`: hoechstes High der Opening-Range-M5-Kerzen
- `OR Low`: tiefstes Low der Opening-Range-M5-Kerzen
- Long-Breakout: eine abgeschlossene M5-Signalkerze bricht ueber `OR High`
- Short-Breakout: eine abgeschlossene M5-Signalkerze bricht unter `OR Low`

Optional muss die Signalkerze auch ausserhalb der Range schliessen. Zusaetzlich koennen Volumenfilter, Monatsfilter und ein Daily-ATR-Volatilitaetsfilter den Entry blockieren.

## Warum v006?

Die vorherige EA-Logik war auf M15 ausgelegt. Auf einem M5-Chart sollte aber nicht die 09:30-M5-Kerze allein als Opening Range verwendet werden. Deshalb aggregiert v006 mehrere M5-Kerzen:

```text
InpOpeningRangeHour    = 9
InpOpeningRangeMinute  = 30
InpOpeningRangeM5Bars  = 3

M5-Kerzen fuer die OR:
09:30-09:35
09:35-09:40
09:40-09:45

Range vollstaendig:
auf der neuen 09:45-M5-Kerze.

Erster handelbarer Breakout:
Kerze 09:45-09:50, geprueft auf der neuen 09:50-M5-Kerze.
```

Wenn `InpOpeningRangeM5Bars` auf `4` gestellt wird, bildet der EA die Opening Range aus 09:30 bis 09:50. Bei `6` waere es 09:30 bis 10:00.

## Zeitlogik

Alle Session-Zeiten sind New-York-Zeit:

| Einstellung | Bedeutung |
| --- | --- |
| `InpOpeningRangeHour` | Stunde des Opening-Range-Starts |
| `InpOpeningRangeMinute` | Minute des Opening-Range-Starts |
| `InpOpeningRangeM5Bars` | Anzahl geschlossener M5-Kerzen fuer die Opening Range |
| `InpNoEntryTradeAfterHour` | Stunde, nach der keine neuen Entries mehr gesucht werden |
| `InpNoEntryTradeAfterMinute` | Minute, nach der keine neuen Entries mehr gesucht werden |
| `InpExitTradeEODAfterHour` | Stunde, ab der offene EA-Positionen per EOD-Regel geschlossen werden |
| `InpExitTradeEODAfterMinute` | Minute, ab der offene EA-Positionen per EOD-Regel geschlossen werden |

Wichtig: `InpNoEntryTradeAfterHour/Minute` begrenzt nur neue Entry-Signale. Offene Positionen werden danach weiter ueber SL/TP, Break-even, EOD-Close und die vorhandenen Schutzmechanismen verwaltet.

Bei Positionen, die ohne EOD-Close ueber den New-York-Tageswechsel laufen, speichert der EA die Opening Range des Einstiegstags positionsbezogen. Dadurch werden SL/TP nicht durch die Opening Range des Folgetags neu berechnet.

## Broker-Zeit und DST

Der EA rechnet Broker-Serverzeit in New-York-Zeit um. Dafuer gibt es folgende Inputs:

| Input | Default | Bedeutung |
| --- | ---: | --- |
| `InpBrokerUsesEuropeanDst` | `true` | Broker-Serverzeit folgt europaeischer Sommerzeit |
| `InpBrokerUtcOffsetWinter` | `1` | Broker-UTC-Offset im Winter |
| `InpBrokerUtcOffsetSummer` | `2` | Broker-UTC-Offset im Sommer |

New-York-DST wird intern nach US-Regeln berechnet. Die Opening Range bleibt dadurch auf den NY-Marktstart bezogen, auch wenn Brokerzeit und NY-Zeit unterschiedlich auf Sommerzeit wechseln.

## Entry-Regeln

Ein Entry wird nur auf neuer M5-Kerze geprueft. Bewertet wird die zuletzt geschlossene M5-Kerze (`rates[1]`).

Ein Signal muss folgende Bedingungen erfuellen:

1. Die Opening Range fuer den NY-Handelstag ist vollstaendig vorhanden.
2. Die Signalkerze gehoert zum gleichen NY-Handelstag.
3. Die Signalkerze liegt nach Ende der Opening Range und vor dem Entry-Cutoff.
4. Es gibt keine bereits verwaltete Position fuer Symbol und Magic Number.
5. `InpMaxTradesPerDay` ist noch nicht erreicht.
6. Der Long- oder Short-Monatsfilter erlaubt die jeweilige Richtung.
7. Der Daily-Volatilitaetsfilter blockiert nicht.
8. Falls aktiviert, erfuellt die Signalkerze den Tick-Volume-Filter.
9. Es gibt genau eine Richtung: Long oder Short, nicht beide gleichzeitig.

### Long-Signal

Long wird vorbereitet, wenn:

- `signalBar.high > OR High`
- und bei `InpRequireCloseBeyondRange = true`: `signalBar.close > OR High`
- Long-Trades aktiv sind
- der Long-Monatsfilter den aktuellen Monat erlaubt

### Short-Signal

Short wird vorbereitet, wenn:

- `signalBar.low < OR Low`
- und bei `InpRequireCloseBeyondRange = true`: `signalBar.close < OR Low`
- Short-Trades aktiv sind
- der Short-Monatsfilter den aktuellen Monat erlaubt

## Volumenfilter

Der Tick-Volume-Filter ist standardmaessig aktiv:

| Input | Default | Bedeutung |
| --- | ---: | --- |
| `InpEnableVolumeFilter` | `true` | aktiviert/deaktiviert den Filter |
| `InpVolumeMultiplier` | `1.50` | Signalkerzen-Volumen muss mindestens Durchschnitt mal Faktor sein |
| `InpVolumeAveragePeriod` | `20` | Anzahl vorheriger M5-Kerzen fuer den Durchschnitt |

Der Durchschnitt wird aus den Kerzen vor der Signalkerze berechnet. Dadurch wird verhindert, dass die Signalkerze selbst den Referenzwert nach oben zieht.

## Daily-Volatility-Filter

Optional kann ein D1-ATR-Filter aktiv sein:

| Modus | Bedeutung |
| --- | --- |
| `DAILY_VOLATILITY_FILTER_OFF` | Kein Filter |
| `DAILY_VOLATILITY_FILTER_GREATER_THAN` | Trade nur, wenn D1 ATR groesser als Schwelle ist |
| `DAILY_VOLATILITY_FILTER_LESS_THAN` | Trade nur, wenn D1 ATR kleiner als Schwelle ist |

Parameter:

| Input | Default | Bedeutung |
| --- | ---: | --- |
| `InpDailyVolatilityAtrPeriod` | `14` | D1-ATR-Periode |
| `InpDailyVolatilityThreshold` | `0.0` | Schwelle fuer den aktiven Modus |

Wenn der Filter aktiv ist, muss die Schwelle groesser als `0.0` sein, sonst verweigert der EA die Initialisierung.

## Risiko und Positionsgroesse

Die Stop-Distanz wird aus Entry-Preis und Opening-Range-Gegenseite berechnet:

- Long: initialer Stop an `OR Low`
- Short: initialer Stop an `OR High`

Parameter:

| Input | Default | Bedeutung |
| --- | ---: | --- |
| `InpUseDynamicLotSize` | `true` | dynamische Positionsgroesse nach Kontorisiko |
| `InpFixedLotSize` | `0.10` | fixe Lots, wenn dynamische Groesse deaktiviert ist |
| `InpRiskPercent` | `2.50` | Risiko in Prozent vom Kontostand |
| `InpTakeProfitRMultiple` | `1.30` | Take-Profit als R-Multiple der Stop-Distanz |

Der EA prueft die Broker-Mindestdistanz fuer Stops. Wenn Entry und Stop zu nah beieinander liegen, wird kein Trade eroeffnet.

## Positionsverwaltung

Die Positionsverwaltung laeuft in v006 ebenfalls auf neuer M5-Kerze. Das ist fuer Backtests effizienter als tickweise Management und passt zur Vorgabe, dass Eroeffnungen, Schliessungen und Schutzlogik auf M5-Kerzen stattfinden.

Der EA verwaltet nur Positionen:

- auf dem aktuellen Symbol
- mit der gesetzten `InpMagicNumber`

### Same-Bar-Hold

Die urspruengliche Same-Bar-Hold-Logik bleibt erhalten:

- Nach Entry werden SL/TP nicht in derselben M5-Kerze gesetzt.
- Schutzlevels werden erst ab der naechsten M5-Kerze nach Entry verwaltet.

Das vermeidet Backtest-Verzerrungen durch schwer aufloesbare Reihenfolgen innerhalb derselben Kerze.

### Break-even

Break-even ist optional:

| Input | Default | Bedeutung |
| --- | ---: | --- |
| `InpEnableBreakEven` | `true` | Break-even-Logik aktiv |
| `InpAtrPeriod` | `14` | ATR-Periode auf M5 |
| `InpBreakEvenAtrMultiple` | `0.5` | Triggerdistanz als ATR-Multiple |
| `InpBreakEvenOffsetPrice` | `0.05` | Offset ab Entry-Preis |

Wenn der offene Gewinn mindestens `ATR * InpBreakEvenAtrMultiple` erreicht, wird der Stop in Richtung Entry plus/minus Offset verbessert. Stops werden nie rueckwaerts verschoben.

### Konservativer Exit bei mehrdeutiger Kerze

Wenn SL und TP in derselben M5-Kerze beruehrt werden koennten, kann der EA konservativ schliessen:

| Input | Default | Bedeutung |
| --- | ---: | --- |
| `InpUseConservativeAmbiguousBarExit` | `true` | aktiviert den konservativen Exit |
| `InpLogAmbiguousBarExits` | `true` | schreibt Logeintraege fuer solche Exits |

Das ist besonders fuer OHLC/M5-Backtests relevant, wenn die echte Tick-Reihenfolge innerhalb der Kerze nicht eindeutig ist.

## Backtest-Optimierungen in v006

v006 vermeidet unnoetige Berechnungen:

- `OnTick()` verarbeitet nur neue M5-Kerzen.
- Wenn der aktuelle M5-Bar bereits verarbeitet wurde, wird sofort beendet.
- Die Opening-Range-History wird erst nach OR-Ende und nur einmal pro NY-Tag geladen.
- Nach `InpNoEntryTradeAfterHour/Minute` werden keine Entry-Checks mehr gemacht.
- Wenn ein Tag ohne offene EA-Position erledigt ist, springt der EA bis zum naechsten Opening-Range-Ende in einen schnellen Sleep-Pfad.
- Wenn `InpMaxTradesPerDay` erreicht ist und keine Position offen ist, werden Entry-Checks fuer den Tag beendet.
- Im Strategy Tester wird die Tagestrade-Anzahl intern gezaehlt; `HistorySelect()` wird dort nicht fuer jeden Tag benoetigt.
- Session-Rechtecke werden pro Tag nur einmal gezeichnet.
- Im nicht-visuellen Strategy Tester werden Chartobjekte und Trade-Marker uebersprungen.
- Im visuellen Strategy Tester werden Trade-Marker aus der Tester-History nachsynchronisiert, damit Entry-/Exit-Pfeile sichtbar bleiben.
- Fuer offene Positionen wird die Entry-Opening-Range gespeichert; mehrtaegige Trades werden nicht mehr durch die Opening Range eines Folgetags verwaltet.

Offene Positionen bleiben die Ausnahme: solange eine passende Position offen ist, wird sie weiter verwaltet.

## Wichtige Inputs im Ueberblick

| Gruppe | Input | Default | Hinweis |
| --- | --- | ---: | --- |
| General | `InpTradingEnabled` | `true` | Master-Schalter fuer Entries |
| General | `InpMagicNumber` | `202615001` | Identifiziert EA-Positionen |
| General | `InpMaxTradesPerDay` | `1` | Tageslimit fuer Entries |
| Session | `InpOpeningRangeHour` | `9` | NY-Zeit |
| Session | `InpOpeningRangeMinute` | `30` | NY-Zeit |
| Session | `InpOpeningRangeM5Bars` | `3` | 3 M5-Kerzen = 15 Minuten |
| Session | `InpNoEntryTradeAfterHour` | `11` | keine neuen Entries danach |
| Session | `InpNoEntryTradeAfterMinute` | `30` | keine neuen Entries danach |
| Exit Rules EOD | `InpExitTradeEODAfterHour` | `15` | EOD-Close ab dieser NY-Stunde |
| Exit Rules EOD | `InpExitTradeEODAfterMinute` | `55` | EOD-Close ab dieser NY-Minute |
| Entry | `InpRequireCloseBeyondRange` | `true` | Close muss jenseits der OR liegen |
| Risk | `InpRiskPercent` | `2.50` | nur bei dynamischer Lotgroesse |
| Risk | `InpTakeProfitRMultiple` | `1.30` | TP auf R-Basis |
| Break Even | `InpEnableBreakEven` | `true` | M5-ATR-basiert |

## Monatsfilter

Long und Short koennen separat je Monat aktiviert/deaktiviert werden.

Default Long deaktiviert:

- Maerz
- September

Default Short deaktiviert:

- Mai
- November

Alle anderen Monate sind im aktuellen Default aktiv.

## Installation in MetaTrader 5

1. Datei `TT_ORB_2026_15M_volume_v006_M5_compatible.mq5` in den MT5-Experts-Ordner kopieren:

   ```text
   MQL5/Experts/TT_ORB_2026_15M_volume/
   ```

2. MetaEditor oeffnen.
3. Datei kompilieren.
4. In MT5 den Navigator aktualisieren.
5. EA auf einen M5-Chart des Zielsymbols ziehen.
6. Inputs kontrollieren, insbesondere Broker-UTC-Offsets und `InpOpeningRangeM5Bars`.

## Kompilieren per MetaEditor CLI

Lokaler Compile-Befehl auf diesem Arbeitsplatz:

```powershell
$src = "J:\prj\Tensortrader_J\codex\ORB_volume_reddit_MT5\bildmaker\metatrader5\TT_ORB_2026_15M_volume\MQL5\Experts\TT_ORB_2026_15M_volume\TT_ORB_2026_15M_volume_v006_M5_compatible.mq5"
$log = "J:\prj\Tensortrader_J\codex\ORB_volume_reddit_MT5\bildmaker\metatrader5\TT_ORB_2026_15M_volume\MQL5\Experts\TT_ORB_2026_15M_volume\TT_ORB_2026_15M_volume_v006_M5_compatible_compile.log"
Start-Process -FilePath "C:\Program Files\MetaTrader 5\metaeditor64.exe" -ArgumentList "/compile:$src","/log:$log" -WindowStyle Hidden -Wait
Get-Content -LiteralPath $log -Tail 120
```

Letzter Compile-Stand:

```text
Result: 0 errors, 0 warnings
```

Hinweis: `.ex5` und Compile-Logs sind generierte Dateien und werden gemaess Repo-Workflow nicht committed.

## Backtest-Empfehlung

Empfohlene Startkonfiguration fuer erste Vergleichstests:

- Chart/Tester-Timeframe: M5
- Modell: je nach Brokerdaten "Every tick based on real ticks" fuer genaue SL/TP-Reihenfolge, sonst konservative Interpretation beachten
- Symbol: USTec/Nasdaq100-CFD des Brokers
- Zeitraum: mehrere Jahre, getrennt nach Marktregime auswerten
- Spread/Commission realistisch setzen
- `InpVerboseLogging = false` fuer schnelle Laeufe
- `InpVerboseLogging = true` nur fuer Debug-Laeufe mit kurzem Zeitraum

Zu pruefende Varianten:

- `InpOpeningRangeM5Bars`: 1, 2, 3, 4, 6
- `InpVolumeMultiplier`: z.B. 1.2, 1.5, 2.0
- `InpRequireCloseBeyondRange`: true/false
- `InpTakeProfitRMultiple`: mehrere R-Multiples
- Long/Short-Monatsfilter getrennt optimieren
- Daily-ATR-Filter an/aus und groesser/kleiner Schwelle

## Verhalten nach Tages-Cutoff

Der alte Name `InpNoTradeAfterHour/Minute` war missverstaendlich. In v006 heisst der Input bewusst:

```text
InpNoEntryTradeAfterHour
InpNoEntryTradeAfterMinute
```

Bedeutung:

- Nach dieser Uhrzeit werden keine neuen Entry-Signale mehr gesucht.
- Eine bereits offene Position wird weiter verwaltet und ab `InpExitTradeEODAfterHour/Minute` geschlossen.
- Wenn keine Position offen ist und fuer den Tag kein Entry mehr moeglich ist, beendet der EA weitere Entry-Pruefungen fuer diesen Tag.

## Bekannte Grenzen

- Der EA ist fuer M5-Signalverarbeitung gebaut. Auf anderen Chart-Timeframes sollte er nicht verwendet werden.
- Die Range-Aggregation erwartet lueckenlose M5-Kerzen ab Opening-Range-Start. Fehlen Kerzen, wird fuer den Tag keine vollstaendige Range gesetzt.
- Konservative Ambiguous-Bar-Exits sind eine Backtest-Schutzlogik, ersetzen aber keine echten Tickdaten.
- Zeitzonenparameter muessen zum Broker passen. Falsche Broker-Offsets verschieben die NY-Session.
- Dies ist keine Anlageberatung und keine Garantie fuer profitable Ergebnisse.

## Version-Historie

| Version | Schwerpunkt |
| --- | --- |
| v005 | M15-basierte ORB-Logik mit konservativer Closure |
| v006 | M5-kompatible Variante mit konfigurierbarer M5-Opening-Range-Aggregation |

## GitHub-Stand

Die v006-Quelle wurde als eigener Commit in `main` aufgenommen. Der EA wurde lokal mit MetaEditor 64 kompiliert und lieferte `0 errors, 0 warnings`.
