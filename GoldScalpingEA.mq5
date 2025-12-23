//+------------------------------------------------------------------+
//|                                              GoldScalpingEA.mq5  |
//|                         Pure Technical Scalping - NO Fundamentals |
//|                                    Same Logic as Python ML Model  |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping System"
#property version   "2.00"
#property description "Pure Technical Scalping EA for XAUUSD"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS ==="
input double   LotSize = 0.1;              // Lot Size (used when RiskPercent=0)
input double   RiskPercent = 0;            // Risk % per trade (0 = use fixed LotSize)
input int      MaxTrades = 3;              // Max concurrent trades
input int      MagicNumber = 12345;        // Magic Number

input group "=== SCALPING PARAMETERS ==="
input int      ScalpTP_Pips = 20;          // Take Profit (pips)
input int      ScalpSL_Pips = 15;          // Stop Loss (pips)
input double   ATR_SL_Multiplier = 1.5;    // ATR multiplier for SL (0 = use fixed)
input double   ATR_TP_Multiplier = 2.0;    // ATR multiplier for TP (0 = use fixed)

input group "=== SIGNAL SETTINGS ==="
input int      MinConfidence = 60;         // Minimum signal confidence (%)
input int      MinIndicators = 4;          // Min indicators agreeing (out of 7)
input bool     TradeOnlyStrong = true;     // Only trade strong signals

input group "=== INDICATOR PERIODS ==="
input int      EMA_Fast = 9;               // Fast EMA period
input int      EMA_Medium = 21;            // Medium EMA period  
input int      EMA_Slow = 50;              // Slow EMA period
input int      RSI_Period = 14;            // RSI period
input int      RSI_Fast_Period = 5;        // Fast RSI period
input int      Stoch_K = 14;               // Stochastic K period
input int      Stoch_D = 3;                // Stochastic D period
input int      ATR_Period = 14;            // ATR period
input int      MACD_Fast = 12;             // MACD fast
input int      MACD_Slow = 26;             // MACD slow
input int      MACD_Signal = 9;            // MACD signal
input int      BB_Period = 20;             // Bollinger Bands period
input double   BB_Deviation = 2.0;         // Bollinger Bands deviation
input int      CCI_Period = 20;            // CCI period

input group "=== TIME FILTER ==="
input bool     UseTimeFilter = false;      // Use trading hours filter
input int      StartHour = 8;              // Start hour (server time)
input int      EndHour = 20;               // End hour (server time)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;

// Indicator handles
int h_ema_fast, h_ema_medium, h_ema_slow;
int h_rsi, h_rsi_fast;
int h_stoch;
int h_macd;
int h_atr;
int h_bb;
int h_cci;

// Signal structure
struct SignalData
{
   string direction;      // "BUY", "SELL", "HOLD"
   int    confidence;     // 0-100
   int    indicators;     // How many agree
   double sl;
   double tp;
   string reasons[];
};

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check symbol
   if(Symbol() != "XAUUSD" && Symbol() != "GOLD" && StringFind(Symbol(), "XAU") < 0)
   {
      Print("⚠️ Warning: This EA is optimized for Gold (XAUUSD)");
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Create indicator handles
   h_ema_fast = iMA(Symbol(), PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_medium = iMA(Symbol(), PERIOD_CURRENT, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow = iMA(Symbol(), PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_rsi = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   h_rsi_fast = iRSI(Symbol(), PERIOD_CURRENT, RSI_Fast_Period, PRICE_CLOSE);
   h_stoch = iStochastic(Symbol(), PERIOD_CURRENT, Stoch_K, Stoch_D, 3, MODE_SMA, STO_LOWHIGH);
   h_macd = iMACD(Symbol(), PERIOD_CURRENT, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   h_atr = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   h_bb = iBands(Symbol(), PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   h_cci = iCCI(Symbol(), PERIOD_CURRENT, CCI_Period, PRICE_TYPICAL);
   
   // Check handles
   if(h_ema_fast == INVALID_HANDLE || h_ema_medium == INVALID_HANDLE || 
      h_ema_slow == INVALID_HANDLE || h_rsi == INVALID_HANDLE ||
      h_stoch == INVALID_HANDLE || h_macd == INVALID_HANDLE ||
      h_atr == INVALID_HANDLE || h_bb == INVALID_HANDLE)
   {
      Print("❌ Error creating indicator handles");
      return INIT_FAILED;
   }
   
   Print("==================================================");
   Print("⚡ GOLD SCALPING EA - Pure Technical Analysis");
   Print("==================================================");
   Print("   Symbol: ", Symbol());
   Print("   Timeframe: ", EnumToString(Period()));
   Print("   Lot Size: ", LotSize);
   Print("   Min Confidence: ", IntegerToString(MinConfidence), "%");
   Print("==================================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(h_ema_fast);
   IndicatorRelease(h_ema_medium);
   IndicatorRelease(h_ema_slow);
   IndicatorRelease(h_rsi);
   IndicatorRelease(h_rsi_fast);
   IndicatorRelease(h_stoch);
   IndicatorRelease(h_macd);
   IndicatorRelease(h_atr);
   IndicatorRelease(h_bb);
   IndicatorRelease(h_cci);
   
   Print("⚡ Gold Scalping EA stopped");
}

//+------------------------------------------------------------------+
//| Get indicator values                                              |
//+------------------------------------------------------------------+
double GetIndicator(int handle, int buffer = 0, int shift = 0)
{
   double value[];
   ArraySetAsSeries(value, true);
   if(CopyBuffer(handle, buffer, shift, 3, value) > 0)
      return value[shift];
   return 0;
}

//+------------------------------------------------------------------+
//| Get trend direction                                               |
//+------------------------------------------------------------------+
string GetTrend()
{
   double ema_fast = GetIndicator(h_ema_fast);
   double ema_medium = GetIndicator(h_ema_medium);
   double ema_slow = GetIndicator(h_ema_slow);
   
   if(ema_fast > ema_medium && ema_medium > ema_slow)
      return "STRONG_UP";
   else if(ema_fast > ema_medium)
      return "UP";
   else if(ema_fast < ema_medium && ema_medium < ema_slow)
      return "STRONG_DOWN";
   else if(ema_fast < ema_medium)
      return "DOWN";
   else
      return "RANGE";
}

//+------------------------------------------------------------------+
//| Check if retracement (pullback in trend)                          |
//+------------------------------------------------------------------+
bool IsRetracement(string trend, double price)
{
   double ema_fast = GetIndicator(h_ema_fast);
   double ema_medium = GetIndicator(h_ema_medium);
   double ema_slow = GetIndicator(h_ema_slow);
   double rsi = GetIndicator(h_rsi);
   
   // Uptrend pullback
   if(StringFind(trend, "UP") >= 0)
   {
      if(price < ema_fast && price > ema_medium)
         return true;
      if(price < ema_medium && price > ema_slow)
         return true;
      if(rsi < 40)
         return true;
   }
   
   // Downtrend bounce
   if(StringFind(trend, "DOWN") >= 0)
   {
      if(price > ema_fast && price < ema_medium)
         return true;
      if(price > ema_medium && price < ema_slow)
         return true;
      if(rsi > 60)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Generate trading signal (same logic as Python model)              |
//+------------------------------------------------------------------+
SignalData GetSignal()
{
   SignalData signal;
   signal.direction = "HOLD";
   signal.confidence = 50;
   signal.indicators = 0;
   
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Get indicator values
   double ema_fast = GetIndicator(h_ema_fast);
   double ema_medium = GetIndicator(h_ema_medium);
   double ema_slow = GetIndicator(h_ema_slow);
   double rsi = GetIndicator(h_rsi);
   double rsi_fast = GetIndicator(h_rsi_fast);
   double stoch_k = GetIndicator(h_stoch, 0);
   double stoch_d = GetIndicator(h_stoch, 1);
   double macd_main = GetIndicator(h_macd, 0);
   double macd_signal = GetIndicator(h_macd, 1);
   double macd_hist = GetIndicator(h_macd, 2);
   double atr = GetIndicator(h_atr);
   double bb_upper = GetIndicator(h_bb, 1);
   double bb_lower = GetIndicator(h_bb, 2);
   double bb_mid = GetIndicator(h_bb, 0);
   double cci = GetIndicator(h_cci);
   
   int buy_score = 0;
   int sell_score = 0;
   
   // ==========================================================
   // SIGNAL LOGIC (Same as Python ML Model)
   // ==========================================================
   
   // 1. EMA Trend (weight: 2)
   if(ema_fast > ema_medium)
      buy_score += 2;
   else
      sell_score += 2;
      
   // 2. Price vs EMA50 (weight: 2)
   if(price > ema_slow)
      buy_score += 2;
   else
      sell_score += 2;
      
   // 3. RSI (weight: 2-3)
   if(rsi < 30)
      buy_score += 3;  // Oversold = strong buy
   else if(rsi > 70)
      sell_score += 3; // Overbought = strong sell
   else if(rsi > 50)
      buy_score += 1;
   else
      sell_score += 1;
      
   // 4. MACD (weight: 2)
   if(macd_main > macd_signal)
      buy_score += 2;
   else
      sell_score += 2;
      
   // 5. Stochastic (weight: 1-2)
   if(stoch_k < 20)
      buy_score += 2;  // Oversold
   else if(stoch_k > 80)
      sell_score += 2; // Overbought
   else if(stoch_k > stoch_d)
      buy_score += 1;
   else
      sell_score += 1;
      
   // 6. Bollinger Bands (weight: 1-2)
   if(price < bb_lower)
      buy_score += 2;  // At lower band
   else if(price > bb_upper)
      sell_score += 2; // At upper band
      
   // 7. CCI (weight: 1)
   if(cci < -100)
      buy_score += 1;
   else if(cci > 100)
      sell_score += 1;
      
   // 8. Fast EMA cross (scalping)
   double ema_3 = iMA(Symbol(), PERIOD_CURRENT, 3, 0, MODE_EMA, PRICE_CLOSE);
   double ema_8 = iMA(Symbol(), PERIOD_CURRENT, 8, 0, MODE_EMA, PRICE_CLOSE);
   double ema3_val[], ema8_val[];
   ArraySetAsSeries(ema3_val, true);
   ArraySetAsSeries(ema8_val, true);
   CopyBuffer(iMA(Symbol(), PERIOD_CURRENT, 3, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 1, ema3_val);
   CopyBuffer(iMA(Symbol(), PERIOD_CURRENT, 8, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 1, ema8_val);
   
   if(ema3_val[0] > ema8_val[0])
      buy_score += 1;
   else
      sell_score += 1;
   
   // ==========================================================
   // CALCULATE SIGNAL
   // ==========================================================
   int total = buy_score + sell_score;
   
   if(buy_score > sell_score)
   {
      signal.direction = "BUY";
      signal.confidence = (int)((double)buy_score / total * 100);
      signal.indicators = buy_score;
   }
   else if(sell_score > buy_score)
   {
      signal.direction = "SELL";
      signal.confidence = (int)((double)sell_score / total * 100);
      signal.indicators = sell_score;
   }
   
   // ==========================================================
   // CALCULATE SL/TP
   // ==========================================================
   double sl_distance, tp_distance;
   
   if(ATR_SL_Multiplier > 0)
      sl_distance = atr * ATR_SL_Multiplier;
   else
      sl_distance = ScalpSL_Pips * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10;
      
   if(ATR_TP_Multiplier > 0)
      tp_distance = atr * ATR_TP_Multiplier;
   else
      tp_distance = ScalpTP_Pips * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10;
   
   if(signal.direction == "BUY")
   {
      signal.sl = price - sl_distance;
      signal.tp = price + tp_distance;
   }
   else if(signal.direction == "SELL")
   {
      signal.sl = price + sl_distance;
      signal.tp = price - tp_distance;
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Count open positions                                              |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if can trade (time filter)                                  |
//+------------------------------------------------------------------+
bool CanTrade()
{
   if(!UseTimeFilter)
      return true;
      
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(dt.hour >= StartHour && dt.hour < EndHour)
      return true;
      
   return false;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance)
{
   if(RiskPercent <= 0)
      return LotSize;
      
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * RiskPercent / 100;
   
   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   
   double lot = risk_amount / (sl_distance / tick_size * tick_value);
   
   // Normalize lot
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   lot = MathMax(min_lot, MathMin(max_lot, lot));
   lot = MathFloor(lot / step) * step;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(SignalData &signal)
{
   double price = (signal.direction == "BUY") ? 
                  SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                  SymbolInfoDouble(Symbol(), SYMBOL_BID);
                  
   double sl_distance = MathAbs(price - signal.sl);
   double lots = CalculateLotSize(sl_distance);
   
   string comment = StringFormat("Scalp_%s_%d%%", signal.direction, signal.confidence);
   
   bool result = false;
   
   if(signal.direction == "BUY")
   {
      result = trade.Buy(lots, Symbol(), price, signal.sl, signal.tp, comment);
   }
   else if(signal.direction == "SELL")
   {
      result = trade.Sell(lots, Symbol(), price, signal.sl, signal.tp, comment);
   }
   
   if(result)
   {
      Print("✅ ", signal.direction, " executed @ ", DoubleToString(price, 2), 
            " | SL: ", DoubleToString(signal.sl, 2), " | TP: ", DoubleToString(signal.tp, 2),
            " | Confidence: ", IntegerToString(signal.confidence), "%");
   }
   else
   {
      Print("❌ Trade failed: ", trade.ResultComment());
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Display signal on chart                                           |
//+------------------------------------------------------------------+
void DisplaySignal(SignalData &signal)
{
   string trend = GetTrend();
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   string emoji = (signal.direction == "BUY") ? "🟢" : 
                  (signal.direction == "SELL") ? "🔴" : "⚪";
   
   Comment(
      "\n⚡ GOLD SCALPING EA - Pure Technical\n",
      "══════════════════════════════════\n",
      "📅 Time: ", TimeToString(TimeCurrent()), "\n",
      "💰 Price: $", DoubleToString(price, 2), "\n",
      "\n📈 Trend: ", trend, "\n",
      "\n", emoji, " Signal: ", signal.direction, "\n",
      "   Confidence: ", signal.confidence, "%\n",
      "   Indicators: ", signal.indicators, "/8\n",
      "\n🎯 Trade Plan:\n",
      "   Entry: $", DoubleToString(price, 2), "\n",
      "   SL: $", DoubleToString(signal.sl, 2), "\n",
      "   TP: $", DoubleToString(signal.tp, 2), "\n",
      "\n══════════════════════════════════\n",
      "Open positions: ", CountPositions(), "/", MaxTrades
   );
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new bar
   static datetime last_bar = 0;
   datetime current_bar = iTime(Symbol(), PERIOD_CURRENT, 0);
   
   if(current_bar == last_bar)
   {
      // Update display every tick
      SignalData signal = GetSignal();
      DisplaySignal(signal);
      return;
   }
   last_bar = current_bar;
   
   // New bar - check for trade
   Print("========================================");
   Print("⚡ New bar: ", TimeToString(current_bar));
   
   // Check time filter
   if(!CanTrade())
   {
      Print("⏰ Outside trading hours");
      return;
   }
   
   // Check max trades
   if(CountPositions() >= MaxTrades)
   {
      Print("📊 Max trades reached: ", CountPositions());
      return;
   }
   
   // Get signal
   SignalData signal = GetSignal();
   DisplaySignal(signal);
   
   Print("📊 Signal: ", signal.direction, 
         " | Confidence: ", IntegerToString(signal.confidence), "%",
         " | Indicators: ", IntegerToString(signal.indicators));
   
   // Check if signal is strong enough
   if(signal.direction == "HOLD")
   {
      Print("⏸️ No clear signal");
      return;
   }
   
   if(signal.confidence < MinConfidence)
   {
      Print("⚠️ Confidence too low: ", IntegerToString(signal.confidence), "% < ", IntegerToString(MinConfidence), "%");
      return;
   }
   
   if(TradeOnlyStrong && signal.indicators < MinIndicators)
   {
      Print("⚠️ Not enough indicators agreeing: ", IntegerToString(signal.indicators), " < ", IntegerToString(MinIndicators));
      return;
   }
   
   // Check for retracement (better entry)
   string trend = GetTrend();
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   if((signal.direction == "BUY" && StringFind(trend, "UP") >= 0) ||
      (signal.direction == "SELL" && StringFind(trend, "DOWN") >= 0))
   {
      if(IsRetracement(trend, price))
      {
         Print("✅ Retracement detected - Good entry!");
      }
   }
   
   // Execute trade
   ExecuteTrade(signal);
}

//+------------------------------------------------------------------+

