# ⚡ Gold SCALPING System - Pure Technical Analysis

A machine learning trading system for **SCALPING XAUUSD (Gold)** using **PURE TECHNICAL INDICATORS ONLY**.

No fundamental factors - just price action and technical analysis.

## ⚡ Scalping Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Prediction** | 2 hours | Short-term scalping horizon |
| **Target** | 0.2% (20 pips) | Typical scalp profit target |
| **Window** | 20 periods | Recent price history |
| **Fundamentals** | NONE | Pure technical only |

## 🤖 Models Used (5 Ensemble)

| Model | Type | Description |
|-------|------|-------------|
| **LSTM** | Deep Learning | Sequential price patterns |
| **Random Forest** | Ensemble | Decision tree voting |
| **GBRT** | Boosting | Gradient boosted trees |
| **XGBoost** | Boosting | Extreme gradient boosting |
| **KNN** | Instance-Based | Similar pattern matching |

## 📊 Pure Technical Features

### Fast Oscillators
- Stochastic K/D (14 and 5 period)
- Williams %R
- CCI (Commodity Channel Index)
- RSI (14 and 5 period fast)

### Trend Indicators
- MA Crossovers (5/20, 10/50)
- MACD with histogram
- EMA 3/8 scalp cross

### Price Action
- Candlestick patterns (engulfing, wicks)
- Body/shadow ratios
- Consecutive up/down candles
- Support/Resistance levels

### Volatility
- ATR percentage
- Bollinger Band position
- Volatility ratio

## 🎯 Output

```
⚡ SCALPING SIGNAL

📅 Time: 2025-12-23 14:00:00
💰 Price: $2620.50

🟢 BUY SIGNAL
   Confidence: 78%
   Model Agreement: 4/5

📊 SCALP PLAN:
   Entry:      $2620.50
   Stop Loss:  $2615.25 (-5.25)
   Take Profit: $2625.75 (+5.25)

⚡ Signal Strength: STRONG
```

## 📁 Files

| File | Description |
|------|-------------|
| `GoldPricePrediction_Training.ipynb` | Main training notebook |
| `quick_predict.py` | Get instant signal |
| `GoldEnsemble_*.keras/.joblib` | Trained models |
| `scaler.joblib` | Feature scaler |

## 🚀 Quick Start

### Get Instant Signal
```bash
python quick_predict.py
```

### Full Training
1. Open `GoldPricePrediction_Training.ipynb`
2. Run all cells (Ctrl+Shift+Enter)
3. Check signals in final cell

## 📈 Signal Interpretation

| Strength | Confidence | Agreement | Action |
|----------|------------|-----------|--------|
| 🔥 STRONG | ≥70% | 4-5/5 | Take the trade |
| 📊 MODERATE | 60-70% | 3/5 | Consider carefully |
| ⚠️ WEAK | <60% | <3/5 | Skip or wait |

## ⚠️ Scalping Tips

1. **Trade during high volume** - More movement
2. **Use tight stops** - Scalping = small losses
3. **Quick exits** - Don't hold scalp trades long
4. **Spread matters** - Use broker with low spreads
5. **Avoid news times** - Pure technical only

## ⚠️ Disclaimer

This system is for educational purposes only. Trading involves substantial risk. Past performance doesn't guarantee future results. Never trade money you can't afford to lose.

## 📄 License

MIT License - Use and modify freely.
