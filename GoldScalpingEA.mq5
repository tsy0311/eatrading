//+------------------------------------------------------------------+
//|                                              GoldScalpingEA.mq5  |
//|                    v4.2 - Removed overly strict momentum filter  |
//|                    Balanced SL/TP, quality signals, no stacking  |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping System v4.2"
#property version   "4.20"
#property description "Balanced: Quality signals, reasonable SL, no stacking"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS ==="
input double   BaseLotSize = 0.1;          // Base Lot Size
input double   RiskPercent = 0;            // Risk % (0 = fixed lot)
input int      MaxPositions = 3;           // Max positions (reduced from 5)
input int      MagicNumber = 12345;        // Magic Number

input group "=== RISK MANAGEMENT (BALANCED) ==="
input double   ATR_SL_Multiplier = 1.2;    // SL = 1.2x ATR (balanced)
input double   ATR_TP_Multiplier = 2.0;    // TP = 2.0x ATR (1:1.67 R:R)
input int      MaxLossPips = 35;           // Maximum loss per trade in pips
input int      MinRiskReward = 1;          // Minimum Risk:Reward ratio

input group "=== EARLY EXIT (BALANCED) ==="
input bool     EnableEarlyExit = true;     // Enable early exit
input int      CutLossPips = -15;          // Cut loss at -15 pips (give room)
input int      BreakevenPips = 12;         // Move to BE at +12 pips
input bool     ExitOnWeakSignal = true;    // Exit if signal weakens

input group "=== TRAILING STOP ==="
input bool     EnableTrailing = true;      // Enable trailing
input int      TrailingStart = 15;         // Start at +15 pips
input int      TrailingStep = 5;           // Trail by 5 pips
input bool     UseATRTrailing = true;      // Use ATR-based trailing

input group "=== STACKING ==="
input bool     EnableStacking = false;     // DISABLED - focus on quality
input int      StackAfterPips = 25;        // Stack after +25 pips
input double   StackMultiplier = 0.3;      // Stack = 0.3x base
input int      MaxStackLevel = 2;          // Max 2 stacks

input group "=== SIGNAL FILTER (QUALITY) ==="
input int      MinConfidence = 65;         // Min 65% confidence (stricter)
input int      StackConfidence = 75;       // Stack needs 75%
input int      ReversalConfidence = 75;    // Reversal needs 75%
input bool     RequireTrendAlignment = true; // Require trend + signal alignment

input group "=== TREND REVERSAL ==="
input bool     EnableReversal = true;      // Trade reversals
input int      ReversalConfirmBars = 2;    // Confirm bars
input bool     CloseOnReversal = true;     // Close opposite on reversal

input group "=== INDICATORS ==="
input int      EMA_Fast = 9;
input int      EMA_Medium = 21;
input int      EMA_Slow = 50;
input int      RSI_Period = 14;
input int      ATR_Period = 14;

input group "=== TIME FILTER ==="
input bool     UseTimeFilter = false;
input int      StartHour = 8;
input int      EndHour = 20;
input bool     AvoidFriday = true;         // No new trades on Friday
input int      FridayCloseHour = 18;       // Close all Friday 18:00

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo posInfo;

int h_ema_fast, h_ema_medium, h_ema_slow;
int h_rsi, h_macd, h_atr, h_bb, h_stoch;

string prevTrend = "NONE";

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
   
   if(h_ema_fast == INVALID_HANDLE || h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   Print("==================================================");
   Print("⚡ GOLD SCALPING EA v4.2 - Balanced");
   Print("==================================================");
   Print("   SL: ", DoubleToString(ATR_SL_Multiplier, 1), "x ATR (max ", IntegerToString(MaxLossPips), " pips)");
   Print("   TP: ", DoubleToString(ATR_TP_Multiplier, 1), "x ATR (R:R = 1:", DoubleToString(ATR_TP_Multiplier/ATR_SL_Multiplier, 1), ")");
   Print("   Cut Loss: ", IntegerToString(CutLossPips), " pips | BE: +", IntegerToString(BreakevenPips), " pips");
   Print("   Min Confidence: ", IntegerToString(MinConfidence), "% | Trend Aligned: ", RequireTrendAlignment ? "YES" : "NO");
   Print("   Stacking: ", EnableStacking ? "ON" : "OFF");
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
//| Get trend with strength                                           |
//+------------------------------------------------------------------+
string GetTrend(int &strength)
{
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   strength = 0;
   
   // Count bullish/bearish conditions
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
//| Get signal with confidence (stricter version)                     |
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
   
   // === TREND INDICATORS (weight: 2 each) ===
   
   // EMA alignment
   if(ema_f > ema_m && ema_m > ema_s) { buy += 3; }
   else if(ema_f < ema_m && ema_m < ema_s) { sell += 3; }
   else if(ema_f > ema_m) { buy += 1; }
   else { sell += 1; }
   
   // Price vs EMA
   if(price > ema_s) buy += 2; else sell += 2;
   
   // === MOMENTUM INDICATORS ===
   
   // RSI with zones
   if(rsi < 25) buy += 3;        // Very oversold
   else if(rsi < 35) buy += 2;   // Oversold
   else if(rsi > 75) sell += 3;  // Very overbought
   else if(rsi > 65) sell += 2;  // Overbought
   else if(rsi > 50) buy += 1;
   else sell += 1;
   
   // MACD
   if(macd > macd_sig && macd > 0) buy += 2;      // Strong bullish
   else if(macd > macd_sig) buy += 1;              // Bullish
   else if(macd < macd_sig && macd < 0) sell += 2; // Strong bearish
   else sell += 1;                                  // Bearish
   
   // Stochastic with confirmation
   if(stoch < 20 && stoch > stoch_d) buy += 2;    // Oversold + turning up
   else if(stoch < 30) buy += 1;
   else if(stoch > 80 && stoch < stoch_d) sell += 2; // Overbought + turning down
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
      // Check if aligned with trend
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
//| Manage positions - trailing, breakeven, early exit                |
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
         // Check if signal reversed
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
               Print("⚠️ EARLY EXIT at ", DoubleToString(profitPips, 1), " pips - Signal reversed");
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
            newSL = openPrice + pip; // 1 pip above entry
            if(currentSL < newSL)
            {
               if(trade.PositionModify(posInfo.Ticket(), newSL, currentTP))
                  Print("✅ BUY moved to breakeven");
            }
         }
         else
         {
            newSL = openPrice - pip; // 1 pip below entry
            if(currentSL > newSL || currentSL == 0)
            {
               if(trade.PositionModify(posInfo.Ticket(), newSL, currentTP))
                  Print("✅ SELL moved to breakeven");
            }
         }
      }
      
      // === 3. TRAILING STOP ===
      if(EnableTrailing && profitPips >= TrailingStart)
      {
         double trailDistance = UseATRTrailing ? atr * 0.8 : TrailingStep * pip;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL + pip)
            {
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(newSL < currentSL - pip || currentSL == 0)
            {
               trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if can open new trade                                       |
//+------------------------------------------------------------------+
bool CanOpenTrade(string direction, int confidence, bool trendAligned)
{
   // Check max positions
   int total = CountPositions(WRONG_VALUE);
   if(total >= MaxPositions) return false;
   
   // Check confidence
   if(confidence < MinConfidence) return false;
   
   // Check trend alignment if required
   if(RequireTrendAlignment && !trendAligned) return false;
   
   // Check if already have position in this direction
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(CountPositions(type) > 0) return false;
   
   // Time filters
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < StartHour || dt.hour >= EndHour) return false;
   }
   
   // Friday filter
   if(AvoidFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if can stack                                                |
//+------------------------------------------------------------------+
bool CanStack(string direction, int confidence)
{
   if(!EnableStacking) return false;
   if(confidence < StackConfidence) return false;
   
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   int currentCount = CountPositions(type);
   
   if(currentCount == 0 || currentCount >= MaxStackLevel) return false;
   
   // Check if existing position is in profit
   double pip = PipValue();
   double minProfit = StackAfterPips * pip;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == Symbol())
         {
            if(posInfo.PositionType() == type)
            {
               double openPrice = posInfo.PriceOpen();
               double currentPrice = (type == POSITION_TYPE_BUY) ? 
                                     SymbolInfoDouble(Symbol(), SYMBOL_BID) :
                                     SymbolInfoDouble(Symbol(), SYMBOL_ASK);
               double profit = (type == POSITION_TYPE_BUY) ? 
                               currentPrice - openPrice : openPrice - currentPrice;
               
               if(profit >= minProfit)
               {
                  Print("✅ Stack condition met: +", DoubleToString(profit/pip, 1), " pips");
                  return true;
               }
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade with proper SL/TP                                   |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, double lots, string comment)
{
   double atr = GetInd(h_atr);
   double pip = PipValue();
   double price, sl, tp;
   
   // Calculate SL distance (capped at MaxLossPips)
   double slDistance = atr * ATR_SL_Multiplier;
   double maxSL = MaxLossPips * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   // Calculate TP distance (maintain R:R ratio)
   double tpDistance = slDistance * ATR_TP_Multiplier;
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - slDistance;
      tp = price + tpDistance;
      
      if(trade.Buy(lots, Symbol(), price, sl, tp, comment))
      {
         Print("✅ BUY @ ", DoubleToString(price, 2), 
               " SL: ", DoubleToString(sl, 2), " (-", DoubleToString(slDistance/pip, 1), " pips)",
               " TP: ", DoubleToString(tp, 2), " (+", DoubleToString(tpDistance/pip, 1), " pips)");
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
               " SL: ", DoubleToString(sl, 2), " (+", DoubleToString(slDistance/pip, 1), " pips)",
               " TP: ", DoubleToString(tp, 2), " (-", DoubleToString(tpDistance/pip, 1), " pips)");
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
   string alignStr = aligned ? "✅ ALIGNED" : "⚠️ NOT ALIGNED";
   
   Comment(
      "\n⚡ GOLD SCALPING EA v4.0 - Optimized\n",
      "══════════════════════════════════════\n",
      "💰 Price: $", DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), 2), "\n",
      "📈 Trend: ", trend, "\n",
      "\n", emoji, " Signal: ", signal, " (", IntegerToString(confidence), "%)\n",
      "   Trend: ", alignStr, "\n",
      "\n📊 POSITIONS:\n",
      "   BUY:  ", IntegerToString(buyCount), " | P/L: $", DoubleToString(buyProfit, 2), "\n",
      "   SELL: ", IntegerToString(sellCount), " | P/L: $", DoubleToString(sellProfit, 2), "\n",
      "   Total: $", DoubleToString(buyProfit + sellProfit, 2), "\n",
      "\n⚙️ SETTINGS:\n",
      "   SL: ", DoubleToString(ATR_SL_Multiplier, 1), "x ATR (max ", IntegerToString(MaxLossPips), " pips)\n",
      "   TP: ", DoubleToString(ATR_TP_Multiplier, 1), "x ATR\n",
      "   Cut Loss: ", IntegerToString(CutLossPips), " pips\n",
      "══════════════════════════════════════"
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
   
   // Manage existing positions (every tick)
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
            Print("🕐 Friday close time - closing all positions");
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
   
   Print("========================================");
   Print("New bar | Signal: ", signal, " (", IntegerToString(confidence), 
         "%) | Trend: ", trend, " | Aligned: ", (trendAligned ? "YES" : "NO"));
   
   // === TREND REVERSAL ===
   if(EnableReversal && confidence >= ReversalConfidence)
   {
      int buyCount = CountPositions(POSITION_TYPE_BUY);
      int sellCount = CountPositions(POSITION_TYPE_SELL);
      
      if(signal == "BUY" && sellCount > 0 && buyCount == 0 && trendAligned)
      {
         Print("🔄 REVERSAL: Closing SELL, opening BUY");
         ClosePositions(POSITION_TYPE_SELL);
         ExecuteTrade("BUY", BaseLotSize, "Reversal_BUY");
         return;
      }
      else if(signal == "SELL" && buyCount > 0 && sellCount == 0 && trendAligned)
      {
         Print("🔄 REVERSAL: Closing BUY, opening SELL");
         ClosePositions(POSITION_TYPE_BUY);
         ExecuteTrade("SELL", BaseLotSize, "Reversal_SELL");
         return;
      }
   }
   
   // === STACKING ===
   if(signal != "HOLD" && CanStack(signal, confidence))
   {
      double stackLots = NormalizeDouble(BaseLotSize * StackMultiplier, 2);
      stackLots = MathMax(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), stackLots);
      ExecuteTrade(signal, stackLots, "Stack_" + signal);
      return;
   }
   
   // === NEW TRADE ===
   if(signal != "HOLD" && CanOpenTrade(signal, confidence, trendAligned))
   {
      ExecuteTrade(signal, BaseLotSize, "Scalp_" + signal);
   }
}
//+------------------------------------------------------------------+
