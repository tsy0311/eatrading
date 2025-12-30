//+------------------------------------------------------------------+
//|                                           GoldScalpingEA_ML.mq5  |
//|                    v6.2 - Ultra-Low Drawdown (3% Target)         |
//|     Supports Trend, Scalping, Mean Reversion, Breakout, News    |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping ML System v6.2"
#property version   "6.20"
#property description "Multi-Strategy: Ultra-Low Drawdown (3% Max) - Ultra Conservative"
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
//| STRATEGY DEFINITIONS                                              |
//+------------------------------------------------------------------+
#define STRATEGY_AUTO        0   // Auto-select based on regime
#define STRATEGY_TREND       1   // Trend Following
#define STRATEGY_SCALPING    2   // Scalping
#define STRATEGY_MEAN_REV    3   // Mean Reversion
#define STRATEGY_BREAKOUT    4   // Breakout Trading
#define STRATEGY_NEWS        5   // News/Volatility Trading

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS (3% DRAWDOWN TARGET) ==="
input double   BaseLotSize = 0.05;         // Base Lot Size (v6.2: Reduced for 3% DD)
input double   RiskPercent = 0.3;          // Risk % per trade (v6.2: Ultra-low 0.3%)
input int      MaxPositions = 1;           // Max positions (v6.2: Only 1 for 3% DD)
input int      MagicNumber = 12345;        // Magic Number
input int      MaxSpreadPips = 25;         // Max spread in pips (v6.2: Tighter)
input bool     CheckSpread = true;        // Enable spread filter

input group "=== DRAWDOWN PROTECTION (3% MAX) ==="
input double   MaxDrawdownPercent = 3.0;   // Max drawdown % (v6.2: 3% target)
input double   DailyLossLimitPercent = 1.0; // Daily loss limit % (v6.2: 1% max/day)
input bool     EnableDrawdownProtection = true; // Enable DD protection
input bool     EnableDailyLossLimit = true; // Enable daily loss limit
input double   InitialBalance = 0;         // Initial balance (0 = auto-detect)

input group "=== STRATEGY SELECTION ==="
input int      StrategyMode = 0;           // Strategy: 0=Auto, 1=Trend, 2=Scalping, 3=MeanRev, 4=Breakout, 5=News
input bool     AllowStrategySwitch = true; // Auto-switch strategy by regime

input group "=== ML REGIME DETECTION ==="
input bool     UseMLRegime = true;         // Use ML regime detection
input int      RegimeUpdateBars = 5;       // Update regime every N bars
input bool     ShowRegimeOnChart = true;   // Display regime info

input group "=== RANGING REGIME SETTINGS ==="
input double   Range_ATR_SL = 1.2;         // SL multiplier (v6.1: Tighter to reduce avg loss)
input double   Range_ATR_TP = 2.5;         // TP multiplier (v6.1: Increased for better R:R)
input int      Range_TrailStart = 12;      // Trail start pips (v6.1: Faster trailing)
input int      Range_MinConf = 65;         // Min confidence % (Gold: higher threshold)

input group "=== TRENDING REGIME SETTINGS ==="
input double   Trend_ATR_SL = 1.5;         // SL multiplier (v6.1: Tighter for trends)
input double   Trend_ATR_TP = 3.5;         // TP multiplier (v6.1: Let winners run more)
input int      Trend_TrailStart = 20;      // Trail start pips (v6.1: Faster trailing)
input int      Trend_MinConf = 60;         // Min confidence % (Gold: slightly higher)

input group "=== VOLATILE REGIME SETTINGS ==="
input double   Volat_ATR_SL = 1.8;         // SL multiplier (v6.1: Tighter for volatility)
input double   Volat_ATR_TP = 3.0;         // TP multiplier (v6.1: Better R:R)
input int      Volat_TrailStart = 25;      // Trail start pips (v6.1: Faster trailing)
input int      Volat_MinConf = 75;         // Min confidence % (Gold: very strict)

input group "=== EARLY EXIT ==="
input bool     EnableEarlyExit = true;     // Enable early exit
input int      CutLossPips = -18;          // Cut loss threshold (v6.1: Tighter -18 pips)
input int      BreakevenPips = 12;         // Move to BE at +X pips (v6.1: Faster BE at +12)
input bool     ExitOnWeakSignal = true;    // Exit on signal reversal
input bool     EnablePartialClose = true;  // Enable partial profit taking (v6.1)
input int      PartialClosePips = 25;      // Partial close at +X pips (v6.1)
input double   PartialClosePercent = 0.5;  // Close % of position (v6.1: 50%)

input group "=== TRAILING STOP ==="
input bool     EnableTrailing = true;      // Enable trailing
input int      TrailingStep = 10;          // Trail step pips (Gold: 10-15 typical)
input bool     UseATRTrailing = true;      // Use ATR-based trailing

input group "=== INDICATORS ==="
input int      EMA_Fast = 9;
input int      EMA_Medium = 21;
input int      EMA_Slow = 50;
input int      RSI_Period = 14;
input int      ATR_Period = 14;
input int      ADX_Period = 14;

input group "=== SCALPING SETTINGS ==="
input double   Scalp_ATR_SL = 0.8;         // Scalping SL (v6.1: Tighter 0.8x ATR)
input double   Scalp_ATR_TP = 2.0;         // Scalping TP (v6.1: Better R:R 2.0x)
input int      Scalp_MinConf = 75;         // High confidence required (Gold: very strict)

input group "=== MEAN REVERSION SETTINGS ==="
input double   MeanRev_ATR_SL = 1.2;      // Mean Rev SL (v6.1: Tighter)
input double   MeanRev_ATR_TP = 2.0;      // Mean Rev TP (v6.1: Better R:R 2.0x)
input int      MeanRev_RSI_Extreme = 20;   // RSI extreme threshold (Gold: 20-25)
input int      MeanRev_MinConf = 70;      // Min confidence (Gold: higher)

input group "=== BREAKOUT SETTINGS ==="
input int      Breakout_Lookback = 24;    // Bars for range detection (Gold: 20-24)
input double   Breakout_ATR_SL = 1.5;     // Breakout SL (v6.1: Tighter)
input double   Breakout_ATR_TP = 3.0;     // Breakout TP (v6.1: Better R:R)
input double   Breakout_Threshold = 1.5;  // ATR multiplier (Gold: 1.5-2.0)
input int      Breakout_MinConf = 65;     // Min confidence (Gold: higher)

input group "=== NEWS/VOLATILITY SETTINGS ==="
input double   News_ATR_SL = 3.0;         // Wide SL (Gold: 3.0x for news volatility)
input double   News_ATR_TP = 2.5;         // News TP (Gold: 2.5x)
input double   News_VolMultiplier = 2.5;  // Volatility threshold (Gold: 2.5x typical)
input int      News_MinConf = 80;         // Very high confidence (Gold: 80%+)

input group "=== TIME FILTER (GOLD OPTIMIZED) ==="
input bool     UseTimeFilter = true;      // Gold: Enable for best sessions
input int      StartHour = 8;             // Gold: London open (08:00 GMT)
input int      EndHour = 20;              // Gold: NY close (20:00 GMT)
input bool     AvoidFriday = true;        // Avoid Friday volatility
input int      FridayCloseHour = 17;      // Close before NY close Friday
input bool     AvoidNewsHours = true;     // Avoid major news (8:30, 10:00, 14:00 GMT)
input int      NewsAvoidMinutes = 30;     // Minutes before/after news to avoid

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

// Current active strategy
int ActiveStrategy = STRATEGY_AUTO;

// Dynamic settings based on regime/strategy
double Active_ATR_SL = 1.2;
double Active_ATR_TP = 2.0;
int Active_TrailStart = 12;
int Active_MinConf = 60;

// Breakout detection
double RangeHigh = 0;
double RangeLow = 0;
datetime RangeStartTime = 0;

// Drawdown protection (v6.2)
double InitialBalanceValue = 0;
double DailyStartBalance = 0;
datetime LastDayCheck = 0;

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
   
   // Initialize strategy
   if(StrategyMode == STRATEGY_AUTO)
      ActiveStrategy = SelectStrategyByRegime();
   else
      ActiveStrategy = StrategyMode;
   
   ApplyRegimeSettings();
   
   // Initialize breakout levels
   UpdateBreakoutLevels();
   
   // Initialize drawdown protection (v6.2)
   if(InitialBalance > 0)
      InitialBalanceValue = InitialBalance;
   else
      InitialBalanceValue = AccountInfoDouble(ACCOUNT_BALANCE);
   
   DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   LastDayCheck = TimeCurrent();
   
   Print("==================================================");
   Print("🤖 GOLD SCALPING EA v6.2 - 3% DRAWDOWN TARGET");
   Print("==================================================");
   Print("   Symbol: ", Symbol(), " (Gold Trading Optimized)");
   Print("   ML Regime Detection: ", UseMLRegime ? "ENABLED" : "DISABLED");
   Print("   Current Regime: ", GetRegimeName(CurrentRegime));
   Print("   Strategy Mode: ", GetStrategyName(StrategyMode));
   Print("   Auto Strategy Switch: ", AllowStrategySwitch ? "ENABLED" : "DISABLED");
   Print("   Active Strategy: ", GetStrategyName(ActiveStrategy));
   Print("   Active SL: ", DoubleToString(Active_ATR_SL, 1), "x ATR");
   Print("   Active TP: ", DoubleToString(Active_ATR_TP, 1), "x ATR");
   Print("   Active Trail: +", IntegerToString(Active_TrailStart), " pips");
   Print("   Max Spread: ", IntegerToString(MaxSpreadPips), " pips");
   Print("   Spread Filter: ", CheckSpread ? "ENABLED" : "DISABLED");
   Print("   News Avoidance: ", AvoidNewsHours ? "ENABLED" : "DISABLED");
   Print("   Max Drawdown: ", DoubleToString(MaxDrawdownPercent, 2), "%");
   Print("   Daily Loss Limit: ", DoubleToString(DailyLossLimitPercent, 2), "%");
   Print("   Initial Balance: $", DoubleToString(InitialBalanceValue, 2));
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
//| Check drawdown protection (v6.2)                                   |
//+------------------------------------------------------------------+
bool CheckDrawdownProtection()
{
   if(!EnableDrawdownProtection) return true;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Use the lower of balance or equity for drawdown calculation
   double currentValue = (currentEquity < currentBalance) ? currentEquity : currentBalance;
   
   if(InitialBalanceValue <= 0) return true;
   
   double drawdown = InitialBalanceValue - currentValue;
   double drawdownPercent = (drawdown / InitialBalanceValue) * 100.0;
   
   if(drawdownPercent >= MaxDrawdownPercent)
   {
      Print("🚫 DRAWDOWN LIMIT REACHED: ", DoubleToString(drawdownPercent, 2), 
            "% (Max: ", DoubleToString(MaxDrawdownPercent, 2), "%)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check daily loss limit (v6.2)                                      |
//+------------------------------------------------------------------+
bool CheckDailyLossLimit()
{
   if(!EnableDailyLossLimit) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDay = StringToTime(IntegerToString(dt.year) + "." + 
                                      IntegerToString(dt.mon) + "." + 
                                      IntegerToString(dt.day));
   
   // Reset daily balance if new day
   if(LastDayCheck < currentDay)
   {
      DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      LastDayCheck = currentDay;
      Print("📅 New trading day - Daily start balance: $", DoubleToString(DailyStartBalance, 2));
   }
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = DailyStartBalance - currentBalance;
   double dailyLossPercent = (dailyLoss / DailyStartBalance) * 100.0;
   
   if(dailyLossPercent >= DailyLossLimitPercent)
   {
      Print("🚫 DAILY LOSS LIMIT REACHED: ", DoubleToString(dailyLossPercent, 2), 
            "% (Max: ", DoubleToString(DailyLossLimitPercent, 2), "%)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get point value for pip calculations (Gold optimized)             |
//+------------------------------------------------------------------+
double PipValue()
{
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   // Gold (XAUUSD) typically uses 2 or 3 decimal places
   // 1 pip = 0.01 for 2 decimals, or 0.1 for 3 decimals
   if(digits == 2) return point * 10;  // 0.01 * 10 = 0.1 (1 pip)
   if(digits == 3) return point * 10;  // 0.001 * 10 = 0.01 (1 pip)
   return point * 10;  // Default
}

//+------------------------------------------------------------------+
//| Get current spread in pips                                       |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spread = ask - bid;
   double pip = PipValue();
   
   if(pip > 0)
      return spread / pip;
   return 0;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable for trading                         |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   if(!CheckSpread) return true;
   
   double spreadPips = GetSpreadPips();
   if(spreadPips <= MaxSpreadPips)
      return true;
   
   return false;
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
//| Get strategy name                                                 |
//+------------------------------------------------------------------+
string GetStrategyName(int strategy)
{
   switch(strategy)
   {
      case STRATEGY_AUTO:      return "🔄 AUTO";
      case STRATEGY_TREND:     return "📈 TREND";
      case STRATEGY_SCALPING:  return "⚡ SCALPING";
      case STRATEGY_MEAN_REV:  return "🔄 MEAN REV";
      case STRATEGY_BREAKOUT:  return "💥 BREAKOUT";
      case STRATEGY_NEWS:      return "📰 NEWS";
      default: return "❓ UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Select strategy based on regime                                  |
//+------------------------------------------------------------------+
int SelectStrategyByRegime()
{
   if(!AllowStrategySwitch) return StrategyMode;
   
   switch(CurrentRegime)
   {
      case REGIME_TRENDING:
         return STRATEGY_TREND;
      case REGIME_RANGING:
         return STRATEGY_MEAN_REV;
      case REGIME_VOLATILE:
         return STRATEGY_NEWS;
      default:
         return STRATEGY_TREND;
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
      
      // Update strategy if auto-switching
      if(AllowStrategySwitch && StrategyMode == STRATEGY_AUTO)
      {
         int newStrategy = SelectStrategyByRegime();
         if(newStrategy != ActiveStrategy)
         {
            Print("🔄 STRATEGY SWITCH: ", GetStrategyName(ActiveStrategy), " → ", GetStrategyName(newStrategy));
            ActiveStrategy = newStrategy;
         }
      }
   }
   
   LastRegimeUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Apply settings based on current regime/strategy                   |
//+------------------------------------------------------------------+
void ApplyRegimeSettings()
{
   // Determine active strategy
   if(StrategyMode == STRATEGY_AUTO)
      ActiveStrategy = SelectStrategyByRegime();
   else
      ActiveStrategy = StrategyMode;
   
   // Apply strategy-specific settings
   switch(ActiveStrategy)
   {
      case STRATEGY_SCALPING:
         Active_ATR_SL = Scalp_ATR_SL;
         Active_ATR_TP = Scalp_ATR_TP;
         Active_TrailStart = 5;  // Very early trailing for scalping
         Active_MinConf = Scalp_MinConf;
         break;
         
      case STRATEGY_MEAN_REV:
         Active_ATR_SL = MeanRev_ATR_SL;
         Active_ATR_TP = MeanRev_ATR_TP;
         Active_TrailStart = Range_TrailStart;
         Active_MinConf = MeanRev_MinConf;
         break;
         
      case STRATEGY_BREAKOUT:
         Active_ATR_SL = Breakout_ATR_SL;
         Active_ATR_TP = Breakout_ATR_TP;
         Active_TrailStart = Trend_TrailStart;
         Active_MinConf = Breakout_MinConf;
         break;
         
      case STRATEGY_NEWS:
         Active_ATR_SL = News_ATR_SL;
         Active_ATR_TP = News_ATR_TP;
         Active_TrailStart = Volat_TrailStart;
         Active_MinConf = News_MinConf;
         break;
         
      case STRATEGY_TREND:
      default:
         // Use regime-based settings for trend following
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
         break;
   }
   
   Print("   Strategy: ", GetStrategyName(ActiveStrategy), " | SL=", DoubleToString(Active_ATR_SL, 1), 
         "x, TP=", DoubleToString(Active_ATR_TP, 1), "x, Trail=+", IntegerToString(Active_TrailStart),
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
//| Detect breakout levels                                            |
//+------------------------------------------------------------------+
void UpdateBreakoutLevels()
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, Breakout_Lookback, high) > 0 &&
      CopyLow(Symbol(), PERIOD_CURRENT, 0, Breakout_Lookback, low) > 0)
   {
      RangeHigh = high[ArrayMaximum(high)];
      RangeLow = low[ArrayMinimum(low)];
      RangeStartTime = iTime(Symbol(), PERIOD_CURRENT, Breakout_Lookback - 1);
   }
}

//+------------------------------------------------------------------+
//| Trend Following Strategy Signal                                   |
//+------------------------------------------------------------------+
void GetTrendSignal(string &direction, int &confidence, bool &trendAligned)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   double adx = GetInd(h_adx, 0);
   double macd = GetInd(h_macd, 0);
   double macd_sig = GetInd(h_macd, 1);
   
   int buy = 0, sell = 0;
   
   // Strong trend: all EMAs aligned
   if(ema_f > ema_m && ema_m > ema_s) 
   {
      buy += 5;
      if(price > ema_f) buy += 2;
   }
   else if(ema_f < ema_m && ema_m < ema_s)
   {
      sell += 5;
      if(price < ema_f) sell += 2;
   }
   
   // ADX confirms trend strength
   if(adx > 25)
   {
      if(ema_f > ema_m) buy += 2;
      else sell += 2;
   }
   
   // MACD confirmation
   if(macd > macd_sig && macd > 0) buy += 2;
   else if(macd < macd_sig && macd < 0) sell += 2;
   
   int total = buy + sell;
   if(total > 0)
   {
      if(buy > sell)
      {
         direction = "BUY";
         confidence = (int)((double)buy / total * 100);
         trendAligned = true;
      }
      else if(sell > buy)
      {
         direction = "SELL";
         confidence = (int)((double)sell / total * 100);
         trendAligned = true;
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
      direction = "HOLD";
      confidence = 0;
      trendAligned = false;
   }
}

//+------------------------------------------------------------------+
//| Scalping Strategy Signal                                          |
//+------------------------------------------------------------------+
void GetScalpingSignal(string &direction, int &confidence, bool &trendAligned)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double rsi = GetInd(h_rsi);
   double stoch = GetInd(h_stoch, 0);
   double stoch_d = GetInd(h_stoch, 1);
   double macd = GetInd(h_macd, 0);
   double macd_sig = GetInd(h_macd, 1);
   
   int buy = 0, sell = 0;
   
   // Quick momentum signals - very sensitive
   if(price > ema_f && ema_f > ema_m) buy += 3;
   else if(price < ema_f && ema_f < ema_m) sell += 3;
   
   // RSI quick signals
   if(rsi < 30 && rsi > 20) buy += 2;
   else if(rsi > 70 && rsi < 80) sell += 2;
   
   // Stochastic quick signals
   if(stoch < 25 && stoch > stoch_d) buy += 2;
   else if(stoch > 75 && stoch < stoch_d) sell += 2;
   
   // MACD quick crossover
   if(macd > macd_sig && macd > 0) buy += 2;
   else if(macd < macd_sig && macd < 0) sell += 2;
   
   int total = buy + sell;
   if(total > 0)
   {
      if(buy > sell)
      {
         direction = "BUY";
         confidence = (int)((double)buy / total * 100);
      }
      else
      {
         direction = "SELL";
         confidence = (int)((double)sell / total * 100);
      }
   }
   else
   {
      direction = "HOLD";
      confidence = 0;
   }
   trendAligned = (direction != "HOLD");
}

//+------------------------------------------------------------------+
//| Mean Reversion Strategy Signal                                    |
//+------------------------------------------------------------------+
void GetMeanReversionSignal(string &direction, int &confidence, bool &trendAligned)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double rsi = GetInd(h_rsi);
   double bb_upper = GetInd(h_bb, 1);
   double bb_lower = GetInd(h_bb, 2);
   double bb_mid = GetInd(h_bb, 0);
   double stoch = GetInd(h_stoch, 0);
   double macd = GetInd(h_macd, 0);
   double macd_sig = GetInd(h_macd, 1);
   
   int buy = 0, sell = 0;
   
   // Price at lower BB = oversold (buy signal)
   if(price <= bb_lower)
   {
      buy += 4;
      if(rsi < MeanRev_RSI_Extreme) buy += 3;
      if(stoch < 20) buy += 2;
   }
   
   // Price at upper BB = overbought (sell signal)
   if(price >= bb_upper)
   {
      sell += 4;
      if(rsi > 100 - MeanRev_RSI_Extreme) sell += 3;
      if(stoch > 80) sell += 2;
   }
   
   // RSI extremes
   if(rsi < MeanRev_RSI_Extreme) buy += 3;
   else if(rsi > 100 - MeanRev_RSI_Extreme) sell += 3;
   
   // MACD divergence (mean reversion setup)
   if(price < bb_mid && macd > macd_sig) buy += 2;
   else if(price > bb_mid && macd < macd_sig) sell += 2;
   
   int total = buy + sell;
   if(total > 0)
   {
      if(buy > sell)
      {
         direction = "BUY";
         confidence = (int)((double)buy / total * 100);
      }
      else
      {
         direction = "SELL";
         confidence = (int)((double)sell / total * 100);
      }
   }
   else
   {
      direction = "HOLD";
      confidence = 0;
   }
   trendAligned = false; // Mean reversion is counter-trend
}

//+------------------------------------------------------------------+
//| Breakout Strategy Signal                                          |
//+------------------------------------------------------------------+
void GetBreakoutSignal(string &direction, int &confidence, bool &trendAligned)
{
   UpdateBreakoutLevels();
   
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double atr = GetInd(h_atr);
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   long volume = iVolume(Symbol(), PERIOD_CURRENT, 0);
   long avgVolume = 0;
   
   // Calculate average volume
   long volumes[];
   ArraySetAsSeries(volumes, true);
   int copied = CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, 10, volumes);
   if(copied > 0)
   {
      int count = MathMin(copied, 10);
      for(int i = 0; i < count; i++) avgVolume += volumes[i];
      if(count > 0) avgVolume /= count;
   }
   
   int buy = 0, sell = 0;
   double breakoutThreshold = atr * Breakout_Threshold;
   
   // Breakout above range
   if(RangeHigh > 0 && price > RangeHigh + breakoutThreshold)
   {
      buy += 5;
      if(avgVolume > 0 && volume > (avgVolume * 1.5)) buy += 3; // Volume confirmation
      if(ema_f > ema_m) buy += 2; // Trend confirmation
   }
   
   // Breakout below range
   if(RangeLow > 0 && price < RangeLow - breakoutThreshold)
   {
      sell += 5;
      if(avgVolume > 0 && volume > (avgVolume * 1.5)) sell += 3; // Volume confirmation
      if(ema_f < ema_m) sell += 2; // Trend confirmation
   }
   
   // Near breakout levels (anticipation)
   if(RangeHigh > 0 && price > RangeHigh && price < RangeHigh + breakoutThreshold * 0.5)
   {
      if(ema_f > ema_m) buy += 2;
   }
   
   if(RangeLow > 0 && price < RangeLow && price > RangeLow - breakoutThreshold * 0.5)
   {
      if(ema_f < ema_m) sell += 2;
   }
   
   int total = buy + sell;
   if(total > 0)
   {
      if(buy > sell)
      {
         direction = "BUY";
         confidence = (int)((double)buy / total * 100);
         trendAligned = true;
      }
      else
      {
         direction = "SELL";
         confidence = (int)((double)sell / total * 100);
         trendAligned = true;
      }
   }
   else
   {
      direction = "HOLD";
      confidence = 0;
      trendAligned = false;
   }
}

//+------------------------------------------------------------------+
//| News/Volatility Strategy Signal                                   |
//+------------------------------------------------------------------+
void GetNewsSignal(string &direction, int &confidence, bool &trendAligned)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double atr = GetInd(h_atr);
   double atr_avg = 0;
   double atr_vals[];
   ArraySetAsSeries(atr_vals, true);
   if(CopyBuffer(h_atr, 0, 0, 20, atr_vals) > 0)
   {
      for(int i = 0; i < 20; i++) atr_avg += atr_vals[i];
      atr_avg /= 20;
   }
   
   double volRatio = (atr_avg > 0) ? atr / atr_avg : 1.0;
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double rsi = GetInd(h_rsi);
   
   int buy = 0, sell = 0;
   
   // Only trade during high volatility
   if(volRatio >= News_VolMultiplier)
   {
      // Follow momentum during volatility spikes
      if(ema_f > ema_m && price > ema_f)
      {
         buy += 4;
         if(rsi > 50 && rsi < 70) buy += 2; // Not overbought yet
      }
      else if(ema_f < ema_m && price < ema_f)
      {
         sell += 4;
         if(rsi < 50 && rsi > 30) sell += 2; // Not oversold yet
      }
   }
   
   int total = buy + sell;
   if(total > 0)
   {
      if(buy > sell)
      {
         direction = "BUY";
         confidence = (int)((double)buy / total * 100);
         trendAligned = true;
      }
      else
      {
         direction = "SELL";
         confidence = (int)((double)sell / total * 100);
         trendAligned = true;
      }
   }
   else
   {
      direction = "HOLD";
      confidence = 0;
      trendAligned = false;
   }
}

//+------------------------------------------------------------------+
//| Get signal with confidence (routes to strategy)                   |
//+------------------------------------------------------------------+
void GetSignal(string &direction, int &confidence, bool &trendAligned)
{
   // Route to appropriate strategy signal function
   switch(ActiveStrategy)
   {
      case STRATEGY_TREND:
         GetTrendSignal(direction, confidence, trendAligned);
         break;
         
      case STRATEGY_SCALPING:
         GetScalpingSignal(direction, confidence, trendAligned);
         break;
         
      case STRATEGY_MEAN_REV:
         GetMeanReversionSignal(direction, confidence, trendAligned);
         break;
         
      case STRATEGY_BREAKOUT:
         GetBreakoutSignal(direction, confidence, trendAligned);
         break;
         
      case STRATEGY_NEWS:
         GetNewsSignal(direction, confidence, trendAligned);
         break;
         
      default:
      {
         // Default: use original combined signal
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
         break;
      }
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
      
      // === 2. PARTIAL PROFIT TAKING (v6.1) ===
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
               continue; // Skip other management for this iteration
            }
         }
      }
      
      // === 3. MOVE TO BREAKEVEN ===
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
      
      // === 4. REGIME-ADAPTIVE TRAILING ===
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
//| Check if current time is during news hours                        |
//+------------------------------------------------------------------+
bool IsNewsHour()
{
   if(!AvoidNewsHours) return false;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Major news times (GMT): 8:30, 10:00, 13:30, 14:00, 15:00
   int newsHours[] = {8, 10, 13, 14, 15};
   int newsMinutes[] = {30, 0, 30, 0, 0};
   
   for(int i = 0; i < ArraySize(newsHours); i++)
   {
      int hourDiff = dt.hour - newsHours[i];
      int minDiff = dt.min - newsMinutes[i];
      int totalMinutes = hourDiff * 60 + minDiff;
      
      // Check if within avoidance window
      if(MathAbs(totalMinutes) <= NewsAvoidMinutes)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if can open new trade (Gold optimized)                     |
//+------------------------------------------------------------------+
bool CanOpenTrade(string direction, int confidence, bool trendAligned)
{
   int total = CountPositions(WRONG_VALUE);
   if(total >= MaxPositions) return false;
   
   // Check spread first (critical for gold)
   if(!IsSpreadAcceptable())
   {
      static datetime lastSpreadWarning = 0;
      if(TimeCurrent() - lastSpreadWarning > 300) // Warn every 5 minutes
      {
         Print("⚠️ Spread too wide: ", DoubleToString(GetSpreadPips(), 1), 
               " pips (Max: ", IntegerToString(MaxSpreadPips), ")");
         lastSpreadWarning = TimeCurrent();
      }
      return false;
   }
   
   // Use regime-adaptive confidence threshold
   if(confidence < Active_MinConf) return false;
   
   // In trending regime, require trend alignment
   if(CurrentRegime == REGIME_TRENDING && !trendAligned) return false;
   
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CountPositions(type) > 0) return false;
   
   if(!PassesMomentumFilter()) return false;
   
   // Avoid news hours (Gold is very sensitive to news)
   if(IsNewsHour()) return false;
   
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
      if(dt.day_of_week == 5 && dt.hour >= FridayCloseHour) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade with regime-adaptive SL/TP (Gold optimized)         |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, double lots, string comment)
{
   // Check spread before executing (critical for gold)
   if(!IsSpreadAcceptable())
   {
      Print("❌ Trade blocked: Spread too wide (", DoubleToString(GetSpreadPips(), 1), 
            " pips > ", IntegerToString(MaxSpreadPips), " pips)");
      return false;
   }
   
   double atr = GetInd(h_atr);
   double pip = PipValue();
   double price, sl, tp;
   
   // Use regime-adaptive multipliers
   double slDistance = atr * Active_ATR_SL;
   double tpDistance = atr * Active_ATR_TP;
   
   // Cap max loss (Gold: 50-60 pips typical, allow up to 80 for volatile)
   double maxSL = 60 * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   // Ensure minimum SL distance accounts for spread (Gold: spread can be 20-40 pips)
   double currentSpread = GetSpreadPips() * pip;
   double minSL = currentSpread * 1.5; // SL should be at least 1.5x spread
   if(slDistance < minSL) slDistance = minSL;
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - slDistance;
      tp = price + tpDistance;
      
      if(trade.Buy(lots, Symbol(), price, sl, tp, comment))
      {
         Print("✅ BUY [", GetRegimeName(CurrentRegime), "] @ ", DoubleToString(price, 2), 
               " SL: -", DoubleToString(slDistance/pip, 1), " TP: +", DoubleToString(tpDistance/pip, 1),
               " Spread: ", DoubleToString(GetSpreadPips(), 1), " pips");
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
               " SL: +", DoubleToString(slDistance/pip, 1), " TP: -", DoubleToString(tpDistance/pip, 1),
               " Spread: ", DoubleToString(GetSpreadPips(), 1), " pips");
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
   
   double spreadPips = GetSpreadPips();
   string spreadStatus = (spreadPips <= MaxSpreadPips) ? "✅" : "⚠️";
   
      // DisplayInfo function is now integrated into OnTick() for v6.2
}

//+------------------------------------------------------------------+
//| Main tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check drawdown protection (v6.2)
   if(!CheckDrawdownProtection())
   {
      Comment("\n🚫 TRADING BLOCKED: Max Drawdown Reached\n",
              "Current DD: ", DoubleToString((InitialBalanceValue - AccountInfoDouble(ACCOUNT_EQUITY)) / InitialBalanceValue * 100, 2), "%\n",
              "Max Allowed: ", DoubleToString(MaxDrawdownPercent, 2), "%");
      return;
   }
   
   // Check daily loss limit (v6.2)
   if(!CheckDailyLossLimit())
   {
      Comment("\n🚫 TRADING BLOCKED: Daily Loss Limit Reached\n",
              "Daily Loss: ", DoubleToString((DailyStartBalance - AccountInfoDouble(ACCOUNT_BALANCE)) / DailyStartBalance * 100, 2), "%\n",
              "Max Allowed: ", DoubleToString(DailyLossLimitPercent, 2), "%");
      return;
   }
   
   // Get signal
   string signal;
   int confidence;
   bool trendAligned;
   GetSignal(signal, confidence, trendAligned);
   
   int trendStrength;
   string trend = GetTrend(trendStrength);
   
   // Display info (v6.2: include drawdown info)
   double currentDD = (InitialBalanceValue > 0) ? 
                      (InitialBalanceValue - AccountInfoDouble(ACCOUNT_EQUITY)) / InitialBalanceValue * 100 : 0;
   double dailyLoss = (DailyStartBalance > 0) ? 
                      (DailyStartBalance - AccountInfoDouble(ACCOUNT_BALANCE)) / DailyStartBalance * 100 : 0;
   
   Comment(
      "\n🤖 GOLD SCALPING EA v6.2 - 3% DRAWDOWN TARGET\n",
      "══════════════════════════════════════════════\n",
      "💰 Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
      " | Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), "\n",
      "📉 Drawdown: ", DoubleToString(currentDD, 2), "% / ", DoubleToString(MaxDrawdownPercent, 2), "%\n",
      "📅 Daily Loss: ", DoubleToString(dailyLoss, 2), "% / ", DoubleToString(DailyLossLimitPercent, 2), "%\n",
      "══════════════════════════════════════════════\n",
      "🎯 REGIME: ", GetRegimeName(CurrentRegime), " (", DoubleToString(CurrentConfidence, 0), "%)\n",
      "📊 STRATEGY: ", GetStrategyName(ActiveStrategy), "\n",
      "📈 Trend: ", trend, "\n",
      (signal == "BUY" ? "🟢" : signal == "SELL" ? "🔴" : "⚪"), " Signal: ", signal, 
      " (", IntegerToString(confidence), "%) ", (trendAligned ? "✅" : "⚠️"), "\n",
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
   
   // Update regime periodically
   static int barsSinceRegimeUpdate = 0;
   barsSinceRegimeUpdate++;
   if(barsSinceRegimeUpdate >= RegimeUpdateBars)
   {
      DetectRegime();
      barsSinceRegimeUpdate = 0;
   }
   
   // Update breakout levels on new bar
   UpdateBreakoutLevels();
   
   Print("──────────────────────────────────────");
   Print("New bar | ", GetRegimeName(CurrentRegime), " | Strategy: ", GetStrategyName(ActiveStrategy),
         " | Signal: ", signal, " (", confidence, "%) | Aligned: ", (trendAligned ? "YES" : "NO"));
   
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

