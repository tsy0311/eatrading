# ⚡ Gold SCALPING System for MT5

Complete scalping system with ML training + MetaTrader 5 Expert Advisor.

## 🔄 Two Core Files

| File | Purpose |
|------|---------|
| `GoldPricePrediction_Training.ipynb` | Train ML models in Python |
| `GoldScalpingEA.mq5` | Execute trades in MT5 |

## 🚀 Quick Start

### Step 1: Train Models (Python)
```bash
# Run the Jupyter notebook
jupyter notebook GoldPricePrediction_Training.ipynb
# Or run all cells in VS Code / Cursor
```

### Step 2: Get Quick Signal (Python)
```bash
python quick_predict.py
python quick_predict.py 2650.50  # with custom price
```

### Step 3: Run EA in MT5
1. Copy `GoldScalpingEA.mq5` to `MQL5/Experts/`
2. Compile in MetaEditor
3. Attach to XAUUSD chart (H1 recommended)
4. Enable AutoTrading

## ⚡ Scalping Configuration

| Parameter | Value |
|-----------|-------|
| Prediction Horizon | 2 hours |
| Target Move | 0.2% (20 pips) |
| Stop Loss | 1.5x ATR |
| Take Profit | 2x ATR |
| Min Confidence | 60% |

## 📊 Technical Indicators (Same in Python & MQ5)

| Indicator | Python | MQ5 |
|-----------|--------|-----|
| EMA 9/21/50 | ✅ | ✅ |
| RSI 14 | ✅ | ✅ |
| RSI 5 (fast) | ✅ | ✅ |
| MACD 12/26/9 | ✅ | ✅ |
| Stochastic 14/3 | ✅ | ✅ |
| Bollinger Bands 20 | ✅ | ✅ |
| CCI 20 | ✅ | ✅ |
| ATR 14 | ✅ | ✅ |

## 🎯 Signal Logic

The same logic is used in both Python and MQ5:

```
BUY Signal when:
✅ EMA9 > EMA21 (bullish)
✅ Price > EMA50
✅ RSI < 30 (oversold) OR RSI > 50
✅ MACD > Signal line
✅ Stochastic < 20 (oversold) OR K > D
✅ Price at lower Bollinger Band

SELL Signal when:
✅ EMA9 < EMA21 (bearish)
✅ Price < EMA50
✅ RSI > 70 (overbought) OR RSI < 50
✅ MACD < Signal line
✅ Stochastic > 80 (overbought) OR K < D
✅ Price at upper Bollinger Band
```

## 📈 Signal Strength

| Confidence | Indicators | Action |
|------------|------------|--------|
| ≥70% | 6+/8 | 🔥 Strong - Trade |
| 60-70% | 4-5/8 | 📊 Moderate - Consider |
| <60% | <4/8 | ⚠️ Weak - Skip |

## 📁 Files

```
eatrading/
├── GoldPricePrediction_Training.ipynb  # Train models
├── GoldScalpingEA.mq5                  # MT5 Expert Advisor
├── quick_predict.py                    # Quick signal script
├── GoldEnsemble_*.keras/.joblib        # Trained models
├── scaler.joblib                       # Feature scaler
├── ensemble_config.json                # Configuration
└── XAUUSD_H1_*.csv                     # Price data
```

## ⚙️ MQ5 EA Parameters

```cpp
// Trade Settings
LotSize = 0.1              // Fixed lot size
RiskPercent = 1.0          // Risk % per trade
MaxTrades = 3              // Max concurrent trades

// Scalping
ScalpTP_Pips = 20          // Take Profit
ScalpSL_Pips = 15          // Stop Loss
ATR_SL_Multiplier = 1.5    // ATR-based SL
ATR_TP_Multiplier = 2.0    // ATR-based TP

// Signal
MinConfidence = 60         // Min confidence %
MinIndicators = 4          // Min indicators agreeing
```

## ⚠️ Risk Warning

Trading involves substantial risk. This system is for educational purposes. Always:
- Use proper position sizing
- Set stop losses
- Never risk more than 1-2% per trade
- Test on demo account first

## 📄 License

MIT License
