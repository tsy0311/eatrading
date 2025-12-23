# 🤖 Gold Scalping ML System

Advanced Gold (XAUUSD) trading system with ML-powered regime detection that dynamically adjusts trading parameters.

## 🎯 Core Concept

Instead of predicting price direction (which is nearly impossible at 50% accuracy), this system:

1. **Detects Market Regime** (what works well):
   - 📊 **RANGING**: Tight stops, quick profits, mean-reversion
   - 📈 **TRENDING**: Wider stops, let profits run, trend-following
   - ⚡ **VOLATILE**: Be cautious, strict entry criteria

2. **Adapts EA Parameters** automatically based on regime

## 📁 Project Structure

```
eatrading/
├── src/                        # Python ML code
│   ├── data_pipeline.py        # Data loading & cleaning
│   ├── features.py             # Feature engineering
│   ├── regime_detector.py      # ML model training
│   └── export_onnx.py          # Export for MT5
├── models/                     # Trained models (after training)
│   ├── regime_detector.joblib  # Sklearn model
│   ├── regime_detector.onnx    # ONNX for MT5
│   ├── regime_config.json      # Model config
│   └── RegimeModelConfig.mqh   # MQL5 include file
├── data/                       # Data files
├── GoldScalpingEA.mq5          # Original EA (technical only)
├── GoldScalpingEA_ML.mq5       # ML-enhanced EA
├── train_regime.py             # Main training script
├── config.yaml                 # Configuration
└── requirements.txt            # Python dependencies
```

## 🚀 Quick Start

### Step 1: Install Dependencies

```bash
pip install -r requirements.txt
```

### Step 2: Train the Model

```bash
python train_regime.py
```

This will:
- Load XAUUSD H1 data
- Engineer features
- Train regime detector
- Export to ONNX and MQL5 config

### Step 3: Deploy to MT5

1. Copy `GoldScalpingEA_ML.mq5` to `MQL5/Experts/`
2. Copy `models/RegimeModelConfig.mqh` to `MQL5/Include/` (optional - for ONNX)
3. Copy `models/regime_detector.onnx` to `MQL5/Files/` (optional - for ONNX)
4. Compile in MetaEditor
5. Attach to XAUUSD H1 chart

### Step 4: Backtest

1. Open MT5 Strategy Tester
2. Select `GoldScalpingEA_ML`
3. Set period: 2020-2024 (out-of-sample)
4. Run backtest

## ⚙️ How Regime Detection Works

The model uses these features to classify market state:

| Feature Group | Indicators | Purpose |
|--------------|------------|---------|
| Volatility | ATR, Range, StdDev | Detect volatile periods |
| Trend | ADX, MA Alignment, Slope | Detect trending markets |
| Momentum | RSI, MACD, Stochastic | Confirm regime |
| Time | Session, Day of Week | Time-based patterns |

### Regime-Specific Settings

| Parameter | RANGING | TRENDING | VOLATILE |
|-----------|---------|----------|----------|
| SL Mult | 1.0x ATR | 1.5x ATR | 2.0x ATR |
| TP Mult | 1.5x ATR | 2.5x ATR | 2.0x ATR |
| Trail Start | +8 pips | +15 pips | +20 pips |
| Min Confidence | 60% | 55% | 70% |

## 📊 EA Input Parameters

### ML Settings
- `UseMLRegime`: Enable/disable ML regime detection
- `RegimeUpdateBars`: How often to update regime (default: 5 bars)

### Regime-Specific (for each regime)
- `Range_ATR_SL`: SL multiplier for ranging
- `Trend_ATR_TP`: TP multiplier for trending
- `Volat_MinConf`: Min confidence for volatile

### General
- Same as original EA (lot size, risk, time filters, etc.)

## 🔧 Customization

### Modify Regime Thresholds

Edit `src/features.py`:

```python
def add_regime_labels(df, 
                      lookforward=10,
                      trend_threshold=0.005,    # Change this
                      vol_threshold=1.5):       # Or this
```

### Add New Features

Edit `src/features.py` and add to `get_feature_columns()`.

### Change Model

Edit `src/regime_detector.py` to use different sklearn models.

## 📈 Expected Results

| Metric | Original EA | ML-Enhanced EA |
|--------|-------------|----------------|
| Regime Detection | N/A | ~60-65% accuracy |
| Adaptive SL/TP | Fixed | Dynamic |
| Win Rate | ~50% | ~50% (same signals) |
| Profit Factor | Varies | Better risk-adjusted |

**Note**: The ML model doesn't predict direction - it adapts parameters. Signal generation still uses technical indicators.

## ⚠️ Important Notes

1. **ML is for regime detection, NOT direction prediction**
2. **Always backtest before live trading**
3. **Past performance ≠ future results**
4. **Start with demo account**

## 📝 Files Reference

| File | Purpose |
|------|---------|
| `GoldScalpingEA.mq5` | Original EA (use this if ML not needed) |
| `GoldScalpingEA_ML.mq5` | ML-enhanced EA with regime detection |
| `train_regime.py` | Train the regime detector |
| `config.yaml` | All configuration in one place |

## 🆘 Troubleshooting

### "skl2onnx not installed"
```bash
pip install skl2onnx onnx
```

### "Data file not found"
Ensure CSV is in project root or specify with `--data` flag:
```bash
python train_regime.py --data path/to/data.csv
```

### Low regime detection accuracy
- Try different features (edit `get_feature_columns()`)
- Adjust regime thresholds
- Use more training data

---

**Good luck trading! 🚀**
