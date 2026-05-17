//+------------------------------------------------------------------+
//| TT_ORB_2026_15M_volume_v001.mq5                                 |
//| 15-minute Opening Range Breakout for USTec / Nasdaq100 CFD      |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1.0"
#property description "Opening Range Breakout EA with volume filter, virtual same-bar hold, ATR break-even and lot sizing modes."

#include <Trade/Trade.mqh>

input group "General"
input bool   InpTradingEnabled             = true;
input ulong  InpMagicNumber                = 202615001;
input string InpTradeComment               = "TT_ORB_2026_15M_volume_v001";
input int    InpMaxTradesPerDay            = 1;
input bool   InpVerboseLogging             = false;

input group "Session Rules (New York Time)"
input int    InpOpeningRangeHour           = 9;
input int    InpOpeningRangeMinute         = 30;
input int    InpOpeningRangeMinutes        = 15;
input int    InpNoTradeAfterHour           = 11;
input int    InpNoTradeAfterMinute         = 30;
input bool   InpBrokerUsesEuropeanDst      = true;
input int    InpBrokerUtcOffsetWinter      = 1;
input int    InpBrokerUtcOffsetSummer      = 2;

input group "Entry Rules"
input bool   InpEnableLongTrades           = true;
input bool   InpEnableShortTrades          = true;
input bool   InpEnableVolumeFilter         = true;
input double InpVolumeMultiplier           = 1.50;
input int    InpVolumeAveragePeriod        = 20;
input bool   InpRequireCloseBeyondRange    = true;

input group "Risk & Position Size"
input bool   InpUseDynamicLotSize          = true;
input double InpFixedLotSize               = 0.10;
input double InpRiskPercent                = 1.00;
input double InpTakeProfitRMultiple        = 2.00;

input group "Break Even"
input bool   InpEnableBreakEven            = true;
input int    InpAtrPeriod                  = 14;
input double InpBreakEvenAtrMultiple       = 1.00;
input double InpBreakEvenOffsetPrice       = 0.05;

input group "Visuals"
input color  InpOpeningRangeColor          = clrDodgerBlue;
input color  InpTradeWindowColor           = clrPaleGreen;
input bool   InpDrawRectanglesInBackground = true;
input int    InpRectangleLineWidth         = 1;

static const ENUM_TIMEFRAMES SIGNAL_TF = PERIOD_M15;

CTrade trade;

double   g_orHigh            = 0.0;
double   g_orLow             = 0.0;
datetime g_orBarTime         = 0;
datetime g_orEndTime         = 0;
datetime g_tradeCutoffTime   = 0;
int      g_orDayKey          = 0;
int      g_tradesToday       = 0;
datetime g_lastProcessedBar  = 0;
int      g_atrHandle         = INVALID_HANDLE;
bool     g_tradingDisabledLogged = false;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_atrHandle = iATR(_Symbol, SIGNAL_TF, InpAtrPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("ATR handle konnte nicht erstellt werden.");
      return INIT_FAILED;
   }

   RefreshSessionState();
   DrawSessionRectangles();

   Print("TT_ORB_2026_15M_volume_v001 initialisiert fuer ", _Symbol,
         ". Session basiert auf New-York-Zeit mit US-DST. Broker UTC Winter=",
         InpBrokerUtcOffsetWinter,
         " Sommer=",
         InpBrokerUtcOffsetSummer,
         " EuropeanDST=",
         InpBrokerUsesEuropeanDst);

   if(!InpTradingEnabled)
      Print("Trading ist deaktiviert. Fuer Backtests bitte InpTradingEnabled auf true setzen.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   Print("TT_ORB_2026_15M_volume_v001 beendet. Reason=", reason);
}

void OnTick()
{
   ManageOpenPosition();

   datetime currentBarTime = iTime(_Symbol, SIGNAL_TF, 0);
   if(currentBarTime == 0 || currentBarTime == g_lastProcessedBar)
      return;

   g_lastProcessedBar = currentBarTime;
   RefreshSessionState();
   DrawSessionRectangles();

   if(!InpTradingEnabled)
   {
      if(!g_tradingDisabledLogged)
      {
         Print("Trading ist deaktiviert. Keine Entries werden ausgefuehrt.");
         g_tradingDisabledLogged = true;
      }
      return;
   }

   if(HasManagedPosition())
      return;

   if(!HasValidOpeningRange())
      return;

   if(g_tradesToday >= InpMaxTradesPerDay)
      return;

   if(currentBarTime < g_orEndTime || currentBarTime > g_tradeCutoffTime)
      return;

   EvaluateEntrySignal();
}

void RefreshSessionState()
{
   const datetime serverNow = TimeTradeServer();
   const int todayNyKey = GetNyDayKey(serverNow);

   if(todayNyKey != g_orDayKey || !HasValidOpeningRange())
   {
      LoadTodayOpeningRange(todayNyKey);
      g_tradesToday = CountTradesForNyDay(todayNyKey);
   }
}

void LoadTodayOpeningRange(const int targetNyDayKey)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   const int copied = CopyRates(_Symbol, SIGNAL_TF, 0, 400, rates);
   if(copied <= 0)
      return;

   g_orHigh = 0.0;
   g_orLow = 0.0;
   g_orBarTime = 0;
   g_orEndTime = 0;
   g_tradeCutoffTime = 0;
   g_orDayKey = targetNyDayKey;

   for(int i = copied - 1; i >= 0; --i)
   {
      if(GetNyDayKey(rates[i].time) != targetNyDayKey)
         continue;

      if(!IsOpeningRangeBar(rates[i].time))
         continue;

      g_orHigh = rates[i].high;
      g_orLow = rates[i].low;
      g_orBarTime = rates[i].time;
      g_orEndTime = g_orBarTime + InpOpeningRangeMinutes * 60;
      g_tradeCutoffTime = g_orBarTime + MinutesBetweenSessionMarks() * 60;

      if(InpVerboseLogging)
      {
         PrintFormat("Opening Range geladen fuer %d: Bar=%s High=%.2f Low=%.2f Cutoff=%s",
                     targetNyDayKey,
                     TimeToString(g_orBarTime, TIME_DATE | TIME_MINUTES),
                     g_orHigh,
                     g_orLow,
                     TimeToString(g_tradeCutoffTime, TIME_DATE | TIME_MINUTES));
      }
   }
}

void DrawSessionRectangles()
{
   if(!HasValidOpeningRange())
      return;

   const string daySuffix = IntegerToString(g_orDayKey);
   const string orName = "TT_OR_ORANGE_" + daySuffix;
   const string twName = "TT_OR_TRADEWINDOW_" + daySuffix;

   DrawRectangle(orName,
                 g_orBarTime,
                 g_orHigh,
                 g_orEndTime,
                 g_orLow,
                 InpOpeningRangeColor);

   DrawRectangle(twName,
                 g_orEndTime,
                 g_orHigh,
                 g_tradeCutoffTime,
                 g_orLow,
                 InpTradeWindowColor);
}

void DrawRectangle(const string name,
                   const datetime time1,
                   const double price1,
                   const datetime time2,
                   const double price2,
                   const color rectColor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
   else
      ObjectMove(0, name, 0, time1, price1);

   ObjectMove(0, name, 1, time2, price2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, rectColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpRectangleLineWidth);
   ObjectSetInteger(0, name, OBJPROP_BACK, InpDrawRectanglesInBackground);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

void EvaluateEntrySignal()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   const int barsNeeded = InpVolumeAveragePeriod + 5;
   const int copied = CopyRates(_Symbol, SIGNAL_TF, 0, barsNeeded, rates);
   if(copied <= InpVolumeAveragePeriod + 1)
      return;

   const MqlRates signalBar = rates[1];
   if(GetNyDayKey(signalBar.time) != g_orDayKey)
      return;

   if(signalBar.time < g_orEndTime || signalBar.time >= g_tradeCutoffTime)
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

   bool longSignal = signalBar.high > g_orHigh;
   bool shortSignal = signalBar.low < g_orLow;

   if(InpRequireCloseBeyondRange)
   {
      longSignal = longSignal && signalBar.close > g_orHigh;
      shortSignal = shortSignal && signalBar.close < g_orLow;
   }

   if(!InpEnableLongTrades)
      longSignal = false;

   if(!InpEnableShortTrades)
      shortSignal = false;

   if(longSignal == shortSignal)
      return;

    if(InpVerboseLogging)
    {
       PrintFormat("Signal erkannt %s | Bar=%s High=%.2f Low=%.2f Close=%.2f TickVol=%I64d AvgVol=%.2f ORHigh=%.2f ORLow=%.2f",
                   longSignal ? "LONG" : "SHORT",
                   TimeToString(signalBar.time, TIME_DATE | TIME_MINUTES),
                   signalBar.high,
                   signalBar.low,
                   signalBar.close,
                   signalBar.tick_volume,
                   averageVolume,
                   g_orHigh,
                   g_orLow);
    }

   const ENUM_ORDER_TYPE orderType = longSignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double referencePrice = (orderType == ORDER_TYPE_BUY)
                               ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double stopPrice = (orderType == ORDER_TYPE_BUY) ? g_orLow : g_orHigh;

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
   Print("Trade eroeffnet: ", EnumToString(orderType),
         " Vol=", DoubleToString(volume, 2),
         " OR High=", DoubleToString(g_orHigh, _Digits),
         " OR Low=", DoubleToString(g_orLow, _Digits));
}

void ManageOpenPosition()
{
   if(!SelectManagedPosition())
      return;

   const ENUM_POSITION_TYPE positionType =
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   const double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   const datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
   const datetime entryBarTime = GetBarOpenTime(entryTime);
   const datetime currentBarTime = iTime(_Symbol, SIGNAL_TF, 0);

   if(entryBarTime == 0 || currentBarTime <= entryBarTime)
      return;

   if(!HasValidOpeningRange())
      return;

   const double initialSl = (positionType == POSITION_TYPE_BUY) ? g_orLow : g_orHigh;
   if(!IsValidRiskDistance(entryPrice, initialSl))
      return;

   double activeSl = NormalizePrice(initialSl);
   const double activeTp = NormalizePrice(GetTakeProfitForPosition(positionType, entryPrice, initialSl));

   if(InpEnableBreakEven)
   {
      double atrValue = 0.0;
      if(GetAtrValue(atrValue))
      {
         const double triggerDistance = atrValue * InpBreakEvenAtrMultiple;
         const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         const double marketPrice = (positionType == POSITION_TYPE_BUY) ? bid : ask;
         const double profitDistance = (positionType == POSITION_TYPE_BUY)
                                     ? marketPrice - entryPrice
                                     : entryPrice - marketPrice;

         if(triggerDistance > 0.0 && profitDistance >= triggerDistance)
         {
            const double desiredBeSl = (positionType == POSITION_TYPE_BUY)
                                     ? entryPrice + InpBreakEvenOffsetPrice
                                     : entryPrice - InpBreakEvenOffsetPrice;

            if(positionType == POSITION_TYPE_BUY)
               activeSl = NormalizePrice(MathMax(activeSl, desiredBeSl));
            else
               activeSl = NormalizePrice(MathMin(activeSl, desiredBeSl));
         }
      }
   }

   if(HasReachedProtectiveLevel(positionType, activeSl, activeTp))
   {
      if(!trade.PositionClose(_Symbol))
      {
         Print("Virtueller Exit fehlgeschlagen. Retcode=", trade.ResultRetcode(),
               " Beschreibung=", trade.ResultRetcodeDescription());
      }
      return;
   }

   if(!CanPlaceProtectiveStopsNow(positionType, activeSl, activeTp))
      return;

   const double currentSl = PositionGetDouble(POSITION_SL);
   const double currentTp = PositionGetDouble(POSITION_TP);

   if(MathAbs(currentSl - activeSl) < (_Point * 0.5) &&
      MathAbs(currentTp - activeTp) < (_Point * 0.5))
      return;

   if(!trade.PositionModify(_Symbol, activeSl, activeTp))
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

   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   const double riskAmount = balance * (InpRiskPercent / 100.0);
   if(riskAmount <= 0.0)
      return 0.0;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
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
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = 0.01;

   double bounded = MathMax(minVolume, MathMin(maxVolume, requestedVolume));
   double steps = MathFloor((bounded - minVolume) / step + 1e-8);
   double normalized = minVolume + (steps * step);

   normalized = MathMax(minVolume, MathMin(maxVolume, normalized));
   return normalized;
}

double GetAverageTickVolume(const MqlRates &rates[],
                            const int startIndex,
                            const int numberOfBars)
{
   double total = 0.0;
   int count = 0;

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

int CountTradesForNyDay(const int nyDayKey)
{
   const datetime fromTime = TimeTradeServer() - (10 * 24 * 60 * 60);
   const datetime toTime = TimeTradeServer();

   if(!HistorySelect(fromTime, toTime))
      return 0;

   int trades = 0;
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

      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      const datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      if(GetNyDayKey(dealTime) == nyDayKey)
         ++trades;
   }

   return trades;
}

bool IsOpeningRangeBar(const datetime serverBarTime)
{
   MqlDateTime nyTime;
   TimeToStruct(ServerToNewYorkTime(serverBarTime), nyTime);

   return (nyTime.hour == InpOpeningRangeHour && nyTime.min == InpOpeningRangeMinute);
}

int GetNyDayKey(const datetime serverTime)
{
   MqlDateTime nyTime;
   TimeToStruct(ServerToNewYorkTime(serverTime), nyTime);
   return (nyTime.year * 10000) + (nyTime.mon * 100) + nyTime.day;
}

datetime ServerToNewYorkTime(const datetime serverTime)
{
   const datetime utcTime = ServerToUtcTime(serverTime);
   const int nyUtcOffsetHours = GetNewYorkUtcOffsetHours(utcTime);
   return utcTime + (nyUtcOffsetHours * 60 * 60);
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
   startDt.mon = 3;
   startDt.day = NthWeekdayOfMonth(dt.year, 3, 0, 2);
   startDt.hour = 7;

   MqlDateTime endDt;
   ZeroMemory(endDt);
   endDt.year = dt.year;
   endDt.mon = 11;
   endDt.day = NthWeekdayOfMonth(dt.year, 11, 0, 1);
   endDt.hour = 6;

   const datetime dstStartUtc = StructToTime(startDt);
   const datetime dstEndUtc = StructToTime(endDt);

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

bool IsEuropeanDstActive(const datetime localBrokerTime)
{
   MqlDateTime dt;
   TimeToStruct(localBrokerTime, dt);

   MqlDateTime startDt;
   ZeroMemory(startDt);
   startDt.year = dt.year;
   startDt.mon = 3;
   startDt.day = LastWeekdayOfMonth(dt.year, 3, 0);
   startDt.hour = 3;

   MqlDateTime endDt;
   ZeroMemory(endDt);
   endDt.year = dt.year;
   endDt.mon = 10;
   endDt.day = LastWeekdayOfMonth(dt.year, 10, 0);
   endDt.hour = 3;

   const datetime dstStartLocal = StructToTime(startDt);
   const datetime dstEndLocal = StructToTime(endDt);

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
   firstDay.mon = month;
   firstDay.day = 1;

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
   lastDay.mon = month + 1;
   lastDay.day = 1;

   datetime firstNextMonth = StructToTime(lastDay);
   datetime lastDate = firstNextMonth - 86400;

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
   const int stopMinutes = (InpNoTradeAfterHour * 60) + InpNoTradeAfterMinute;
   return (stopMinutes - openMinutes);
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, _Digits);
}

double GetMinimumStopDistancePrice()
{
   const long stopsLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double brokerMinimum = (double)stopsLevelPoints * _Point;
   return MathMax(brokerMinimum, _Point * 2.0);
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
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(positionType == POSITION_TYPE_BUY)
   {
      if((bid - stopPrice) < minimumDistance)
         return false;

      if((takeProfitPrice - bid) < minimumDistance)
         return false;

      return true;
   }

   if((stopPrice - ask) < minimumDistance)
      return false;

   if((ask - takeProfitPrice) < minimumDistance)
      return false;

   return true;
}
