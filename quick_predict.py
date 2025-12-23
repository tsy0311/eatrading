#!/usr/bin/env python3
"""
⚡ GOLD SCALPING - Complete Analysis & Signal
=============================================
Pure Technical Analysis with Full Trade Plan

Usage: python quick_predict.py
       python quick_predict.py 4483  (with custom price)
"""

import numpy as np
import pandas as pd
import joblib
import json
import os
import sys
from datetime import datetime

# Suppress warnings
import warnings
warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

# =============================================================================
# LOAD DATA AND ADD ALL INDICATORS
# =============================================================================

def load_data(csv_path='XAUUSD_H1_201501020900_202512221100.csv'):
    """Load price data"""
    if not os.path.exists(csv_path):
        print(f"❌ Data file not found: {csv_path}")
        return None
        
    df = pd.read_csv(csv_path, sep='\t')
    df = df.rename(columns={
        '<DATE>': 'Date', '<TIME>': 'Time', '<OPEN>': 'Open',
        '<HIGH>': 'High', '<LOW>': 'Low', '<CLOSE>': 'Close',
        '<TICKVOL>': 'TickVolume', '<VOL>': 'Volume', '<SPREAD>': 'Spread'
    })
    df['Date'] = pd.to_datetime(df['Date'] + ' ' + df['Time'])
    df = df.sort_values('Date').reset_index(drop=True)
    return df

def add_all_indicators(df):
    """Add all technical indicators for complete analysis"""
    
    # ========== MOVING AVERAGES ==========
    df['EMA_9'] = df['Close'].ewm(span=9).mean()
    df['EMA_21'] = df['Close'].ewm(span=21).mean()
    df['EMA_50'] = df['Close'].ewm(span=50).mean()
    df['SMA_5'] = df['Close'].rolling(5).mean()
    df['SMA_20'] = df['Close'].rolling(20).mean()
    df['SMA_50'] = df['Close'].rolling(50).mean()
    df['EMA_3'] = df['Close'].ewm(span=3).mean()
    df['EMA_8'] = df['Close'].ewm(span=8).mean()
    
    # MA Crosses
    df['MA_Cross_5_20'] = (df['SMA_5'] > df['SMA_20']).astype(int)
    df['MA_Cross_9_21'] = (df['EMA_9'] > df['EMA_21']).astype(int)
    df['Scalp_Cross'] = (df['EMA_3'] > df['EMA_8']).astype(int)
    
    # Price vs MAs
    df['Price_vs_EMA9'] = (df['Close'] - df['EMA_9']) / df['EMA_9']
    df['Price_vs_EMA21'] = (df['Close'] - df['EMA_21']) / df['EMA_21']
    df['Price_vs_EMA50'] = (df['Close'] - df['EMA_50']) / df['EMA_50']
    df['Trend_Strength'] = (df['EMA_9'] - df['EMA_50']) / df['EMA_50']
    
    # ========== RSI ==========
    delta = df['Close'].diff()
    gain = delta.where(delta > 0, 0).rolling(14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
    rs = gain / (loss + 1e-10)
    df['RSI'] = 100 - (100 / (1 + rs))
    
    # Fast RSI
    gain_fast = delta.where(delta > 0, 0).rolling(5).mean()
    loss_fast = (-delta.where(delta < 0, 0)).rolling(5).mean()
    rs_fast = gain_fast / (loss_fast + 1e-10)
    df['RSI_Fast'] = 100 - (100 / (1 + rs_fast))
    
    # ========== MACD ==========
    ema12 = df['Close'].ewm(span=12).mean()
    ema26 = df['Close'].ewm(span=26).mean()
    df['MACD'] = ema12 - ema26
    df['MACD_Signal'] = df['MACD'].ewm(span=9).mean()
    df['MACD_Hist'] = df['MACD'] - df['MACD_Signal']
    df['MACD_Cross'] = (df['MACD'] > df['MACD_Signal']).astype(int)
    
    # ========== STOCHASTIC ==========
    low_14 = df['Low'].rolling(14).min()
    high_14 = df['High'].rolling(14).max()
    df['Stoch_K'] = 100 * (df['Close'] - low_14) / (high_14 - low_14 + 1e-10)
    df['Stoch_D'] = df['Stoch_K'].rolling(3).mean()
    
    # Fast Stochastic
    low_5 = df['Low'].rolling(5).min()
    high_5 = df['High'].rolling(5).max()
    df['Stoch_Fast'] = 100 * (df['Close'] - low_5) / (high_5 - low_5 + 1e-10)
    
    # ========== WILLIAMS %R ==========
    df['Williams_R'] = -100 * (high_14 - df['Close']) / (high_14 - low_14 + 1e-10)
    
    # ========== CCI ==========
    typical_price = (df['High'] + df['Low'] + df['Close']) / 3
    sma_tp = typical_price.rolling(20).mean()
    mad = typical_price.rolling(20).apply(lambda x: np.abs(x - x.mean()).mean())
    df['CCI'] = (typical_price - sma_tp) / (0.015 * mad + 1e-10)
    
    # ========== ATR ==========
    high_low = df['High'] - df['Low']
    high_close = abs(df['High'] - df['Close'].shift())
    low_close = abs(df['Low'] - df['Close'].shift())
    tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
    df['ATR'] = tr.rolling(14).mean()
    df['ATR_Pct'] = df['ATR'] / df['Close']
    
    # ========== BOLLINGER BANDS ==========
    df['BB_Mid'] = df['Close'].rolling(20).mean()
    bb_std = df['Close'].rolling(20).std()
    df['BB_Upper'] = df['BB_Mid'] + 2 * bb_std
    df['BB_Lower'] = df['BB_Mid'] - 2 * bb_std
    df['BB_Position'] = (df['Close'] - df['BB_Mid']) / (2 * bb_std + 1e-10)
    
    # ========== SWING LEVELS ==========
    df['Swing_High'] = df['High'].rolling(10).max()
    df['Swing_Low'] = df['Low'].rolling(10).min()
    
    # Fibonacci from swing
    df['Fib_Range'] = df['Swing_High'] - df['Swing_Low']
    df['Fib_382'] = df['Swing_High'] - 0.382 * df['Fib_Range']
    df['Fib_500'] = df['Swing_High'] - 0.500 * df['Fib_Range']
    df['Fib_618'] = df['Swing_High'] - 0.618 * df['Fib_Range']
    
    # ========== PRICE ACTION ==========
    df['Body'] = (df['Close'] - df['Open']) / df['Open']
    df['Up_Candle'] = (df['Close'] > df['Open']).astype(int)
    df['Candle_Range'] = df['High'] - df['Low']
    df['Upper_Wick'] = (df['High'] - df[['Open', 'Close']].max(axis=1)) / (df['Candle_Range'] + 1e-10)
    df['Lower_Wick'] = (df[['Open', 'Close']].min(axis=1) - df['Low']) / (df['Candle_Range'] + 1e-10)
    
    # Consecutive candles
    df['Consecutive_Up'] = df['Up_Candle'].rolling(3).sum()
    
    # Engulfing
    df['Prev_Body'] = (df['Close'].shift(1) - df['Open'].shift(1)).abs()
    df['Curr_Body'] = (df['Close'] - df['Open']).abs()
    df['Engulfing'] = ((df['Curr_Body'] > df['Prev_Body'] * 1.5) & 
                       (df['Up_Candle'] != df['Up_Candle'].shift(1))).astype(int)
    
    # Support/Resistance
    df['Near_Resistance'] = (df['Close'] > df['Swing_High'] * 0.998).astype(int)
    df['Near_Support'] = (df['Close'] < df['Swing_Low'] * 1.002).astype(int)
    
    # Momentum
    df['ROC_5'] = df['Close'].pct_change(5)
    df['ROC_10'] = df['Close'].pct_change(10)
    df['Momentum_3'] = df['Close'].pct_change(3)
    
    # Volatility
    df['Volatility'] = df['ATR_Pct'].rolling(10).mean()
    df['Volatility_Ratio'] = df['ATR_Pct'] / (df['Volatility'] + 1e-10)
    
    return df

# =============================================================================
# ANALYSIS FUNCTIONS
# =============================================================================

def get_trend(df):
    """Determine current trend"""
    row = df.iloc[-1]
    price = row['Close']
    
    if row['EMA_9'] > row['EMA_21'] > row['EMA_50']:
        return "STRONG UPTREND ↑↑", "bullish", 2
    elif row['EMA_9'] > row['EMA_21']:
        return "UPTREND ↑", "bullish", 1
    elif row['EMA_9'] < row['EMA_21'] < row['EMA_50']:
        return "STRONG DOWNTREND ↓↓", "bearish", -2
    elif row['EMA_9'] < row['EMA_21']:
        return "DOWNTREND ↓", "bearish", -1
    else:
        return "RANGING ↔", "neutral", 0

def is_retracement(df, price=None):
    """Check if current move is a retracement (pullback in trend)"""
    row = df.iloc[-1]
    if price is None:
        price = row['Close']
        
    trend, bias, strength = get_trend(df)
    
    result = {
        'is_retracement': False,
        'type': None,
        'message': "",
        'action': ""
    }
    
    # In uptrend
    if strength > 0:
        if price < row['EMA_9'] and price > row['EMA_21']:
            result['is_retracement'] = True
            result['type'] = "PULLBACK"
            result['message'] = f"Price pulled back below EMA9 (${row['EMA_9']:.2f}) but holding above EMA21 (${row['EMA_21']:.2f})"
            result['action'] = "GOOD BUY ZONE - Look for bullish confirmation"
        elif price < row['EMA_21'] and price > row['EMA_50']:
            result['is_retracement'] = True
            result['type'] = "DEEP PULLBACK"
            result['message'] = f"Deep pullback to EMA50 zone (${row['EMA_50']:.2f})"
            result['action'] = "EXCELLENT BUY ZONE - High reward setup"
        elif row['RSI'] < 40:
            result['is_retracement'] = True
            result['type'] = "RSI OVERSOLD"
            result['message'] = f"RSI oversold ({row['RSI']:.1f}) in uptrend"
            result['action'] = "BUY on RSI recovery above 40"
        else:
            result['message'] = "Trend continuation - not a pullback"
            result['action'] = "Wait for pullback or breakout entry"
            
    # In downtrend
    elif strength < 0:
        if price > row['EMA_9'] and price < row['EMA_21']:
            result['is_retracement'] = True
            result['type'] = "BOUNCE"
            result['message'] = f"Price bounced above EMA9 (${row['EMA_9']:.2f}) but below EMA21 (${row['EMA_21']:.2f})"
            result['action'] = "GOOD SELL ZONE - Look for bearish confirmation"
        elif price > row['EMA_21'] and price < row['EMA_50']:
            result['is_retracement'] = True
            result['type'] = "DEEP BOUNCE"
            result['message'] = f"Deep bounce to EMA50 zone (${row['EMA_50']:.2f})"
            result['action'] = "EXCELLENT SELL ZONE - High reward setup"
        elif row['RSI'] > 60:
            result['is_retracement'] = True
            result['type'] = "RSI OVERBOUGHT"
            result['message'] = f"RSI overbought ({row['RSI']:.1f}) in downtrend"
            result['action'] = "SELL on RSI rejection below 60"
        else:
            result['message'] = "Trend continuation - not a bounce"
            result['action'] = "Wait for bounce or breakdown entry"
    else:
        result['message'] = "Market ranging - no clear trend"
        result['action'] = "Wait for breakout"
        
    return result

def get_signal(df, price=None):
    """Get BUY/SELL signal with confidence"""
    row = df.iloc[-1]
    if price is None:
        price = row['Close']
        
    buy_score = 0
    sell_score = 0
    buy_reasons = []
    sell_reasons = []
    
    # EMA Trend (weight: 2)
    if row['EMA_9'] > row['EMA_21']:
        buy_score += 2
        buy_reasons.append("EMA9 > EMA21 (bullish)")
    else:
        sell_score += 2
        sell_reasons.append("EMA9 < EMA21 (bearish)")
        
    # Price vs EMA50 (weight: 2)
    if price > row['EMA_50']:
        buy_score += 2
        buy_reasons.append("Price above EMA50")
    else:
        sell_score += 2
        sell_reasons.append("Price below EMA50")
        
    # RSI (weight: 2)
    if row['RSI'] < 30:
        buy_score += 3
        buy_reasons.append(f"RSI OVERSOLD ({row['RSI']:.1f}) - Strong BUY")
    elif row['RSI'] > 70:
        sell_score += 3
        sell_reasons.append(f"RSI OVERBOUGHT ({row['RSI']:.1f}) - Strong SELL")
    elif row['RSI'] > 50:
        buy_score += 1
        buy_reasons.append(f"RSI bullish ({row['RSI']:.1f})")
    else:
        sell_score += 1
        sell_reasons.append(f"RSI bearish ({row['RSI']:.1f})")
        
    # MACD (weight: 2)
    if row['MACD'] > row['MACD_Signal']:
        buy_score += 2
        if row['MACD_Hist'] > 0:
            buy_reasons.append("MACD bullish + histogram positive")
        else:
            buy_reasons.append("MACD bullish cross")
    else:
        sell_score += 2
        if row['MACD_Hist'] < 0:
            sell_reasons.append("MACD bearish + histogram negative")
        else:
            sell_reasons.append("MACD bearish cross")
            
    # Stochastic (weight: 1)
    if row['Stoch_K'] < 20:
        buy_score += 2
        buy_reasons.append(f"Stochastic OVERSOLD ({row['Stoch_K']:.1f})")
    elif row['Stoch_K'] > 80:
        sell_score += 2
        sell_reasons.append(f"Stochastic OVERBOUGHT ({row['Stoch_K']:.1f})")
    elif row['Stoch_K'] > row['Stoch_D']:
        buy_score += 1
        buy_reasons.append("Stochastic bullish")
    else:
        sell_score += 1
        sell_reasons.append("Stochastic bearish")
        
    # Bollinger Bands (weight: 1)
    if price < row['BB_Lower']:
        buy_score += 2
        buy_reasons.append("Price at LOWER BB (oversold)")
    elif price > row['BB_Upper']:
        sell_score += 2
        sell_reasons.append("Price at UPPER BB (overbought)")
        
    # Scalp Cross (weight: 1)
    if row['Scalp_Cross'] == 1:
        buy_score += 1
        buy_reasons.append("Fast EMA bullish (3>8)")
    else:
        sell_score += 1
        sell_reasons.append("Fast EMA bearish (3<8)")
        
    # Calculate confidence
    total = buy_score + sell_score
    if buy_score > sell_score:
        confidence = (buy_score / total) * 100
        return "BUY", confidence, buy_reasons, sell_reasons
    elif sell_score > buy_score:
        confidence = (sell_score / total) * 100
        return "SELL", confidence, sell_reasons, buy_reasons
    else:
        return "HOLD", 50, buy_reasons, sell_reasons

def get_sl_tp(df, direction, price=None):
    """Calculate Stop Loss and Take Profit levels"""
    row = df.iloc[-1]
    if price is None:
        price = row['Close']
        
    atr = row['ATR']
    
    if direction.upper() == "BUY":
        # SL below swing low or 1.5x ATR
        sl_swing = row['Swing_Low'] - 2
        sl_atr = price - (atr * 1.5)
        sl = max(sl_swing, sl_atr)
        
        risk = price - sl
        tp1 = price + risk * 1.0   # 1:1
        tp2 = price + risk * 1.5   # 1:1.5
        tp3 = price + risk * 2.0   # 1:2
        
    else:  # SELL
        # SL above swing high or 1.5x ATR
        sl_swing = row['Swing_High'] + 2
        sl_atr = price + (atr * 1.5)
        sl = min(sl_swing, sl_atr)
        
        risk = sl - price
        tp1 = price - risk * 1.0   # 1:1
        tp2 = price - risk * 1.5   # 1:1.5
        tp3 = price - risk * 2.0   # 1:2
        
    return {
        'direction': direction.upper(),
        'entry': round(price, 2),
        'sl': round(sl, 2),
        'tp1': round(tp1, 2),
        'tp2': round(tp2, 2),
        'tp3': round(tp3, 2),
        'risk_pips': round(abs(price - sl), 2),
        'atr': round(atr, 2)
    }

def calculate_risk(entry, sl, lot_size=0.1):
    """Calculate potential loss if SL is hit"""
    risk_pips = abs(entry - sl)
    # Gold: ~$10 per pip per 1.0 lot
    pip_value = 10
    loss = risk_pips * pip_value * lot_size
    return {
        'entry': entry,
        'sl': sl,
        'lot_size': lot_size,
        'risk_pips': round(risk_pips, 2),
        'total_loss': round(loss, 2)
    }

def when_valid(df, direction, price=None):
    """Check when BUY or SELL setup is valid"""
    row = df.iloc[-1]
    if price is None:
        price = row['Close']
        
    conditions = []
    valid_count = 0
    
    if direction.upper() == "BUY":
        # Condition 1: Price above EMAs
        if price > row['EMA_9'] and price > row['EMA_21']:
            conditions.append("✅ Price above EMA9 & EMA21")
            valid_count += 1
        else:
            conditions.append(f"❌ Need price above EMA9 (${row['EMA_9']:.2f}) & EMA21 (${row['EMA_21']:.2f})")
            
        # Condition 2: RSI
        if row['RSI'] > 50 or row['RSI'] < 30:
            conditions.append(f"✅ RSI favorable ({row['RSI']:.1f})")
            valid_count += 1
        else:
            conditions.append(f"❌ Need RSI > 50 or oversold (current: {row['RSI']:.1f})")
            
        # Condition 3: MACD
        if row['MACD'] > row['MACD_Signal']:
            conditions.append("✅ MACD bullish")
            valid_count += 1
        else:
            conditions.append("❌ Need MACD bullish cross")
            
        # Condition 4: Higher low
        recent_lows = df['Low'].iloc[-5:]
        if recent_lows.iloc[-1] > recent_lows.min():
            conditions.append("✅ Higher low forming")
            valid_count += 1
        else:
            conditions.append("❌ No higher low yet")
            
        zone = f"${row['Fib_500']:.2f} - ${row['Fib_618']:.2f}"
        ideal = row['EMA_21']
        
    else:  # SELL
        # Condition 1: Price below EMAs
        if price < row['EMA_9'] and price < row['EMA_21']:
            conditions.append("✅ Price below EMA9 & EMA21")
            valid_count += 1
        else:
            conditions.append(f"❌ Need price below EMA9 (${row['EMA_9']:.2f}) & EMA21 (${row['EMA_21']:.2f})")
            
        # Condition 2: RSI
        if row['RSI'] < 50 or row['RSI'] > 70:
            conditions.append(f"✅ RSI favorable ({row['RSI']:.1f})")
            valid_count += 1
        else:
            conditions.append(f"❌ Need RSI < 50 or overbought (current: {row['RSI']:.1f})")
            
        # Condition 3: MACD
        if row['MACD'] < row['MACD_Signal']:
            conditions.append("✅ MACD bearish")
            valid_count += 1
        else:
            conditions.append("❌ Need MACD bearish cross")
            
        # Condition 4: Lower high
        recent_highs = df['High'].iloc[-5:]
        if recent_highs.iloc[-1] < recent_highs.max():
            conditions.append("✅ Lower high forming")
            valid_count += 1
        else:
            conditions.append("❌ No lower high yet")
            
        zone = f"${row['Fib_382']:.2f} - ${row['Fib_500']:.2f}"
        ideal = row['EMA_21']
        
    return {
        'valid': valid_count >= 3,
        'score': f"{valid_count}/4",
        'conditions': conditions,
        'entry_zone': zone,
        'ideal_entry': round(ideal, 2)
    }

def stacking_advice(df, position, price=None):
    """Advice on adding to position (stacking)"""
    row = df.iloc[-1]
    if price is None:
        price = row['Close']
        
    trend, bias, strength = get_trend(df)
    advice = []
    can_stack = False
    
    if position.upper() == "BUY":
        if strength > 0:
            advice.append(f"✅ Trend is {trend} - stacking possible")
            
            if price < row['EMA_9'] and price > row['EMA_21']:
                advice.append(f"✅ GOOD ZONE: Pullback to ${price:.2f}")
                advice.append(f"   Stack near EMA21: ${row['EMA_21']:.2f}")
                can_stack = True
            elif price < row['EMA_21'] and price > row['EMA_50']:
                advice.append(f"✅ EXCELLENT ZONE: Deep pullback")
                advice.append(f"   Stack near EMA50: ${row['EMA_50']:.2f}")
                can_stack = True
            else:
                advice.append(f"⚠️ Wait for pullback to EMA9 (${row['EMA_9']:.2f}) or EMA21")
                
            if row['RSI'] < 40:
                advice.append("✅ RSI oversold - good stack level")
                can_stack = True
        else:
            advice.append("❌ Trend NOT bullish - DO NOT stack buys")
            advice.append("   Consider closing or reducing position")
            
    else:  # SELL
        if strength < 0:
            advice.append(f"✅ Trend is {trend} - stacking possible")
            
            if price > row['EMA_9'] and price < row['EMA_21']:
                advice.append(f"✅ GOOD ZONE: Bounce to ${price:.2f}")
                advice.append(f"   Stack near EMA21: ${row['EMA_21']:.2f}")
                can_stack = True
            elif price > row['EMA_21'] and price < row['EMA_50']:
                advice.append(f"✅ EXCELLENT ZONE: Deep bounce")
                advice.append(f"   Stack near EMA50: ${row['EMA_50']:.2f}")
                can_stack = True
            else:
                advice.append(f"⚠️ Wait for bounce to EMA9 (${row['EMA_9']:.2f}) or EMA21")
                
            if row['RSI'] > 60:
                advice.append("✅ RSI overbought - good stack level")
                can_stack = True
        else:
            advice.append("❌ Trend NOT bearish - DO NOT stack sells")
            advice.append("   Consider closing or reducing position")
            
    return {
        'can_stack': can_stack,
        'trend': trend,
        'advice': advice
    }

# =============================================================================
# MAIN OUTPUT
# =============================================================================

def main():
    # Check for custom price argument
    custom_price = None
    if len(sys.argv) > 1:
        try:
            custom_price = float(sys.argv[1])
        except:
            pass
    
    print("\n" + "="*65)
    print("⚡ GOLD SCALPING - COMPLETE ANALYSIS (Pure Technical)")
    print("="*65)
    
    # Load data
    df = load_data()
    if df is None:
        return
        
    # Add indicators
    df = add_all_indicators(df)
    df = df.dropna()
    
    row = df.iloc[-1]
    price = custom_price if custom_price else row['Close']
    
    # ===== HEADER =====
    print(f"\n📅 Date: {row['Date']}")
    print(f"💰 Price: ${price:.2f}" + (" (custom)" if custom_price else ""))
    
    # ===== TREND =====
    trend, bias, strength = get_trend(df)
    print(f"\n{'='*65}")
    print(f"📈 TREND: {trend}")
    print(f"{'='*65}")
    
    # ===== SIGNAL =====
    signal, confidence, reasons_for, reasons_against = get_signal(df, price)
    emoji = "🟢" if signal == "BUY" else "🔴" if signal == "SELL" else "⚪"
    
    print(f"\n{emoji} SIGNAL: {signal} ({confidence:.0f}% confidence)")
    print(f"\n   ✅ Reasons FOR {signal}:")
    for r in reasons_for[:4]:
        print(f"      • {r}")
    print(f"\n   ⚠️ Against:")
    for r in reasons_against[:3]:
        print(f"      • {r}")
    
    # ===== RETRACEMENT =====
    retrace = is_retracement(df, price)
    print(f"\n{'='*65}")
    print(f"🔄 RETRACEMENT CHECK")
    print(f"{'='*65}")
    if retrace['is_retracement']:
        print(f"   ✅ YES - {retrace['type']}")
    else:
        print(f"   ❌ NO")
    print(f"   {retrace['message']}")
    print(f"   💡 {retrace['action']}")
    
    # ===== SL / TP =====
    direction = "BUY" if signal == "BUY" else "SELL"
    levels = get_sl_tp(df, direction, price)
    
    print(f"\n{'='*65}")
    print(f"🎯 {levels['direction']} TRADE PLAN")
    print(f"{'='*65}")
    print(f"   Entry:      ${levels['entry']:.2f}")
    print(f"   Stop Loss:  ${levels['sl']:.2f} ({levels['risk_pips']:.2f} pips risk)")
    print(f"   TP1 (1:1):  ${levels['tp1']:.2f}")
    print(f"   TP2 (1:1.5): ${levels['tp2']:.2f}")
    print(f"   TP3 (1:2):  ${levels['tp3']:.2f}")
    
    # ===== RISK CALCULATION =====
    risk = calculate_risk(levels['entry'], levels['sl'], 0.1)
    print(f"\n   📊 Risk @ 0.1 lot: ${risk['total_loss']:.2f} if SL hit")
    print(f"   📊 Risk @ 0.5 lot: ${risk['total_loss']*5:.2f} if SL hit")
    print(f"   📊 Risk @ 1.0 lot: ${risk['total_loss']*10:.2f} if SL hit")
    
    # ===== SETUP VALIDITY =====
    validity = when_valid(df, direction, price)
    print(f"\n{'='*65}")
    print(f"✅ {direction} SETUP VALIDITY: {validity['score']}")
    print(f"{'='*65}")
    for c in validity['conditions']:
        print(f"   {c}")
    print(f"\n   💡 Entry zone: {validity['entry_zone']}")
    print(f"   💡 Ideal entry: ${validity['ideal_entry']:.2f}")
    
    # ===== STACKING =====
    stack = stacking_advice(df, direction, price)
    print(f"\n{'='*65}")
    print(f"📦 STACKING ({direction}): {'✅ YES' if stack['can_stack'] else '❌ NO'}")
    print(f"{'='*65}")
    for a in stack['advice']:
        print(f"   {a}")
    
    # ===== KEY LEVELS =====
    print(f"\n{'='*65}")
    print(f"📊 KEY LEVELS")
    print(f"{'='*65}")
    print(f"   EMA9:  ${row['EMA_9']:.2f}")
    print(f"   EMA21: ${row['EMA_21']:.2f}")
    print(f"   EMA50: ${row['EMA_50']:.2f}")
    print(f"   Swing High: ${row['Swing_High']:.2f}")
    print(f"   Swing Low:  ${row['Swing_Low']:.2f}")
    print(f"   ATR: ${row['ATR']:.2f}")
    
    # ===== INDICATORS =====
    print(f"\n{'='*65}")
    print(f"📉 INDICATORS")
    print(f"{'='*65}")
    print(f"   RSI: {row['RSI']:.1f} {'(oversold)' if row['RSI']<30 else '(overbought)' if row['RSI']>70 else ''}")
    print(f"   MACD: {row['MACD']:.2f} (Signal: {row['MACD_Signal']:.2f})")
    print(f"   Stoch: {row['Stoch_K']:.1f} / {row['Stoch_D']:.1f}")
    print(f"   CCI: {row['CCI']:.1f}")
    print(f"   BB Position: {row['BB_Position']:.2f}")
    
    # ===== SUMMARY =====
    print(f"\n{'='*65}")
    if confidence >= 70 and validity['valid']:
        print(f"🔥 STRONG {signal} SETUP - High probability trade!")
    elif confidence >= 60:
        print(f"📊 MODERATE {signal} - Consider with proper risk management")
    else:
        print(f"⚠️ WEAK SETUP - Wait for better confirmation")
    print(f"{'='*65}\n")

if __name__ == "__main__":
    main()
