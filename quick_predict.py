#!/usr/bin/env python3
"""
🥇 Gold Trading - Quick Prediction Script
==========================================
Load pre-trained models and get instant trading signals!

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
    print("🔄 Loading Pre-trained Models...")
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

def add_technical_indicators(df):
    """Add technical indicators to dataframe"""
    # Moving Averages
    df['SMA_5'] = df['Price'].rolling(5).mean()
    df['SMA_20'] = df['Price'].rolling(20).mean()
    df['SMA_50'] = df['Price'].rolling(50).mean()
    df['EMA_3'] = df['Price'].ewm(span=3).mean()
    df['EMA_8'] = df['Price'].ewm(span=8).mean()
    
    # MA Crossovers
    df['MA_Cross_5_20'] = (df['SMA_5'] > df['SMA_20']).astype(int)
    df['MA_Cross_10_50'] = (df['Price'].rolling(10).mean() > df['SMA_50']).astype(int)
    
    # Price vs SMAs
    df['Price_vs_SMA20'] = (df['Price'] - df['SMA_20']) / df['SMA_20']
    df['Price_vs_SMA50'] = (df['Price'] - df['SMA_50']) / df['SMA_50']
    
    # Trend Strength
    df['Trend_Strength'] = (df['SMA_5'] - df['SMA_50']) / df['SMA_50']
    
    # RSI
    delta = df['Price'].diff()
    gain = delta.where(delta > 0, 0).rolling(14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
    rs = gain / loss
    df['RSI'] = 100 - (100 / (1 + rs))
    df['RSI'] = df['RSI'] / 100  # Normalize
    df['RSI_Signal'] = np.where(df['RSI'] < 0.3, 1, np.where(df['RSI'] > 0.7, -1, 0))
    
    # Fast RSI
    gain_fast = delta.where(delta > 0, 0).rolling(5).mean()
    loss_fast = (-delta.where(delta < 0, 0)).rolling(5).mean()
    rs_fast = gain_fast / loss_fast
    df['RSI_Fast'] = (100 - (100 / (1 + rs_fast))) / 100
    
    # MACD
    ema12 = df['Price'].ewm(span=12).mean()
    ema26 = df['Price'].ewm(span=26).mean()
    macd = ema12 - ema26
    signal = macd.ewm(span=9).mean()
    df['MACD_Cross'] = (macd > signal).astype(int)
    df['MACD_Histogram'] = (macd - signal) / df['Price']
    
    # ROC
    df['ROC_5'] = df['Price'].pct_change(5)
    df['ROC_10'] = df['Price'].pct_change(10)
    
    # Momentum
    df['Momentum_3'] = df['Price'].pct_change(3)
    
    # Scalp Cross
    df['Scalp_Cross'] = (df['EMA_3'] > df['EMA_8']).astype(int)
    
    # ATR
    high_low = df['High'] - df['Low']
    high_close = abs(df['High'] - df['Price'].shift())
    low_close = abs(df['Low'] - df['Price'].shift())
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    df['ATR'] = tr.rolling(14).mean()
    df['ATR_Pct'] = df['ATR'] / df['Price']
    
    # Bollinger Bands
    bb_mid = df['Price'].rolling(20).mean()
    bb_std = df['Price'].rolling(20).std()
    df['BB_Position'] = (df['Price'] - bb_mid) / (2 * bb_std)
    
    # Volatility Ratio
    df['Volatility'] = df['Price'].rolling(10).std()
    df['Volatility_Avg'] = df['Price'].rolling(50).std()
    df['Volatility_Ratio'] = df['Volatility'] / df['Volatility_Avg']
    
    # Candlestick patterns
    df['Body'] = (df['Price'] - df['Open']) / df['Open']
    df['Upper_Shadow'] = (df['High'] - df[['Open', 'Price']].max(axis=1)) / df['Open']
    df['Lower_Shadow'] = (df[['Open', 'Price']].min(axis=1) - df['Low']) / df['Open']
    
    return df

def prepare_latest_data(df, config, scaler):
    """Prepare the latest data for prediction"""
    window_size = config['window_size']
    feature_columns = config['feature_columns']
    
    # Add indicators
    df = add_technical_indicators(df)
    df = df.dropna()
    
    # Get latest window
    latest = df[feature_columns].iloc[-window_size:].values
    
    # Scale
    if scaler:
        latest_scaled = scaler.transform(latest)
    else:
        latest_scaled = latest
    
    return latest_scaled, df.iloc[-1]

def get_predictions(models, data_3d, data_flat, num_features=20):
    """Get predictions from all models"""
    predictions = {}
    probabilities = {}
    
    for name, model in models.items():
        try:
            if name == 'LSTM':
                proba = model.predict(data_3d, verbose=0)[0]
            elif name in ['RandomForest', 'XGBoost', 'KNN']:
                # Use last 20 timesteps (400 features = 20 * 20)
                data_tree = data_flat[:, -(20 * num_features):]
                proba = model.predict_proba(data_tree)[0]
            elif name == 'GBRT':
                # GBRT uses reduced features (last 10 timesteps = 200 features)
                data_reduced = data_flat[:, -(10 * num_features):]
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
    print("🥇 GOLD TRADING - QUICK PREDICTION")
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
    print("📊 Loading Latest Data...")
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
    latest_scaled, latest_row = prepare_latest_data(df, config, scaler)
    
    # Reshape for models
    data_3d = latest_scaled.reshape(1, config['window_size'], -1)
    data_flat = latest_scaled.flatten().reshape(1, -1)
    
    # Get predictions
    predictions, probabilities = get_predictions(models, data_3d, data_flat)
    
    # Ensemble vote
    ensemble_pred, ensemble_conf, agreement = ensemble_vote(predictions, probabilities)
    
    # Get ATR for stop loss/take profit
    df_with_indicators = add_technical_indicators(df.copy())
    current_atr = df_with_indicators['ATR'].iloc[-1]
    current_price = latest_row['Price']
    
    # Print results
    print("\n" + "="*60)
    print("💹 TRADING SIGNAL")
    print("="*60)
    
    signal_map = {0: ('🔴 SELL', 'Short'), 1: ('🟢 BUY', 'Long')}
    signal_text, position = signal_map.get(ensemble_pred, ('⚪ HOLD', 'None'))
    
    print(f"\n📅 Date: {latest_row['Date']}")
    print(f"💰 Current Price: ${current_price:.2f}")
    
    print(f"\n{signal_text} ({position} Position)")
    print(f"   Confidence: {ensemble_conf*100:.1f}%")
    print(f"   Model Agreement: {agreement}/{len(models)}")
    
    print("\n📊 MODEL PREDICTIONS:")
    print("-"*40)
    for name, pred in predictions.items():
        direction = "DOWN (SELL)" if pred == 0 else "UP (BUY)"
        conf = max(probabilities[name]) * 100
        print(f"   {name:<15}: {direction} ({conf:.1f}%)")
    
    # Trading plan
    print("\n" + "="*60)
    print(f"📋 TRADING PLAN ({signal_text})")
    print("="*60)
    
    if ensemble_pred == 1:  # BUY
        sl = current_price - (current_atr * 1.5)
        tp1 = current_price + (current_atr * 2)
        tp2 = current_price + (current_atr * 3)
        tp3 = current_price + (current_atr * 4)
        print(f"   Entry:       ${current_price:.2f}")
        print(f"   Stop Loss:   ${sl:.2f} (-${current_price-sl:.2f})")
        print(f"   Take Profit 1: ${tp1:.2f} (+${tp1-current_price:.2f})")
        print(f"   Take Profit 2: ${tp2:.2f} (+${tp2-current_price:.2f})")
        print(f"   Take Profit 3: ${tp3:.2f} (+${tp3-current_price:.2f})")
    else:  # SELL
        sl = current_price + (current_atr * 1.5)
        tp1 = current_price - (current_atr * 2)
        tp2 = current_price - (current_atr * 3)
        tp3 = current_price - (current_atr * 4)
        print(f"   Entry:       ${current_price:.2f}")
        print(f"   Stop Loss:   ${sl:.2f} (+${sl-current_price:.2f})")
        print(f"   Take Profit 1: ${tp1:.2f} (-${current_price-tp1:.2f})")
        print(f"   Take Profit 2: ${tp2:.2f} (-${current_price-tp2:.2f})")
        print(f"   Take Profit 3: ${tp3:.2f} (-${current_price-tp3:.2f})")
    
    # Signal strength
    if agreement >= 5 and ensemble_conf >= 0.8:
        strength = "🔥 VERY STRONG"
    elif agreement >= 4 and ensemble_conf >= 0.7:
        strength = "💪 STRONG"
    elif agreement >= 3 and ensemble_conf >= 0.6:
        strength = "📊 MODERATE"
    else:
        strength = "⚠️ WEAK"
    
    print(f"\n📈 Signal Strength: {strength} ({agreement}/{len(models)} models)")
    print("="*60)

if __name__ == "__main__":
    main()

