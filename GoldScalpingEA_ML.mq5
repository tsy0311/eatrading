//+------------------------------------------------------------------+
//|                                           GoldScalpingEA_ML.mq5  |
//|                    v6.0 - Optimized for 5X Returns               |
//|          ML Regime + Compounding + Aggressive Profit Taking      |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping ML System v6.0 - 5X Target"
#property version   "6.00"
#property description "ML Regime Adaptive + Compounding for 5X returns"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| REGIME DEFINITIONS                                                |
//+------------------------------------------------------------------+
#define REGIME_RANGING   0   // Mean-reversion, tight stops
#define REGIME_TRENDING  1   // Trend following, let profits run
#define REGIME_VOLATILE  2   // High volatility, be cautious

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS ==="
input double   BaseLotSize = 0.2;          // Base Lot Size (increased)
input int      MaxPositions = 3;           // Max positions
input int      MagicNumber = 12345;        // Magic Number

input group "=== COMPOUNDING (5X TARGET) ==="
input bool     EnableCompounding = true;   // Auto-increase lot with profit
input double   CompoundPercent = 2.0;      // Risk % of balance per trade
input double   MaxLotSize = 2.0;           // Maximum lot size cap
input double   MinLotSize = 0.1;           // Minimum lot size

input group "=== PROFIT TARGETS ==="
input double   DailyProfitTarget = 3.0;    // Daily profit target %
input double   WeeklyProfitTarget = 10.0;  // Weekly profit target %
input bool     ReduceAfterTarget = true;   // Reduce lot after hitting target
input double   TargetReduction = 0.5;      // Reduce to 50% lot after target

input group "=== ML REGIME DETECTION ==="
input bool     UseMLRegime = true;         // Use ML regime detection
input int      RegimeUpdateBars = 5;       // Update regime every N bars

input group "=== RANGING REGIME (Optimized) ==="
input double   Range_ATR_SL = 0.8;         // Tight SL for ranging
input double   Range_ATR_TP = 1.2;         // Quick TP
input int      Range_TrailStart = 6;       // Fast trail
input int      Range_MinConf = 62;         // Good confidence

input group "=== TRENDING REGIME (Let Winners Run) ==="
input double   Trend_ATR_SL = 1.2;         // Moderate SL
input double   Trend_ATR_TP = 3.0;         // BIG TP - catch trends!
input int      Trend_TrailStart = 12;      // Let it breathe
input int      Trend_MinConf = 55;         // Lower threshold, more trades

input group "=== VOLATILE REGIME (Careful) ==="
input double   Volat_ATR_SL = 1.5;         // Wider SL
input double   Volat_ATR_TP = 2.0;         // Balanced TP
input int      Volat_TrailStart = 18;      // Wide trail
input int      Volat_MinConf = 72;         // Strict entry

input group "=== EARLY EXIT ==="
input bool     EnableEarlyExit = true;
input int      CutLossPips = -12;          // Tighter cut loss
input int      BreakevenPips = 10;         // Faster BE
input bool     ExitOnWeakSignal = true;

input group "=== TRAILING STOP ==="
input bool     EnableTrailing = true;
input int      TrailingStep = 4;           // Tighter trail
input bool     UseATRTrailing = true;

input group "=== INDICATORS ==="
input int      EMA_Fast = 8;               // Faster EMA
input int      EMA_Medium = 21;
input int      EMA_Slow = 50;
input int      RSI_Period = 14;
input int      ATR_Period = 14;
input int      ADX_Period = 14;

input group "=== TIME FILTER ==="
input bool     UseSessionFilter = true;    // Trade best sessions
input int      LondonStart = 7;            // London open
input int      NYStart = 13;               // NY open
input int      SessionEnd = 21;            // End trading
input bool     AvoidFriday = true;
input int      FridayCloseHour = 16;       // Close early Friday

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo posInfo;

int h_ema_fast, h_ema_medium, h_ema_slow;
int h_rsi, h_macd, h_atr, h_bb, h_stoch, h_adx;

// Regime state
int CurrentRegime = REGIME_RANGING;
double CurrentConfidence = 0;

// Dynamic settings
double Active_ATR_SL = 1.0;
double Active_ATR_TP = 2.0;
int Active_TrailStart = 12;
int Active_MinConf = 60;

// Tracking
double DayStartBalance = 0;
double WeekStartBalance = 0;
datetime LastDay = 0;
datetime LastWeek = 0;
bool DailyTargetHit = false;
bool WeeklyTargetHit = false;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   h_ema_fast = iMA(Symbol(), PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_medium = iMA(Symbol(), PERIOD_CURRENT, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow = iMA(Symbol(), PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_rsi = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   h_macd = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   h_atr = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   h_stoch = iStochastic(Symbol(), PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_bb = iBands(Symbol(), PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   h_adx = iADX(Symbol(), PERIOD_CURRENT, ADX_Period);
   
   if(h_ema_fast == INVALID_HANDLE || h_rsi == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   WeekStartBalance = DayStartBalance;
   
   DetectRegime();
   ApplyRegimeSettings();
   
   Print("==================================================");
   Print("🚀 GOLD ML EA v6.0 - 5X PROFIT TARGET");
   Print("==================================================");
   Print("   Compounding: ", EnableCompounding ? "ON" : "OFF");
   Print("   Base Lot: ", DoubleToString(BaseLotSize, 2));
   Print("   Risk per Trade: ", DoubleToString(CompoundPercent, 1), "%");
   Print("   Daily Target: +", DoubleToString(DailyProfitTarget, 1), "%");
   Print("   Current Regime: ", GetRegimeName(CurrentRegime));
   Print("==================================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_ema_fast);
   IndicatorRelease(h_ema_medium);
   IndicatorRelease(h_ema_slow);
   IndicatorRelease(h_rsi);
   IndicatorRelease(h_macd);
   IndicatorRelease(h_atr);
   IndicatorRelease(h_stoch);
   IndicatorRelease(h_bb);
   IndicatorRelease(h_adx);
   Comment("");
}

//+------------------------------------------------------------------+
//| Get indicator value                                               |
//+------------------------------------------------------------------+
double GetInd(int handle, int buffer = 0, int shift = 0)
{
   double val[];
   ArraySetAsSeries(val, true);
   if(CopyBuffer(handle, buffer, shift, 3, val) > 0)
      return val[shift];
   return 0;
}

//+------------------------------------------------------------------+
//| Pip value                                                         |
//+------------------------------------------------------------------+
double PipValue()
{
   return SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10;
}

//+------------------------------------------------------------------+
//| Get regime name                                                   |
//+------------------------------------------------------------------+
string GetRegimeName(int regime)
{
   switch(regime)
   {
      case REGIME_RANGING:  return "📊 RANGING";
      case REGIME_TRENDING: return "📈 TRENDING";
      case REGIME_VOLATILE: return "⚡ VOLATILE";
      default: return "❓ UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size with compounding                               |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double lots = BaseLotSize;
   
   if(EnableCompounding)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double atr = GetInd(h_atr);
      double pip = PipValue();
      double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
      
      // Risk amount based on balance
      double riskAmount = balance * (CompoundPercent / 100.0);
      
      // SL distance in pips (use active regime setting)
      double slPips = (atr * Active_ATR_SL) / pip;
      if(slPips < 10) slPips = 10;  // Min 10 pips SL
      if(slPips > 30) slPips = 30;  // Max 30 pips SL
      
      // Calculate lot size: risk / (SL_pips * pip_value)
      double pipValuePerLot = tickValue * 10;  // Value per pip per lot
      if(pipValuePerLot > 0)
         lots = riskAmount / (slPips * pipValuePerLot);
      
      // Reduce if target hit
      if(ReduceAfterTarget && (DailyTargetHit || WeeklyTargetHit))
         lots *= TargetReduction;
   }
   
   // Apply limits
   lots = MathMax(MinLotSize, lots);
   lots = MathMin(MaxLotSize, lots);
   lots = NormalizeDouble(lots, 2);
   
   // Ensure within broker limits
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   lots = MathMax(minLot, lots);
   lots = MathMin(maxLot, lots);
   lots = MathFloor(lots / lotStep) * lotStep;
   
   return lots;
}

//+------------------------------------------------------------------+
//| Check profit targets                                              |
//+------------------------------------------------------------------+
void CheckProfitTargets()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + 
                                  IntegerToString(dt.mon) + "." + 
                                  IntegerToString(dt.day));
   
   // Reset daily tracking
   if(today != LastDay)
   {
      LastDay = today;
      DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      DailyTargetHit = false;
      
      // Check weekly reset (Monday)
      if(dt.day_of_week == 1)
      {
         WeekStartBalance = DayStartBalance;
         WeeklyTargetHit = false;
      }
   }
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Check daily target
   double dailyPL = ((balance - DayStartBalance) / DayStartBalance) * 100;
   if(dailyPL >= DailyProfitTarget && !DailyTargetHit)
   {
      DailyTargetHit = true;
      Print("🎯 DAILY TARGET HIT! +", DoubleToString(dailyPL, 2), "%");
   }
   
   // Check weekly target
   double weeklyPL = ((balance - WeekStartBalance) / WeekStartBalance) * 100;
   if(weeklyPL >= WeeklyProfitTarget && !WeeklyTargetHit)
   {
      WeeklyTargetHit = true;
      Print("🏆 WEEKLY TARGET HIT! +", DoubleToString(weeklyPL, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Check if in trading session                                       |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   if(!UseSessionFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // London or NY session
   return (hour >= LondonStart && hour < SessionEnd);
}

//+------------------------------------------------------------------+
//| Detect market regime                                              |
//+------------------------------------------------------------------+
void DetectRegime()
{
   if(!UseMLRegime) return;
   
   double atr = GetInd(h_atr);
   double atr_avg = 0;
   double atr_vals[];
   ArraySetAsSeries(atr_vals, true);
   if(CopyBuffer(h_atr, 0, 0, 20, atr_vals) > 0)
   {
      for(int i = 0; i < 20; i++) atr_avg += atr_vals[i];
      atr_avg /= 20;
   }
   
   double adx = GetInd(h_adx, 0);
   double rsi = GetInd(h_rsi);
   double volRatio = (atr_avg > 0) ? atr / atr_avg : 1.0;
   
   double rangingScore = 0;
   double trendingScore = 0;
   double volatileScore = 0;
   
   // ADX trend detection
   if(adx > 30) trendingScore += 4;
   else if(adx > 25) trendingScore += 2;
   else if(adx < 20) rangingScore += 3;
   
   // Volatility detection  
   if(volRatio > 1.5) volatileScore += 4;
   else if(volRatio > 1.2) volatileScore += 2;
   else if(volRatio < 0.7) rangingScore += 2;
   
   // MA alignment
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   
   if((ema_f > ema_m && ema_m > ema_s) || (ema_f < ema_m && ema_m < ema_s))
      trendingScore += 3;
   else
      rangingScore += 2;
   
   // RSI extremes
   if(rsi < 25 || rsi > 75) rangingScore += 1;  // Potential reversal
   
   int prevRegime = CurrentRegime;
   double totalScore = rangingScore + trendingScore + volatileScore + 0.001;
   
   if(volatileScore > trendingScore && volatileScore > rangingScore)
   {
      CurrentRegime = REGIME_VOLATILE;
      CurrentConfidence = volatileScore / totalScore * 100;
   }
   else if(trendingScore > rangingScore)
   {
      CurrentRegime = REGIME_TRENDING;
      CurrentConfidence = trendingScore / totalScore * 100;
   }
   else
   {
      CurrentRegime = REGIME_RANGING;
      CurrentConfidence = rangingScore / totalScore * 100;
   }
   
   if(prevRegime != CurrentRegime)
   {
      Print("🔄 REGIME: ", GetRegimeName(prevRegime), " → ", GetRegimeName(CurrentRegime));
      ApplyRegimeSettings();
   }
}

//+------------------------------------------------------------------+
//| Apply regime settings                                             |
//+------------------------------------------------------------------+
void ApplyRegimeSettings()
{
   switch(CurrentRegime)
   {
      case REGIME_RANGING:
         Active_ATR_SL = Range_ATR_SL;
         Active_ATR_TP = Range_ATR_TP;
         Active_TrailStart = Range_TrailStart;
         Active_MinConf = Range_MinConf;
         break;
         
      case REGIME_TRENDING:
         Active_ATR_SL = Trend_ATR_SL;
         Active_ATR_TP = Trend_ATR_TP;
         Active_TrailStart = Trend_TrailStart;
         Active_MinConf = Trend_MinConf;
         break;
         
      case REGIME_VOLATILE:
         Active_ATR_SL = Volat_ATR_SL;
         Active_ATR_TP = Volat_ATR_TP;
         Active_TrailStart = Volat_TrailStart;
         Active_MinConf = Volat_MinConf;
         break;
   }
}

//+------------------------------------------------------------------+
//| Get trend                                                         |
//+------------------------------------------------------------------+
string GetTrend(int &strength)
{
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   strength = 0;
   if(ema_f > ema_m) strength++; else strength--;
   if(ema_m > ema_s) strength++; else strength--;
   if(price > ema_m) strength++; else strength--;
   
   if(strength >= 2) return "STRONG_UP";
   else if(strength == 1) return "UP";
   else if(strength <= -2) return "STRONG_DOWN";
   else if(strength == -1) return "DOWN";
   return "RANGE";
}

//+------------------------------------------------------------------+
//| Get signal                                                        |
//+------------------------------------------------------------------+
void GetSignal(string &direction, int &confidence, bool &trendAligned)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   double rsi = GetInd(h_rsi);
   double macd = GetInd(h_macd, 0);
   double macd_sig = GetInd(h_macd, 1);
   double stoch = GetInd(h_stoch, 0);
   double stoch_d = GetInd(h_stoch, 1);
   double bb_upper = GetInd(h_bb, 1);
   double bb_lower = GetInd(h_bb, 2);
   double adx = GetInd(h_adx, 0);
   
   int buy = 0, sell = 0;
   
   // EMA alignment (stronger weight in trending)
   int emaWeight = (CurrentRegime == REGIME_TRENDING) ? 4 : 2;
   if(ema_f > ema_m && ema_m > ema_s) buy += emaWeight;
   else if(ema_f < ema_m && ema_m < ema_s) sell += emaWeight;
   else if(ema_f > ema_m) buy += 1;
   else sell += 1;
   
   // Price position
   if(price > ema_s) buy += 2; else sell += 2;
   
   // RSI (stronger weight in ranging)
   int rsiWeight = (CurrentRegime == REGIME_RANGING) ? 3 : 2;
   if(rsi < 25) buy += rsiWeight + 1;
   else if(rsi < 35) buy += rsiWeight;
   else if(rsi > 75) sell += rsiWeight + 1;
   else if(rsi > 65) sell += rsiWeight;
   else if(rsi > 50) buy += 1;
   else sell += 1;
   
   // MACD
   if(macd > macd_sig && macd > 0) buy += 2;
   else if(macd > macd_sig) buy += 1;
   else if(macd < macd_sig && macd < 0) sell += 2;
   else sell += 1;
   
   // Stochastic
   if(stoch < 20 && stoch > stoch_d) buy += 2;
   else if(stoch < 30) buy += 1;
   else if(stoch > 80 && stoch < stoch_d) sell += 2;
   else if(stoch > 70) sell += 1;
   
   // Bollinger (stronger in ranging)
   int bbWeight = (CurrentRegime == REGIME_RANGING) ? 3 : 2;
   if(price < bb_lower) buy += bbWeight;
   else if(price > bb_upper) sell += bbWeight;
   
   // ADX confirmation for trending
   if(CurrentRegime == REGIME_TRENDING && adx > 25)
   {
      if(ema_f > ema_m) buy += 2;
      else sell += 2;
   }
   
   int total = buy + sell;
   trendAligned = false;
   
   if(buy > sell)
   {
      direction = "BUY";
      confidence = (int)((double)buy / total * 100);
      int str;
      string trend = GetTrend(str);
      trendAligned = (StringFind(trend, "UP") >= 0);
   }
   else if(sell > buy)
   {
      direction = "SELL";
      confidence = (int)((double)sell / total * 100);
      int str;
      string trend = GetTrend(str);
      trendAligned = (StringFind(trend, "DOWN") >= 0);
   }
   else
   {
      direction = "HOLD";
      confidence = 50;
   }
}

//+------------------------------------------------------------------+
//| Count positions                                                   |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == Symbol())
         {
            if(type == WRONG_VALUE || posInfo.PositionType() == type)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get position profit                                               |
//+------------------------------------------------------------------+
double GetPositionProfit(ENUM_POSITION_TYPE type)
{
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == Symbol())
         {
            if(type == WRONG_VALUE || posInfo.PositionType() == type)
               profit += posInfo.Profit();
         }
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Close positions                                                   |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == Symbol())
         {
            if(type == WRONG_VALUE || posInfo.PositionType() == type)
               trade.PositionClose(posInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage positions                                                  |
//+------------------------------------------------------------------+
void ManagePositions(string currentSignal, int signalConf)
{
   double pip = PipValue();
   double atr = GetInd(h_atr);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != MagicNumber || posInfo.Symbol() != Symbol()) continue;
      
      double openPrice = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      double currentTP = posInfo.TakeProfit();
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
      
      double currentPrice = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_BID) 
                                  : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      
      double profitPips = isBuy ? (currentPrice - openPrice) / pip 
                                : (openPrice - currentPrice) / pip;
      
      // Early exit on signal reversal
      if(EnableEarlyExit && profitPips <= CutLossPips && ExitOnWeakSignal)
      {
         if((isBuy && currentSignal == "SELL" && signalConf >= 62) ||
            (!isBuy && currentSignal == "BUY" && signalConf >= 62))
         {
            trade.PositionClose(posInfo.Ticket());
            Print("⚠️ EARLY EXIT at ", DoubleToString(profitPips, 1), " pips");
            continue;
         }
      }
      
      // Breakeven
      if(profitPips >= BreakevenPips)
      {
         double newSL = isBuy ? openPrice + pip * 2 : openPrice - pip * 2;
         if(isBuy && currentSL < newSL)
            trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         else if(!isBuy && (currentSL > newSL || currentSL == 0))
            trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
      }
      
      // Trailing - regime adaptive
      if(EnableTrailing && profitPips >= Active_TrailStart)
      {
         double trailDist = UseATRTrailing ? atr * 0.6 : TrailingStep * pip;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDist;
            if(newSL > currentSL + pip)
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         }
         else
         {
            newSL = currentPrice + trailDist;
            if(newSL < currentSL - pip || currentSL == 0)
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Can open trade                                                    |
//+------------------------------------------------------------------+
bool CanOpenTrade(string direction, int confidence, bool trendAligned)
{
   if(CountPositions(WRONG_VALUE) >= MaxPositions) return false;
   if(confidence < Active_MinConf) return false;
   if(CurrentRegime == REGIME_TRENDING && !trendAligned) return false;
   
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CountPositions(type) > 0) return false;
   
   if(!IsActiveSession()) return false;
   
   if(AvoidFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, string comment)
{
   double atr = GetInd(h_atr);
   double pip = PipValue();
   double lots = CalculateLotSize();
   double price, sl, tp;
   
   double slDistance = atr * Active_ATR_SL;
   double tpDistance = atr * Active_ATR_TP;
   
   // Cap SL
   double maxSL = 30 * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   // Ensure minimum R:R of 1:1.5
   if(tpDistance < slDistance * 1.5)
      tpDistance = slDistance * 1.5;
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - slDistance;
      tp = price + tpDistance;
      
      if(trade.Buy(lots, Symbol(), price, sl, tp, comment))
      {
         Print("🟢 BUY ", DoubleToString(lots, 2), " lots [", GetRegimeName(CurrentRegime), 
               "] SL:", DoubleToString(slDistance/pip, 0), " TP:", DoubleToString(tpDistance/pip, 0));
         return true;
      }
   }
   else
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      sl = price + slDistance;
      tp = price - tpDistance;
      
      if(trade.Sell(lots, Symbol(), price, sl, tp, comment))
      {
         Print("🔴 SELL ", DoubleToString(lots, 2), " lots [", GetRegimeName(CurrentRegime),
               "] SL:", DoubleToString(slDistance/pip, 0), " TP:", DoubleToString(tpDistance/pip, 0));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Display info                                                      |
//+------------------------------------------------------------------+
void DisplayInfo(string signal, int confidence, string trend, bool aligned)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = GetPositionProfit(WRONG_VALUE);
   int buyCount = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   
   double totalReturn = ((balance - 10000) / 10000) * 100;
   double dailyPL = ((balance - DayStartBalance) / DayStartBalance) * 100;
   double progress5x = (balance / 50000) * 100;
   
   string emoji = (signal == "BUY") ? "🟢" : (signal == "SELL") ? "🔴" : "⚪";
   double nextLot = CalculateLotSize();
   
   Comment(
      "\n🚀 GOLD ML EA v6.0 - 5X TARGET\n",
      "══════════════════════════════════════════════\n",
      "💰 Balance: $", DoubleToString(balance, 2), "\n",
      "📈 Total Return: ", (totalReturn >= 0 ? "+" : ""), DoubleToString(totalReturn, 1), "%\n",
      "📊 Today: ", (dailyPL >= 0 ? "+" : ""), DoubleToString(dailyPL, 2), "%",
      (DailyTargetHit ? " 🎯" : ""), "\n",
      "🎯 Progress to 5X: ", DoubleToString(progress5x, 1), "%\n",
      "\n", GetRegimeName(CurrentRegime), " | ", emoji, " ", signal, " (", IntegerToString(confidence), "%)\n",
      "   Trend: ", trend, " | Aligned: ", (aligned ? "✅" : "⚠️"), "\n",
      "\n📊 Positions: BUY ", IntegerToString(buyCount), " SELL ", IntegerToString(sellCount),
      " | P/L: $", DoubleToString(profit, 2), "\n",
      "\n⚙️ Next Lot: ", DoubleToString(nextLot, 2),
      " | SL:", DoubleToString(Active_ATR_SL, 1), "x TP:", DoubleToString(Active_ATR_TP, 1), "x\n",
      "══════════════════════════════════════════════"
   );
}

//+------------------------------------------------------------------+
//| Main tick                                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check profit targets
   CheckProfitTargets();
   
   // Get signal
   string signal;
   int confidence;
   bool trendAligned;
   GetSignal(signal, confidence, trendAligned);
   
   int trendStrength;
   string trend = GetTrend(trendStrength);
   
   DisplayInfo(signal, confidence, trend, trendAligned);
   ManagePositions(signal, confidence);
   
   // Friday close
   if(AvoidFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= FridayCloseHour)
      {
         if(CountPositions(WRONG_VALUE) > 0)
         {
            Print("🕐 Friday close");
            ClosePositions(WRONG_VALUE);
         }
         return;
      }
   }
   
   // New bar only
   static datetime lastBar = 0;
   datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   // Update regime
   static int barCount = 0;
   barCount++;
   if(barCount >= RegimeUpdateBars)
   {
      DetectRegime();
      barCount = 0;
   }
   
   // Reversal logic
   if(confidence >= 75 && trendAligned)
   {
      int buyCount = CountPositions(POSITION_TYPE_BUY);
      int sellCount = CountPositions(POSITION_TYPE_SELL);
      
      if(signal == "BUY" && sellCount > 0 && buyCount == 0)
      {
         ClosePositions(POSITION_TYPE_SELL);
         ExecuteTrade("BUY", "REV_BUY");
         return;
      }
      else if(signal == "SELL" && buyCount > 0 && sellCount == 0)
      {
         ClosePositions(POSITION_TYPE_BUY);
         ExecuteTrade("SELL", "REV_SELL");
         return;
      }
   }
   
   // New trade
   if(signal != "HOLD" && CanOpenTrade(signal, confidence, trendAligned))
   {
      ExecuteTrade(signal, GetRegimeName(CurrentRegime) + "_" + signal);
   }
}
//+------------------------------------------------------------------+
