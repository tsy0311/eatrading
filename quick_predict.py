#!/usr/bin/env python3
"""
⚡ Gold SCALPING - Quick Prediction Script
==========================================
Pure Technical Analysis - NO Fundamentals!

Usage: python quick_predict.py
"""

import numpy as np
import pandas as pd
import joblib
import json
import os
from datetime import datetime

# Suppress warnings
import warnings
warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

def load_models():
    """Load all pre-trained models"""
    print("="*60)
    print("⚡ Loading SCALPING Models...")
    print("="*60)
    
    models = {}
    
    # Load LSTM
    try:
        from tensorflow.keras.models import load_model
        models['LSTM'] = load_model('GoldEnsemble_LSTM.keras', compile=False)
        print("✅ LSTM loaded")
    except Exception as e:
        print(f"❌ LSTM failed: {e}")
    
    # Load Random Forest
    try:
        models['RandomForest'] = joblib.load('GoldEnsemble_RF.joblib')
        print("✅ Random Forest loaded")
    except Exception as e:
        print(f"❌ Random Forest failed: {e}")
    
    # Load GBRT
    try:
        models['GBRT'] = joblib.load('GoldEnsemble_GBRT.joblib')
        print("✅ GBRT loaded")
    except Exception as e:
        print(f"❌ GBRT failed: {e}")
    
    # Load XGBoost
    try:
        models['XGBoost'] = joblib.load('GoldEnsemble_XGB.joblib')
        print("✅ XGBoost loaded")
    except Exception as e:
        print(f"❌ XGBoost failed: {e}")
    
    # Load KNN
    try:
        models['KNN'] = joblib.load('GoldEnsemble_KNN.joblib')
        print("✅ KNN loaded")
    except Exception as e:
        print(f"❌ KNN failed: {e}")
    
    # Load Scaler
    try:
        scaler = joblib.load('scaler.joblib')
        print("✅ Scaler loaded")
    except Exception as e:
        print(f"❌ Scaler failed: {e}")
        scaler = None
    
    print(f"\n📊 Models loaded: {len(models)}/5")
    return models, scaler

def load_config():
    """Load ensemble configuration"""
    with open('ensemble_config.json', 'r') as f:
        return json.load(f)

def add_scalping_indicators(df):
    """Add PURE TECHNICAL indicators for scalping - NO fundamentals"""
    
    # ========== MOVING AVERAGES (Short-term) ==========
    df['SMA_5'] = df['Price'].rolling(5).mean()
    df['SMA_10'] = df['Price'].rolling(10).mean()
    df['SMA_20'] = df['Price'].rolling(20).mean()
    df['SMA_50'] = df['Price'].rolling(50).mean()
    df['EMA_3'] = df['Price'].ewm(span=3).mean()
    df['EMA_8'] = df['Price'].ewm(span=8).mean()
    
    # MA Crossovers
    df['MA_Cross_5_20'] = (df['SMA_5'] > df['SMA_20']).astype(int)
    df['MA_Cross_10_50'] = (df['SMA_10'] > df['SMA_50']).astype(int)
    df['Scalp_Cross'] = (df['EMA_3'] > df['EMA_8']).astype(int)
    
    # Price vs SMAs
    df['Price_vs_SMA20'] = (df['Price'] - df['SMA_20']) / df['SMA_20']
    df['Price_vs_SMA50'] = (df['Price'] - df['SMA_50']) / df['SMA_50']
    df['Trend_Strength'] = (df['SMA_5'] - df['SMA_50']) / df['SMA_50']
    
    # ========== RSI (Standard + Fast) ==========
    delta = df['Price'].diff()
    gain = delta.where(delta > 0, 0).rolling(14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
    rs = gain / (loss + 1e-10)
    df['RSI'] = 100 - (100 / (1 + rs))
    df['RSI_Signal'] = np.where(df['RSI'] < 30, 1, np.where(df['RSI'] > 70, -1, 0))
    
    # Fast RSI (5-period)
    gain_fast = delta.where(delta > 0, 0).rolling(5).mean()
    loss_fast = (-delta.where(delta < 0, 0)).rolling(5).mean()
    rs_fast = gain_fast / (loss_fast + 1e-10)
    df['RSI_Fast'] = 100 - (100 / (1 + rs_fast))
    
    # ========== MACD ==========
    ema12 = df['Price'].ewm(span=12).mean()
    ema26 = df['Price'].ewm(span=26).mean()
    macd = ema12 - ema26
    signal = macd.ewm(span=9).mean()
    df['MACD_Cross'] = (macd > signal).astype(int)
    df['MACD_Histogram'] = (macd - signal) / df['Price']
    
    # ========== ROC & MOMENTUM ==========
    df['ROC_5'] = df['Price'].pct_change(5)
    df['ROC_10'] = df['Price'].pct_change(10)
    df['Momentum_3'] = df['Price'].pct_change(3)
    
    # ========== STOCHASTIC (Key for Scalping) ==========
    low_14 = df['Low'].rolling(14).min()
    high_14 = df['High'].rolling(14).max()
    df['Stoch_K'] = 100 * (df['Price'] - low_14) / (high_14 - low_14 + 1e-10)
    df['Stoch_D'] = df['Stoch_K'].rolling(3).mean()
    df['Stoch_Signal'] = np.where(df['Stoch_K'] > df['Stoch_D'], 1, -1)
    
    # Fast Stochastic
    low_5 = df['Low'].rolling(5).min()
    high_5 = df['High'].rolling(5).max()
    df['Stoch_Fast'] = 100 * (df['Price'] - low_5) / (high_5 - low_5 + 1e-10)
    
    # ========== WILLIAMS %R ==========
    df['Williams_R'] = -100 * (high_14 - df['Price']) / (high_14 - low_14 + 1e-10)
    
    # ========== CCI ==========
    typical_price = (df['High'] + df['Low'] + df['Price']) / 3
    sma_tp = typical_price.rolling(20).mean()
    mad = typical_price.rolling(20).apply(lambda x: np.abs(x - x.mean()).mean())
    df['CCI'] = (typical_price - sma_tp) / (0.015 * mad + 1e-10)
    df['CCI_Signal'] = np.where(df['CCI'] > 100, -1, np.where(df['CCI'] < -100, 1, 0))
    
    # ========== ATR & VOLATILITY ==========
    high_low = df['High'] - df['Low']
    high_close = abs(df['High'] - df['Price'].shift())
    low_close = abs(df['Low'] - df['Price'].shift())
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    df['ATR'] = tr.rolling(14).mean()
    df['ATR_Pct'] = df['ATR'] / df['Price']
    
    # Bollinger Bands
    bb_mid = df['Price'].rolling(20).mean()
    bb_std = df['Price'].rolling(20).std()
    df['BB_Position'] = (df['Price'] - bb_mid) / (2 * bb_std + 1e-10)
    
    # Volatility Ratio
    df['Volatility'] = df['ATR_Pct'].rolling(10).mean()
    df['Volatility_Ratio'] = df['ATR_Pct'] / (df['Volatility'] + 1e-10)
    
    # ========== PRICE ACTION ==========
    df['Body'] = (df['Price'] - df['Open']) / df['Open']
    df['Upper_Shadow'] = (df['High'] - df[['Open', 'Price']].max(axis=1)) / df['Open']
    df['Lower_Shadow'] = (df[['Open', 'Price']].min(axis=1) - df['Low']) / df['Open']
    
    # Candle size
    df['Candle_Size'] = abs(df['Price'] - df['Open']) / (df['ATR'] + 1e-10)
    
    # Wick ratios
    candle_range = df['High'] - df['Low'] + 1e-10
    df['Upper_Wick_Ratio'] = (df['High'] - df[['Open', 'Price']].max(axis=1)) / candle_range
    df['Lower_Wick_Ratio'] = (df[['Open', 'Price']].min(axis=1) - df['Low']) / candle_range
    
    # Engulfing pattern
    df['Prev_Body'] = (df['Price'].shift(1) - df['Open'].shift(1)).abs()
    df['Curr_Body'] = (df['Price'] - df['Open']).abs()
    df['Up_Candle'] = (df['Price'] > df['Open']).astype(int)
    df['Engulfing'] = ((df['Curr_Body'] > df['Prev_Body'] * 1.5) & 
                       (df['Up_Candle'] != df['Up_Candle'].shift(1))).astype(int)
    
    # Consecutive candles
    df['Consecutive_Up'] = df['Up_Candle'].rolling(3).sum()
    df['Consecutive_Down'] = 3 - df['Consecutive_Up']
    
    # ========== SUPPORT/RESISTANCE ==========
    df['Recent_High'] = df['High'].rolling(10).max()
    df['Recent_Low'] = df['Low'].rolling(10).min()
    df['Near_Resistance'] = (df['Price'] > df['Recent_High'] * 0.998).astype(int)
    df['Near_Support'] = (df['Price'] < df['Recent_Low'] * 1.002).astype(int)
    df['Dist_From_High'] = (df['Recent_High'] - df['Price']) / df['Price']
    df['Dist_From_Low'] = (df['Price'] - df['Recent_Low']) / df['Price']
    
    return df

def prepare_latest_data(df, config, scaler):
    """Prepare the latest data for prediction"""
    window_size = config['window_size']
    feature_columns = config['feature_columns']
    
    # Add indicators
    df = add_scalping_indicators(df)
    df = df.dropna()
    
    # Filter to available features
    available_features = [col for col in feature_columns if col in df.columns]
    
    # Get latest window
    latest = df[available_features].iloc[-window_size:].values
    
    # Scale
    if scaler:
        latest_scaled = scaler.transform(latest)
    else:
        latest_scaled = latest
    
    return latest_scaled, df.iloc[-1], len(available_features)

def get_predictions(models, data_3d, data_flat, num_features=20):
    """Get predictions from all models"""
    predictions = {}
    probabilities = {}
    
    for name, model in models.items():
        try:
            if name == 'LSTM':
                proba = model.predict(data_3d, verbose=0)[0]
            elif name in ['RandomForest', 'XGBoost', 'KNN']:
                # Use appropriate number of features
                expected_features = 20 * num_features  # window * features
                if data_flat.shape[1] >= expected_features:
                    data_tree = data_flat[:, -expected_features:]
                else:
                    data_tree = data_flat
                proba = model.predict_proba(data_tree)[0]
            elif name == 'GBRT':
                # GBRT uses reduced features
                expected_features = 10 * num_features
                if data_flat.shape[1] >= expected_features:
                    data_reduced = data_flat[:, -expected_features:]
                else:
                    data_reduced = data_flat
                proba = model.predict_proba(data_reduced)[0]
            
            pred = np.argmax(proba)
            predictions[name] = pred
            probabilities[name] = proba
        except Exception as e:
            print(f"⚠️ {name} prediction failed: {e}")
    
    return predictions, probabilities

def ensemble_vote(predictions, probabilities):
    """Combine predictions using soft voting"""
    if not probabilities:
        return 0, 0.5, 0
    
    # Average probabilities
    all_proba = np.array(list(probabilities.values()))
    avg_proba = np.mean(all_proba, axis=0)
    
    ensemble_pred = np.argmax(avg_proba)
    ensemble_conf = np.max(avg_proba)
    
    # Count agreement
    agreement = sum(1 for p in predictions.values() if p == ensemble_pred)
    
    return ensemble_pred, ensemble_conf, agreement

def main():
    print("\n" + "="*60)
    print("⚡ GOLD SCALPING - PURE TECHNICAL SIGNAL")
    print("="*60 + "\n")
    
    # Check if data file exists
    csv_file = 'XAUUSD_H1_201501020900_202512221100.csv'
    if not os.path.exists(csv_file):
        print(f"❌ Data file not found: {csv_file}")
        return
    
    # Load models
    models, scaler = load_models()
    if len(models) == 0:
        print("❌ No models loaded. Please run the notebook first.")
        return
    
    # Load config
    config = load_config()
    
    # Load and prepare data
    print("\n" + "="*60)
    print("📊 Analyzing Price Action...")
    print("="*60)
    
    df = pd.read_csv(csv_file, sep='\t')
    df = df.rename(columns={
        '<DATE>': 'Date', '<TIME>': 'Time', '<OPEN>': 'Open',
        '<HIGH>': 'High', '<LOW>': 'Low', '<CLOSE>': 'Price',
        '<TICKVOL>': 'TickVolume', '<VOL>': 'Volume', '<SPREAD>': 'Spread'
    })
    df['Date'] = pd.to_datetime(df['Date'] + ' ' + df['Time'])
    df = df.sort_values('Date').reset_index(drop=True)
    
    # Prepare latest window
    latest_scaled, latest_row, num_features = prepare_latest_data(df, config, scaler)
    
    # Reshape for models
    data_3d = latest_scaled.reshape(1, config['window_size'], -1)
    data_flat = latest_scaled.flatten().reshape(1, -1)
    
    # Get predictions
    predictions, probabilities = get_predictions(models, data_3d, data_flat, num_features)
    
    # Ensemble vote
    ensemble_pred, ensemble_conf, agreement = ensemble_vote(predictions, probabilities)
    
    # Get ATR for stop loss/take profit (scalping = tight)
    df_with_indicators = add_scalping_indicators(df.copy())
    current_atr = df_with_indicators['ATR'].iloc[-1]
    current_price = latest_row['Price']
    
    # Print results
    print("\n" + "="*60)
    print("⚡ SCALPING SIGNAL (Pure Technical)")
    print("="*60)
    
    signal_map = {0: ('🔴 SELL', 'Short'), 1: ('🟢 BUY', 'Long')}
    signal_text, position = signal_map.get(ensemble_pred, ('⚪ HOLD', 'None'))
    
    print(f"\n📅 Time: {latest_row['Date']}")
    print(f"💰 Price: ${current_price:.2f}")
    
    print(f"\n{signal_text} ({position})")
    print(f"   Confidence: {ensemble_conf*100:.1f}%")
    print(f"   Model Agreement: {agreement}/{len(models)}")
    
    print("\n📊 MODEL BREAKDOWN:")
    print("-"*40)
    for name, pred in predictions.items():
        direction = "SELL ↓" if pred == 0 else "BUY ↑"
        conf = max(probabilities[name]) * 100
        print(f"   {name:<15}: {direction} ({conf:.1f}%)")
    
    # Scalping plan (tight stops)
    scalp_sl = current_atr * 1.0  # 1x ATR stop loss (tight for scalping)
    scalp_tp = current_atr * 1.5  # 1.5x ATR take profit (1:1.5 RR)
    
    print("\n" + "="*60)
    print(f"⚡ SCALP PLAN ({signal_text})")
    print("="*60)
    
    if ensemble_pred == 1:  # BUY
        sl = current_price - scalp_sl
        tp = current_price + scalp_tp
        print(f"   Entry:       ${current_price:.2f}")
        print(f"   Stop Loss:   ${sl:.2f} (-${scalp_sl:.2f})")
        print(f"   Take Profit: ${tp:.2f} (+${scalp_tp:.2f})")
    else:  # SELL
        sl = current_price + scalp_sl
        tp = current_price - scalp_tp
        print(f"   Entry:       ${current_price:.2f}")
        print(f"   Stop Loss:   ${sl:.2f} (+${scalp_sl:.2f})")
        print(f"   Take Profit: ${tp:.2f} (-${scalp_tp:.2f})")
    
    print(f"   Risk/Reward: 1:1.5")
    
    # Signal strength
    if agreement >= 4 and ensemble_conf >= 0.7:
        strength = "🔥 STRONG - TAKE IT"
    elif agreement >= 3 and ensemble_conf >= 0.6:
        strength = "📊 MODERATE - CONSIDER"
    else:
        strength = "⚠️ WEAK - SKIP"
    
    print(f"\n⚡ Signal Strength: {strength}")
    print("="*60)
    print("\n💡 Scalping Tips:")
    print("   • Trade during high volume sessions")
    print("   • Exit quickly - don't hold scalps")
    print("   • Avoid news events (pure technical only)")
    print("="*60)

if __name__ == "__main__":
    main()
