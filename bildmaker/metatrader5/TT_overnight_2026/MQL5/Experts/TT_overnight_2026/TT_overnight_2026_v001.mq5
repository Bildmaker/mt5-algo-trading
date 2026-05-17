//+------------------------------------------------------------------+
//| TT_overnight_2026_v001.mq5                                      |
//| Simple time-based overnight and intraday holding EA              |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1.0"
#property description "Simple Berlin-time overnight/intraday EA with US DST compensation and even/odd day filters."

#include <Trade/Trade.mqh>

input group "General"
input bool   InpTradingEnabled             = true;
input ulong  InpMagicNumber                = 202620001;
input string InpTradeCommentPrefix         = "TT_overnight_2026_v001";
input double InpFixedLotSize               = 0.20;
input bool   InpVerboseLogging             = false;

input group "Session Rules (Berlin Time)"
input bool   InpEnableOvernightMode        = true;
input int    InpOvernightEntryHour         = 22;
input int    InpOvernightEntryMinute       = 0;
input int    InpOvernightExitHour          = 8;
input int    InpOvernightExitMinute        = 0;
input bool   InpEnableIntradayMode         = false;
input int    InpIntradayEntryHour          = 15;
input int    InpIntradayEntryMinute        = 30;
input int    InpIntradayExitHour           = 22;
input int    InpIntradayExitMinute         = 0;
input bool   InpCompensateUsDstGap         = false;

input group "Broker Time Conversion"
input bool   InpBrokerUsesEuropeanDst      = true;
input int    InpBrokerUtcOffsetWinter      = 1;
input int    InpBrokerUtcOffsetSummer      = 2;

input group "Direction"
input bool   InpEnableLongTrades           = true;
input bool   InpEnableShortTrades          = false;

input group "Day Filter"
input bool   InpTradeEvenDays              = true;
input bool   InpTradeOddDays               = true;

CTrade trade;

bool g_loggedTradingDisabled = false;
bool g_isHedgingAccount = false;
int  g_lastOvernightEntryKey = 0;
int  g_lastOvernightExitKey = 0;
int  g_lastIntradayEntryKey = 0;
int  g_lastIntradayExitKey = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   const long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_isHedgingAccount = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   Print("TT_overnight_2026_v001 initialisiert fuer ", _Symbol,
         ". Berlin-Zeit aktiv, US-DST-Kompensation=",
         InpCompensateUsDstGap,
         ", HedgingAccount=",
         g_isHedgingAccount);

   if(!g_isHedgingAccount && InpEnableLongTrades && InpEnableShortTrades)
      Print("Hinweis: Long und Short sind beide aktiv, aber das Konto ist kein Hedging-Konto. Gegenseitige Positionen koennen nicht parallel gehalten werden.");

   if(!InpTradingEnabled)
      Print("Trading ist deaktiviert. Es werden keine Orders ausgefuehrt.");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!InpTradingEnabled)
   {
      if(!g_loggedTradingDisabled)
      {
         Print("Trading ist deaktiviert. Keine Entries oder Exits werden ausgefuehrt.");
         g_loggedTradingDisabled = true;
      }
      return;
   }

   const datetime serverNow = TimeTradeServer();
   if(serverNow == 0)
      return;

   const datetime berlinNow = ServerToBerlinTime(serverNow);

   ProcessOvernightExit(berlinNow);
   ProcessIntradayEntry(berlinNow);
   ProcessIntradayExit(berlinNow);
   ProcessOvernightEntry(berlinNow);
}

void ProcessOvernightEntry(const datetime berlinNow)
{
   if(!InpEnableOvernightMode)
      return;

   const int dayKey = GetDayKey(berlinNow);
   if(g_lastOvernightEntryKey == dayKey)
      return;

   if(GetMinuteOfDay(berlinNow) != GetAdjustedMinuteOfDay(InpOvernightEntryHour, InpOvernightEntryMinute, berlinNow))
      return;

   g_lastOvernightEntryKey = dayKey;

   if(!IsEntryDayAllowed(berlinNow))
   {
      LogVerbose("Overnight-Entry wegen Day-Filter uebersprungen.");
      return;
   }

   OpenModePositions("OVN");
}

void ProcessOvernightExit(const datetime berlinNow)
{
   if(!InpEnableOvernightMode)
      return;

   const int dayKey = GetDayKey(berlinNow);
   if(g_lastOvernightExitKey == dayKey)
      return;

   if(GetMinuteOfDay(berlinNow) != GetAdjustedMinuteOfDay(InpOvernightExitHour, InpOvernightExitMinute, berlinNow))
      return;

   g_lastOvernightExitKey = dayKey;
   CloseModePositions("OVN");
}

void ProcessIntradayEntry(const datetime berlinNow)
{
   if(!InpEnableIntradayMode)
      return;

   const int dayKey = GetDayKey(berlinNow);
   if(g_lastIntradayEntryKey == dayKey)
      return;

   if(GetMinuteOfDay(berlinNow) != GetAdjustedMinuteOfDay(InpIntradayEntryHour, InpIntradayEntryMinute, berlinNow))
      return;

   g_lastIntradayEntryKey = dayKey;

   if(!IsEntryDayAllowed(berlinNow))
   {
      LogVerbose("Intraday-Entry wegen Day-Filter uebersprungen.");
      return;
   }

   OpenModePositions("DAY");
}

void ProcessIntradayExit(const datetime berlinNow)
{
   if(!InpEnableIntradayMode)
      return;

   const int dayKey = GetDayKey(berlinNow);
   if(g_lastIntradayExitKey == dayKey)
      return;

   if(GetMinuteOfDay(berlinNow) != GetAdjustedMinuteOfDay(InpIntradayExitHour, InpIntradayExitMinute, berlinNow))
      return;

   g_lastIntradayExitKey = dayKey;
   CloseModePositions("DAY");
}

void OpenModePositions(const string modeTag)
{
   if(!InpEnableLongTrades && !InpEnableShortTrades)
   {
      Print("Keine Richtung aktiviert. Weder Long noch Short ist eingeschaltet.");
      return;
   }

   if(InpEnableLongTrades)
      OpenDirectionForMode(modeTag, POSITION_TYPE_BUY);

   if(InpEnableShortTrades)
      OpenDirectionForMode(modeTag, POSITION_TYPE_SELL);
}

void OpenDirectionForMode(const string modeTag, const ENUM_POSITION_TYPE positionType)
{
   if(ModeDirectionPositionExists(modeTag, positionType))
   {
      LogVerbose("Position existiert bereits fuer " + modeTag + " / " + PositionTypeToText(positionType));
      return;
   }

   if(!g_isHedgingAccount && HasAnyManagedPosition())
   {
      Print("Netting-Konto: weitere Position fuer ", modeTag,
            " / ", PositionTypeToText(positionType),
            " wird uebersprungen, da bereits eine gemanagte Position offen ist.");
      return;
   }

   const double volume = NormalizeVolume(InpFixedLotSize);
   if(volume <= 0.0)
   {
      Print("Ungueltige Lotgroesse fuer ", modeTag, " / ", PositionTypeToText(positionType));
      return;
   }

   const string comment = BuildPositionComment(modeTag, positionType);
   bool sent = false;

   if(positionType == POSITION_TYPE_BUY)
      sent = trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, comment);

   if(!sent)
   {
      Print("OrderSend fehlgeschlagen fuer ", comment,
            ". Retcode=", trade.ResultRetcode(),
            " Beschreibung=", trade.ResultRetcodeDescription());
      return;
   }

   Print("Position eroeffnet: ", comment, " Vol=", DoubleToString(volume, 2));
}

void CloseModePositions(const string modeTag)
{
   int closed = 0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPosition())
         continue;

      const string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "|" + modeTag + "|") < 0)
         continue;

      if(!trade.PositionClose(ticket))
      {
         Print("PositionClose fehlgeschlagen fuer Ticket ", ticket,
               ". Retcode=", trade.ResultRetcode(),
               " Beschreibung=", trade.ResultRetcodeDescription());
         continue;
      }

      ++closed;
   }

   if(closed > 0 || InpVerboseLogging)
      Print("CloseModePositions(", modeTag, ") -> ", closed, " Position(en) geschlossen.");
}

bool ModeDirectionPositionExists(const string modeTag, const ENUM_POSITION_TYPE positionType)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPosition())
         continue;

      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != positionType)
         continue;

      const string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "|" + modeTag + "|") >= 0)
         return true;
   }

   return false;
}

bool HasAnyManagedPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(IsManagedPosition())
         return true;
   }

   return false;
}

bool IsManagedPosition()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;

   return ((ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

bool IsEntryDayAllowed(const datetime berlinNow)
{
   if(InpTradeEvenDays && InpTradeOddDays)
      return true;

   if(!InpTradeEvenDays && !InpTradeOddDays)
      return false;

   MqlDateTime dt;
   TimeToStruct(berlinNow, dt);

   const bool isEvenDay = ((dt.day % 2) == 0);
   if(isEvenDay)
      return InpTradeEvenDays;

   return InpTradeOddDays;
}

string BuildPositionComment(const string modeTag, const ENUM_POSITION_TYPE positionType)
{
   return InpTradeCommentPrefix + "|" + modeTag + "|" + PositionTypeToText(positionType);
}

string PositionTypeToText(const ENUM_POSITION_TYPE positionType)
{
   if(positionType == POSITION_TYPE_BUY)
      return "BUY";

   return "SELL";
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

int GetAdjustedMinuteOfDay(const int baseHour,
                           const int baseMinute,
                           const datetime berlinNow)
{
   int minuteOfDay = (baseHour * 60) + baseMinute;

   if(InpCompensateUsDstGap && IsUsEuropeDstGapActive(berlinNow))
      minuteOfDay -= 60;

   while(minuteOfDay < 0)
      minuteOfDay += 1440;

   while(minuteOfDay >= 1440)
      minuteOfDay -= 1440;

   return minuteOfDay;
}

int GetMinuteOfDay(const datetime localTime)
{
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   return (dt.hour * 60) + dt.min;
}

int GetDayKey(const datetime localTime)
{
   MqlDateTime dt;
   TimeToStruct(localTime, dt);
   return (dt.year * 10000) + (dt.mon * 100) + dt.day;
}

datetime ServerToBerlinTime(const datetime serverTime)
{
   const datetime utcTime = ServerToUtcTime(serverTime);
   return UtcToBerlinTime(utcTime);
}

datetime ServerToUtcTime(const datetime serverTime)
{
   const int brokerOffsetHours = GetBrokerUtcOffsetHours(serverTime);
   return serverTime - (brokerOffsetHours * 3600);
}

datetime UtcToBerlinTime(const datetime utcTime)
{
   const int berlinOffsetHours = IsEuropeanDstActiveUtc(utcTime) ? 2 : 1;
   return utcTime + (berlinOffsetHours * 3600);
}

datetime BerlinToUtcTime(const datetime berlinLocalTime)
{
   const int berlinOffsetHours = IsEuropeanDstActiveLocal(berlinLocalTime) ? 2 : 1;
   return berlinLocalTime - (berlinOffsetHours * 3600);
}

int GetBrokerUtcOffsetHours(const datetime serverTime)
{
   if(!InpBrokerUsesEuropeanDst)
      return InpBrokerUtcOffsetWinter;

   if(IsEuropeanDstActiveLocal(serverTime))
      return InpBrokerUtcOffsetSummer;

   return InpBrokerUtcOffsetWinter;
}

bool IsUsEuropeDstGapActive(const datetime berlinLocalTime)
{
   const datetime utcTime = BerlinToUtcTime(berlinLocalTime);
   return (IsUsDstActiveUtc(utcTime) != IsEuropeanDstActiveUtc(utcTime));
}

bool IsUsDstActiveUtc(const datetime utcTime)
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

   return (utcTime >= dstStartUtc && utcTime < dstEndUtc);
}

bool IsEuropeanDstActiveUtc(const datetime utcTime)
{
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);

   MqlDateTime startDt;
   ZeroMemory(startDt);
   startDt.year = dt.year;
   startDt.mon = 3;
   startDt.day = LastWeekdayOfMonth(dt.year, 3, 0);
   startDt.hour = 1;

   MqlDateTime endDt;
   ZeroMemory(endDt);
   endDt.year = dt.year;
   endDt.mon = 10;
   endDt.day = LastWeekdayOfMonth(dt.year, 10, 0);
   endDt.hour = 1;

   const datetime dstStartUtc = StructToTime(startDt);
   const datetime dstEndUtc = StructToTime(endDt);

   return (utcTime >= dstStartUtc && utcTime < dstEndUtc);
}

bool IsEuropeanDstActiveLocal(const datetime localTime)
{
   MqlDateTime dt;
   TimeToStruct(localTime, dt);

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

   return (localTime >= dstStartLocal && localTime < dstEndLocal);
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
   MqlDateTime firstOfNextMonth;
   ZeroMemory(firstOfNextMonth);
   firstOfNextMonth.year = (month == 12) ? (year + 1) : year;
   firstOfNextMonth.mon = (month == 12) ? 1 : (month + 1);
   firstOfNextMonth.day = 1;

   const datetime firstNextMonth = StructToTime(firstOfNextMonth);
   const datetime lastDate = firstNextMonth - 86400;

   MqlDateTime info;
   TimeToStruct(lastDate, info);

   int dayOffset = info.day_of_week - weekday;
   if(dayOffset < 0)
      dayOffset += 7;

   return info.day - dayOffset;
}

void LogVerbose(const string text)
{
   if(InpVerboseLogging)
      Print(text);
}
