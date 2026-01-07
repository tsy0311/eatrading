//+------------------------------------------------------------------+
//|                                           GoldScalpingEA_ML.mq5  |
//|              Advanced Gold Trading EA with Multi-Timeframe        |
//|              Trend, Momentum, Volatility & Pattern Analysis     |
//+------------------------------------------------------------------+
#property copyright "Gold Trading EA"
#property version   "2.00"
#property description "Advanced Gold Trading System: Multi-Timeframe Analysis, Golden Cross, Supertrend, VWAP, Fibonacci, Support/Resistance"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Trading Mode Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_TRADING_MODE {
   MODE_SWING,      // Swing Trading (H4/Daily)
   MODE_INTRADAY    // Intraday Trading (H1/M15)
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADING MODE ==="
input ENUM_TRADING_MODE TradingMode = MODE_SWING;  // Trading Mode

input group "=== TRADE SETTINGS ==="
input bool     UseRiskBasedLotSize = true;  // Use risk-based lot size
input double   BaseLotSize = 0.05;         // Base Lot Size
input double   RiskPercent = 0.3;          // Risk % per trade
input int      MaxPositions = 1;           // Max positions
input int      MagicNumber = 12345;        // Magic Number
input int      MaxSpreadPips = 25;         // Max spread in pips
input bool     CheckSpread = true;         // Enable spread filter
input double   MaxLotSize = 10.0;          // Maximum lot size
input double   RiskRewardRatio = 2.0;      // Risk:Reward Ratio (1:2 default)
input int      MinConfidence = 50;         // Minimum Confidence % (Lower = More Trades)

input group "=== SWING TRADING INDICATORS (H4/Daily) ==="
input int      Swing_EMA_50 = 50;          // EMA 50 Period
input int      Swing_EMA_200 = 200;         // EMA 200 Period
input int      Swing_RSI_Period = 14;      // RSI Period
input int      Swing_ADX_Threshold = 25;  // ADX Trend Strength Threshold

input group "=== INTRADAY INDICATORS (H1/M15) ==="
input int      Intraday_EMA_Fast = 8;      // Fast EMA Period
input int      Intraday_EMA_Slow = 21;      // Slow EMA Period
input int      Intraday_RSI_Period = 14;    // RSI Period
input int      Stochastic_K = 14;          // Stochastic %K
input int      Stochastic_D = 3;            // Stochastic %D
input int      Stochastic_Slowing = 3;      // Stochastic Slowing

input group "=== VOLATILITY & PATTERN TOOLS ==="
input int      BB_Period = 20;             // Bollinger Bands Period
input double   BB_Deviation = 2.0;          // Bollinger Bands Deviation
input int      ATR_Period = 14;             // ATR Period
input bool     UseFibonacci = true;         // Use Fibonacci Retracement
input bool     UseSupportResistance = true;  // Use Support/Resistance Levels
input int      SRLookback = 50;             // S/R Lookback Periods

input group "=== TREND FILTERS ==="
input bool     UseSupertrend = true;        // Use Supertrend Filter
input double   Supertrend_ATR_Mult = 3.0;  // Supertrend ATR Multiplier
input int      Supertrend_Period = 10;     // Supertrend Period
input bool     UseVWAP = true;              // Use VWAP Filter
input int      VWAP_Period = 20;            // VWAP Period

input group "=== MULTI-TIMEFRAME ==="
input bool     UseMultiTimeframe = true;    // Enable Multi-Timeframe Analysis
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H4;  // Higher Timeframe for Trend Confirmation
input ENUM_TIMEFRAMES LowerTimeframe = PERIOD_H1;  // Lower Timeframe for Entry

input group "=== TRAILING & EXIT ==="
input bool     EnableTrailing = true;      // Enable trailing stop
input int      TrailStartPips = 15;         // Trailing stop start (pips)
input bool     UseATRTrailing = true;      // Use ATR-based trailing
input bool     EnableEarlyExit = true;      // Enable early exit
input int      CutLossPips = -18;           // Cut loss threshold (pips)
input int      BreakevenPips = 12;          // Move to BE at +X pips
input bool     EnablePartialClose = true;   // Enable partial profit taking
input int      PartialClosePips = 25;       // Partial close at +X pips
input double   PartialClosePercent = 0.5;    // Close % of position

input group "=== TIME FILTER ==="
input bool     UseTimeFilter = true;        // Enable time filter
input int      StartHour = 8;               // Start hour (GMT)
input int      EndHour = 20;                // End hour (GMT)
input bool     AvoidFriday = true;          // Avoid Friday volatility
input int      FridayCloseHour = 17;        // Friday close hour
input bool     AvoidNewsHours = true;       // Avoid news hours
input int      NewsAvoidMinutes = 30;       // News avoidance window (minutes)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo posInfo;

// Current timeframe indicators
int h_ema_fast, h_ema_slow, h_ema_50, h_ema_200, h_ema_20, h_ema_50_intra;
int h_rsi, h_rsi_long, h_macd, h_atr, h_bb, h_stoch, h_adx;
int h_sma_50, h_sma_200;

// Multi-timeframe handles
int h_ema_50_higher, h_ema_200_higher, h_rsi_higher, h_adx_higher;
int h_ema_fast_lower, h_ema_slow_lower, h_rsi_lower, h_stoch_lower;

// Support/Resistance levels
double SupportLevels[];
double ResistanceLevels[];
datetime LastSRUpdate = 0;

// Fibonacci levels
double FibLevels[];

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Initialize arrays
   ArrayResize(SupportLevels, 5);
   ArrayResize(ResistanceLevels, 5);
   ArrayResize(FibLevels, 6);
   
   // Create indicators based on trading mode
   if(TradingMode == MODE_SWING)
   {
      // Swing trading indicators
      h_ema_50 = iMA(Symbol(), PERIOD_CURRENT, Swing_EMA_50, 0, MODE_EMA, PRICE_CLOSE);
      h_ema_200 = iMA(Symbol(), PERIOD_CURRENT, Swing_EMA_200, 0, MODE_EMA, PRICE_CLOSE);
      h_sma_50 = iMA(Symbol(), PERIOD_CURRENT, Swing_EMA_50, 0, MODE_SMA, PRICE_CLOSE);
      h_sma_200 = iMA(Symbol(), PERIOD_CURRENT, Swing_EMA_200, 0, MODE_SMA, PRICE_CLOSE);
      h_rsi = iRSI(Symbol(), PERIOD_CURRENT, Swing_RSI_Period, PRICE_CLOSE);
      h_rsi_long = iRSI(Symbol(), PERIOD_CURRENT, 20, PRICE_CLOSE); // Longer RSI for less noise
   }
   else // MODE_INTRADAY
   {
      // Intraday indicators
      h_ema_fast = iMA(Symbol(), PERIOD_CURRENT, Intraday_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      h_ema_slow = iMA(Symbol(), PERIOD_CURRENT, Intraday_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      h_ema_20 = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
      h_ema_50_intra = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
      h_rsi = iRSI(Symbol(), PERIOD_CURRENT, Intraday_RSI_Period, PRICE_CLOSE);
      h_stoch = iStochastic(Symbol(), PERIOD_CURRENT, Stochastic_K, Stochastic_D, Stochastic_Slowing, MODE_SMA, STO_LOWHIGH);
   }
   
   // Common indicators
   h_macd = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   h_atr = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   h_bb = iBands(Symbol(), PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   h_adx = iADX(Symbol(), PERIOD_CURRENT, 14);
   
   // Multi-timeframe indicators
   if(UseMultiTimeframe)
   {
      h_ema_50_higher = iMA(Symbol(), HigherTimeframe, Swing_EMA_50, 0, MODE_EMA, PRICE_CLOSE);
      h_ema_200_higher = iMA(Symbol(), HigherTimeframe, Swing_EMA_200, 0, MODE_EMA, PRICE_CLOSE);
      h_rsi_higher = iRSI(Symbol(), HigherTimeframe, Swing_RSI_Period, PRICE_CLOSE);
      h_adx_higher = iADX(Symbol(), HigherTimeframe, 14);
      
      h_ema_fast_lower = iMA(Symbol(), LowerTimeframe, Intraday_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      h_ema_slow_lower = iMA(Symbol(), LowerTimeframe, Intraday_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      h_rsi_lower = iRSI(Symbol(), LowerTimeframe, Intraday_RSI_Period, PRICE_CLOSE);
      h_stoch_lower = iStochastic(Symbol(), LowerTimeframe, Stochastic_K, Stochastic_D, Stochastic_Slowing, MODE_SMA, STO_LOWHIGH);
   }
   
   // Validate indicators
   if((TradingMode == MODE_SWING && (h_ema_50 == INVALID_HANDLE || h_ema_200 == INVALID_HANDLE)) ||
      (TradingMode == MODE_INTRADAY && (h_ema_fast == INVALID_HANDLE || h_ema_slow == INVALID_HANDLE)) ||
      h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE)
   {
      Print("❌ Error creating indicators");
      return INIT_FAILED;
   }
   
   Print("==================================================");
   Print("🤖 ADVANCED GOLD TRADING EA v2.0");
   Print("==================================================");
   Print("   Mode: ", TradingMode == MODE_SWING ? "SWING (H4/Daily)" : "INTRADAY (H1/M15)");
   Print("   Symbol: ", Symbol());
   Print("   Risk:Reward: 1:", DoubleToString(RiskRewardRatio, 1));
   Print("   Multi-Timeframe: ", UseMultiTimeframe ? "ENABLED" : "DISABLED");
   Print("   Supertrend: ", UseSupertrend ? "ENABLED" : "DISABLED");
   Print("   VWAP: ", UseVWAP ? "ENABLED" : "DISABLED");
   Print("   Fibonacci: ", UseFibonacci ? "ENABLED" : "DISABLED");
   Print("   S/R Levels: ", UseSupportResistance ? "ENABLED" : "DISABLED");
   Print("==================================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_ema_fast);
   IndicatorRelease(h_ema_slow);
   IndicatorRelease(h_ema_50);
   IndicatorRelease(h_ema_200);
   IndicatorRelease(h_ema_20);
   IndicatorRelease(h_ema_50_intra);
   IndicatorRelease(h_rsi);
   IndicatorRelease(h_rsi_long);
   IndicatorRelease(h_macd);
   IndicatorRelease(h_atr);
   IndicatorRelease(h_bb);
   IndicatorRelease(h_stoch);
   IndicatorRelease(h_adx);
   IndicatorRelease(h_sma_50);
   IndicatorRelease(h_sma_200);
   
   if(UseMultiTimeframe)
   {
      IndicatorRelease(h_ema_50_higher);
      IndicatorRelease(h_ema_200_higher);
      IndicatorRelease(h_rsi_higher);
      IndicatorRelease(h_adx_higher);
      IndicatorRelease(h_ema_fast_lower);
      IndicatorRelease(h_ema_slow_lower);
      IndicatorRelease(h_rsi_lower);
      IndicatorRelease(h_stoch_lower);
   }
   
   Comment("");
}

//+------------------------------------------------------------------+
//| Get indicator value                                               |
//+------------------------------------------------------------------+
double GetInd(int handle, int buffer = 0, int shift = 0)
{
   if(handle == INVALID_HANDLE) return 0;
   double val[];
   ArraySetAsSeries(val, true);
   if(CopyBuffer(handle, buffer, shift, 3, val) > 0)
      return val[shift];
   return 0;
}

//+------------------------------------------------------------------+
//| Get indicator value from different timeframe                      |
//+------------------------------------------------------------------+
double GetIndMTF(int handle, int buffer = 0, int shift = 0)
{
   if(handle == INVALID_HANDLE) return 0;
   double val[];
   ArraySetAsSeries(val, true);
   if(CopyBuffer(handle, buffer, shift, 3, val) > 0)
      return val[shift];
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate Supertrend                                              |
//+------------------------------------------------------------------+
bool GetSupertrend(double &upperBand, double &lowerBand, int &trend)
{
   double atr = GetInd(h_atr);
   if(atr <= 0) return false;
   
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   int bars = Supertrend_Period + 2;
   if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, bars, high) <= 0) return false;
   if(CopyLow(Symbol(), PERIOD_CURRENT, 0, bars, low) <= 0) return false;
   if(CopyClose(Symbol(), PERIOD_CURRENT, 0, bars, close) <= 0) return false;
   
   // Calculate HL2 (typical price)
   double hl2 = (high[1] + low[1]) / 2.0;
   
   // Calculate basic bands
   double basicUpper = hl2 + (Supertrend_ATR_Mult * atr);
   double basicLower = hl2 - (Supertrend_ATR_Mult * atr);
   
   // Final upper and lower bands (Supertrend logic)
   double finalUpper = basicUpper;
   double finalLower = basicLower;
   
   // Adjust bands based on previous close
   if(close[1] <= finalUpper)
      finalUpper = MathMin(finalUpper, high[1]);
   
   if(close[1] >= finalLower)
      finalLower = MathMax(finalLower, low[1]);
   
   upperBand = finalUpper;
   lowerBand = finalLower;
   
   // Determine trend based on current price
   double currentPrice = close[0];
   if(currentPrice > finalUpper)
      trend = 1; // Bullish
   else if(currentPrice < finalLower)
      trend = -1; // Bearish
   else
   {
      // Use previous trend if price is between bands
      static int lastTrend = 0;
      trend = lastTrend;
      if(trend == 0) trend = (currentPrice > hl2) ? 1 : -1;
      lastTrend = trend;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate VWAP                                                   |
//+------------------------------------------------------------------+
double GetVWAP(int period)
{
   double high[], low[], close[];
   long volume[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(volume, true);
   
   int bars = period + 1;
   if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, bars, high) <= 0) return 0;
   if(CopyLow(Symbol(), PERIOD_CURRENT, 0, bars, low) <= 0) return 0;
   if(CopyClose(Symbol(), PERIOD_CURRENT, 0, bars, close) <= 0) return 0;
   if(CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, bars, volume) <= 0) return 0;
   
   double sumPV = 0;
   long sumV = 0;
   
   for(int i = 1; i <= period; i++)
   {
      double typicalPrice = (high[i] + low[i] + close[i]) / 3.0;
      sumPV += typicalPrice * (double)volume[i];
      sumV += volume[i];
   }
   
   if(sumV > 0)
      return sumPV / (double)sumV;
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Retracement Levels                           |
//+------------------------------------------------------------------+
void CalculateFibonacci(double high, double low)
{
   double diff = high - low;
   if(diff <= 0) return;
   
   FibLevels[0] = high;                    // 100% (High)
   FibLevels[1] = high - (diff * 0.236);   // 23.6%
   FibLevels[2] = high - (diff * 0.382);   // 38.2%
   FibLevels[3] = high - (diff * 0.500);   // 50%
   FibLevels[4] = high - (diff * 0.618);   // 61.8%
   FibLevels[5] = low;                     // 0% (Low)
}

//+------------------------------------------------------------------+
//| Detect Support and Resistance Levels                              |
//+------------------------------------------------------------------+
void UpdateSupportResistance()
{
   datetime currentTime = TimeCurrent();
   if(UseSupportResistance && (currentTime - LastSRUpdate) < 3600) return; // Update hourly
   
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   int lookback = SRLookback;
   if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, lookback, high) <= 0) return;
   if(CopyLow(Symbol(), PERIOD_CURRENT, 0, lookback, low) <= 0) return;
   if(CopyClose(Symbol(), PERIOD_CURRENT, 0, lookback, close) <= 0) return;
   
   // Find swing highs (resistance) and swing lows (support)
   ArrayInitialize(SupportLevels, 0);
   ArrayInitialize(ResistanceLevels, 0);
   
   int supportCount = 0;
   int resistanceCount = 0;
   
   for(int i = 3; i < lookback - 3 && (supportCount < 5 || resistanceCount < 5); i++)
   {
      // Check for swing high (resistance)
      if(high[i] > high[i-1] && high[i] > high[i-2] && high[i] > high[i+1] && high[i] > high[i+2])
      {
         if(resistanceCount < 5)
         {
            ResistanceLevels[resistanceCount] = high[i];
            resistanceCount++;
         }
      }
      
      // Check for swing low (support)
      if(low[i] < low[i-1] && low[i] < low[i-2] && low[i] < low[i+1] && low[i] < low[i+2])
      {
         if(supportCount < 5)
         {
            SupportLevels[supportCount] = low[i];
            supportCount++;
         }
      }
   }
   
   // Sort levels
   ArraySort(SupportLevels);
   ArraySort(ResistanceLevels);
   ArrayReverse(ResistanceLevels);
   
   LastSRUpdate = currentTime;
}

//+------------------------------------------------------------------+
//| Check price reaction to Fibonacci and S/R levels                 |
//+------------------------------------------------------------------+
int CheckPriceReaction(double price)
{
   int signal = 0; // 0 = neutral, 1 = bullish, -1 = bearish
   
   if(UseFibonacci)
   {
      for(int i = 0; i < ArraySize(FibLevels); i++)
      {
         double pip = PipValue();
         double tolerance = 5 * pip; // 5 pips tolerance
         
         if(MathAbs(price - FibLevels[i]) < tolerance)
         {
            // Price near Fibonacci level - potential support/resistance
            if(i < 3) signal = 1; // Near upper Fib levels - potential support
            else signal = -1; // Near lower Fib levels - potential resistance
         }
      }
   }
   
   if(UseSupportResistance)
   {
      for(int i = 0; i < ArraySize(SupportLevels); i++)
      {
         if(SupportLevels[i] > 0)
         {
            double pip = PipValue();
            double tolerance = 5 * pip;
            
            if(MathAbs(price - SupportLevels[i]) < tolerance)
            {
               signal = 1; // Near support - bullish
               break;
            }
         }
      }
      
      for(int i = 0; i < ArraySize(ResistanceLevels); i++)
      {
         if(ResistanceLevels[i] > 0)
         {
            double pip = PipValue();
            double tolerance = 5 * pip;
            
            if(MathAbs(price - ResistanceLevels[i]) < tolerance)
            {
               signal = -1; // Near resistance - bearish
               break;
            }
         }
      }
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Detect Golden Cross (Bullish) and Death Cross (Bearish)          |
//+------------------------------------------------------------------+
int DetectMACross()
{
   double ema50 = GetInd(h_ema_50);
   double ema200 = GetInd(h_ema_200);
   double ema50_prev = GetInd(h_ema_50, 0, 1);
   double ema200_prev = GetInd(h_ema_200, 0, 1);
   
   if(ema50 <= 0 || ema200 <= 0) return 0;
   
   // Golden Cross: EMA50 crosses above EMA200
   if(ema50_prev <= ema200_prev && ema50 > ema200)
      return 1; // Bullish
   
   // Death Cross: EMA50 crosses below EMA200
   if(ema50_prev >= ema200_prev && ema50 < ema200)
      return -1; // Bearish
   
   return 0; // No cross
}

//+------------------------------------------------------------------+
//| Get Pip Value                                                     |
//+------------------------------------------------------------------+
double PipValue()
{
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   if(digits == 2 || digits == 3) return point * 10;
   return point * 10;
}

//+------------------------------------------------------------------+
//| Get Spread in Pips                                                |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spread = ask - bid;
   double pip = PipValue();
   if(pip > 0) return spread / pip;
   return 0;
}

//+------------------------------------------------------------------+
//| Check if Spread is Acceptable                                     |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   if(!CheckSpread) return true;
   return GetSpreadPips() <= MaxSpreadPips;
}

//+------------------------------------------------------------------+
//| Multi-Timeframe Trend Confirmation                                |
//+------------------------------------------------------------------+
bool ConfirmHigherTimeframeTrend(string direction)
{
   if(!UseMultiTimeframe) return true;
   
   double ema50_h = GetIndMTF(h_ema_50_higher);
   double ema200_h = GetIndMTF(h_ema_200_higher);
   double adx_h = GetIndMTF(h_adx_higher, 0);
   
   if(ema50_h <= 0 || ema200_h <= 0) return false;
   
   if(direction == "BUY")
   {
      // Higher timeframe must be bullish
      if(ema50_h > ema200_h && adx_h > Swing_ADX_Threshold)
         return true;
   }
   else if(direction == "SELL")
   {
      // Higher timeframe must be bearish
      if(ema50_h < ema200_h && adx_h > Swing_ADX_Threshold)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Generate Comprehensive Trading Signal                             |
//+------------------------------------------------------------------+
void GetComprehensiveSignal(string &direction, int &confidence, bool &trendAligned)
{
   direction = "HOLD";
   confidence = 0;
   trendAligned = false;
   
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   int buySignals = 0;
   int sellSignals = 0;
   int totalSignals = 0;
   
   if(TradingMode == MODE_SWING)
   {
      // === SWING TRADING SIGNAL GENERATION ===
      
      // 1. Golden Cross / Death Cross
      int maCross = DetectMACross();
      if(maCross == 1) { buySignals += 10; totalSignals += 10; }
      else if(maCross == -1) { sellSignals += 10; totalSignals += 10; }
      
      // 2. EMA 50/200 Trend Filter
      double ema50 = GetInd(h_ema_50);
      double ema200 = GetInd(h_ema_200);
      if(ema50 > ema200) { buySignals += 8; totalSignals += 8; }
      else if(ema50 < ema200) { sellSignals += 8; totalSignals += 8; }
      
      // 3. Price vs EMAs
      if(price > ema50 && price > ema200) { buySignals += 5; totalSignals += 5; }
      else if(price < ema50 && price < ema200) { sellSignals += 5; totalSignals += 5; }
      
      // 4. RSI Momentum
      double rsi = GetInd(h_rsi);
      double rsi_long = GetInd(h_rsi_long);
      if(rsi > 50 && rsi < 70) { buySignals += 3; totalSignals += 3; }
      else if(rsi < 50 && rsi > 30) { sellSignals += 3; totalSignals += 3; }
      if(rsi_long > 55) { buySignals += 2; totalSignals += 2; }
      else if(rsi_long < 45) { sellSignals += 2; totalSignals += 2; }
      
      // 5. MACD
      double macd = GetInd(h_macd, 0);
      double macd_sig = GetInd(h_macd, 1);
      if(macd > macd_sig && macd > 0) { buySignals += 5; totalSignals += 5; }
      else if(macd < macd_sig && macd < 0) { sellSignals += 5; totalSignals += 5; }
      
      // 6. ADX Trend Strength
      double adx = GetInd(h_adx, 0);
      if(adx > Swing_ADX_Threshold)
      {
         if(ema50 > ema200) { buySignals += 5; totalSignals += 5; }
         else { sellSignals += 5; totalSignals += 5; }
      }
      
      // 7. Price Reaction to Fibonacci & S/R
      UpdateSupportResistance();
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      CopyHigh(Symbol(), PERIOD_CURRENT, 0, 20, high);
      CopyLow(Symbol(), PERIOD_CURRENT, 0, 20, low);
      int swingHighIdx = ArrayMaximum(high, 0, 20);
      int swingLowIdx = ArrayMinimum(low, 0, 20);
      double swingHigh = high[swingHighIdx];
      double swingLow = low[swingLowIdx];
      CalculateFibonacci(swingHigh, swingLow);
      int priceReaction = CheckPriceReaction(price);
      if(priceReaction == 1) { buySignals += 4; totalSignals += 4; }
      else if(priceReaction == -1) { sellSignals += 4; totalSignals += 4; }
      
      // 8. Supertrend Filter
      if(UseSupertrend)
      {
         double stUpper, stLower;
         int stTrend;
         if(GetSupertrend(stUpper, stLower, stTrend))
         {
            if(stTrend == 1) { buySignals += 6; totalSignals += 6; }
            else if(stTrend == -1) { sellSignals += 6; totalSignals += 6; }
         }
      }
   }
   else // MODE_INTRADAY
   {
      // === INTRADAY TRADING SIGNAL GENERATION ===
      
      // 1. EMA 8/21 Trend Filter
      double ema_fast = GetInd(h_ema_fast);
      double ema_slow = GetInd(h_ema_slow);
      if(ema_fast > ema_slow) { buySignals += 8; totalSignals += 8; }
      else if(ema_fast < ema_slow) { sellSignals += 8; totalSignals += 8; }
      
      // 2. Price vs EMAs
      if(price > ema_fast && price > ema_slow) { buySignals += 5; totalSignals += 5; }
      else if(price < ema_fast && price < ema_slow) { sellSignals += 5; totalSignals += 5; }
      
      // 3. Stochastic Oscillator
      double stoch_main = GetInd(h_stoch, 0);
      double stoch_sig = GetInd(h_stoch, 1);
      if(stoch_main > stoch_sig && stoch_main < 80) { buySignals += 4; totalSignals += 4; }
      else if(stoch_main < stoch_sig && stoch_main > 20) { sellSignals += 4; totalSignals += 4; }
      
      // 4. RSI
      double rsi = GetInd(h_rsi);
      if(rsi > 50 && rsi < 70) { buySignals += 4; totalSignals += 4; }
      else if(rsi < 50 && rsi > 30) { sellSignals += 4; totalSignals += 4; }
      
      // 5. Bollinger Bands Breakout
      double bb_upper = GetInd(h_bb, 1);
      double bb_lower = GetInd(h_bb, 2);
      double bb_middle = GetInd(h_bb, 0);
      if(price > bb_upper) { buySignals += 5; totalSignals += 5; }
      else if(price < bb_lower) { sellSignals += 5; totalSignals += 5; }
      else if(price > bb_middle) { buySignals += 2; totalSignals += 2; }
      else { sellSignals += 2; totalSignals += 2; }
      
      // 6. VWAP Confirmation
      if(UseVWAP)
      {
         double vwap = GetVWAP(VWAP_Period);
         if(price > vwap) { buySignals += 4; totalSignals += 4; }
         else if(price < vwap) { sellSignals += 4; totalSignals += 4; }
      }
      
      // 7. Supertrend Filter
      if(UseSupertrend)
      {
         double stUpper, stLower;
         int stTrend;
         if(GetSupertrend(stUpper, stLower, stTrend))
         {
            if(stTrend == 1) { buySignals += 6; totalSignals += 6; }
            else if(stTrend == -1) { sellSignals += 6; totalSignals += 6; }
         }
      }
   }
   
   // Calculate final signal - More lenient approach
   if(totalSignals > 0)
   {
      // Calculate confidence based on signal strength
      int maxSignals = MathMax(buySignals, sellSignals);
      int minSignals = MathMin(buySignals, sellSignals);
      
      if(buySignals > sellSignals && buySignals >= 3) // Require at least 3 buy signals
      {
         direction = "BUY";
         // More lenient confidence calculation
         confidence = (int)((double)buySignals / totalSignals * 100);
         // Boost confidence if we have strong signals
         if(buySignals >= totalSignals * 0.6) confidence = MathMin(confidence + 10, 95);
         trendAligned = (buySignals >= totalSignals * 0.4); // More lenient alignment
      }
      else if(sellSignals > buySignals && sellSignals >= 3) // Require at least 3 sell signals
      {
         direction = "SELL";
         // More lenient confidence calculation
         confidence = (int)((double)sellSignals / totalSignals * 100);
         // Boost confidence if we have strong signals
         if(sellSignals >= totalSignals * 0.6) confidence = MathMin(confidence + 10, 95);
         trendAligned = (sellSignals >= totalSignals * 0.4); // More lenient alignment
      }
      else
      {
         direction = "HOLD";
         confidence = 50;
         trendAligned = false;
      }
   }
   else
   {
      // Even if no signals, check basic trend
      if(TradingMode == MODE_SWING)
      {
         double ema50 = GetInd(h_ema_50);
         double ema200 = GetInd(h_ema_200);
         double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         
         if(ema50 > ema200 && price > ema50)
         {
            direction = "BUY";
            confidence = 45; // Lower confidence but still tradeable
            trendAligned = true;
         }
         else if(ema50 < ema200 && price < ema50)
         {
            direction = "SELL";
            confidence = 45;
            trendAligned = true;
         }
      }
      else // MODE_INTRADAY
      {
         double ema_fast = GetInd(h_ema_fast);
         double ema_slow = GetInd(h_ema_slow);
         double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         
         if(ema_fast > ema_slow && price > ema_fast)
         {
            direction = "BUY";
            confidence = 45;
            trendAligned = true;
         }
         else if(ema_fast < ema_slow && price < ema_fast)
         {
            direction = "SELL";
            confidence = 45;
            trendAligned = true;
         }
      }
   }
   
   // Multi-timeframe confirmation - Less strict
   if(UseMultiTimeframe && direction != "HOLD")
   {
      if(!ConfirmHigherTimeframeTrend(direction))
      {
         confidence = (int)(confidence * 0.85); // Less reduction (was 0.7, now 0.85)
         // Don't block trade, just reduce confidence slightly
      }
   }
}

//+------------------------------------------------------------------+
//| Count Positions                                                   |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(type == WRONG_VALUE || PositionGetInteger(POSITION_TYPE) == type)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get Position Profit                                               |
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
//| Close Positions                                                    |
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
//| Manage Positions                                                  |
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
      
      // Early exit
      if(EnableEarlyExit && profitPips <= CutLossPips)
      {
         if(isBuy && currentSignal == "SELL" && signalConf >= 60)
         {
            trade.PositionClose(posInfo.Ticket());
            Print("⚠️ EARLY EXIT at ", DoubleToString(profitPips, 1), " pips");
            continue;
         }
         else if(!isBuy && currentSignal == "BUY" && signalConf >= 60)
         {
            trade.PositionClose(posInfo.Ticket());
            Print("⚠️ EARLY EXIT at ", DoubleToString(profitPips, 1), " pips");
            continue;
         }
      }
      
      // Partial close
      if(EnablePartialClose && profitPips >= PartialClosePips)
      {
         double currentVolume = posInfo.Volume();
         double partialVolume = NormalizeDouble(currentVolume * PartialClosePercent, 2);
         if(partialVolume >= SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN))
         {
            if(trade.PositionClosePartial(posInfo.Ticket(), partialVolume))
            {
               Print("💰 PARTIAL CLOSE: ", DoubleToString(partialVolume, 2), 
                     " lots at +", DoubleToString(profitPips, 1), " pips");
               continue;
            }
         }
      }
      
      // Breakeven
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
      
      // Trailing stop
      if(EnableTrailing && profitPips >= TrailStartPips)
      {
         double trailDistance = UseATRTrailing ? atr * 0.8 : TrailStartPips * pip;
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
//| Check if Can Open Trade                                           |
//+------------------------------------------------------------------+
bool CanOpenTrade(string direction, int confidence, bool trendAligned)
{
   if(CountPositions(WRONG_VALUE) >= MaxPositions)
   {
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning > 300)
      {
         Print("🚫 Trade blocked: Max positions reached");
         lastWarning = TimeCurrent();
      }
      return false;
   }
   
   if(!IsSpreadAcceptable())
   {
      static datetime lastSpreadWarning = 0;
      if(TimeCurrent() - lastSpreadWarning > 300)
      {
         Print("🚫 Trade blocked: Spread too wide: ", DoubleToString(GetSpreadPips(), 1), " pips");
         lastSpreadWarning = TimeCurrent();
      }
      return false;
   }
   
   if(confidence < MinConfidence)
   {
      static datetime lastConfWarning = 0;
      if(TimeCurrent() - lastConfWarning > 300)
      {
         Print("🚫 Trade blocked: Confidence too low: ", confidence, "% (Min: ", MinConfidence, "%)");
         lastConfWarning = TimeCurrent();
      }
      return false;
   }
   
   if(!trendAligned)
   {
      static datetime lastAlignWarning = 0;
      if(TimeCurrent() - lastAlignWarning > 300)
      {
         Print("🚫 Trade blocked: Trend not aligned");
         lastAlignWarning = TimeCurrent();
      }
      return false;
   }
   
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CountPositions(type) > 0)
   {
      Print("🚫 Trade blocked: Already have ", direction, " position");
      return false;
   }
   
   // Multi-timeframe confirmation - Make it optional/warning only
   // Don't block trades, just log if not aligned
   if(UseMultiTimeframe && !ConfirmHigherTimeframeTrend(direction))
   {
      static datetime lastMTFWarning = 0;
      if(TimeCurrent() - lastMTFWarning > 300)
      {
         Print("⚠️ Warning: Higher timeframe not fully aligned (trade still allowed)");
         lastMTFWarning = TimeCurrent();
      }
      // Don't return false - allow trade but with reduced confidence
   }
   
   // Time filter
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < StartHour || dt.hour >= EndHour)
      {
         static datetime lastTimeWarning = 0;
         if(TimeCurrent() - lastTimeWarning > 300)
         {
            Print("🚫 Trade blocked: Outside trading hours");
            lastTimeWarning = TimeCurrent();
         }
         return false;
      }
   }
   
   if(AvoidFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= FridayCloseHour)
      {
         Print("🚫 Trade blocked: Friday close time");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   if(!UseRiskBasedLotSize || slDistance <= 0)
      return BaseLotSize;
   
   double riskBaseAmount = AccountInfoDouble(ACCOUNT_BALANCE);
   if(riskBaseAmount <= 0) return BaseLotSize;
   
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0) return BaseLotSize;
   
   double riskAmount = riskBaseAmount * RiskPercent / 100.0;
   double pip = PipValue();
   double slPips = slDistance / pip;
   
   if(slPips <= 0) return BaseLotSize;
   
   double calculatedLot = riskAmount / (slPips * tickValue);
   
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;
   
   if(calculatedLot > MaxLotSize) calculatedLot = MaxLotSize;
   if(calculatedLot > maxLot) calculatedLot = maxLot;
   if(calculatedLot < minLot) calculatedLot = 0;
   
   return NormalizeDouble(calculatedLot, 2);
}

//+------------------------------------------------------------------+
//| Execute Trade (with 1:2 Risk-Reward)                             |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, double lots, string comment)
{
   if(!IsSpreadAcceptable())
   {
      Print("❌ Trade blocked: Spread too wide");
      return false;
   }
   
   double atr = GetInd(h_atr);
   double pip = PipValue();
   double price, sl, tp;
   
   // Calculate SL based on ATR
   double slDistance = atr * 1.5; // Default SL
   
   // Calculate TP based on Risk:Reward ratio (1:2)
   double tpDistance = slDistance * RiskRewardRatio;
   
   // Cap max loss
   double maxSL = 60 * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   // Ensure minimum SL accounts for spread
   double currentSpread = GetSpreadPips() * pip;
   double minSL = currentSpread * 1.5;
   if(slDistance < minSL) slDistance = minSL;
   
   // Recalculate TP with adjusted SL
   tpDistance = slDistance * RiskRewardRatio;
   
   // Calculate lot size
   if(UseRiskBasedLotSize)
   {
      lots = CalculateLotSize(slDistance);
      if(lots <= 0)
      {
         Print("❌ Trade blocked: Calculated lot size too small");
         return false;
      }
   }
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - slDistance;
      tp = price + tpDistance;
      
      if(trade.Buy(lots, Symbol(), price, sl, tp, comment))
      {
         Print("✅ BUY @ ", DoubleToString(price, 2), 
               " Lots: ", DoubleToString(lots, 2),
               " SL: -", DoubleToString(slDistance/pip, 1), 
               " TP: +", DoubleToString(tpDistance/pip, 1),
               " R:R = 1:", DoubleToString(RiskRewardRatio, 1));
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
         Print("✅ SELL @ ", DoubleToString(price, 2),
               " Lots: ", DoubleToString(lots, 2),
               " SL: +", DoubleToString(slDistance/pip, 1), 
               " TP: -", DoubleToString(tpDistance/pip, 1),
               " R:R = 1:", DoubleToString(RiskRewardRatio, 1));
         return true;
      }
   }
   
   Print("❌ Trade failed: ", trade.ResultComment());
   return false;
}

//+------------------------------------------------------------------+
//| Main Tick Function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Get comprehensive signal
   string signal;
   int confidence;
   bool trendAligned;
   GetComprehensiveSignal(signal, confidence, trendAligned);
   
   // Display info
   string modeStr = TradingMode == MODE_SWING ? "SWING" : "INTRADAY";
   Comment(
      "\n🤖 ADVANCED GOLD EA v2.0 [", modeStr, "]\n",
      "══════════════════════════════════════════════\n",
      "💰 Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
      " | Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), "\n",
      "══════════════════════════════════════════════\n",
      (signal == "BUY" ? "🟢" : signal == "SELL" ? "🔴" : "⚪"), " Signal: ", signal, 
      " (", IntegerToString(confidence), "%) ", (trendAligned ? "✅" : "⚠️"), "\n",
      "📊 Spread: ", DoubleToString(GetSpreadPips(), 1), " pips\n",
      "📈 Positions: ", IntegerToString(CountPositions(WRONG_VALUE)), "\n",
      "══════════════════════════════════════════════"
   );
   
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
   
   Print("──────────────────────────────────────");
   Print("New bar | Mode: ", modeStr, " | Signal: ", signal, " (", confidence, "%) | Aligned: ", (trendAligned ? "YES" : "NO"));
   
   // Execute new trades
   if(signal != "HOLD")
   {
      if(CanOpenTrade(signal, confidence, trendAligned))
      {
         string comment = modeStr + "_" + signal;
         Print("✅ Attempting to open ", signal, " trade (Confidence: ", confidence, "%)...");
         ExecuteTrade(signal, BaseLotSize, comment);
      }
      else
      {
         // Detailed diagnostic logging
         Print("❌ Trade blocked by filters:");
         if(CountPositions(WRONG_VALUE) >= MaxPositions)
            Print("   - Max positions reached");
         if(!IsSpreadAcceptable())
            Print("   - Spread too wide: ", DoubleToString(GetSpreadPips(), 1), " pips");
         if(confidence < MinConfidence)
            Print("   - Confidence too low: ", confidence, "% (Min: ", MinConfidence, "%)");
         if(!trendAligned)
            Print("   - Trend not aligned");
         if(CountPositions((signal == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL) > 0)
            Print("   - Already have ", signal, " position");
         if(UseTimeFilter)
         {
            MqlDateTime dt;
            TimeToStruct(TimeCurrent(), dt);
            if(dt.hour < StartHour || dt.hour >= EndHour)
               Print("   - Outside trading hours: ", dt.hour, "h (Allowed: ", StartHour, "-", EndHour, ")");
         }
      }
   }
   else
   {
      Print("⏸️ Signal is HOLD - no trade");
   }
}
//+------------------------------------------------------------------+
