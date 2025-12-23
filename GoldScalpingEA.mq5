//+------------------------------------------------------------------+
//|                                              GoldScalpingEA.mq5  |
//|                    v5.0 - Aggressive Profit Target (5x Return)   |
//|                    Let Winners Run, Cut Losers Fast              |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping System v5.0"
#property version   "5.00"
#property description "Target: 5x returns. Big wins, small losses."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS ==="
input double   BaseLotSize = 0.1;          // Base Lot Size
input int      MaxPositions = 2;           // Max positions (quality over quantity)
input int      MagicNumber = 12345;        // Magic Number

input group "=== PROFIT TARGET SYSTEM ==="
input double   ATR_SL_Multiplier = 0.8;    // Tight SL = 0.8x ATR
input double   ATR_TP_Multiplier = 2.5;    // Big TP = 2.5x ATR (R:R = 1:3)
input int      MaxLossPips = 20;           // Max loss 20 pips (TIGHT)
input int      MinProfitPips = 40;         // Min TP 40 pips (LET IT RUN)

input group "=== SMART EXIT ==="
input bool     EnableTrailing = true;      // Enable trailing stop
input int      TrailingStart = 20;         // Trail after +20 pips
input int      TrailingStep = 8;           // Trail by 8 pips
input int      BreakevenPips = 15;         // Breakeven at +15 pips
input bool     PartialClose = true;        // Close 50% at first target
input int      PartialClosePips = 25;      // Partial close at +25 pips

input group "=== SIGNAL QUALITY (STRICT) ==="
input int      MinConfidence = 70;         // HIGH confidence only (70%)
input bool     RequireStrongTrend = true;  // Only trade strong trends
input bool     RequireMultiTimeframe = true; // Check higher TF trend

input group "=== TREND FILTER ==="
input int      EMA_Fast = 8;               // Fast EMA
input int      EMA_Medium = 21;            // Medium EMA  
input int      EMA_Slow = 50;              // Slow EMA
input int      EMA_Trend = 200;            // Trend EMA (H4 equivalent)

input group "=== MOMENTUM ==="
input int      RSI_Period = 14;
input int      RSI_Overbought = 70;        // Overbought level
input int      RSI_Oversold = 30;          // Oversold level
input int      ATR_Period = 14;

input group "=== SESSION FILTER ==="
input bool     UseSessionFilter = true;    // Trade only active sessions
input int      LondonStart = 8;            // London session start
input int      LondonEnd = 17;             // London session end
input int      NYStart = 13;               // NY session start
input int      NYEnd = 21;                 // NY session end

input group "=== RISK CONTROL ==="
input double   MaxDailyLoss = 3.0;         // Max daily loss % (stop trading)
input double   MaxDailyProfit = 10.0;      // Daily profit target %
input bool     AvoidFriday = true;         // No new trades Friday
input bool     AvoidNews = true;           // Avoid trading near news (manual)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo posInfo;

int h_ema_fast, h_ema_medium, h_ema_slow, h_ema_trend;
int h_rsi, h_macd, h_atr, h_bb, h_stoch;
int h_ema_h4;  // Higher timeframe

double dailyProfit = 0;
double dailyStartBalance = 0;
datetime lastDay = 0;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Current timeframe indicators
   h_ema_fast = iMA(Symbol(), PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_medium = iMA(Symbol(), PERIOD_CURRENT, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow = iMA(Symbol(), PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_trend = iMA(Symbol(), PERIOD_CURRENT, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   h_rsi = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   h_macd = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   h_atr = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   h_stoch = iStochastic(Symbol(), PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_bb = iBands(Symbol(), PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   
   // H4 trend for multi-timeframe
   h_ema_h4 = iMA(Symbol(), PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   
   if(h_ema_fast == INVALID_HANDLE || h_rsi == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("==================================================");
   Print("🚀 GOLD SCALPING EA v5.0 - 5X PROFIT TARGET");
   Print("==================================================");
   Print("   R:R Target = 1:", DoubleToString(ATR_TP_Multiplier/ATR_SL_Multiplier, 1));
   Print("   Max Loss: ", IntegerToString(MaxLossPips), " pips");
   Print("   Min Profit: ", IntegerToString(MinProfitPips), " pips");
   Print("   Confidence: ", IntegerToString(MinConfidence), "%+");
   Print("   Strong Trend Required: ", RequireStrongTrend ? "YES" : "NO");
   Print("   Session Filter: ", UseSessionFilter ? "ON" : "OFF");
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
   IndicatorRelease(h_ema_trend);
   IndicatorRelease(h_rsi);
   IndicatorRelease(h_macd);
   IndicatorRelease(h_atr);
   IndicatorRelease(h_stoch);
   IndicatorRelease(h_bb);
   IndicatorRelease(h_ema_h4);
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
//| Pip value for calculations                                        |
//+------------------------------------------------------------------+
double PipValue()
{
   return SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10;
}

//+------------------------------------------------------------------+
//| Check if in active trading session                                |
//+------------------------------------------------------------------+
bool IsActiveSession()
{
   if(!UseSessionFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // London or NY session (overlap is best)
   bool inLondon = (hour >= LondonStart && hour < LondonEnd);
   bool inNY = (hour >= NYStart && hour < NYEnd);
   
   return (inLondon || inNY);
}

//+------------------------------------------------------------------+
//| Get trend strength (0-5 scale)                                    |
//+------------------------------------------------------------------+
int GetTrendStrength(string &trendDir)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   double ema_t = GetInd(h_ema_trend);
   double ema_h4 = GetInd(h_ema_h4);
   
   int bullScore = 0;
   int bearScore = 0;
   
   // EMA stacking
   if(ema_f > ema_m) bullScore++; else bearScore++;
   if(ema_m > ema_s) bullScore++; else bearScore++;
   if(ema_s > ema_t) bullScore++; else bearScore++;
   
   // Price position
   if(price > ema_m) bullScore++; else bearScore++;
   
   // Higher timeframe alignment
   if(RequireMultiTimeframe)
   {
      if(price > ema_h4) bullScore++; else bearScore++;
   }
   
   if(bullScore > bearScore)
   {
      trendDir = "UP";
      return bullScore;
   }
   else
   {
      trendDir = "DOWN";
      return bearScore;
   }
}

//+------------------------------------------------------------------+
//| Get high-quality signal                                           |
//+------------------------------------------------------------------+
void GetSignal(string &direction, int &confidence, bool &isStrong)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   double ema_t = GetInd(h_ema_trend);
   double rsi = GetInd(h_rsi);
   double macd = GetInd(h_macd, 0);
   double macd_sig = GetInd(h_macd, 1);
   double stoch = GetInd(h_stoch, 0);
   double bb_upper = GetInd(h_bb, 1);
   double bb_lower = GetInd(h_bb, 2);
   double bb_mid = GetInd(h_bb, 0);
   
   int buy = 0, sell = 0;
   isStrong = false;
   
   // === TREND ALIGNMENT (most important) ===
   string trendDir;
   int trendStrength = GetTrendStrength(trendDir);
   
   if(trendDir == "UP")
   {
      buy += trendStrength * 2;  // Weight by strength
      if(trendStrength >= 4) isStrong = true;
   }
   else
   {
      sell += trendStrength * 2;
      if(trendStrength >= 4) isStrong = true;
   }
   
   // === MOMENTUM CONFIRMATION ===
   
   // RSI extremes (reversal zones)
   if(rsi < RSI_Oversold) buy += 3;
   else if(rsi > RSI_Overbought) sell += 3;
   else if(rsi > 50) buy += 1;
   else sell += 1;
   
   // MACD momentum
   if(macd > macd_sig) buy += 2;
   else sell += 2;
   
   // MACD histogram strength
   double hist = macd - macd_sig;
   if(hist > 0 && hist > GetInd(h_macd, 0, 1) - GetInd(h_macd, 1, 1))
      buy += 1;  // Increasing bullish momentum
   else if(hist < 0 && hist < GetInd(h_macd, 0, 1) - GetInd(h_macd, 1, 1))
      sell += 1; // Increasing bearish momentum
   
   // Stochastic in extreme zones
   if(stoch < 20) buy += 2;
   else if(stoch > 80) sell += 2;
   
   // Bollinger Band position
   if(price < bb_lower) buy += 2;
   else if(price > bb_upper) sell += 2;
   else if(price < bb_mid) buy += 1;
   else sell += 1;
   
   // Calculate result
   int total = buy + sell;
   
   if(buy > sell)
   {
      direction = "BUY";
      confidence = (int)((double)buy / total * 100);
   }
   else if(sell > buy)
   {
      direction = "SELL";
      confidence = (int)((double)sell / total * 100);
   }
   else
   {
      direction = "HOLD";
      confidence = 50;
      isStrong = false;
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
//| Get position profit in pips                                       |
//+------------------------------------------------------------------+
double GetPositionProfitPips(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return 0;
   
   double pip = PipValue();
   double openPrice = posInfo.PriceOpen();
   bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
   double currentPrice = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_BID) 
                               : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   
   if(isBuy)
      return (currentPrice - openPrice) / pip;
   else
      return (openPrice - currentPrice) / pip;
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
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage positions - trailing, breakeven, partial close             |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double pip = PipValue();
   
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
      
      double profitPips = GetPositionProfitPips(ticket);
      
      // === PARTIAL CLOSE at first target ===
      if(PartialClose && profitPips >= PartialClosePips && lots > 0.02)
      {
         double closeLots = NormalizeDouble(lots * 0.5, 2);
         closeLots = MathMax(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), closeLots);
         
         if(trade.PositionClosePartial(ticket, closeLots))
         {
            Print("✅ Partial close 50% at +", DoubleToString(profitPips, 1), " pips");
         }
      }
      
      // === MOVE TO BREAKEVEN ===
      if(profitPips >= BreakevenPips)
      {
         double newSL;
         if(isBuy)
         {
            newSL = openPrice + pip * 2;  // 2 pips profit locked
            if(currentSL < newSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
         else
         {
            newSL = openPrice - pip * 2;
            if(currentSL > newSL || currentSL == 0)
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
      
      // === TRAILING STOP ===
      if(EnableTrailing && profitPips >= TrailingStart)
      {
         double trailDist = TrailingStep * pip;
         double newSL;
         
         if(isBuy)
         {
            double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            newSL = bid - trailDist;
            if(newSL > currentSL + pip)
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
         else
         {
            double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            newSL = ask + trailDist;
            if(newSL < currentSL - pip || currentSL == 0)
            {
               trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check daily limits                                                |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + 
                                  IntegerToString(dt.mon) + "." + 
                                  IntegerToString(dt.day));
   
   // Reset daily tracking
   if(today != lastDay)
   {
      lastDay = today;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dailyProfit = 0;
   }
   
   // Calculate today's P&L
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyProfit = currentBalance - dailyStartBalance;
   double dailyProfitPct = (dailyProfit / dailyStartBalance) * 100;
   
   // Check daily loss limit
   if(dailyProfitPct <= -MaxDailyLoss)
   {
      Print("⚠️ Daily loss limit reached: ", DoubleToString(dailyProfitPct, 2), "%");
      return false;
   }
   
   // Check daily profit target (optional - keep trading)
   if(dailyProfitPct >= MaxDailyProfit)
   {
      Print("🎯 Daily profit target reached: ", DoubleToString(dailyProfitPct, 2), "%");
      // Continue trading but reduce risk could be added
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade with optimal SL/TP                                  |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, string comment)
{
   double atr = GetInd(h_atr);
   double pip = PipValue();
   double price, sl, tp;
   
   // Calculate SL (tight, capped)
   double slDistance = atr * ATR_SL_Multiplier;
   double maxSL = MaxLossPips * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   // Calculate TP (big, minimum enforced)
   double tpDistance = atr * ATR_TP_Multiplier;
   double minTP = MinProfitPips * pip;
   if(tpDistance < minTP) tpDistance = minTP;
   
   // Ensure minimum R:R of 1:2
   if(tpDistance < slDistance * 2)
      tpDistance = slDistance * 2.5;
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - slDistance;
      tp = price + tpDistance;
      
      if(trade.Buy(BaseLotSize, Symbol(), price, sl, tp, comment))
      {
         Print("🟢 BUY @ ", DoubleToString(price, 2));
         Print("   SL: ", DoubleToString(sl, 2), " (-", DoubleToString(slDistance/pip, 0), " pips)");
         Print("   TP: ", DoubleToString(tp, 2), " (+", DoubleToString(tpDistance/pip, 0), " pips)");
         Print("   R:R = 1:", DoubleToString(tpDistance/slDistance, 1));
         return true;
      }
   }
   else
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      sl = price + slDistance;
      tp = price - tpDistance;
      
      if(trade.Sell(BaseLotSize, Symbol(), price, sl, tp, comment))
      {
         Print("🔴 SELL @ ", DoubleToString(price, 2));
         Print("   SL: ", DoubleToString(sl, 2), " (+", DoubleToString(slDistance/pip, 0), " pips)");
         Print("   TP: ", DoubleToString(tp, 2), " (-", DoubleToString(tpDistance/pip, 0), " pips)");
         Print("   R:R = 1:", DoubleToString(tpDistance/slDistance, 1));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Display info                                                      |
//+------------------------------------------------------------------+
void DisplayInfo(string signal, int confidence, bool isStrong, string trend, int trendStr)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int buyCount = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   
   string emoji = (signal == "BUY") ? "🟢" : (signal == "SELL") ? "🔴" : "⚪";
   string strengthStr = isStrong ? "💪 STRONG" : "📊 Normal";
   
   double profitPct = ((balance - 10000) / 10000) * 100;
   double target5x = 50000;
   double progress = (balance / target5x) * 100;
   
   Comment(
      "\n🚀 GOLD EA v5.0 - 5X PROFIT TARGET\n",
      "══════════════════════════════════════\n",
      "💰 Balance: $", DoubleToString(balance, 2), "\n",
      "📈 Total P/L: ", (profitPct >= 0 ? "+" : ""), DoubleToString(profitPct, 1), "%\n",
      "🎯 Progress to 5x: ", DoubleToString(progress, 1), "%\n",
      "\n", emoji, " Signal: ", signal, " (", IntegerToString(confidence), "%)\n",
      "   ", strengthStr, " | Trend: ", trend, " (", IntegerToString(trendStr), "/5)\n",
      "\n📊 Positions: BUY ", IntegerToString(buyCount), " | SELL ", IntegerToString(sellCount), "\n",
      "\n⚙️ Settings:\n",
      "   SL: ", IntegerToString(MaxLossPips), " pips max\n",
      "   TP: ", IntegerToString(MinProfitPips), " pips min\n",
      "   Min R:R = 1:2.5\n",
      "══════════════════════════════════════"
   );
}

//+------------------------------------------------------------------+
//| Main tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage existing positions every tick
   ManagePositions();
   
   // Get signal
   string signal;
   int confidence;
   bool isStrong;
   GetSignal(signal, confidence, isStrong);
   
   string trendDir;
   int trendStrength = GetTrendStrength(trendDir);
   
   // Display
   DisplayInfo(signal, confidence, isStrong, trendDir, trendStrength);
   
   // Check for new bar only
   static datetime lastBar = 0;
   datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   // === FILTERS ===
   
   // Daily limits
   if(!CheckDailyLimits()) return;
   
   // Session filter
   if(!IsActiveSession())
   {
      Print("Outside active session - no trading");
      return;
   }
   
   // Friday filter
   if(AvoidFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5)
      {
         Print("Friday - no new trades");
         return;
      }
   }
   
   // Max positions
   int totalPos = CountPositions(WRONG_VALUE);
   if(totalPos >= MaxPositions)
   {
      return;
   }
   
   // === SIGNAL QUALITY CHECKS ===
   
   // Minimum confidence
   if(confidence < MinConfidence)
   {
      Print("Signal confidence too low: ", IntegerToString(confidence), "%");
      return;
   }
   
   // Require strong trend
   if(RequireStrongTrend && !isStrong)
   {
      Print("Waiting for strong trend signal...");
      return;
   }
   
   // Trend alignment check
   if((signal == "BUY" && trendDir != "UP") || (signal == "SELL" && trendDir != "DOWN"))
   {
      Print("Signal not aligned with trend - skip");
      return;
   }
   
   // Check if already have position in this direction
   ENUM_POSITION_TYPE posType = (signal == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CountPositions(posType) > 0)
   {
      return;
   }
   
   // === EXECUTE TRADE ===
   Print("========================================");
   Print("🎯 HIGH QUALITY SIGNAL DETECTED!");
   Print("   Direction: ", signal);
   Print("   Confidence: ", IntegerToString(confidence), "%");
   Print("   Trend: ", trendDir, " (", IntegerToString(trendStrength), "/5)");
   Print("   Strong: ", isStrong ? "YES" : "NO");
   
   if(signal == "BUY")
   {
      ExecuteTrade("BUY", "v5_BUY_" + IntegerToString(confidence));
   }
   else if(signal == "SELL")
   {
      ExecuteTrade("SELL", "v5_SELL_" + IntegerToString(confidence));
   }
}
//+------------------------------------------------------------------+
