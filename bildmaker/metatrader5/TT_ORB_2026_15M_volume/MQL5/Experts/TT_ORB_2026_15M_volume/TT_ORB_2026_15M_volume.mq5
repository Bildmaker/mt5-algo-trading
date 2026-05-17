//+------------------------------------------------------------------+
//| TT_ORB_2026_15M_volume.mq5                                      |
//| Opening Range Breakout EA skeleton for MetaTrader 5              |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1.0"
#property description "15M Opening Range Breakout EA skeleton with volume-filter placeholders."

#include <Trade/Trade.mqh>

input bool            InpTradingEnabled   = false;
input ulong           InpMagicNumber      = 20261501;
input ENUM_TIMEFRAMES InpSignalTimeframe  = PERIOD_M15;
input double          InpLots             = 0.10;
input int             InpOpeningMinutes   = 15;
input double          InpVolumeMultiplier = 1.50;

CTrade trade;
datetime g_lastBarTime = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);

   if(InpSignalTimeframe != PERIOD_M15)
      Print("Hinweis: Dieser EA ist fuer M15 geplant. Aktueller Signal-Timeframe: ", EnumToString(InpSignalTimeframe));

   Print("TT_ORB_2026_15M_volume initialisiert. TradingEnabled=", InpTradingEnabled);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Print("TT_ORB_2026_15M_volume beendet. Reason=", reason);
}

void OnTick()
{
   if(!IsNewSignalBar())
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   const int copied = CopyRates(_Symbol, InpSignalTimeframe, 0, 20, rates);
   if(copied < 2)
   {
      Print("Nicht genug Kursdaten fuer ", _Symbol, " auf ", EnumToString(InpSignalTimeframe));
      return;
   }

   // TODO: Opening Range fuer die definierte Session berechnen.
   // TODO: Volumenfilter gegen historischen Durchschnitt pruefen.
   // TODO: Breakout-Entry, Stop, Take-Profit und Risikoregeln implementieren.
   // TODO: Tageslimit und Positionsmanagement absichern.
   PrintFormat("Neue M15-Bar: %s Close=%.5f TickVolume=%I64d",
               TimeToString(rates[0].time, TIME_DATE | TIME_MINUTES),
               rates[0].close,
               rates[0].tick_volume);
}

bool IsNewSignalBar()
{
   datetime barTime = iTime(_Symbol, InpSignalTimeframe, 0);
   if(barTime == 0)
      return false;

   if(barTime == g_lastBarTime)
      return false;

   g_lastBarTime = barTime;
   return true;
}

