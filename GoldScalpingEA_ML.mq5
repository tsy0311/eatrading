//+------------------------------------------------------------------+
//|                                           GoldScalpingEA_ML.mq5  |
//|                    Simplified Trend Following EA                 |
//+------------------------------------------------------------------+
#property copyright "Gold Scalping EA"
#property version   "1.00"
#property description "Simple Trend Following EA for Gold Trading"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>


//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== TRADE SETTINGS ==="
input bool     UseRiskBasedLotSize = true;  // Use risk-based lot size calculation
input double   BaseLotSize = 0.05;         // Base Lot Size (if not using risk-based)
input double   RiskPercent = 0.3;          // Risk % per trade
input int      MaxPositions = 1;           // Max positions
input int      MagicNumber = 12345;        // Magic Number
input int      MaxSpreadPips = 25;         // Max spread in pips
input bool     CheckSpread = true;        // Enable spread filter
input double   MaxLotSize = 10.0;          // Maximum lot size allowed

input group "=== TRADING PARAMETERS ==="
input double   ATR_SL_Mult = 1.5;          // Stop Loss multiplier (x ATR)
input double   ATR_TP_Mult = 2.5;          // Take Profit multiplier (x ATR)
input int      TrailStartPips = 15;        // Trailing stop start (pips)
input int      MinConfidence = 60;         // Minimum signal confidence %

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
   
   Print("==================================================");
   Print("🤖 GOLD SCALPING EA");
   Print("==================================================");
   Print("   Symbol: ", Symbol());
   Print("   Lot Size: ", UseRiskBasedLotSize ? "Risk-Based (" + DoubleToString(RiskPercent, 2) + "%)" : "Fixed (" + DoubleToString(BaseLotSize, 2) + ")");
   Print("   SL: ", DoubleToString(ATR_SL_Mult, 1), "x ATR");
   Print("   TP: ", DoubleToString(ATR_TP_Mult, 1), "x ATR");
   Print("   Trail Start: +", IntegerToString(TrailStartPips), " pips");
   Print("   Max Spread: ", IntegerToString(MaxSpreadPips), " pips");
   Print("   Spread Filter: ", CheckSpread ? "ENABLED" : "DISABLED");
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
//| Get signal with confidence (routes to strategy)                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Count positions (improved from MT4-MT5 Collections)             |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
      {
         int error = GetLastError();
         if(error != 0)
            Print("⚠️ Error selecting position: ", error);
         continue;
      }
      
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      if(type == WRONG_VALUE || PositionGetInteger(POSITION_TYPE) == type)
         count++;
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
      if(EnableTrailing && profitPips >= TrailStartPips)
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
//| Check momentum filter (relaxed for better trade opportunities)   |
//+------------------------------------------------------------------+
bool PassesMomentumFilter()
{
   double atr = GetInd(h_atr);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   // Relaxed ATR threshold (was 20, now 10)
   double minATR = 10 * point;
   if(atr < minATR) return false;
   
   double rsi = GetInd(h_rsi);
   
   // Relaxed RSI filter - only block if RSI is very neutral (was 40-60, now 45-55)
   if(rsi > 45 && rsi < 55) return false;
   
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
   if(total >= MaxPositions)
   {
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning > 300)
      {
         Print("🚫 Trade blocked: Max positions reached (", total, "/", MaxPositions, ")");
         lastWarning = TimeCurrent();
      }
      return false;
   }
   
   // Check spread first (critical for gold)
   if(!IsSpreadAcceptable())
   {
      static datetime lastSpreadWarning = 0;
      if(TimeCurrent() - lastSpreadWarning > 300) // Warn every 5 minutes
      {
         Print("🚫 Trade blocked: Spread too wide: ", DoubleToString(GetSpreadPips(), 1), 
               " pips (Max: ", IntegerToString(MaxSpreadPips), ")");
         lastSpreadWarning = TimeCurrent();
      }
      return false;
   }
   
   // Use confidence threshold
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
   
   // Require trend alignment
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
   
   if(!PassesMomentumFilter())
   {
      static datetime lastMomentumWarning = 0;
      if(TimeCurrent() - lastMomentumWarning > 300)
      {
         double atr = GetInd(h_atr);
         double rsi = GetInd(h_rsi);
         Print("🚫 Trade blocked: Momentum filter failed - ATR: ", DoubleToString(atr, 5), " RSI: ", DoubleToString(rsi, 1));
         lastMomentumWarning = TimeCurrent();
      }
      return false;
   }
   
   // Avoid news hours (Gold is very sensitive to news)
   if(IsNewsHour())
   {
      static datetime lastNewsWarning = 0;
      if(TimeCurrent() - lastNewsWarning > 300)
      {
         Print("🚫 Trade blocked: News hour avoidance");
         lastNewsWarning = TimeCurrent();
      }
      return false;
   }
   
   // Time filters
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < StartHour || dt.hour >= EndHour)
      {
         static datetime lastTimeWarning = 0;
         if(TimeCurrent() - lastTimeWarning > 300)
         {
            Print("🚫 Trade blocked: Outside trading hours (", dt.hour, "h - Allowed: ", StartHour, "-", EndHour, ")");
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
//| Calculate lot size based on risk (from MT4-MT5 Collections)     |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   if(!UseRiskBasedLotSize || slDistance <= 0)
      return BaseLotSize;
   
   // Get account balance for risk calculation
   double riskBaseAmount = AccountInfoDouble(ACCOUNT_BALANCE);
   if(riskBaseAmount <= 0) return BaseLotSize;
   
   // Get tick value (value of 1 pip for 1 lot)
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0) return BaseLotSize;
   
   // Calculate lot size based on risk percentage
   // Formula: LotSize = (RiskAmount) / (SL in pips * TickValue)
   double riskAmount = riskBaseAmount * RiskPercent / 100.0;
   double pip = PipValue();
   double slPips = slDistance / pip;
   
   if(slPips <= 0) return BaseLotSize;
   
   double calculatedLot = riskAmount / (slPips * tickValue);
   
   // Normalize lot size to broker's step
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   
   calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;
   
   // Apply limits
   if(calculatedLot > MaxLotSize) calculatedLot = MaxLotSize;
   if(calculatedLot > maxLot) calculatedLot = maxLot;
   if(calculatedLot < minLot) calculatedLot = 0; // Too small, don't trade
   
   return NormalizeDouble(calculatedLot, 2);
}

//+------------------------------------------------------------------+
//| Execute trade with risk-based lot size (Gold optimized)          |
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
   
   // Use fixed multipliers
   double slDistance = atr * ATR_SL_Mult;
   double tpDistance = atr * ATR_TP_Mult;
   
   // Cap max loss (Gold: 50-60 pips typical, allow up to 80 for volatile)
   double maxSL = 60 * pip;
   if(slDistance > maxSL) slDistance = maxSL;
   
   // Ensure minimum SL distance accounts for spread (Gold: spread can be 20-40 pips)
   double currentSpread = GetSpreadPips() * pip;
   double minSL = currentSpread * 1.5; // SL should be at least 1.5x spread
   if(slDistance < minSL) slDistance = minSL;
   
   // Calculate lot size based on risk if enabled
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
         Print("✅ SELL @ ", DoubleToString(price, 2),
               " Lots: ", DoubleToString(lots, 2),
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
   // Get signal
   string signal;
   int confidence;
   bool trendAligned;
   GetTrendSignal(signal, confidence, trendAligned);
   
   int trendStrength;
   string trend = GetTrend(trendStrength);
   
   // Display info
   Comment(
      "\n🤖 GOLD SCALPING EA\n",
      "══════════════════════════════════════════════\n",
      "💰 Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
      " | Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), "\n",
      "══════════════════════════════════════════════\n",
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
   
   Print("──────────────────────────────────────");
   Print("New bar | Signal: ", signal, " (", confidence, "%) | Aligned: ", (trendAligned ? "YES" : "NO"));
   Print("   Spread: ", DoubleToString(GetSpreadPips(), 1), " pips | Positions: ", CountPositions(WRONG_VALUE));
   
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
   if(signal != "HOLD")
   {
      if(CanOpenTrade(signal, confidence, trendAligned))
      {
         string comment = "TREND_" + signal;
         Print("✅ Attempting to open ", signal, " trade...");
         ExecuteTrade(signal, BaseLotSize, comment);
      }
      else
      {
         Print("❌ Trade blocked by filters - check logs above");
      }
   }
   else
   {
      Print("⏸️ Signal is HOLD - no trade");
   }
}
//+------------------------------------------------------------------+

