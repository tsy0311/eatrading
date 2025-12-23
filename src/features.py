"""
Feature Engineering for Regime Detection
=========================================
Creates features optimized for detecting market regime:
- TRENDING: Strong directional movement
- RANGING: Sideways, mean-reverting
- VOLATILE: High volatility, choppy
"""

import pandas as pd
import numpy as np
from typing import List, Tuple


def add_price_features(df: pd.DataFrame) -> pd.DataFrame:
    """Basic price-derived features"""
    df = df.copy()
    
    # Returns
    df['Return'] = df['Close'].pct_change()
    df['Return_Abs'] = df['Return'].abs()
    
    # Log returns (better for ML)
    df['LogReturn'] = np.log(df['Close'] / df['Close'].shift(1))
    
    # Range
    df['Range'] = df['High'] - df['Low']
    df['RangePercent'] = df['Range'] / df['Close']
    
    # Body and wicks
    df['Body'] = abs(df['Close'] - df['Open'])
    df['BodyPercent'] = df['Body'] / df['Range'].replace(0, np.nan)
    df['UpperWick'] = df['High'] - df[['Open', 'Close']].max(axis=1)
    df['LowerWick'] = df[['Open', 'Close']].min(axis=1) - df['Low']
    
    return df


def add_volatility_features(df: pd.DataFrame, periods: List[int] = [5, 10, 20, 50]) -> pd.DataFrame:
    """Volatility indicators for regime detection"""
    df = df.copy()
    
    for p in periods:
        # ATR
        high_low = df['High'] - df['Low']
        high_close = abs(df['High'] - df['Close'].shift(1))
        low_close = abs(df['Low'] - df['Close'].shift(1))
        tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        df[f'ATR_{p}'] = tr.rolling(p).mean()
        
        # ATR as percentage of price
        df[f'ATR_{p}_Pct'] = df[f'ATR_{p}'] / df['Close']
        
        # Standard deviation of returns
        df[f'Volatility_{p}'] = df['Return'].rolling(p).std()
        
        # Range volatility
        df[f'RangeVol_{p}'] = df['Range'].rolling(p).std()
    
    # Volatility ratio (current vs average)
    df['VolatilityRatio'] = df['Volatility_5'] / df['Volatility_20'].replace(0, np.nan)
    df['ATRRatio'] = df['ATR_5'] / df['ATR_20'].replace(0, np.nan)
    
    return df


def add_trend_features(df: pd.DataFrame) -> pd.DataFrame:
    """Trend strength indicators"""
    df = df.copy()
    
    # Moving averages
    for p in [5, 10, 20, 50, 100]:
        df[f'SMA_{p}'] = df['Close'].rolling(p).mean()
        df[f'EMA_{p}'] = df['Close'].ewm(span=p, adjust=False).mean()
    
    # Price position relative to MAs
    df['PriceVsSMA20'] = (df['Close'] - df['SMA_20']) / df['SMA_20']
    df['PriceVsSMA50'] = (df['Close'] - df['SMA_50']) / df['SMA_50']
    
    # MA slopes (trend direction)
    df['SMA20_Slope'] = (df['SMA_20'] - df['SMA_20'].shift(5)) / df['SMA_20'].shift(5)
    df['SMA50_Slope'] = (df['SMA_50'] - df['SMA_50'].shift(10)) / df['SMA_50'].shift(10)
    
    # MA alignment (trending indicator)
    df['MA_Alignment'] = (
        (df['EMA_5'] > df['EMA_10']).astype(int) +
        (df['EMA_10'] > df['EMA_20']).astype(int) +
        (df['EMA_20'] > df['EMA_50']).astype(int)
    ) - 1.5  # Center around 0
    
    # ADX-like trend strength (simplified)
    plus_dm = df['High'].diff()
    minus_dm = -df['Low'].diff()
    plus_dm[plus_dm < 0] = 0
    minus_dm[minus_dm < 0] = 0
    
    tr = pd.concat([
        df['High'] - df['Low'],
        abs(df['High'] - df['Close'].shift(1)),
        abs(df['Low'] - df['Close'].shift(1))
    ], axis=1).max(axis=1)
    
    atr14 = tr.rolling(14).mean()
    plus_di = 100 * (plus_dm.rolling(14).mean() / atr14)
    minus_di = 100 * (minus_dm.rolling(14).mean() / atr14)
    
    dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di).replace(0, np.nan)
    df['ADX'] = dx.rolling(14).mean()
    df['DI_Diff'] = plus_di - minus_di
    
    return df


def add_momentum_features(df: pd.DataFrame) -> pd.DataFrame:
    """Momentum indicators"""
    df = df.copy()
    
    # RSI
    delta = df['Close'].diff()
    gain = delta.where(delta > 0, 0).rolling(14).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
    rs = gain / loss.replace(0, np.nan)
    df['RSI'] = 100 - (100 / (1 + rs))
    
    # RSI extremes
    df['RSI_Extreme'] = ((df['RSI'] < 30) | (df['RSI'] > 70)).astype(int)
    
    # MACD
    ema12 = df['Close'].ewm(span=12, adjust=False).mean()
    ema26 = df['Close'].ewm(span=26, adjust=False).mean()
    df['MACD'] = ema12 - ema26
    df['MACD_Signal'] = df['MACD'].ewm(span=9, adjust=False).mean()
    df['MACD_Hist'] = df['MACD'] - df['MACD_Signal']
    
    # Stochastic
    low14 = df['Low'].rolling(14).min()
    high14 = df['High'].rolling(14).max()
    df['Stoch_K'] = 100 * (df['Close'] - low14) / (high14 - low14).replace(0, np.nan)
    df['Stoch_D'] = df['Stoch_K'].rolling(3).mean()
    
    # ROC (Rate of Change)
    for p in [5, 10, 20]:
        df[f'ROC_{p}'] = (df['Close'] - df['Close'].shift(p)) / df['Close'].shift(p)
    
    return df


def add_regime_labels(df: pd.DataFrame, 
                       lookforward: int = 10,
                       trend_threshold: float = 0.005,
                       vol_threshold: float = 1.5) -> pd.DataFrame:
    """
    Create regime labels based on future price action.
    
    Regimes:
    - 0: RANGING (low volatility, no clear direction)
    - 1: TRENDING (clear directional move)
    - 2: VOLATILE (high volatility, choppy)
    """
    df = df.copy()
    
    # Future return
    df['FutureReturn'] = df['Close'].shift(-lookforward) / df['Close'] - 1
    df['FutureReturnAbs'] = df['FutureReturn'].abs()
    
    # Future volatility
    future_vol = df['Return_Abs'].rolling(lookforward).mean().shift(-lookforward)
    avg_vol = df['Return_Abs'].rolling(50).mean()
    df['FutureVolRatio'] = future_vol / avg_vol.replace(0, np.nan)
    
    # Assign regimes
    conditions = [
        # TRENDING: Strong directional move
        (df['FutureReturnAbs'] > trend_threshold) & (df['FutureVolRatio'] < vol_threshold),
        # VOLATILE: High volatility, choppy
        (df['FutureVolRatio'] >= vol_threshold),
        # RANGING: Everything else (default)
    ]
    choices = [1, 2]  # 1=TRENDING, 2=VOLATILE
    df['Regime'] = np.select(conditions, choices, default=0)  # 0=RANGING
    
    return df


def get_feature_columns() -> List[str]:
    """Return list of feature columns for ML model"""
    return [
        # Volatility
        'ATR_5_Pct', 'ATR_10_Pct', 'ATR_20_Pct',
        'Volatility_5', 'Volatility_10', 'Volatility_20',
        'VolatilityRatio', 'ATRRatio',
        'RangePercent', 'BodyPercent',
        
        # Trend
        'PriceVsSMA20', 'PriceVsSMA50',
        'SMA20_Slope', 'SMA50_Slope',
        'MA_Alignment', 'ADX', 'DI_Diff',
        
        # Momentum
        'RSI', 'RSI_Extreme',
        'MACD_Hist', 'Stoch_K',
        'ROC_5', 'ROC_10', 'ROC_20',
        
        # Time features
        'Hour', 'DayOfWeek',
        'IsAsianSession', 'IsLondonSession', 'IsNYSession', 'IsOverlap'
    ]


def prepare_features(df: pd.DataFrame, add_labels: bool = True) -> pd.DataFrame:
    """Full feature engineering pipeline"""
    print("Adding features...")
    
    df = add_price_features(df)
    df = add_volatility_features(df)
    df = add_trend_features(df)
    df = add_momentum_features(df)
    
    if add_labels:
        df = add_regime_labels(df)
    
    # Drop NaN rows
    initial_len = len(df)
    df = df.dropna().reset_index(drop=True)
    print(f"  Dropped {initial_len - len(df)} rows with NaN")
    
    return df


if __name__ == "__main__":
    # Test feature engineering
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).parent.parent))
    
    from src.data_pipeline import load_mt5_csv, clean_data, create_time_features
    
    csv_path = Path(__file__).parent.parent / "XAUUSD_H1_201501020900_202512221100.csv"
    
    if csv_path.exists():
        df = load_mt5_csv(str(csv_path))
        df = clean_data(df)
        df = create_time_features(df)
        df = prepare_features(df)
        
        print(f"\nDataset shape: {df.shape}")
        print(f"\nRegime distribution:")
        print(df['Regime'].value_counts().sort_index())
        print("\n0=RANGING, 1=TRENDING, 2=VOLATILE")
        
        feature_cols = get_feature_columns()
        print(f"\nFeature columns ({len(feature_cols)}):")
        for col in feature_cols:
            if col in df.columns:
                print(f"  ✓ {col}")
            else:
                print(f"  ✗ {col} (missing)")

