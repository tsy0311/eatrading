# 🥇 Gold Price Prediction - Ensemble ML Trading System

An advanced machine learning trading system for XAUUSD (Gold) using **4 different ML models** combined into an ensemble for optimal predictions.

## 🤖 Models Used

| Model | Type | Description |
|-------|------|-------------|
| **LSTM** | Deep Learning | Captures sequential patterns in time series |
| **Random Forest** | Ensemble | Combines multiple decision trees |
| **GBRT** | Boosting | Sequential error correction |
| **XGBoost** | Gradient Boosting | High-performance gradient boosting |

## 📊 Features

- **60-period sliding window** for pattern recognition
- **20+ technical indicators** including:
  - Moving Averages (SMA, EMA ratios)
  - RSI (normalized)
  - MACD components
  - Bollinger Bands
  - Stochastic Oscillator
  - Momentum indicators
  - Volatility measures
- **Ensemble voting** with confidence scores
- **Model agreement analysis** (4/4, 3/4, etc.)
- **Risk management** with ATR-based stop loss/take profit

## 🎯 Output

For each signal, the system provides:

```
📅 Date: 2025-12-22 11:00:00
💰 Current Price: $2620.50

🟢 SIGNAL: BUY (Long Position)
   Confidence: 72.5%
   Model Agreement: 4/4

📊 BUY PLAN:
   ├── Entry Price:      $2620.50
   ├── Stop Loss:        $2605.25 (-$15.25)
   ├── Take Profit 1:    $2635.75 (+$15.25) [1:1 RR]
   ├── Take Profit 2:    $2651.00 (+$30.50) [1:2 RR]
   └── Take Profit 3:    $2666.25 (+$45.75) [1:3 RR]

📈 Signal Strength: 💪 STRONG
```

## 📁 Files

### Training Notebook
- `GoldPricePrediction_Training.ipynb` - Main Jupyter notebook

### Saved Models
- `GoldEnsemble_LSTM.keras` - LSTM neural network
- `GoldEnsemble_RF.joblib` - Random Forest
- `GoldEnsemble_GBRT.joblib` - Gradient Boosted Trees
- `GoldEnsemble_XGB.joblib` - XGBoost

### Configuration
- `ensemble_config.json` - Model configuration
- `scaler.joblib` - Feature scaler

### Data
- `XAUUSD_H1_*.csv` - Historical price data (H1 timeframe)

## 🚀 Quick Start

1. **Install dependencies:**
```bash
pip install numpy pandas matplotlib plotly scikit-learn tensorflow xgboost joblib
```

2. **Run the notebook:**
   - Open `GoldPricePrediction_Training.ipynb`
   - Run all cells (Ctrl+Shift+Enter)

3. **Get predictions:**
   - Check Step 16 for live trading signals
   - Use signals with ≥60% confidence and 3+/4 model agreement

## 📈 Signal Interpretation

| Strength | Confidence | Agreement | Recommendation |
|----------|------------|-----------|----------------|
| 🔥 VERY STRONG | ≥70% | 4/4 | High probability trade |
| 💪 STRONG | ≥60% | 3/4 | Good opportunity |
| 📊 MODERATE | ≥55% | 2/4 | Consider with caution |
| ⚠️ WEAK | <55% | <2/4 | Wait for better signal |

## ⚠️ Disclaimer

This system is for educational and research purposes only. Trading financial instruments involves substantial risk of loss. Past performance is not indicative of future results. Always use proper risk management and never trade with money you cannot afford to lose.

## 📄 License

MIT License - Feel free to use and modify for your needs.
