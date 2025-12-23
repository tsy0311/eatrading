#!/usr/bin/env python3
"""
Train Regime Detection Model
=============================
Main script to train the market regime detector for Gold trading.

Usage:
    python train_regime.py
    python train_regime.py --data data/XAUUSD_H1.csv
"""

import argparse
import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent))

from src.data_pipeline import load_mt5_csv, clean_data, create_time_features, split_data
from src.features import prepare_features, get_feature_columns
from src.regime_detector import train_regime_detector
from src.export_onnx import export_to_onnx, create_mt5_include, ONNX_AVAILABLE


def main():
    parser = argparse.ArgumentParser(description='Train Regime Detection Model')
    parser.add_argument('--data', type=str, default=None, help='Path to CSV data file')
    args = parser.parse_args()
    
    print("=" * 70)
    print("🎯 REGIME DETECTION MODEL TRAINING")
    print("=" * 70)
    
    # Find data file
    if args.data:
        csv_path = Path(args.data)
    else:
        # Look for CSV in common locations
        possible_paths = [
            Path("XAUUSD_H1_201501020900_202512221100.csv"),
            Path("data/XAUUSD_H1.csv"),
            Path("data/XAUUSD_H1_201501020900_202512221100.csv"),
        ]
        csv_path = None
        for p in possible_paths:
            if p.exists():
                csv_path = p
                break
    
    if not csv_path or not csv_path.exists():
        print(f"ERROR: Data file not found")
        print("Please provide path with --data argument")
        return 1
    
    print(f"\n📂 Loading data from: {csv_path}")
    
    # Load and prepare data
    df = load_mt5_csv(str(csv_path))
    print(f"   Raw records: {len(df):,}")
    
    df = clean_data(df)
    print(f"   After cleaning: {len(df):,}")
    
    df = create_time_features(df)
    df = prepare_features(df)
    print(f"   After features: {len(df):,}")
    
    # Show regime distribution
    print("\n📊 Regime Distribution:")
    regime_counts = df['Regime'].value_counts().sort_index()
    regime_names = {0: 'RANGING', 1: 'TRENDING', 2: 'VOLATILE'}
    for regime_id, count in regime_counts.items():
        pct = count / len(df) * 100
        print(f"   {regime_names[regime_id]}: {count:,} ({pct:.1f}%)")
    
    # Split data (time-series aware)
    print("\n📈 Splitting data (time-series)...")
    train_df, val_df, test_df = split_data(df, train_ratio=0.7, val_ratio=0.15, test_ratio=0.15)
    
    # Get feature columns
    feature_cols = get_feature_columns()
    feature_cols = [c for c in feature_cols if c in df.columns]
    print(f"\n🔧 Using {len(feature_cols)} features")
    
    # Create models directory
    models_dir = Path("models")
    models_dir.mkdir(exist_ok=True)
    
    # Train model
    print("\n" + "=" * 70)
    print("🤖 TRAINING REGIME DETECTOR")
    print("=" * 70)
    
    detector, results = train_regime_detector(
        train_df, val_df, test_df,
        feature_cols,
        save_path=str(models_dir / "regime_detector.joblib")
    )
    
    # Export to ONNX
    print("\n" + "=" * 70)
    print("📦 EXPORTING MODEL")
    print("=" * 70)
    
    if ONNX_AVAILABLE:
        success = export_to_onnx(
            str(models_dir / "regime_detector.joblib"),
            str(models_dir / "regime_detector.onnx"),
            str(models_dir / "regime_config.json")
        )
        
        if success:
            create_mt5_include(
                str(models_dir / "regime_config.json"),
                str(models_dir / "RegimeModelConfig.mqh")
            )
    else:
        print("⚠️  ONNX export skipped (skl2onnx not installed)")
        print("   Install with: pip install skl2onnx")
        print("   Model saved as .joblib for Python use")
    
    # Summary
    print("\n" + "=" * 70)
    print("✅ TRAINING COMPLETE")
    print("=" * 70)
    print(f"\n📊 Results:")
    print(f"   Training Accuracy:   {results.get('train_accuracy', 0):.2%}")
    print(f"   Validation Accuracy: {results.get('val_accuracy', 0):.2%}")
    print(f"   Test Accuracy:       {results.get('accuracy', 0):.2%}")
    
    print(f"\n📁 Files created in {models_dir}/:")
    for f in models_dir.iterdir():
        print(f"   - {f.name}")
    
    print("\n🎯 Next Steps:")
    print("   1. Copy RegimeModelConfig.mqh to MQL5/Include/")
    print("   2. Copy regime_detector.onnx to MQL5/Files/")
    print("   3. Update GoldScalpingEA.mq5 to use regime detection")
    print("   4. Backtest with regime-adaptive settings")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

