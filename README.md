# 🥇 Gold Price Prediction - Ensemble ML Trading System

An advanced machine learning trading system for XAUUSD (Gold) using **5 different ML models** combined into an ensemble for optimal predictions.

## 🤖 Models Used

| Model | Type | Description |
|-------|------|-------------|
| **LSTM** | Deep Learning | Captures sequential patterns in time series |
| **Random Forest** | Ensemble | Combines multiple decision trees |
| **GBRT** | Boosting | Sequential error correction |
| **XGBoost** | Gradient Boosting | High-performance gradient boosting |
| **KNN** | Instance-Based | Pattern matching with similar historical setups |

## 📊 Features

- **30-period sliding window** for pattern recognition (optimized for intraday)
- **20+ technical indicators** including:
  - Moving Averages (SMA, EMA crossovers)
  - RSI with signal zones (Fast & Standard)
  - MACD components & histogram
  - Bollinger Bands position
  - Stochastic Oscillator
  - Momentum indicators (3, 5, 10 period)
  - Volatility ratio measures
  - Candlestick patterns (body, shadows)
- **Ensemble voting** with confidence scores
- **Model agreement analysis** (5/5, 4/5, 3/5, etc.)
- **KNN Pattern Analysis** - finds similar historical setups
- **Risk management** with ATR-based stop loss/take profit
- **Dual timeframe** - Scalping (2H) & Mid-term (8H) signals

## 🎯 Output

For each signal, the system provides:

```
📅 Date: 2025-12-22 11:00:00
💰 Current Price: $2620.50
📊 Volatility: 1.12x average
🎯 TRADE TYPE: 🔄 MIXED

🟢 SIGNAL: BUY (Long Position)
   Confidence: 97.0%
   Model Agreement: 5/5

📊 BUY PLAN:
   ├── Entry Price:      $2620.50
   ├── Stop Loss:        $2605.25 (-$15.25)
   ├── Take Profit 1:    $2635.75 (+$15.25) [1:1 RR]
   ├── Take Profit 2:    $2651.00 (+$30.50) [1:2 RR]
   └── Take Profit 3:    $2666.25 (+$45.75) [1:3 RR]

🔍 KNN PATTERN ANALYSIS:
   Similar patterns: 10 found
   Historical win rate: 90%
   Pattern suggestion: BUY

📈 Signal Strength: 🔥 VERY STRONG (5/5)
```

## 📁 Files

### Training Notebook
- `GoldPricePrediction_Training.ipynb` - Main Jupyter notebook

### Quick Prediction
- `quick_predict.py` - Get instant signal without retraining

### Saved Models (5 models)
- `GoldEnsemble_LSTM.keras` - LSTM neural network
- `GoldEnsemble_RF.joblib` - Random Forest
- `GoldEnsemble_GBRT.joblib` - Gradient Boosted Trees
- `GoldEnsemble_XGB.joblib` - XGBoost
- `GoldEnsemble_KNN.joblib` - K-Nearest Neighbors

### Configuration
- `ensemble_config.json` - Model configuration
- `scaler.joblib` - Feature scaler

### Data
- `XAUUSD_H1_*.csv` - Historical price data (H1 timeframe)

## 🚀 Quick Start

### Option 1: Quick Prediction (Recommended)
```bash
python quick_predict.py
```
This loads pre-trained models and gives you an instant signal!

### Option 2: Full Training
1. **Install dependencies:**
```bash
pip install numpy pandas matplotlib plotly scikit-learn tensorflow xgboost joblib
```

2. **Run the notebook:**
   - Open `GoldPricePrediction_Training.ipynb`
   - Run all cells (Ctrl+Shift+Enter)

3. **Get predictions:**
   - Check Step 16 for live trading signals
   - Use signals with ≥60% confidence and 4+/5 model agreement

## 📈 Signal Interpretation

| Strength | Confidence | Agreement | Recommendation |
|----------|------------|-----------|----------------|
| 🔥 VERY STRONG | ≥80% | 5/5 | High probability trade |
| 💪 STRONG | ≥70% | 4/5 | Good opportunity |
| 📊 MODERATE | ≥60% | 3/5 | Consider with caution |
| ⚠️ WEAK | <60% | <3/5 | Wait for better signal |

## 🎯 Trading Style Support

This system is optimized for **Mid-Intraday Trading**:
- **Scalping**: 2-hour prediction horizon, 0.15% threshold
- **Mid-term**: 8-hour prediction horizon, 0.30% threshold
- **Mixed**: Adapts based on current volatility

## ⚠️ Disclaimer

This system is for educational and research purposes only. Trading financial instruments involves substantial risk of loss. Past performance is not indicative of future results. Always use proper risk management and never trade with money you cannot afford to lose.

## 📄 License

MIT License - Feel free to use and modify for your needs.
