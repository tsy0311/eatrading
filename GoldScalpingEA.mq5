//+------------------------------------------------------------------+
//|                                              GoldScalpingEA.mq5  |
//|                    Advanced Scalping with Dynamic Position Mgmt  |
//|           Stacking, Early Exit, Trend Reversal, Flexible Trading |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping System v3.0"
#property version   "3.00"
#property description "Smart Scalping: Stack, Cut Loss, Trend Reversal"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS ==="
input double   BaseLotSize = 0.1;          // Base Lot Size
input double   RiskPercent = 0;            // Risk % (0 = use fixed lot)
input int      MaxPositions = 5;           // Max positions (for stacking)
input int      MagicNumber = 12345;        // Magic Number

input group "=== STACKING SETTINGS ==="
input bool     EnableStacking = true;      // Enable position stacking
input int      StackAfterPips = 15;        // Stack after X pips profit
input double   StackMultiplier = 0.5;      // Stack lot multiplier (0.5 = half size)
input int      MaxStackLevel = 3;          // Max stack levels per direction

input group "=== EARLY EXIT / CUT LOSS ==="
input bool     EnableEarlyExit = true;     // Enable early exit on reversal
input int      EarlyExitPips = -10;        // Cut loss at X pips (negative)
input bool     ExitOnReversalSignal = true;// Exit when signal reverses
input int      MinProfitToProtect = 10;    // Move SL to BE after X pips profit

input group "=== TREND REVERSAL ==="
input bool     EnableReversal = true;      // Enable trend reversal trading
input int      ReversalConfirmBars = 2;    // Bars to confirm reversal
input bool     CloseOnReversal = true;     // Close opposite positions on reversal

input group "=== TRAILING STOP ==="
input bool     EnableTrailing = true;      // Enable trailing stop
input int      TrailingStart = 15;         // Start trailing after X pips
input int      TrailingStep = 5;           // Trailing step in pips

input group "=== INDICATOR PERIODS ==="
input int      EMA_Fast = 9;               // Fast EMA
input int      EMA_Medium = 21;            // Medium EMA
input int      EMA_Slow = 50;              // Slow EMA
input int      RSI_Period = 14;            // RSI period
input int      ATR_Period = 14;            // ATR period
input int      MACD_Fast = 12;             // MACD fast
input int      MACD_Slow = 26;             // MACD slow
input int      MACD_Signal = 9;            // MACD signal

input group "=== SIGNAL SETTINGS ==="
input int      MinConfidence = 55;         // Min confidence for new trade
input int      StackConfidence = 65;       // Min confidence for stacking
input int      ReversalConfidence = 70;    // Min confidence for reversal

input group "=== TIME FILTER ==="
input bool     UseTimeFilter = false;      // Use time filter
input int      StartHour = 8;              // Start hour
input int      EndHour = 20;               // End hour

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo posInfo;

int h_ema_fast, h_ema_medium, h_ema_slow;
int h_rsi, h_macd, h_atr, h_bb, h_stoch;

string currentTrend = "NONE";
string previousTrend = "NONE";
int trendChangeBars = 0;

struct PositionData {
   ulong ticket;
   double openPrice;
   double profit;
   double lots;
   ENUM_POSITION_TYPE type;
   int stackLevel;
};

//+------------------------------------------------------------------+
//| Expert initialization                                             |
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
   h_macd = iMACD(Symbol(), PERIOD_CURRENT, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   h_atr = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   h_stoch = iStochastic(Symbol(), PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_bb = iBands(Symbol(), PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   
   if(h_ema_fast == INVALID_HANDLE || h_rsi == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   Print("==================================================");
   Print("⚡ GOLD SCALPING EA v3.0 - Smart Trading");
   Print("==================================================");
   Print("   Stacking: ", EnableStacking ? "ON" : "OFF");
   Print("   Early Exit: ", EnableEarlyExit ? "ON" : "OFF");
   Print("   Trend Reversal: ", EnableReversal ? "ON" : "OFF");
   Print("   Trailing Stop: ", EnableTrailing ? "ON" : "OFF");
   Print("==================================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
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
//| Get current trend                                                 |
//+------------------------------------------------------------------+
string GetTrend()
{
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   
   if(ema_f > ema_m && ema_m > ema_s)
      return "STRONG_UP";
   else if(ema_f > ema_m)
      return "UP";
   else if(ema_f < ema_m && ema_m < ema_s)
      return "STRONG_DOWN";
   else if(ema_f < ema_m)
      return "DOWN";
   return "RANGE";
}

//+------------------------------------------------------------------+
//| Check for trend reversal                                          |
//+------------------------------------------------------------------+
bool IsTrendReversal(string &newTrend)
{
   string trend = GetTrend();
   newTrend = trend;
   
   // Check if trend changed direction
   bool wasUp = (StringFind(previousTrend, "UP") >= 0);
   bool wasDown = (StringFind(previousTrend, "DOWN") >= 0);
   bool isUp = (StringFind(trend, "UP") >= 0);
   bool isDown = (StringFind(trend, "DOWN") >= 0);
   
   if((wasUp && isDown) || (wasDown && isUp))
   {
      trendChangeBars++;
      if(trendChangeBars >= ReversalConfirmBars)
      {
         previousTrend = trend;
         trendChangeBars = 0;
         return true;
      }
   }
   else
   {
      trendChangeBars = 0;
      previousTrend = trend;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get signal with confidence                                        |
//+------------------------------------------------------------------+
void GetSignal(string &direction, int &confidence)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ema_f = GetInd(h_ema_fast);
   double ema_m = GetInd(h_ema_medium);
   double ema_s = GetInd(h_ema_slow);
   double rsi = GetInd(h_rsi);
   double macd = GetInd(h_macd, 0);
   double macd_sig = GetInd(h_macd, 1);
   double stoch = GetInd(h_stoch, 0);
   double bb_upper = GetInd(h_bb, 1);
   double bb_lower = GetInd(h_bb, 2);
   
   int buy = 0, sell = 0;
   
   // EMA trend
   if(ema_f > ema_m) buy += 2; else sell += 2;
   if(price > ema_s) buy += 2; else sell += 2;
   
   // RSI
   if(rsi < 30) buy += 3;
   else if(rsi > 70) sell += 3;
   else if(rsi > 50) buy += 1;
   else sell += 1;
   
   // MACD
   if(macd > macd_sig) buy += 2; else sell += 2;
   
   // Stochastic
   if(stoch < 20) buy += 2;
   else if(stoch > 80) sell += 2;
   
   // Bollinger
   if(price < bb_lower) buy += 2;
   else if(price > bb_upper) sell += 2;
   
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
   }
}

//+------------------------------------------------------------------+
//| Count positions by type                                           |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type, double &totalProfit, double &totalLots)
{
   int count = 0;
   totalProfit = 0;
   totalLots = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == Symbol())
         {
            if(posInfo.PositionType() == type)
            {
               count++;
               totalProfit += posInfo.Profit();
               totalLots += posInfo.Volume();
            }
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get total position info                                           |
//+------------------------------------------------------------------+
int GetAllPositions(double &buyProfit, double &sellProfit, int &buyCount, int &sellCount)
{
   double buyLots, sellLots;
   buyCount = CountPositions(POSITION_TYPE_BUY, buyProfit, buyLots);
   sellCount = CountPositions(POSITION_TYPE_SELL, sellProfit, sellLots);
   return buyCount + sellCount;
}

//+------------------------------------------------------------------+
//| Close all positions of a type                                     |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == Symbol())
         {
            if(posInfo.PositionType() == type)
            {
               trade.PositionClose(posInfo.Ticket());
               Print("Closed ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
                     " @ ", DoubleToString(posInfo.PriceOpen(), 2),
                     " P/L: ", DoubleToString(posInfo.Profit(), 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   ClosePositions(POSITION_TYPE_BUY);
   ClosePositions(POSITION_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Check and apply trailing stop                                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!EnableTrailing) return;
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() != MagicNumber || posInfo.Symbol() != Symbol())
            continue;
            
         double openPrice = posInfo.PriceOpen();
         double currentSL = posInfo.StopLoss();
         double currentTP = posInfo.TakeProfit();
         
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            double profitPips = (bid - openPrice) / point / 10;
            
            if(profitPips >= TrailingStart)
            {
               double newSL = bid - TrailingStep * point * 10;
               if(newSL > currentSL + point)
               {
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
               }
            }
            // Move to breakeven
            else if(profitPips >= MinProfitToProtect && currentSL < openPrice)
            {
               trade.PositionModify(posInfo.Ticket(), openPrice + point * 10, currentTP);
               Print("BUY moved to breakeven");
            }
         }
         else // SELL
         {
            double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            double profitPips = (openPrice - ask) / point / 10;
            
            if(profitPips >= TrailingStart)
            {
               double newSL = ask + TrailingStep * point * 10;
               if(newSL < currentSL - point || currentSL == 0)
               {
                  trade.PositionModify(posInfo.Ticket(), newSL, currentTP);
               }
            }
            // Move to breakeven
            else if(profitPips >= MinProfitToProtect && (currentSL > openPrice || currentSL == 0))
            {
               trade.PositionModify(posInfo.Ticket(), openPrice - point * 10, currentTP);
               Print("SELL moved to breakeven");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for early exit signals                                      |
//+------------------------------------------------------------------+
void CheckEarlyExit(string currentSignal, int signalConf)
{
   if(!EnableEarlyExit) return;
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() != MagicNumber || posInfo.Symbol() != Symbol())
            continue;
            
         double openPrice = posInfo.PriceOpen();
         double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ?
                               SymbolInfoDouble(Symbol(), SYMBOL_BID) :
                               SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         
         double profitPips;
         if(posInfo.PositionType() == POSITION_TYPE_BUY)
            profitPips = (currentPrice - openPrice) / point / 10;
         else
            profitPips = (openPrice - currentPrice) / point / 10;
         
         // Early cut loss
         if(profitPips <= EarlyExitPips)
         {
            // Check if signal reversed
            if(ExitOnReversalSignal)
            {
               if((posInfo.PositionType() == POSITION_TYPE_BUY && currentSignal == "SELL" && signalConf >= ReversalConfidence) ||
                  (posInfo.PositionType() == POSITION_TYPE_SELL && currentSignal == "BUY" && signalConf >= ReversalConfidence))
               {
                  trade.PositionClose(posInfo.Ticket());
                  Print("⚠️ EARLY EXIT: Signal reversed! Closed at ", 
                        DoubleToString(profitPips, 1), " pips");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if can stack position                                       |
//+------------------------------------------------------------------+
bool CanStack(string direction, int signalConf)
{
   if(!EnableStacking) return false;
   if(signalConf < StackConfidence) return false;
   
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   ENUM_POSITION_TYPE type = (direction == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   
   int stackCount = 0;
   double bestProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == Symbol())
         {
            if(posInfo.PositionType() == type)
            {
               stackCount++;
               double openPrice = posInfo.PriceOpen();
               double currentPrice = (type == POSITION_TYPE_BUY) ?
                                     SymbolInfoDouble(Symbol(), SYMBOL_BID) :
                                     SymbolInfoDouble(Symbol(), SYMBOL_ASK);
               
               double profitPips;
               if(type == POSITION_TYPE_BUY)
                  profitPips = (currentPrice - openPrice) / point / 10;
               else
                  profitPips = (openPrice - currentPrice) / point / 10;
               
               if(profitPips > bestProfit)
                  bestProfit = profitPips;
            }
         }
      }
   }
   
   // Can stack if: under max level AND best position is in profit
   if(stackCount < MaxStackLevel && bestProfit >= StackAfterPips)
   {
      Print("✅ Stack condition met: ", IntegerToString(stackCount), " positions, ",
            DoubleToString(bestProfit, 1), " pips profit");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(string direction, double lots, string comment)
{
   double atr = GetInd(h_atr);
   double price, sl, tp;
   
   if(direction == "BUY")
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      sl = price - atr * 1.5;
      tp = price + atr * 2.5;
      return trade.Buy(lots, Symbol(), price, sl, tp, comment);
   }
   else
   {
      price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      sl = price + atr * 1.5;
      tp = price - atr * 2.5;
      return trade.Sell(lots, Symbol(), price, sl, tp, comment);
   }
}

//+------------------------------------------------------------------+
//| Display info on chart                                             |
//+------------------------------------------------------------------+
void DisplayInfo(string signal, int confidence, string trend)
{
   double buyProfit, sellProfit;
   int buyCount, sellCount;
   GetAllPositions(buyProfit, sellProfit, buyCount, sellCount);
   
   string emoji = (signal == "BUY") ? "🟢" : (signal == "SELL") ? "🔴" : "⚪";
   
   Comment(
      "\n⚡ GOLD SCALPING EA v3.0\n",
      "══════════════════════════════════\n",
      "💰 Price: $", DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), 2), "\n",
      "📈 Trend: ", trend, "\n",
      "\n", emoji, " Signal: ", signal, " (", IntegerToString(confidence), "%)\n",
      "\n📊 POSITIONS:\n",
      "   BUY:  ", IntegerToString(buyCount), " | P/L: $", DoubleToString(buyProfit, 2), "\n",
      "   SELL: ", IntegerToString(sellCount), " | P/L: $", DoubleToString(sellProfit, 2), "\n",
      "   Total: $", DoubleToString(buyProfit + sellProfit, 2), "\n",
      "\n⚙️ FEATURES:\n",
      "   Stacking: ", (EnableStacking ? "ON" : "OFF"), "\n",
      "   Early Exit: ", (EnableEarlyExit ? "ON" : "OFF"), "\n",
      "   Trailing: ", (EnableTrailing ? "ON" : "OFF"), "\n",
      "══════════════════════════════════"
   );
}

//+------------------------------------------------------------------+
//| Main tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Always manage positions
   ManageTrailingStop();
   
   // Get current signal
   string signal;
   int confidence;
   GetSignal(signal, confidence);
   
   string trend = GetTrend();
   DisplayInfo(signal, confidence, trend);
   
   // Check early exit
   CheckEarlyExit(signal, confidence);
   
   // Check for new bar
   static datetime lastBar = 0;
   datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   // Time filter
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < StartHour || dt.hour >= EndHour) return;
   }
   
   Print("========================================");
   Print("New bar: ", TimeToString(currentBar));
   Print("Signal: ", signal, " (", IntegerToString(confidence), "%) | Trend: ", trend);
   
   // Check trend reversal
   string newTrend;
   if(EnableReversal && IsTrendReversal(newTrend))
   {
      Print("🔄 TREND REVERSAL DETECTED: ", newTrend);
      
      if(CloseOnReversal)
      {
         if(StringFind(newTrend, "UP") >= 0)
         {
            Print("Closing all SELL positions...");
            ClosePositions(POSITION_TYPE_SELL);
         }
         else if(StringFind(newTrend, "DOWN") >= 0)
         {
            Print("Closing all BUY positions...");
            ClosePositions(POSITION_TYPE_BUY);
         }
      }
   }
   
   // Get position counts
   double buyProfit, sellProfit;
   int buyCount, sellCount;
   int totalPos = GetAllPositions(buyProfit, sellProfit, buyCount, sellCount);
   
   // === STACKING LOGIC ===
   if(EnableStacking && signal != "HOLD")
   {
      if(signal == "BUY" && CanStack("BUY", confidence))
      {
         double stackLots = NormalizeDouble(BaseLotSize * StackMultiplier, 2);
         stackLots = MathMax(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), stackLots);
         
         if(ExecuteTrade("BUY", stackLots, "Stack_BUY_" + IntegerToString(buyCount + 1)))
            Print("✅ STACKED BUY #", IntegerToString(buyCount + 1), " @ ", DoubleToString(stackLots, 2), " lots");
      }
      else if(signal == "SELL" && CanStack("SELL", confidence))
      {
         double stackLots = NormalizeDouble(BaseLotSize * StackMultiplier, 2);
         stackLots = MathMax(SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN), stackLots);
         
         if(ExecuteTrade("SELL", stackLots, "Stack_SELL_" + IntegerToString(sellCount + 1)))
            Print("✅ STACKED SELL #", IntegerToString(sellCount + 1), " @ ", DoubleToString(stackLots, 2), " lots");
      }
   }
   
   // === NEW POSITION LOGIC ===
   if(totalPos >= MaxPositions)
   {
      Print("Max positions reached: ", IntegerToString(totalPos));
      return;
   }
   
   if(confidence < MinConfidence)
   {
      Print("Confidence too low: ", IntegerToString(confidence), "%");
      return;
   }
   
   // Open new position if none in that direction
   if(signal == "BUY" && buyCount == 0)
   {
      if(ExecuteTrade("BUY", BaseLotSize, "Scalp_BUY_" + IntegerToString(confidence)))
         Print("✅ NEW BUY opened");
   }
   else if(signal == "SELL" && sellCount == 0)
   {
      if(ExecuteTrade("SELL", BaseLotSize, "Scalp_SELL_" + IntegerToString(confidence)))
         Print("✅ NEW SELL opened");
   }
   
   // === REVERSAL TRADE ===
   if(EnableReversal && confidence >= ReversalConfidence)
   {
      // If strong BUY signal but have SELL positions
      if(signal == "BUY" && sellCount > 0 && buyCount == 0)
      {
         Print("🔄 Reversal: Closing SELL, Opening BUY");
         ClosePositions(POSITION_TYPE_SELL);
         ExecuteTrade("BUY", BaseLotSize, "Reversal_BUY");
      }
      // If strong SELL signal but have BUY positions
      else if(signal == "SELL" && buyCount > 0 && sellCount == 0)
      {
         Print("🔄 Reversal: Closing BUY, Opening SELL");
         ClosePositions(POSITION_TYPE_BUY);
         ExecuteTrade("SELL", BaseLotSize, "Reversal_SELL");
      }
   }
}
//+------------------------------------------------------------------+
