//+------------------------------------------------------------------+
//|                                        GoldScalpingEA_ML_v2.mq5  |
//|                    v6.0 - OPTIMIZED for Higher Profitability     |
//|     Improvements: Better R:R, Fewer trades, Asymmetric shorts    |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping ML System v6.0"
#property version   "6.00"
#property description "OPTIMIZED: Better R:R, Quality over Quantity"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| REGIME DEFINITIONS                                                |
//+------------------------------------------------------------------+
#define REGIME_RANGING   0
#define REGIME_TRENDING  1
#define REGIME_VOLATILE  2

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS ==="
input double   BaseLotSize = 0.1;          // Base Lot Size
input double   RiskPercent = 0;            // Risk % (0 = fixed lot)
input int      MaxPositions = 2;           // Max positions (reduced!)
input int      MagicNumber = 12345;        // Magic Number

input group "=== ML REGIME DETECTION ==="
input bool     UseMLRegime = true;         // Use ML regime detection
input int      RegimeUpdateBars = 5;       // Update regime every N bars

input group "=== OPTIMIZED RANGING REGIME ==="
input double   Range_ATR_SL = 0.8;         // SL = 0.8x ATR (TIGHTER)
input double   Range_ATR_TP = 1.8;         // TP = 1.8x ATR (HIGHER R:R)
input int      Range_TrailStart = 10;      // Trail start pips
input int      Range_MinConf = 65;         // Min confidence (STRICTER)

input group "=== OPTIMIZED TRENDING REGIME ==="
input double   Trend_ATR_SL = 1.2;         // SL = 1.2x ATR
input double   Trend_ATR_TP = 3.0;         // TP = 3.0x ATR (LET WINNERS RUN)
input int      Trend_TrailStart = 15;      // Trail start pips
input int      Trend_MinConf = 60;         // Min confidence

input group "=== OPTIMIZED VOLATILE REGIME ==="
input double   Volat_ATR_SL = 1.5;         // SL = 1.5x ATR
input double   Volat_ATR_TP = 2.5;         // TP = 2.5x ATR
input int      Volat_TrailStart = 18;      // Trail start pips
input int      Volat_MinConf = 72;         // Min confidence (STRICTER)

input group "=== ASYMMETRIC SHORT SETTINGS ==="
input bool     UseAsymmetricShorts = true; // Require more for shorts
input int      ShortExtraConf = 5;         // Extra confidence for shorts
input bool     RequireDowntrend = true;    // Shorts need downtrend

input group "=== SMART EXIT SYSTEM ==="
input bool     EnableEarlyExit = true;     // Enable early exit
input int      CutLossPips = -12;          // Cut loss at -12 (TIGHTER)
input int      BreakevenPips = 10;         // Move to BE at +10 pips
input bool     EnablePartialClose = true;  // Close 50% at first target
input int      PartialClosePips = 15;      // Partial close at +15 pips
input double   PartialClosePercent = 50;   // Close 50% of position

input group "=== TRAILING STOP ==="
input bool     EnableTrailing = true;      // Enable trailing
input int      TrailingStep = 5;           // Trail step pips
input bool     UseATRTrailing = true;      // Use ATR-based trailing
input double   TrailATRMult = 0.6;         // Trail = 0.6x ATR (TIGHTER)

input group "=== TRADE QUALITY FILTERS ==="
input bool     UseADXFilter = true;        // Require ADX confirmation
input int      MinADX = 20;                // Min ADX for trading
input int      TradeCooldownBars = 2;      // Wait N bars between trades
input bool     RequireMACD_Confirm = true; // MACD must confirm direction
input bool     RequireStoch_Confirm = true;// Stoch must confirm entry

input group "=== OPTIMAL TIME FILTER ==="
input bool     UseTimeFilter = true;       // ENABLED - trade best hours
input int      StartHour = 7;              // Start at 7:00 (London pre)
input int      EndHour = 20;               // End at 20:00
input bool     AvoidLunchHour = true;      // Skip 12:00-13:00 (low vol)
input bool     AvoidFriday = true;         // No new trades Friday
input int      FridayCloseHour = 16;       // Close earlier on Friday

input group "=== INDICATORS ==="
input int      EMA_Fast = 9;
input int      EMA_Medium = 21;
input int      EMA_Slow = 50;
input int      RSI_Period = 14;
input int      ATR_Period = 14;
input int      ADX_Period = 14;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo posInfo;

int h_ema_fast, h_ema_medium, h_ema_slow;
int h_rsi, h_macd, h_atr, h_bb, h_stoch, h_adx;

int CurrentRegime = REGIME_RANGING;
double CurrentConfidence = 0;
datetime LastTradeTime = 0;

double Active_ATR_SL = 1.0;
double Active_ATR_TP = 2.0;
int Active_TrailStart = 12;
int Active_MinConf = 65;

// Statistics
int totalTrades = 0;
int winningTrades = 0;
double totalProfit = 0;

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
   
   if(h_ema_fast == INVALID_HANDLE || h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   DetectRegime();
   ApplyRegimeSettings();
   
   Print("══════════════════════════════════════════════════");
   Print("🚀 GOLD SCALPING EA v6.0 - OPTIMIZED PROFITABILITY");
   Print("══════════════════════════════════════════════════");
   Print("📈 KEY IMPROVEMENTS:");
   Print("   ✓ Better R:R ratios (avg win > avg loss target)");
   Print("   ✓ Fewer, higher quality trades");
   Print("   ✓ Asymmetric shorts (higher confidence)");
   Print("   ✓ Partial close at first target");
   Print("   ✓ ADX + MACD + Stoch confirmation");
   Print("   ✓ Optimal trading hours only");
   Print("══════════════════════════════════════════════════");
   Print("   Current Regime: ", GetRegimeName(CurrentRegime));
   Print("   SL: ", DoubleToString(Active_ATR_SL, 1), "x | TP: ", DoubleToString(Active_ATR_TP, 1), "x");
   Print("   R:R Target = 1:", DoubleToString(Active_ATR_TP/Active_ATR_SL, 1));
   Print("══════════════════════════════════════════════════");
   
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
   
   // Print final stats
   if(totalTrades > 0)
   {
      Print("══════════════════════════════════════════════════");
      Print("📊 SESSION STATISTICS:");
      Print("   Total Trades: ", totalTrades);
      Print("   Win Rate: ", DoubleToString((double)winningTrades/totalTrades*100, 1), "%");
      Print("   Total P/L: $", DoubleToString(totalProfit, 2));
      Print("══════════════════════════════════════════════════");
   }
   
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
//| Get point value for pip calculations                              |
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
   
   // ADX scoring
   if(adx > 30) trendingScore += 4;
   else if(adx > 25) trendingScore += 2;
   else if(adx < 18) rangingScore += 3;
   else rangingScore += 1;
   
   // Volatility scoring
   if(volRatio > 1.6) volatileScore += 4;
   else if(volRatio > 1.3) volatileScore += 2;
   else if(volRatio < 0.7) rangingScore += 2;
   
   // RSI
   if(rsi < 25 || rsi > 75) rangingScore += 2;
   else if(rsi > 42 && rsi < 58) rangingScore += 1;
   
   // MA alignment
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   
   if((ema_f > ema_m && ema_m > ema_s) || (ema_f < ema_m && ema_m < ema_s))
      trendingScore += 3;
   else
      rangingScore += 2;
   
   // Determine regime
   int prevRegime = CurrentRegime;
   double totalScore = rangingScore + trendingScore + volatileScore;
   
   if(volatileScore >= trendingScore && volatileScore >= rangingScore && volatileScore > 2)
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
//| Apply settings based on regime                                    |
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
//| Get trend with strength                                           |
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
   if(price > ema_s) strength++; else strength--;
   
   if(strength >= 3) return "STRONG_UP";
   else if(strength >= 1) return "UP";
   else if(strength <= -3) return "STRONG_DOWN";
   else if(strength <= -1) return "DOWN";
   return "RANGE";
}

//+------------------------------------------------------------------+
//| Check MACD confirmation                                           |
//+------------------------------------------------------------------+
bool CheckMACDConfirm(string direction)
{
   if(!RequireMACD_Confirm) return true;
   
   double macd = GetInd(h_macd, 0);
   double macd_sig = GetInd(h_macd, 1);
   double macd_hist = macd - macd_sig;
   double macd_hist_prev = GetInd(h_macd, 0, 1) - GetInd(h_macd, 1, 1);
   
   if(direction == "BUY")
   {
      // MACD above signal OR histogram turning positive
      return (macd > macd_sig) || (macd_hist > macd_hist_prev && macd_hist > -0.5);
   }
   else
   {
      return (macd < macd_sig) || (macd_hist < macd_hist_prev && macd_hist < 0.5);
   }
}

//+------------------------------------------------------------------+
//| Check Stochastic confirmation                                     |
//+------------------------------------------------------------------+
bool CheckStochConfirm(string direction)
{
   if(!RequireStoch_Confirm) return true;
   
   double stoch_k = GetInd(h_stoch, 0);
   double stoch_d = GetInd(h_stoch, 1);
   
   if(direction == "BUY")
   {
      // Oversold turning up, or above 20 with positive cross
      return (stoch_k < 25) || (stoch_k > stoch_d && stoch_k < 70);
   }
   else
   {
      // Overbought turning down, or below 80 with negative cross
      return (stoch_k > 75) || (stoch_k < stoch_d && stoch_k > 30);
   }
}

//+------------------------------------------------------------------+
//| Get signal with confidence                                        |
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
   
   // === EMA ALIGNMENT (Strong weight) ===
   if(ema_f > ema_m && ema_m > ema_s) { buy += 4; }
   else if(ema_f < ema_m && ema_m < ema_s) { sell += 4; }
   else if(ema_f > ema_m) { buy += 2; }
   else { sell += 2; }
   
   // === PRICE VS EMA ===
   if(price > ema_s) buy += 2; else sell += 2;
   if(price > ema_m) buy += 1; else sell += 1;
   
   // === RSI ===
   if(rsi < 22) buy += 4;        // Very oversold
   else if(rsi < 32) buy += 2;   // Oversold
   else if(rsi > 78) sell += 4;  // Very overbought
   else if(rsi > 68) sell += 2;  // Overbought
   else if(rsi > 55) buy += 1;
   else if(rsi < 45) sell += 1;
   
   // === MACD ===
   if(macd > macd_sig && macd > 0) buy += 3;
   else if(macd > macd_sig) buy += 1;
   else if(macd < macd_sig && macd < 0) sell += 3;
   else sell += 1;
   
   // === STOCHASTIC ===
   if(stoch < 18 && stoch > stoch_d) buy += 3;
   else if(stoch < 28) buy += 1;
   else if(stoch > 82 && stoch < stoch_d) sell += 3;
   else if(stoch > 72) sell += 1;
   
   // === BOLLINGER BANDS ===
   if(price < bb_lower) buy += 3;
   else if(price > bb_upper) sell += 3;
   
   // === ADX BONUS (trend strength) ===
   if(UseADXFilter && adx > 25)
   {
      double di_plus = GetInd(h_adx, 1);
      double di_minus = GetInd(h_adx, 2);
      if(di_plus > di_minus) buy += 2;
      else sell += 2;
   }
   
   // Calculate result
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
//| Get total position profit                                         |
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
            {
               double profit = posInfo.Profit();
               trade.PositionClose(posInfo.Ticket());
               totalProfit += profit;
               totalTrades++;
               if(profit > 0) winningTrades++;
               Print("Closed: ", profit >= 0 ? "+" : "", DoubleToString(profit, 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage positions with partial close and smart trailing            |
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
      double lots = posInfo.Volume();
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
      ulong ticket = posInfo.Ticket();
      
      double currentPrice = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_BID) 
                                  : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      
      double profitPips = isBuy ? (currentPrice - openPrice) / pip 
                                : (openPrice - currentPrice) / pip;
      
      // === 1. EARLY CUT LOSS ===
      if(EnableEarlyExit && profitPips <= CutLossPips)
      {
         bool shouldExit = false;
         
         if(isBuy && currentSignal == "SELL" && signalConf >= 62)
            shouldExit = true;
         else if(!isBuy && currentSignal == "BUY" && signalConf >= 62)
            shouldExit = true;
         
         if(shouldExit)
         {
            double profit = posInfo.Profit();
            trade.PositionClose(ticket);
            totalProfit += profit;
            totalTrades++;
            Print("⚠️ CUT LOSS at ", DoubleToString(profitPips, 1), " pips");
            continue;
         }
      }
      
      // === 2. PARTIAL CLOSE AT FIRST TARGET ===
      if(EnablePartialClose && profitPips >= PartialClosePips && lots > 0.02)
      {
         double closeLots = NormalizeDouble(lots * PartialClosePercent / 100, 2);
         closeLots = MathMax(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), closeLots);
         
         if(trade.PositionClosePartial(ticket, closeLots))
         {
            Print("💰 PARTIAL CLOSE ", DoubleToString(closeLots, 2), " lots at +", 
                  DoubleToString(profitPips, 1), " pips");
         }
      }
      
      // === 3. MOVE TO BREAKEVEN ===
      if(profitPips >= BreakevenPips)
      {
         double newSL;
         if(isBuy)
         {
            newSL = openPrice + pip * 2; // Lock 2 pips profit
            if(currentSL < newSL)
               trade.PositionModify(ticket, newSL, currentTP);
         }
         else
         {
            newSL = openPrice - pip * 2;
            if(currentSL > newSL || currentSL == 0)
               trade.PositionModify(ticket, newSL, currentTP);
         }
      }
      
      // === 4. AGGRESSIVE TRAILING ===
      if(EnableTrailing && profitPips >= Active_TrailStart)
      {
         double trailDistance = UseATRTrailing ? atr * TrailATRMult : TrailingStep * pip;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL + pip)
               trade.PositionModify(ticket, newSL, currentTP);
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(newSL < currentSL - pip || currentSL == 0)
               trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check time filter                                                 |
//+------------------------------------------------------------------+
bool IsGoodTradingTime()
{
   if(!UseTimeFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Outside trading hours
   if(hour < StartHour || hour >= EndHour) return false;
   
   // Avoid lunch hour (low volume)
   if(AvoidLunchHour && (hour == 12)) return false;
   
   // Friday restrictions
   if(AvoidFriday && dt.day_of_week == 5) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check trade cooldown                                              |
//+------------------------------------------------------------------+
bool PassesCooldown()
{
   if(TradeCooldownBars == 0) return true;
   
   datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
   long barDiff = (currentBar - LastTradeTime) / PeriodSeconds(PERIOD_CURRENT);
   
   return barDiff >= TradeCooldownBars;
}

//+------------------------------------------------------------------+
//| Check if can open new trade                                       |
//+------------------------------------------------------------------+
bool CanOpenTrade(string direction, int confidence, bool trendAligned)
{
   // Max positions
   int total = CountPositions(WRONG_VALUE);
   if(total >= MaxPositions) return false;
   
   // Already have this direction
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CountPositions(type) > 0) return false;
   
   // Cooldown
   if(!PassesCooldown()) return false;
   
   // Time filter
   if(!IsGoodTradingTime()) return false;
   
   // Confidence threshold (asymmetric for shorts)
   int requiredConf = Active_MinConf;
   if(direction == "SELL" && UseAsymmetricShorts)
   {
      requiredConf += ShortExtraConf;
      
      // Also require downtrend for shorts
      if(RequireDowntrend)
      {
         int str;
         string trend = GetTrend(str);
         if(StringFind(trend, "DOWN") < 0) return false;
      }
   }
   
   if(confidence < requiredConf) return false;
   
   // In trending regime, require alignment
   if(CurrentRegime == REGIME_TRENDING && !trendAligned) return false;
   
   // ADX filter
   if(UseADXFilter)
   {
      double adx = GetInd(h_adx, 0);
      if(adx < MinADX) return false;
   }
   
   // MACD confirmation
   if(!CheckMACDConfirm(direction)) return false;
   
   // Stochastic confirmation
   if(!CheckStochConfirm(direction)) return false;
   
   // Momentum filter
   double rsi = GetInd(h_rsi);
   if(CurrentRegime == REGIME_RANGING)
   {
      if(rsi > 32 && rsi < 68) return false;
   }
   else
   {
      if(rsi > 38 && rsi < 62) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, double lots, string comment)
{
   double atr = GetInd(h_atr);
   double pip = PipValue();
   double price, sl, tp;
   
   double slDistance = atr * Active_ATR_SL;
   double tpDistance = atr * Active_ATR_TP;
   
   // Cap max loss at 30 pips
   double maxSL = 30 * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   // Ensure minimum R:R of 1.5
   if(tpDistance < slDistance * 1.5)
      tpDistance = slDistance * 1.5;
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - slDistance;
      tp = price + tpDistance;
      
      if(trade.Buy(lots, Symbol(), price, sl, tp, comment))
      {
         LastTradeTime = iTime(Symbol(), PERIOD_CURRENT, 0);
         Print("✅ BUY [", GetRegimeName(CurrentRegime), "] @ ", DoubleToString(price, 2), 
               " | SL: -", DoubleToString(slDistance/pip, 0), " | TP: +", DoubleToString(tpDistance/pip, 0),
               " | R:R = 1:", DoubleToString(tpDistance/slDistance, 1));
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
         LastTradeTime = iTime(Symbol(), PERIOD_CURRENT, 0);
         Print("✅ SELL [", GetRegimeName(CurrentRegime), "] @ ", DoubleToString(price, 2),
               " | SL: +", DoubleToString(slDistance/pip, 0), " | TP: -", DoubleToString(tpDistance/pip, 0),
               " | R:R = 1:", DoubleToString(tpDistance/slDistance, 1));
         return true;
      }
   }
   
   Print("❌ Trade failed: ", trade.ResultComment());
   return false;
}

//+------------------------------------------------------------------+
//| Display info                                                      |
//+------------------------------------------------------------------+
void DisplayInfo(string signal, int confidence, string trend, bool aligned)
{
   double buyProfit = GetPositionProfit(POSITION_TYPE_BUY);
   double sellProfit = GetPositionProfit(POSITION_TYPE_SELL);
   int buyCount = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   
   string emoji = (signal == "BUY") ? "🟢" : (signal == "SELL") ? "🔴" : "⚪";
   string alignStr = aligned ? "✅" : "⚠️";
   double rr = Active_ATR_TP / Active_ATR_SL;
   
   Comment(
      "\n🚀 GOLD SCALPING EA v6.0 - OPTIMIZED\n",
      "══════════════════════════════════════════════\n",
      "💰 Price: $", DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), 2), "\n",
      "\n🎯 REGIME: ", GetRegimeName(CurrentRegime), "\n",
      "   R:R = 1:", DoubleToString(rr, 1), " | MinConf: ", IntegerToString(Active_MinConf), "%\n",
      "\n📈 Trend: ", trend, "\n",
      emoji, " Signal: ", signal, " (", IntegerToString(confidence), "%) ", alignStr, "\n",
      "\n📊 POSITIONS:\n",
      "   BUY:  ", IntegerToString(buyCount), " | $", DoubleToString(buyProfit, 2), "\n",
      "   SELL: ", IntegerToString(sellCount), " | $", DoubleToString(sellProfit, 2), "\n",
      "\n📈 SESSION: ", IntegerToString(totalTrades), " trades | $", DoubleToString(totalProfit, 2), "\n",
      "══════════════════════════════════════════════"
   );
}

//+------------------------------------------------------------------+
//| Main tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   string signal;
   int confidence;
   bool trendAligned;
   GetSignal(signal, confidence, trendAligned);
   
   int trendStrength;
   string trend = GetTrend(trendStrength);
   
   DisplayInfo(signal, confidence, trend, trendAligned);
   ManagePositions(signal, confidence);
   
   // Friday close all
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
   static int barsSinceUpdate = 0;
   barsSinceUpdate++;
   if(barsSinceUpdate >= RegimeUpdateBars)
   {
      DetectRegime();
      barsSinceUpdate = 0;
   }
   
   // Log
   Print("─── ", GetRegimeName(CurrentRegime), " | ", signal, " (", confidence, 
         "%) | Aligned: ", (trendAligned ? "Y" : "N"), " | Time OK: ", (IsGoodTradingTime() ? "Y" : "N"));
   
   // === REVERSAL TRADE ===
   if(confidence >= 78 && trendAligned)
   {
      int buyCount = CountPositions(POSITION_TYPE_BUY);
      int sellCount = CountPositions(POSITION_TYPE_SELL);
      
      if(signal == "BUY" && sellCount > 0 && buyCount == 0)
      {
         Print("🔄 REVERSAL → BUY");
         ClosePositions(POSITION_TYPE_SELL);
         if(CanOpenTrade("BUY", confidence, trendAligned))
            ExecuteTrade("BUY", BaseLotSize, "Rev_BUY");
         return;
      }
      else if(signal == "SELL" && buyCount > 0 && sellCount == 0)
      {
         Print("🔄 REVERSAL → SELL");
         ClosePositions(POSITION_TYPE_BUY);
         if(CanOpenTrade("SELL", confidence, trendAligned))
            ExecuteTrade("SELL", BaseLotSize, "Rev_SELL");
         return;
      }
   }
   
   // === NEW TRADE ===
   if(signal != "HOLD" && CanOpenTrade(signal, confidence, trendAligned))
   {
      ExecuteTrade(signal, BaseLotSize, GetRegimeName(CurrentRegime) + "_" + signal);
   }
}
//+------------------------------------------------------------------+

