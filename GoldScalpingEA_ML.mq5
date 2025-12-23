//+------------------------------------------------------------------+
//|                                           GoldScalpingEA_ML.mq5  |
//|                    v5.0 - ML Regime-Adaptive Trading System      |
//|     Dynamically adjusts parameters based on market regime        |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping ML System v5.0"
#property version   "5.00"
#property description "ML-Enhanced: Adapts SL/TP/Trailing based on regime"
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
input double   BaseLotSize = 0.1;          // Base Lot Size
input double   RiskPercent = 0;            // Risk % (0 = fixed lot)
input int      MaxPositions = 3;           // Max positions
input int      MagicNumber = 12345;        // Magic Number

input group "=== ML REGIME DETECTION ==="
input bool     UseMLRegime = true;         // Use ML regime detection
input int      RegimeUpdateBars = 5;       // Update regime every N bars
input bool     ShowRegimeOnChart = true;   // Display regime info

input group "=== RANGING REGIME SETTINGS ==="
input double   Range_ATR_SL = 1.0;         // SL multiplier (tight)
input double   Range_ATR_TP = 1.5;         // TP multiplier
input int      Range_TrailStart = 8;       // Trail start pips
input int      Range_MinConf = 60;         // Min confidence %

input group "=== TRENDING REGIME SETTINGS ==="
input double   Trend_ATR_SL = 1.5;         // SL multiplier (wider)
input double   Trend_ATR_TP = 2.5;         // TP multiplier (let run)
input int      Trend_TrailStart = 15;      // Trail start pips
input int      Trend_MinConf = 55;         // Min confidence %

input group "=== VOLATILE REGIME SETTINGS ==="
input double   Volat_ATR_SL = 2.0;         // SL multiplier (wide)
input double   Volat_ATR_TP = 2.0;         // TP multiplier
input int      Volat_TrailStart = 20;      // Trail start pips
input int      Volat_MinConf = 70;         // Min confidence % (strict)

input group "=== EARLY EXIT ==="
input bool     EnableEarlyExit = true;     // Enable early exit
input int      CutLossPips = -15;          // Cut loss threshold
input int      BreakevenPips = 12;         // Move to BE at +X pips
input bool     ExitOnWeakSignal = true;    // Exit on signal reversal

input group "=== TRAILING STOP ==="
input bool     EnableTrailing = true;      // Enable trailing
input int      TrailingStep = 5;           // Trail step pips
input bool     UseATRTrailing = true;      // Use ATR-based trailing

input group "=== INDICATORS ==="
input int      EMA_Fast = 9;
input int      EMA_Medium = 21;
input int      EMA_Slow = 50;
input int      RSI_Period = 14;
input int      ATR_Period = 14;
input int      ADX_Period = 14;

input group "=== TIME FILTER ==="
input bool     UseTimeFilter = false;
input int      StartHour = 8;
input int      EndHour = 20;
input bool     AvoidFriday = true;
input int      FridayCloseHour = 18;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo posInfo;

int h_ema_fast, h_ema_medium, h_ema_slow;
int h_rsi, h_macd, h_atr, h_bb, h_stoch, h_adx;

// Current regime state
int CurrentRegime = REGIME_RANGING;
double CurrentConfidence = 0;
datetime LastRegimeUpdate = 0;

// Dynamic settings based on regime
double Active_ATR_SL = 1.2;
double Active_ATR_TP = 2.0;
int Active_TrailStart = 12;
int Active_MinConf = 60;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Create indicators
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
   
   // Initialize regime
   DetectRegime();
   ApplyRegimeSettings();
   
   Print("==================================================");
   Print("🤖 GOLD SCALPING EA v5.0 - ML REGIME ADAPTIVE");
   Print("==================================================");
   Print("   ML Regime Detection: ", UseMLRegime ? "ENABLED" : "DISABLED");
   Print("   Current Regime: ", GetRegimeName(CurrentRegime));
   Print("   Active SL: ", DoubleToString(Active_ATR_SL, 1), "x ATR");
   Print("   Active TP: ", DoubleToString(Active_ATR_TP, 1), "x ATR");
   Print("   Active Trail: +", IntegerToString(Active_TrailStart), " pips");
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
//| Detect market regime using technical indicators                   |
//+------------------------------------------------------------------+
void DetectRegime()
{
   if(!UseMLRegime) return;
   
   // Get indicators
   double atr = GetInd(h_atr);
   double atr_avg = 0;
   double atr_vals[];
   ArraySetAsSeries(atr_vals, true);
   if(CopyBuffer(h_atr, 0, 0, 20, atr_vals) > 0)
   {
      for(int i = 0; i < 20; i++) atr_avg += atr_vals[i];
      atr_avg /= 20;
   }
   
   double adx = GetInd(h_adx, 0);  // Main ADX line
   double rsi = GetInd(h_rsi);
   
   // Volatility ratio
   double volRatio = (atr_avg > 0) ? atr / atr_avg : 1.0;
   
   // Calculate regime scores
   double rangingScore = 0;
   double trendingScore = 0;
   double volatileScore = 0;
   
   // ADX-based trend detection
   if(adx > 25) trendingScore += 3;
   else if(adx > 20) trendingScore += 1;
   else if(adx < 20) rangingScore += 2;
   
   // Volatility detection
   if(volRatio > 1.5) volatileScore += 3;
   else if(volRatio > 1.2) volatileScore += 1;
   else if(volRatio < 0.8) rangingScore += 2;
   
   // RSI extremes indicate potential reversals (ranging)
   if(rsi < 30 || rsi > 70) rangingScore += 1;
   else if(rsi > 45 && rsi < 55) rangingScore += 1;
   
   // MA alignment for trending
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   
   if((ema_f > ema_m && ema_m > ema_s) || (ema_f < ema_m && ema_m < ema_s))
      trendingScore += 2;
   else
      rangingScore += 1;
   
   // Determine regime
   int prevRegime = CurrentRegime;
   double maxScore = MathMax(rangingScore, MathMax(trendingScore, volatileScore));
   double totalScore = rangingScore + trendingScore + volatileScore;
   
   if(volatileScore >= trendingScore && volatileScore >= rangingScore)
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
   
   // Log regime change
   if(prevRegime != CurrentRegime)
   {
      Print("🔄 REGIME CHANGE: ", GetRegimeName(prevRegime), " → ", GetRegimeName(CurrentRegime),
            " (Confidence: ", DoubleToString(CurrentConfidence, 0), "%)");
      ApplyRegimeSettings();
   }
   
   LastRegimeUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Apply settings based on current regime                            |
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
   
   Print("   Applied: SL=", DoubleToString(Active_ATR_SL, 1), "x, TP=", 
         DoubleToString(Active_ATR_TP, 1), "x, Trail=+", IntegerToString(Active_TrailStart),
         ", MinConf=", IntegerToString(Active_MinConf), "%");
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
   
   if(strength >= 2) return "STRONG_UP";
   else if(strength == 1) return "UP";
   else if(strength <= -2) return "STRONG_DOWN";
   else if(strength == -1) return "DOWN";
   return "RANGE";
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
   
   int buy = 0, sell = 0;
   
   // EMA alignment
   if(ema_f > ema_m && ema_m > ema_s) { buy += 3; }
   else if(ema_f < ema_m && ema_m < ema_s) { sell += 3; }
   else if(ema_f > ema_m) { buy += 1; }
   else { sell += 1; }
   
   // Price vs EMA
   if(price > ema_s) buy += 2; else sell += 2;
   
   // RSI
   if(rsi < 25) buy += 3;
   else if(rsi < 35) buy += 2;
   else if(rsi > 75) sell += 3;
   else if(rsi > 65) sell += 2;
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
   
   // Bollinger Bands
   if(price < bb_lower) buy += 2;
   else if(price > bb_upper) sell += 2;
   
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
               trade.PositionClose(posInfo.Ticket());
               Print("Closed position: ", posInfo.Profit() >= 0 ? "+" : "", 
                     DoubleToString(posInfo.Profit(), 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage positions - regime-adaptive trailing                       |
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
      
      // === 1. EARLY CUT LOSS ===
      if(EnableEarlyExit && profitPips <= CutLossPips)
      {
         if(ExitOnWeakSignal)
         {
            bool shouldExit = false;
            
            if(isBuy && currentSignal == "SELL" && signalConf >= 60)
               shouldExit = true;
            else if(!isBuy && currentSignal == "BUY" && signalConf >= 60)
               shouldExit = true;
            
            if(shouldExit)
            {
               trade.PositionClose(posInfo.Ticket());
               Print("⚠️ EARLY EXIT at ", DoubleToString(profitPips, 1), " pips");
               continue;
            }
         }
      }
      
      // === 2. MOVE TO BREAKEVEN ===
      if(profitPips >= BreakevenPips)
      {
         double newSL;
         if(isBuy)
         {
            newSL = openPrice + pip;
            if(currentSL < newSL)
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         }
         else
         {
            newSL = openPrice - pip;
            if(currentSL > newSL || currentSL == 0)
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         }
      }
      
      // === 3. REGIME-ADAPTIVE TRAILING ===
      if(EnableTrailing && profitPips >= Active_TrailStart)
      {
         double trailDistance = UseATRTrailing ? atr * 0.8 : TrailingStep * pip;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL + pip)
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(newSL < currentSL - pip || currentSL == 0)
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check momentum filter                                             |
//+------------------------------------------------------------------+
bool PassesMomentumFilter()
{
   double atr = GetInd(h_atr);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   // Adjust threshold based on regime
   double minATR = (CurrentRegime == REGIME_VOLATILE) ? 30 * point : 20 * point;
   if(atr < minATR) return false;
   
   double rsi = GetInd(h_rsi);
   
   // In ranging regime, wait for extremes
   if(CurrentRegime == REGIME_RANGING)
   {
      if(rsi > 35 && rsi < 65) return false;
   }
   else
   {
      if(rsi > 40 && rsi < 60) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if can open new trade                                       |
//+------------------------------------------------------------------+
bool CanOpenTrade(string direction, int confidence, bool trendAligned)
{
   int total = CountPositions(WRONG_VALUE);
   if(total >= MaxPositions) return false;
   
   // Use regime-adaptive confidence threshold
   if(confidence < Active_MinConf) return false;
   
   // In trending regime, require trend alignment
   if(CurrentRegime == REGIME_TRENDING && !trendAligned) return false;
   
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CountPositions(type) > 0) return false;
   
   if(!PassesMomentumFilter()) return false;
   
   // Time filters
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < StartHour || dt.hour >= EndHour) return false;
   }
   
   if(AvoidFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade with regime-adaptive SL/TP                          |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, double lots, string comment)
{
   double atr = GetInd(h_atr);
   double pip = PipValue();
   double price, sl, tp;
   
   // Use regime-adaptive multipliers
   double slDistance = atr * Active_ATR_SL;
   double tpDistance = atr * Active_ATR_TP;
   
   // Cap max loss at 35 pips
   double maxSL = 35 * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - slDistance;
      tp = price + tpDistance;
      
      if(trade.Buy(lots, Symbol(), price, sl, tp, comment))
      {
         Print("✅ BUY [", GetRegimeName(CurrentRegime), "] @ ", DoubleToString(price, 2), 
               " SL: -", DoubleToString(slDistance/pip, 1), " TP: +", DoubleToString(tpDistance/pip, 1));
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
         Print("✅ SELL [", GetRegimeName(CurrentRegime), "] @ ", DoubleToString(price, 2),
               " SL: +", DoubleToString(slDistance/pip, 1), " TP: -", DoubleToString(tpDistance/pip, 1));
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
   
   Comment(
      "\n🤖 GOLD SCALPING EA v5.0 - ML REGIME ADAPTIVE\n",
      "══════════════════════════════════════════════\n",
      "💰 Price: $", DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), 2), "\n",
      "\n🎯 REGIME: ", GetRegimeName(CurrentRegime), " (", DoubleToString(CurrentConfidence, 0), "%)\n",
      "   SL: ", DoubleToString(Active_ATR_SL, 1), "x ATR | TP: ", DoubleToString(Active_ATR_TP, 1), "x ATR\n",
      "   Trail: +", IntegerToString(Active_TrailStart), " pips | MinConf: ", IntegerToString(Active_MinConf), "%\n",
      "\n📈 Trend: ", trend, "\n",
      emoji, " Signal: ", signal, " (", IntegerToString(confidence), "%) ", alignStr, "\n",
      "\n📊 POSITIONS:\n",
      "   BUY:  ", IntegerToString(buyCount), " | P/L: $", DoubleToString(buyProfit, 2), "\n",
      "   SELL: ", IntegerToString(sellCount), " | P/L: $", DoubleToString(sellProfit, 2), "\n",
      "   Total: $", DoubleToString(buyProfit + sellProfit, 2), "\n",
      "══════════════════════════════════════════════"
   );
}

//+------------------------------------------------------------------+
//| Main tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Get signal
   string signal;
   int confidence;
   bool trendAligned;
   GetSignal(signal, confidence, trendAligned);
   
   int trendStrength;
   string trend = GetTrend(trendStrength);
   
   // Display info
   DisplayInfo(signal, confidence, trend, trendAligned);
   
   // Manage existing positions
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
            Print("🕐 Friday close - closing all positions");
            ClosePositions(WRONG_VALUE);
         }
         return;
      }
   }
   
   // Check for new bar
   static datetime lastBar = 0;
   datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   // Update regime periodically
   static int barsSinceRegimeUpdate = 0;
   barsSinceRegimeUpdate++;
   if(barsSinceRegimeUpdate >= RegimeUpdateBars)
   {
      DetectRegime();
      barsSinceRegimeUpdate = 0;
   }
   
   Print("──────────────────────────────────────");
   Print("New bar | ", GetRegimeName(CurrentRegime), " | Signal: ", signal, " (", confidence, 
         "%) | Aligned: ", (trendAligned ? "YES" : "NO"));
   
   // === TREND REVERSAL ===
   if(confidence >= 75)
   {
      int buyCount = CountPositions(POSITION_TYPE_BUY);
      int sellCount = CountPositions(POSITION_TYPE_SELL);
      
      if(signal == "BUY" && sellCount > 0 && buyCount == 0 && trendAligned)
      {
         Print("🔄 REVERSAL: Closing SELL, opening BUY");
         ClosePositions(POSITION_TYPE_SELL);
         ExecuteTrade("BUY", BaseLotSize, "Rev_BUY");
         return;
      }
      else if(signal == "SELL" && buyCount > 0 && sellCount == 0 && trendAligned)
      {
         Print("🔄 REVERSAL: Closing BUY, opening SELL");
         ClosePositions(POSITION_TYPE_BUY);
         ExecuteTrade("SELL", BaseLotSize, "Rev_SELL");
         return;
      }
   }
   
   // === NEW TRADE ===
   if(signal != "HOLD" && CanOpenTrade(signal, confidence, trendAligned))
   {
      string comment = GetRegimeName(CurrentRegime) + "_" + signal;
      ExecuteTrade(signal, BaseLotSize, comment);
   }
}
//+------------------------------------------------------------------+

