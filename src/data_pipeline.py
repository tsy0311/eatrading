"""
Data Pipeline for Gold Trading ML System
=========================================
Loads and preprocesses XAUUSD data for regime detection.
"""

import pandas as pd
import numpy as np
from pathlib import Path
from typing import Tuple, Optional


def load_mt5_csv(filepath: str) -> pd.DataFrame:
    """Load MT5 exported CSV (tab-separated)"""
    df = pd.read_csv(filepath, sep='\t')
    
    # Rename columns to standard format
    column_map = {
        '<DATE>': 'Date',
        '<TIME>': 'Time',
        '<OPEN>': 'Open',
        '<HIGH>': 'High',
        '<LOW>': 'Low',
        '<CLOSE>': 'Close',
        '<TICKVOL>': 'TickVolume',
        '<VOL>': 'Volume',
        '<SPREAD>': 'Spread'
    }
    df = df.rename(columns=column_map)
    
    # Combine Date and Time
    if 'Time' in df.columns:
        df['Date'] = pd.to_datetime(df['Date'] + ' ' + df['Time'])
        df = df.drop(columns=['Time'])
    else:
        df['Date'] = pd.to_datetime(df['Date'])
    
    df = df.sort_values('Date').reset_index(drop=True)
    
    return df


def clean_data(df: pd.DataFrame) -> pd.DataFrame:
    """Clean and validate price data"""
    # Remove duplicates
    df = df.drop_duplicates(subset=['Date'])
    
    # Remove rows with zero/negative prices
    price_cols = ['Open', 'High', 'Low', 'Close']
    for col in price_cols:
        if col in df.columns:
            df = df[df[col] > 0]
    
    # Ensure High >= Low
    df = df[df['High'] >= df['Low']]
    
    # Reset index
    df = df.reset_index(drop=True)
    
    return df


def create_time_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add time-based features"""
    df = df.copy()
    
    df['Hour'] = df['Date'].dt.hour
    df['DayOfWeek'] = df['Date'].dt.dayofweek
    df['Month'] = df['Date'].dt.month
    
    # Trading sessions (UTC times - adjust for your broker)
    df['IsAsianSession'] = ((df['Hour'] >= 0) & (df['Hour'] < 8)).astype(int)
    df['IsLondonSession'] = ((df['Hour'] >= 8) & (df['Hour'] < 16)).astype(int)
    df['IsNYSession'] = ((df['Hour'] >= 13) & (df['Hour'] < 22)).astype(int)
    df['IsOverlap'] = ((df['Hour'] >= 13) & (df['Hour'] < 16)).astype(int)  # London/NY overlap
    
    return df


def split_data(
    df: pd.DataFrame,
    train_ratio: float = 0.7,
    val_ratio: float = 0.15,
    test_ratio: float = 0.15
) -> Tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Time-series aware data split (no shuffle!)"""
    
    n = len(df)
    train_end = int(n * train_ratio)
    val_end = int(n * (train_ratio + val_ratio))
    
    train = df.iloc[:train_end].copy()
    val = df.iloc[train_end:val_end].copy()
    test = df.iloc[val_end:].copy()
    
    print(f"Data split:")
    print(f"  Train: {len(train):,} samples ({train['Date'].min()} to {train['Date'].max()})")
    print(f"  Val:   {len(val):,} samples ({val['Date'].min()} to {val['Date'].max()})")
    print(f"  Test:  {len(test):,} samples ({test['Date'].min()} to {test['Date'].max()})")
    
    return train, val, test


if __name__ == "__main__":
    # Test the pipeline
    import sys
    sys.path.insert(0, str(Path(__file__).parent.parent))
    
    csv_path = Path(__file__).parent.parent / "data" / "XAUUSD_H1.csv"
    if not csv_path.exists():
        # Try root directory
        csv_path = Path(__file__).parent.parent / "XAUUSD_H1_201501020900_202512221100.csv"
    
    if csv_path.exists():
        df = load_mt5_csv(str(csv_path))
        df = clean_data(df)
        df = create_time_features(df)
        print(f"\nLoaded {len(df):,} records")
        print(f"Columns: {list(df.columns)}")
        print(df.head())
    else:
        print(f"CSV not found: {csv_path}")

