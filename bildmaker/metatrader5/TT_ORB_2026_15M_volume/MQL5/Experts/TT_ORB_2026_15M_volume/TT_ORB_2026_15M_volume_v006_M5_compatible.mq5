// +------------------------------------------------------------------+
// | TT_ORB_2026_15M_volume_v006_M5_compatible.mq5                   |
// | M5 Opening Range Breakout fuer USTec / Nasdaq100 CFD            |
// | Aggregates configurable M5 bars into the opening range           |
// +------------------------------------------------------------------+
#property strict
#property version   "6.002"
#property description "M5-compatible Opening Range Breakout EA with configurable M5 opening range aggregation, volume filter, daily ATR volatility filter, virtual same-bar hold, ATR break-even and lot sizing modes."

#include <Trade/Trade.mqh>

enum ENUM_DAILY_VOLATILITY_FILTER_MODE
{
      DAILY_VOLATILITY_FILTER_OFF          = 0, // Daily volatility filter disabled
      DAILY_VOLATILITY_FILTER_GREATER_THAN = 1, // Trade only if D1 ATR > threshold
      DAILY_VOLATILITY_FILTER_LESS_THAN    = 2  // Trade only if D1 ATR < threshold
};

input group "General"
input bool     InpTradingEnabled                        = true;
input ulong    InpMagicNumber                           = 202615001;
input string   InpTradeComment                          = "TT_ORB_2026_15M_volume_v006_M5_compatible";
input int      InpMaxTradesPerDay                       = 1;
input bool     InpVerboseLogging                        = false;

input group "Session Rules (New York Time)"
input int      InpOpeningRangeHour                      = 9;
input int      InpOpeningRangeMinute                    = 30;
input int      InpOpeningRangeM5Bars                    = 3;
input int      InpNoEntryTradeAfterHour                 = 11;
input int      InpNoEntryTradeAfterMinute               = 30;
input bool     InpBrokerUsesEuropeanDst                 = true;
input int      InpBrokerUtcOffsetWinter                 = 1;
input int      InpBrokerUtcOffsetSummer                 = 2;

input group "Entry Rules"
input bool     InpEnableLongTrades                      = true;
input bool     InpEnableShortTrades                     = true;
input bool     InpEnableVolumeFilter                    = true;
input double   InpVolumeMultiplier                      = 1.50;
input int      InpVolumeAveragePeriod                   = 20;
input bool     InpRequireCloseBeyondRange               = true;

input group "Daily Volatility Filter (D1 ATR)"
input ENUM_DAILY_VOLATILITY_FILTER_MODE InpDailyVolatilityFilterMode = DAILY_VOLATILITY_FILTER_OFF;
input int      InpDailyVolatilityAtrPeriod              = 14;
input double   InpDailyVolatilityThreshold              = 0.0;

input group "Risk & Position Size"
input bool     InpUseDynamicLotSize                     = true;
input double   InpFixedLotSize                          = 0.10;
input double   InpRiskPercent                           = 2.50;
input double   InpTakeProfitRMultiple                   = 1.30;


input group "Backtest Safety"
input bool     InpUseConservativeAmbiguousBarExit       = true;
input bool     InpLogAmbiguousBarExits                  = true;

input group "Break Even"
input bool     InpEnableBreakEven                       = true;
input int      InpAtrPeriod                             = 14;
input double   InpBreakEvenAtrMultiple                  = 0.5;
input double   InpBreakEvenOffsetPrice                  = 0.05;

input group "Visuals"
input color    InpOpeningRangeColor                     = clrDarkBlue;
input color    InpTradeWindowColor                      = clrDarkSlateBlue;
input bool     InpDrawRectanglesInBackground            = true;
input int      InpRectangleLineWidth                    = 1;
input bool     InpDrawTradeMarkers                      = true;
input color    InpEntryMarkerColor                      = clrLime;
input color    InpExitMarkerColor                       = clrRed;

input group "Month Filter - Long Side (false = kein Long in diesem Monat)"
input bool     InpLongMonthJan                          = true;
input bool     InpLongMonthFeb                          = true;
input bool     InpLongMonthMar                          = false;
input bool     InpLongMonthApr                          = true;
input bool     InpLongMonthMay                          = true;
input bool     InpLongMonthJun                          = true;
input bool     InpLongMonthJul                          = true;
input bool     InpLongMonthAug                          = true;
input bool     InpLongMonthSep                          = false;
input bool     InpLongMonthOct                          = true;
input bool     InpLongMonthNov                          = true;
input bool     InpLongMonthDec                          = true;

input group "Month Filter - Short Side (false = kein Short in diesem Monat)"
input bool     InpShortMonthJan                         = true;
input bool     InpShortMonthFeb                         = true;
input bool     InpShortMonthMar                         = true;
input bool     InpShortMonthApr                         = true;
input bool     InpShortMonthMay                         = false;
input bool     InpShortMonthJun                         = true;
input bool     InpShortMonthJul                         = true;
input bool     InpShortMonthAug                         = true;
input bool     InpShortMonthSep                         = true;
input bool     InpShortMonthOct                         = true;
input bool     InpShortMonthNov                         = false;
input bool     InpShortMonthDec                         = true;

static const ENUM_TIMEFRAMES SIGNAL_TF        = PERIOD_M5;
static const int             SIGNAL_TF_SECONDS = 5 * 60;

CTrade trade;

double       g_orHigh                       = 0.0;
double       g_orLow                        = 0.0;
datetime     g_orBarTime                    = 0;
datetime     g_orEndTime                    = 0;
datetime     g_entryCutoffTime              = 0;
int          g_orDayKey                     = 0;
int          g_tradesToday                  = 0;
int          g_tradesCountedDayKey          = 0;
datetime     g_lastProcessedBar             = 0;
int          g_atrHandle                    = INVALID_HANDLE;
int          g_dailyVolaAtrHandle           = INVALID_HANDLE;
bool         g_tradingDisabledLogged        = false;
bool         g_entryChecksDoneForDay         = false;
bool         g_sessionRectanglesDrawn        = false;
bool         g_openingRangeLoadAttempted     = false;
bool         g_hasManagedPosition            = false;
datetime     g_noEntryChecksUntil            = 0;
datetime     g_lastTradeMarkerSyncTo         = 0;

int OnInit()
{
      trade.SetExpertMagicNumber(InpMagicNumber);
      trade.SetTypeFillingBySymbol(_Symbol);

      if(InpOpeningRangeM5Bars <= 0)
      {
            Print("InpOpeningRangeM5Bars muss groesser als 0 sein.");
            return INIT_PARAMETERS_INCORRECT;
      }

      g_atrHandle = iATR(_Symbol, SIGNAL_TF, InpAtrPeriod);
      if(g_atrHandle == INVALID_HANDLE)
      {
            Print("ATR handle konnte nicht erstellt werden.");
            return INIT_FAILED;
      }

      if(InpDailyVolatilityFilterMode != DAILY_VOLATILITY_FILTER_OFF)
      {
            if(InpDailyVolatilityAtrPeriod <= 0)
            {
                  Print("Daily-Vola ATR Periode muss groesser als 0 sein.");
                  return INIT_PARAMETERS_INCORRECT;
            }

            if(InpDailyVolatilityThreshold <= 0.0)
            {
                  Print("Daily-Vola Schwelle muss groesser als 0 sein, wenn der Filter aktiv ist.");
                  return INIT_PARAMETERS_INCORRECT;
            }

            g_dailyVolaAtrHandle = iATR(_Symbol, PERIOD_D1, InpDailyVolatilityAtrPeriod);
            if(g_dailyVolaAtrHandle == INVALID_HANDLE)
            {
                  Print("Daily-Vola ATR handle konnte nicht erstellt werden.");
                  return INIT_FAILED;
            }
      }

      g_hasManagedPosition = HasManagedPosition();
      if(!MQLInfoInteger(MQL_TESTER))
      {
            RefreshSessionState(TimeTradeServer());
            DrawSessionRectangles();
      }

      Print("TT_ORB_2026_15M_volume_v006_M5_compatible initialisiert fuer ", _Symbol,
                  ". Session basiert auf New-York-Zeit mit US-DST. Broker UTC Winter=",
                  InpBrokerUtcOffsetWinter,
                  " Sommer=",
                  InpBrokerUtcOffsetSummer,
                  " EuropeanDST=",
                  InpBrokerUsesEuropeanDst,
                  " OpeningRangeM5Bars=",
                  InpOpeningRangeM5Bars,
                  " DailyVolaFilter=",
                  EnumToString(InpDailyVolatilityFilterMode),
                  " DailyVolaAtrPeriod=",
                  InpDailyVolatilityAtrPeriod,
                  " DailyVolaThreshold=",
                  DoubleToString(InpDailyVolatilityThreshold, 2));

      if(!InpTradingEnabled)
            Print("Trading ist deaktiviert. Fuer Backtests bitte InpTradingEnabled auf true setzen.");

      return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
      if(g_atrHandle != INVALID_HANDLE)
            IndicatorRelease(g_atrHandle);

      if(g_dailyVolaAtrHandle != INVALID_HANDLE)
            IndicatorRelease(g_dailyVolaAtrHandle);

      Print("TT_ORB_2026_15M_volume_v006_M5_compatible beendet. Reason=", reason);
}

void OnTick()
{
      datetime currentBarTime = iTime(_Symbol, SIGNAL_TF, 0);
      if(currentBarTime == 0 || currentBarTime == g_lastProcessedBar)
            return;

      g_lastProcessedBar = currentBarTime;

      SyncVisualTradeMarkers(currentBarTime);

      if(!g_hasManagedPosition && g_noEntryChecksUntil > 0)
      {
            if(currentBarTime < g_noEntryChecksUntil)
                  return;

            g_noEntryChecksUntil = 0;
      }

      MqlDateTime currentNyTime;
      TimeToStruct(ServerToNewYorkTime(currentBarTime), currentNyTime);

      const int currentNyDayKey   = NyDayKeyFromStruct(currentNyTime);
      const int currentNyMinutes  = MinutesFromDayStart(currentNyTime);

      if(g_entryChecksDoneForDay && currentNyDayKey == g_orDayKey && !g_hasManagedPosition)
            return;

      RefreshSessionState(currentBarTime, currentNyDayKey, currentNyMinutes);

      if(g_hasManagedPosition)
      {
            ManageOpenPosition();
            return;
      }

      if(g_entryChecksDoneForDay)
            return;

      if(!InpTradingEnabled)
      {
            if(!g_tradingDisabledLogged)
            {
                  Print("Trading ist deaktiviert. Keine Entries werden ausgefuehrt.");
                  g_tradingDisabledLogged = true;
            }
            return;
      }

      if(!HasValidOpeningRange())
      {
            if(currentNyMinutes > NoEntryCutoffMinutes())
                  MarkEntryChecksDoneForDay(currentNyTime);
            return;
      }

      if(g_tradesToday >= InpMaxTradesPerDay)
      {
            MarkEntryChecksDoneForDay(currentNyTime);
            return;
      }

      if(currentBarTime < g_orEndTime)
            return;

      if(currentBarTime > g_entryCutoffTime)
      {
            MarkEntryChecksDoneForDay(currentNyTime);
            return;
      }

      EvaluateEntrySignal();

      if(currentBarTime >= g_entryCutoffTime && !g_hasManagedPosition)
            MarkEntryChecksDoneForDay(currentNyTime);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
            return;

      if(!HistoryDealSelect(trans.deal))
            return;

      if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
            return;

      if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber)
            return;

      const ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

      if(dealEntry == DEAL_ENTRY_IN)
            g_hasManagedPosition = true;

      if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
            g_hasManagedPosition = HasManagedPosition();

      if(!ShouldDrawChartObjects() || !InpDrawTradeMarkers)
            return;

      if(dealEntry == DEAL_ENTRY_IN)
            DrawTradeDealMarker(trans.deal, "ENTRY");

      if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
            DrawTradeDealMarker(trans.deal, "EXIT");
}

void RefreshSessionState(const datetime currentBarTime)
{
      MqlDateTime currentNyTime;
      TimeToStruct(ServerToNewYorkTime(currentBarTime), currentNyTime);

      RefreshSessionState(currentBarTime,
                          NyDayKeyFromStruct(currentNyTime),
                          MinutesFromDayStart(currentNyTime));
}

void RefreshSessionState(const datetime currentBarTime,
                         const int currentNyDayKey,
                         const int currentNyMinutes)
{
      const int todayNyKey = currentNyDayKey;

      if(todayNyKey != g_orDayKey)
      {
            g_tradesToday         = CountTradesForNyDay(todayNyKey, currentBarTime);
            g_tradesCountedDayKey = todayNyKey;
            ResetOpeningRangeForDay(todayNyKey);
            TryLoadTodayOpeningRange(todayNyKey, currentNyMinutes);
            return;
      }

      if(g_tradesCountedDayKey != todayNyKey)
      {
            g_tradesToday         = CountTradesForNyDay(todayNyKey, currentBarTime);
            g_tradesCountedDayKey = todayNyKey;
      }

      if(!HasValidOpeningRange())
            TryLoadTodayOpeningRange(todayNyKey, currentNyMinutes);
}

void ResetOpeningRangeForDay(const int targetNyDayKey)
{
      g_orHigh                   = 0.0;
      g_orLow                    = 0.0;
      g_orBarTime                = 0;
      g_orEndTime                = 0;
      g_entryCutoffTime          = 0;
      g_orDayKey                 = targetNyDayKey;
      g_entryChecksDoneForDay    = false;
      g_sessionRectanglesDrawn   = false;
      g_openingRangeLoadAttempted = false;
      g_noEntryChecksUntil       = 0;
}

void MarkEntryChecksDoneForDay(const MqlDateTime &currentNyTime)
{
      g_entryChecksDoneForDay = true;
      g_noEntryChecksUntil    = GetNextOpeningRangeEndServerTime(currentNyTime);
}

void TryLoadTodayOpeningRange(const int targetNyDayKey,
                              const int currentNyMinutes)
{
      if(g_openingRangeLoadAttempted)
            return;

      if(currentNyMinutes < OpeningRangeEndMinutes())
            return;

      g_openingRangeLoadAttempted = true;
      LoadTodayOpeningRange(targetNyDayKey);
}

void LoadTodayOpeningRange(const int targetNyDayKey)
{
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      const int copied = CopyRates(_Symbol, SIGNAL_TF, 0, 400, rates);
      if(copied <= 0)
      {
            g_openingRangeLoadAttempted = false;
            return;
      }

      g_orHigh            = 0.0;
      g_orLow             = 0.0;
      g_orBarTime         = 0;
      g_orEndTime         = 0;
      g_entryCutoffTime   = 0;
      g_orDayKey          = targetNyDayKey;
      g_entryChecksDoneForDay = false;
      g_sessionRectanglesDrawn = false;

      const int openingRangeBars = OpeningRangeM5Bars();
      int       collectedBars    = 0;
      datetime  expectedBarTime  = 0;
      double    rangeHigh        = 0.0;
      double    rangeLow         = 0.0;

      for(int i = copied - 1; i >= 1; --i)
      {
            if(GetNyDayKey(rates[i].time) != targetNyDayKey)
                  continue;

            if(collectedBars == 0)
            {
                  if(!IsOpeningRangeStartBar(rates[i].time))
                        continue;

                  g_orBarTime    = rates[i].time;
                  expectedBarTime = g_orBarTime;
                  rangeHigh       = rates[i].high;
                  rangeLow        = rates[i].low;
                  collectedBars   = 1;
            }
            else
            {
                  expectedBarTime += SIGNAL_TF_SECONDS;

                  if(rates[i].time != expectedBarTime)
                  {
                        if(InpVerboseLogging)
                        {
                              PrintFormat("Opening Range fuer %d unvollstaendig: erwartete M5-Bar=%s, gefunden=%s",
                                                      targetNyDayKey,
                                                      TimeToString(expectedBarTime, TIME_DATE | TIME_MINUTES),
                                                      TimeToString(rates[i].time, TIME_DATE | TIME_MINUTES));
                        }
                        return;
                  }

                  rangeHigh = MathMax(rangeHigh, rates[i].high);
                  rangeLow  = MathMin(rangeLow,  rates[i].low);
                  ++collectedBars;
            }

            if(collectedBars < openingRangeBars)
                  continue;

            g_orHigh          = rangeHigh;
            g_orLow           = rangeLow;
            g_orEndTime       = g_orBarTime + OpeningRangeSeconds();
            g_entryCutoffTime = g_orBarTime + MinutesBetweenSessionMarks() * 60;

            if(InpVerboseLogging)
            {
                  PrintFormat("Opening Range geladen fuer %d: Start=%s M5Bars=%d High=%.2f Low=%.2f EntryCutoff=%s",
                                          targetNyDayKey,
                                          TimeToString(g_orBarTime,   TIME_DATE | TIME_MINUTES),
                                          openingRangeBars,
                                          g_orHigh,
                                          g_orLow,
                                          TimeToString(g_entryCutoffTime, TIME_DATE | TIME_MINUTES));
            }

            DrawSessionRectangles();
            return;
      }
}

void DrawSessionRectangles()
{
      if(!ShouldDrawChartObjects())
            return;

      if(!HasValidOpeningRange())
            return;

      if(g_sessionRectanglesDrawn)
            return;

      const string daySuffix = IntegerToString(g_orDayKey);
      const string orName    = "TT_OR_ORANGE_"       + daySuffix;
      const string twName    = "TT_OR_TRADEWINDOW_" + daySuffix;

      DrawRectangle(orName,
                              g_orBarTime,
                              g_orHigh,
                              g_orEndTime,
                              g_orLow,
                              InpOpeningRangeColor);

      DrawRectangle(twName,
                              g_orEndTime,
                              g_orHigh,
                              g_entryCutoffTime,
                              g_orLow,
                              InpTradeWindowColor);

      g_sessionRectanglesDrawn = true;
}

void DrawRectangle(const string   name,
                   const datetime time1,
                   const double   price1,
                   const datetime time2,
                   const double   price2,
                   const color    rectColor)
{
      if(ObjectFind(0, name) < 0)
            ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
      else
            ObjectMove(0, name, 0, time1, price1);

      ObjectMove(0, name, 1, time2, price2);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      rectColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpRectangleLineWidth);
      ObjectSetInteger(0, name, OBJPROP_BACK,       InpDrawRectanglesInBackground);
      ObjectSetInteger(0, name, OBJPROP_FILL,       true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
}

void DrawTradeDealMarker(const ulong dealTicket, const string label)
{
      if(!ShouldDrawChartObjects())
            return;

      const datetime dealTime  = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      const double   dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      const double   volume    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      const ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);

      const string baseName  = "TT_ORB_" + label + "_" + IntegerToString((long)dealTicket);
      const string arrowName = baseName + "_ARROW";
      const string textName  = baseName + "_TEXT";

      const bool isBuyDeal = (dealType == DEAL_TYPE_BUY);
      const color markerColor = (label == "ENTRY") ? InpEntryMarkerColor : InpExitMarkerColor;

      if(ObjectFind(0, arrowName) < 0)
            ObjectCreate(0, arrowName, OBJ_ARROW, 0, dealTime, dealPrice);

      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isBuyDeal ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, markerColor);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, false);

      if(ObjectFind(0, textName) < 0)
            ObjectCreate(0, textName, OBJ_TEXT, 0, dealTime, dealPrice);

      ObjectSetString(0, textName, OBJPROP_TEXT,
                        label + " " + DoubleToString(volume, 2) + " @ " + DoubleToString(dealPrice, _Digits));
      ObjectSetInteger(0, textName, OBJPROP_COLOR, markerColor);
      ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, textName, OBJPROP_ANCHOR, isBuyDeal ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, textName, OBJPROP_HIDDEN, false);

      ChartRedraw(0);
}

void SyncVisualTradeMarkers(const datetime currentBarTime)
{
      if(!MQLInfoInteger(MQL_TESTER) || !MQLInfoInteger(MQL_VISUAL_MODE) || !InpDrawTradeMarkers)
            return;

      const datetime fromTime = (g_lastTradeMarkerSyncTo > 0)
                                ? g_lastTradeMarkerSyncTo - 60
                                : currentBarTime - (2 * 24 * 60 * 60);
      const datetime toTime = currentBarTime + SIGNAL_TF_SECONDS;

      if(!HistorySelect(fromTime, toTime))
            return;

      const int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; ++i)
      {
            const ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0)
                  continue;

            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
                  continue;

            if((ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
                  continue;

            const ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(dealEntry == DEAL_ENTRY_IN)
                  DrawTradeDealMarker(dealTicket, "ENTRY");

            if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
                  DrawTradeDealMarker(dealTicket, "EXIT");
      }

      g_lastTradeMarkerSyncTo = toTime;
}

bool ShouldDrawChartObjects()
{
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
            return false;

      return true;
}

void EvaluateEntrySignal()
{
      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      const int barsNeeded = InpVolumeAveragePeriod + 5;
      const int copied     = CopyRates(_Symbol, SIGNAL_TF, 0, barsNeeded, rates);
      if(copied <= InpVolumeAveragePeriod + 1)
            return;

      const MqlRates signalBar = rates[1];
      if(GetNyDayKey(signalBar.time) != g_orDayKey)
            return;

      if(signalBar.time < g_orEndTime || signalBar.time >= g_entryCutoffTime)
            return;

      double dailyVolatility = 0.0;
      if(!PassesDailyVolatilityFilter(dailyVolatility))
            return;

      double averageVolume = 0.0;
      if(InpEnableVolumeFilter)
      {
            averageVolume = GetAverageTickVolume(rates, 2, InpVolumeAveragePeriod);
            if(averageVolume <= 0.0)
                  return;

            if((double)signalBar.tick_volume < averageVolume * InpVolumeMultiplier)
                  return;
      }

      bool longSignal  = signalBar.high > g_orHigh;
      bool shortSignal = signalBar.low  < g_orLow;

      if(InpRequireCloseBeyondRange)
      {
            longSignal  = longSignal  && signalBar.close > g_orHigh;
            shortSignal = shortSignal && signalBar.close < g_orLow;
      }

      if(!InpEnableLongTrades)
            longSignal = false;

      if(!InpEnableShortTrades)
            shortSignal = false;

      MqlDateTime nyTime;
      TimeToStruct(ServerToNewYorkTime(signalBar.time), nyTime);
      const int currentNyMonth = nyTime.mon;

      if(!IsLongAllowedInMonth(currentNyMonth))
            longSignal = false;

      if(!IsShortAllowedInMonth(currentNyMonth))
            shortSignal = false;

      if(longSignal == shortSignal)
            return;

      if(InpVerboseLogging)
      {
            PrintFormat("Signal erkannt %s | Bar=%s High=%.2f Low=%.2f Close=%.2f TickVol=%I64d AvgVol=%.2f DailyVola=%.2f ORHigh=%.2f ORLow=%.2f",
                                    longSignal ? "LONG" : "SHORT",
                                    TimeToString(signalBar.time, TIME_DATE | TIME_MINUTES),
                                    signalBar.high,
                                    signalBar.low,
                                    signalBar.close,
                                    signalBar.tick_volume,
                                    averageVolume,
                                    dailyVolatility,
                                    g_orHigh,
                                    g_orLow);
      }

      const ENUM_ORDER_TYPE orderType      = longSignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      const double          referencePrice = (orderType == ORDER_TYPE_BUY)
                                             ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double          stopPrice      = (orderType == ORDER_TYPE_BUY) ? g_orLow : g_orHigh;

      if(!IsValidRiskDistance(referencePrice, stopPrice))
            return;

      const double volume = CalculateOrderVolume(referencePrice, stopPrice);
      if(volume <= 0.0)
      {
            Print("Lotgroesse konnte nicht berechnet werden.");
            return;
      }

      const bool sent = (orderType == ORDER_TYPE_BUY)
                        ? trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, InpTradeComment)
                        : trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, InpTradeComment);

      if(!sent)
      {
            Print("OrderSend fehlgeschlagen. Retcode=", trade.ResultRetcode(),
                        " Beschreibung=", trade.ResultRetcodeDescription());
            return;
      }

      ++g_tradesToday;
      g_hasManagedPosition = true;
      Print("Trade eroeffnet: ", EnumToString(orderType),
                  " Vol=",     DoubleToString(volume, 2),
                  " OR High=", DoubleToString(g_orHigh, _Digits),
                  " OR Low=",  DoubleToString(g_orLow,  _Digits));
}

void ManageOpenPosition()
{
      if(!SelectManagedPosition())
      {
            g_hasManagedPosition = false;
            return;
      }

      const ENUM_POSITION_TYPE positionType =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      const double   entryPrice     = PositionGetDouble(POSITION_PRICE_OPEN);
      const datetime entryTime      = (datetime)PositionGetInteger(POSITION_TIME);
      const datetime entryBarTime   = GetBarOpenTime(entryTime);
      const datetime currentBarTime = iTime(_Symbol, SIGNAL_TF, 0);

      // Keep the original same-bar hold behavior:
      // no real SL/TP is placed until the next M5 bar after entry.
      if(entryBarTime == 0 || currentBarTime <= entryBarTime)
            return;

      if(!HasValidOpeningRange())
            return;

      const double initialSl = NormalizePrice((positionType == POSITION_TYPE_BUY) ? g_orLow : g_orHigh);
      if(!IsValidRiskDistance(entryPrice, initialSl))
            return;

      const double desiredTp = NormalizePrice(GetTakeProfitForPosition(positionType, entryPrice, initialSl));

      double currentSl = NormalizePrice(PositionGetDouble(POSITION_SL));
      double currentTp = NormalizePrice(PositionGetDouble(POSITION_TP));

      double desiredSl = initialSl;

      // Start from the existing SL, so protective stops can never move backwards.
      if(currentSl > 0.0)
      {
            if(positionType == POSITION_TYPE_BUY)
                  desiredSl = MathMax(desiredSl, currentSl);
            else
                  desiredSl = MathMin(desiredSl, currentSl);
      }

      if(InpEnableBreakEven)
      {
            double atrValue = 0.0;
            if(GetAtrValue(atrValue))
            {
                  const double triggerDistance = atrValue * InpBreakEvenAtrMultiple;
                  const double bid             = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  const double ask             = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                  const double marketPrice     = (positionType == POSITION_TYPE_BUY) ? bid : ask;

                  const double profitDistance = (positionType == POSITION_TYPE_BUY)
                                                ? marketPrice - entryPrice
                                                : entryPrice  - marketPrice;

                  if(triggerDistance > 0.0 && profitDistance >= triggerDistance)
                  {
                        const double breakEvenSl = NormalizePrice(
                              (positionType == POSITION_TYPE_BUY)
                              ? entryPrice + InpBreakEvenOffsetPrice
                              : entryPrice - InpBreakEvenOffsetPrice
                        );

                        if(positionType == POSITION_TYPE_BUY)
                              desiredSl = MathMax(desiredSl, breakEvenSl);
                        else
                              desiredSl = MathMin(desiredSl, breakEvenSl);
                  }
            }
      }

      desiredSl = NormalizePrice(desiredSl);

      if(IsAmbiguousProtectiveBar(positionType, desiredSl, desiredTp, entryBarTime))
      {
            if(InpLogAmbiguousBarExits)
            {
                  PrintFormat("Konservativer Exit: SL und TP wurden in derselben M5-Kerze beruehrt. Position wird geschlossen. Type=%s SL=%.2f TP=%.2f",
                              EnumToString(positionType),
                              desiredSl,
                              desiredTp);
            }

            if(!trade.PositionClose(_Symbol))
            {
                  Print("Konservativer virtueller Exit fehlgeschlagen. Retcode=", trade.ResultRetcode(),
                              " Beschreibung=", trade.ResultRetcodeDescription());
            }
            else
                  g_hasManagedPosition = false;
            return;
      }

      if(HasReachedProtectiveLevel(positionType, desiredSl, desiredTp))
      {
            if(!trade.PositionClose(_Symbol))
            {
                  Print("Virtueller Exit fehlgeschlagen. Retcode=", trade.ResultRetcode(),
                              " Beschreibung=", trade.ResultRetcodeDescription());
            }
            else
                  g_hasManagedPosition = false;
            return;
      }

      if(!CanPlaceProtectiveStopsNow(positionType, desiredSl, desiredTp))
            return;

      const bool slMissing = (currentSl <= 0.0);
      const bool tpMissing = (currentTp <= 0.0);

      bool slImproves = false;

      if(positionType == POSITION_TYPE_BUY)
            slImproves = slMissing || desiredSl > currentSl + (_Point * 0.5);
      else
            slImproves = slMissing || desiredSl < currentSl - (_Point * 0.5);

      const bool tpChanged = tpMissing || MathAbs(currentTp - desiredTp) >= (_Point * 0.5);

      if(!slImproves && !tpChanged)
            return;

      if(!trade.PositionModify(_Symbol, desiredSl, desiredTp))
      {
            Print("Schutzlevels konnten nicht gesetzt werden. Retcode=",
                        trade.ResultRetcode(),
                        " Beschreibung=", trade.ResultRetcodeDescription());
      }
}

double CalculateOrderVolume(const double entryPrice,
                            const double stopPrice)
{
      if(!InpUseDynamicLotSize)
            return NormalizeVolume(InpFixedLotSize);

      const double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      const double riskAmount = balance * (InpRiskPercent / 100.0);
      if(riskAmount <= 0.0)
            return 0.0;

      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
            return 0.0;

      const double stopDistance = MathAbs(entryPrice - stopPrice);
      if(stopDistance <= 0.0)
            return 0.0;

      const double lossPerLot = (stopDistance / tickSize) * tickValue;
      if(lossPerLot <= 0.0)
            return 0.0;

      const double rawVolume = riskAmount / lossPerLot;
      return NormalizeVolume(rawVolume);
}

double NormalizeVolume(const double requestedVolume)
{
      double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      if(step <= 0.0)
            step = 0.01;

      double bounded    = MathMax(minVolume, MathMin(maxVolume, requestedVolume));
      double steps      = MathFloor((bounded - minVolume) / step + 1e-8);
      double normalized = minVolume + (steps * step);

      normalized = MathMax(minVolume, MathMin(maxVolume, normalized));
      return normalized;
}

double GetAverageTickVolume(const MqlRates &rates[],
                            const int startIndex,
                            const int numberOfBars)
{
      double total = 0.0;
      int    count = 0;

      for(int i = startIndex; i < startIndex + numberOfBars; ++i)
      {
            if(i >= ArraySize(rates))
                  break;

            total += (double)rates[i].tick_volume;
            ++count;
      }

      if(count == 0)
            return 0.0;

      return total / (double)count;
}

bool GetAtrValue(double &atrValue)
{
      atrValue = 0.0;

      if(g_atrHandle == INVALID_HANDLE)
            return false;

      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);

      if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuffer) != 1)
            return false;

      atrValue = atrBuffer[0];
      return atrValue > 0.0;
}

bool GetDailyVolatilityValue(double &dailyVolatility)
{
      dailyVolatility = 0.0;

      if(g_dailyVolaAtrHandle == INVALID_HANDLE)
            return false;

      double dailyAtrBuffer[];
      ArraySetAsSeries(dailyAtrBuffer, true);

      if(CopyBuffer(g_dailyVolaAtrHandle, 0, 1, 1, dailyAtrBuffer) != 1)
            return false;

      dailyVolatility = dailyAtrBuffer[0];
      return dailyVolatility > 0.0;
}

bool PassesDailyVolatilityFilter(double &dailyVolatility)
{
      dailyVolatility = 0.0;

      if(InpDailyVolatilityFilterMode == DAILY_VOLATILITY_FILTER_OFF)
            return true;

      if(!GetDailyVolatilityValue(dailyVolatility))
      {
            if(InpVerboseLogging)
                  Print("Daily-Vola Filter blockiert: D1 ATR Wert konnte nicht gelesen werden.");
            return false;
      }

      bool passed = true;

      if(InpDailyVolatilityFilterMode == DAILY_VOLATILITY_FILTER_GREATER_THAN)
            passed = (dailyVolatility > InpDailyVolatilityThreshold);
      else if(InpDailyVolatilityFilterMode == DAILY_VOLATILITY_FILTER_LESS_THAN)
            passed = (dailyVolatility < InpDailyVolatilityThreshold);

      if(!passed && InpVerboseLogging)
      {
            PrintFormat("Daily-Vola Filter blockiert: D1 ATR=%.2f Schwelle=%.2f Modus=%s",
                                    dailyVolatility,
                                    InpDailyVolatilityThreshold,
                                    EnumToString(InpDailyVolatilityFilterMode));
      }

      return passed;
}

double GetTakeProfitForPosition(const ENUM_POSITION_TYPE positionType,
                                const double entryPrice,
                                const double stopPrice)
{
      const double riskDistance = MathAbs(entryPrice - stopPrice);

      if(positionType == POSITION_TYPE_BUY)
            return entryPrice + (riskDistance * InpTakeProfitRMultiple);

      return entryPrice - (riskDistance * InpTakeProfitRMultiple);
}

bool SelectManagedPosition()
{
      if(!PositionSelect(_Symbol))
            return false;

      const long magicNumber = PositionGetInteger(POSITION_MAGIC);
      return ((ulong)magicNumber == InpMagicNumber);
}

bool HasManagedPosition()
{
      return SelectManagedPosition();
}

bool HasValidOpeningRange()
{
      return (g_orBarTime > 0 && g_orHigh > g_orLow);
}

bool IsValidRiskDistance(const double entryPrice, const double stopPrice)
{
      const double stopDistance = MathAbs(entryPrice - stopPrice);
      return (stopDistance >= GetMinimumStopDistancePrice());
}

datetime GetBarOpenTime(const datetime moment)
{
      const int shift = iBarShift(_Symbol, SIGNAL_TF, moment, false);
      if(shift < 0)
            return 0;

      return iTime(_Symbol, SIGNAL_TF, shift);
}

int CountTradesForNyDay(const int nyDayKey,
                        const datetime currentBarTime)
{
      if(MQLInfoInteger(MQL_TESTER))
            return 0;

      const datetime fromTime = currentBarTime - (10 * 24 * 60 * 60);
      const datetime toTime   = currentBarTime;

      if(!HistorySelect(fromTime, toTime))
            return 0;

      int       trades = 0;
      const int deals  = HistoryDealsTotal();

      for(int i = 0; i < deals; ++i)
      {
            const ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0)
                  continue;

            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
                  continue;

            if((ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
                  continue;

            if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN)
                  continue;

            const datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            if(GetNyDayKey(dealTime) == nyDayKey)
                  ++trades;
      }

      return trades;
}

int OpeningRangeM5Bars()
{
      return InpOpeningRangeM5Bars;
}

int OpeningRangeStartMinutes()
{
      return (InpOpeningRangeHour * 60) + InpOpeningRangeMinute;
}

int OpeningRangeEndMinutes()
{
      return OpeningRangeStartMinutes() + (OpeningRangeM5Bars() * 5);
}

int NoEntryCutoffMinutes()
{
      return (InpNoEntryTradeAfterHour * 60) + InpNoEntryTradeAfterMinute;
}

int MinutesFromDayStart(const MqlDateTime &timeInfo)
{
      return (timeInfo.hour * 60) + timeInfo.min;
}

int NyDayKeyFromStruct(const MqlDateTime &nyTime)
{
      return (nyTime.year * 10000) + (nyTime.mon * 100) + nyTime.day;
}

int OpeningRangeSeconds()
{
      return OpeningRangeM5Bars() * SIGNAL_TF_SECONDS;
}

bool IsOpeningRangeStartBar(const datetime serverBarTime)
{
      MqlDateTime nyTime;
      TimeToStruct(ServerToNewYorkTime(serverBarTime), nyTime);

      return (nyTime.hour == InpOpeningRangeHour && nyTime.min == InpOpeningRangeMinute);
}

bool IsAfterNoEntryCutoff(const datetime serverBarTime)
{
      MqlDateTime nyTime;
      TimeToStruct(ServerToNewYorkTime(serverBarTime), nyTime);

      return (MinutesFromDayStart(nyTime) > NoEntryCutoffMinutes());
}

datetime GetNextOpeningRangeEndServerTime(const MqlDateTime &currentNyTime)
{
      MqlDateTime nextNyOpen = currentNyTime;
      nextNyOpen.hour = InpOpeningRangeHour;
      nextNyOpen.min  = InpOpeningRangeMinute;
      nextNyOpen.sec  = 0;

      datetime nextNyOpenLocal = StructToTime(nextNyOpen);
      if(MinutesFromDayStart(currentNyTime) >= OpeningRangeEndMinutes())
            nextNyOpenLocal += 24 * 60 * 60;

      TimeToStruct(nextNyOpenLocal, nextNyOpen);
      return NewYorkLocalToServerTime(nextNyOpen) + OpeningRangeSeconds();
}

int GetNyDayKey(const datetime serverTime)
{
      MqlDateTime nyTime;
      TimeToStruct(ServerToNewYorkTime(serverTime), nyTime);
      return NyDayKeyFromStruct(nyTime);
}

datetime ServerToNewYorkTime(const datetime serverTime)
{
      const datetime utcTime           = ServerToUtcTime(serverTime);
      const int      nyUtcOffsetHours  = GetNewYorkUtcOffsetHours(utcTime);
      return utcTime + (nyUtcOffsetHours * 60 * 60);
}

datetime NewYorkLocalToServerTime(const MqlDateTime &nyLocalTime)
{
      const datetime nyLocalTimestamp = StructToTime(nyLocalTime);
      const datetime utcGuess         = nyLocalTimestamp + (5 * 60 * 60);
      const int      nyUtcOffsetHours = GetNewYorkUtcOffsetHours(utcGuess);
      const datetime utcTime          = nyLocalTimestamp - (nyUtcOffsetHours * 60 * 60);
      const int      brokerOffset     = GetBrokerUtcOffsetHoursFromUtc(utcTime);

      return utcTime + (brokerOffset * 60 * 60);
}

datetime ServerToUtcTime(const datetime serverTime)
{
      const int brokerUtcOffsetHours = GetBrokerUtcOffsetHours(serverTime);
      return serverTime - (brokerUtcOffsetHours * 60 * 60);
}

int GetNewYorkUtcOffsetHours(const datetime utcTime)
{
      MqlDateTime dt;
      TimeToStruct(utcTime, dt);

      MqlDateTime startDt;
      ZeroMemory(startDt);
      startDt.year = dt.year;
      startDt.mon  = 3;
      startDt.day  = NthWeekdayOfMonth(dt.year, 3, 0, 2);
      startDt.hour = 7;

      MqlDateTime endDt;
      ZeroMemory(endDt);
      endDt.year = dt.year;
      endDt.mon  = 11;
      endDt.day  = NthWeekdayOfMonth(dt.year, 11, 0, 1);
      endDt.hour = 6;

      const datetime dstStartUtc = StructToTime(startDt);
      const datetime dstEndUtc   = StructToTime(endDt);

      if(utcTime >= dstStartUtc && utcTime < dstEndUtc)
            return -4;

      return -5;
}

int GetBrokerUtcOffsetHours(const datetime serverTime)
{
      if(!InpBrokerUsesEuropeanDst)
            return InpBrokerUtcOffsetWinter;

      if(IsEuropeanDstActive(serverTime))
            return InpBrokerUtcOffsetSummer;

      return InpBrokerUtcOffsetWinter;
}

int GetBrokerUtcOffsetHoursFromUtc(const datetime utcTime)
{
      if(!InpBrokerUsesEuropeanDst)
            return InpBrokerUtcOffsetWinter;

      const datetime brokerSummerLocalTime = utcTime + (InpBrokerUtcOffsetSummer * 60 * 60);
      if(IsEuropeanDstActive(brokerSummerLocalTime))
            return InpBrokerUtcOffsetSummer;

      return InpBrokerUtcOffsetWinter;
}

bool IsEuropeanDstActive(const datetime localBrokerTime)
{
      MqlDateTime dt;
      TimeToStruct(localBrokerTime, dt);

      MqlDateTime startDt;
      ZeroMemory(startDt);
      startDt.year = dt.year;
      startDt.mon  = 3;
      startDt.day  = LastWeekdayOfMonth(dt.year, 3, 0);
      startDt.hour = 3;

      MqlDateTime endDt;
      ZeroMemory(endDt);
      endDt.year = dt.year;
      endDt.mon  = 10;
      endDt.day  = LastWeekdayOfMonth(dt.year, 10, 0);
      endDt.hour = 3;

      const datetime dstStartLocal = StructToTime(startDt);
      const datetime dstEndLocal   = StructToTime(endDt);

      return (localBrokerTime >= dstStartLocal && localBrokerTime < dstEndLocal);
}

int NthWeekdayOfMonth(const int year,
                      const int month,
                      const int weekday,
                      const int occurrence)
{
      MqlDateTime firstDay;
      ZeroMemory(firstDay);
      firstDay.year = year;
      firstDay.mon  = month;
      firstDay.day  = 1;

      const datetime firstDate = StructToTime(firstDay);

      MqlDateTime firstInfo;
      TimeToStruct(firstDate, firstInfo);

      int dayOffset = weekday - firstInfo.day_of_week;
      if(dayOffset < 0)
            dayOffset += 7;

      return 1 + dayOffset + ((occurrence - 1) * 7);
}

int LastWeekdayOfMonth(const int year,
                       const int month,
                       const int weekday)
{
      MqlDateTime lastDay;
      ZeroMemory(lastDay);
      lastDay.year = year;
      lastDay.mon  = month + 1;
      lastDay.day  = 1;

      datetime firstNextMonth = StructToTime(lastDay);
      datetime lastDate       = firstNextMonth - 86400;

      MqlDateTime info;
      TimeToStruct(lastDate, info);

      int dayOffset = info.day_of_week - weekday;
      if(dayOffset < 0)
            dayOffset += 7;

      return info.day - dayOffset;
}

int MinutesBetweenSessionMarks()
{
      const int openMinutes = (InpOpeningRangeHour * 60) + InpOpeningRangeMinute;
      const int stopMinutes = (InpNoEntryTradeAfterHour * 60) + InpNoEntryTradeAfterMinute;
      return (stopMinutes - openMinutes);
}

double NormalizePrice(const double price)
{
      return NormalizeDouble(price, _Digits);
}

double GetMinimumStopDistancePrice()
{
      const long   stopsLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      const double brokerMinimum    = (double)stopsLevelPoints * _Point;
      return MathMax(brokerMinimum, _Point * 2.0);
}

bool IsAmbiguousProtectiveBar(const ENUM_POSITION_TYPE positionType,
                              const double stopPrice,
                              const double takeProfitPrice,
                              const datetime entryBarTime)
{
      if(!InpUseConservativeAmbiguousBarExit)
            return false;

      // Check current and last closed M5 bar.
      // The entry bar itself is ignored because the EA intentionally keeps
      // the same-bar virtual hold behavior and does not protect the entry bar.
      for(int shift = 0; shift <= 1; ++shift)
      {
            const datetime barTime = iTime(_Symbol, SIGNAL_TF, shift);
            if(barTime == 0 || barTime <= entryBarTime)
                  continue;

            const double barHigh = iHigh(_Symbol, SIGNAL_TF, shift);
            const double barLow  = iLow(_Symbol, SIGNAL_TF, shift);

            bool stopHit = false;
            bool tpHit   = false;

            if(positionType == POSITION_TYPE_BUY)
            {
                  stopHit = (barLow <= stopPrice);
                  tpHit   = (barHigh >= takeProfitPrice);
            }
            else
            {
                  stopHit = (barHigh >= stopPrice);
                  tpHit   = (barLow <= takeProfitPrice);
            }

            if(stopHit && tpHit)
                  return true;
      }

      return false;
}

bool HasReachedProtectiveLevel(const ENUM_POSITION_TYPE positionType,
                               const double stopPrice,
                               const double takeProfitPrice)
{
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(positionType == POSITION_TYPE_BUY)
            return (bid <= stopPrice || bid >= takeProfitPrice);

      return (ask >= stopPrice || ask <= takeProfitPrice);
}

bool CanPlaceProtectiveStopsNow(const ENUM_POSITION_TYPE positionType,
                                const double stopPrice,
                                const double takeProfitPrice)
{
      const double minimumDistance = GetMinimumStopDistancePrice();
      const double bid             = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask             = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(positionType == POSITION_TYPE_BUY)
      {
            if((bid - stopPrice)       < minimumDistance) return false;
            if((takeProfitPrice - bid) < minimumDistance) return false;
            return true;
      }

      if((stopPrice - ask)       < minimumDistance) return false;
      if((ask - takeProfitPrice) < minimumDistance) return false;

      return true;
}

// +------------------------------------------------------------------+
// | Monatsfilter-Hilfsfunktionen                                     |
// +------------------------------------------------------------------+

bool IsLongAllowedInMonth(const int month)
{
      switch(month)
      {
            case 1:  return InpLongMonthJan;
            case 2:  return InpLongMonthFeb;
            case 3:  return InpLongMonthMar;
            case 4:  return InpLongMonthApr;
            case 5:  return InpLongMonthMay;
            case 6:  return InpLongMonthJun;
            case 7:  return InpLongMonthJul;
            case 8:  return InpLongMonthAug;
            case 9:  return InpLongMonthSep;
            case 10: return InpLongMonthOct;
            case 11: return InpLongMonthNov;
            case 12: return InpLongMonthDec;
      }
      return true;
}

bool IsShortAllowedInMonth(const int month)
{
      switch(month)
      {
            case 1:  return InpShortMonthJan;
            case 2:  return InpShortMonthFeb;
            case 3:  return InpShortMonthMar;
            case 4:  return InpShortMonthApr;
            case 5:  return InpShortMonthMay;
            case 6:  return InpShortMonthJun;
            case 7:  return InpShortMonthJul;
            case 8:  return InpShortMonthAug;
            case 9:  return InpShortMonthSep;
            case 10: return InpShortMonthOct;
            case 11: return InpShortMonthNov;
            case 12: return InpShortMonthDec;
      }
      return true;
}
