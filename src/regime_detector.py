"""
Market Regime Detector
======================
ML model to classify market regime:
- RANGING (0): Trade with mean-reversion, tight stops
- TRENDING (1): Trade with trend, let profits run
- VOLATILE (2): Be cautious, wider stops or skip

Uses ensemble of simple models for robustness.
"""

import numpy as np
import pandas as pd
import joblib
from pathlib import Path
from typing import Tuple, Dict, Optional
from sklearn.ensemble import (
    RandomForestClassifier, 
    GradientBoostingClassifier,
    VotingClassifier
)
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
from sklearn.model_selection import cross_val_score


class RegimeDetector:
    """Market regime detection model"""
    
    REGIME_NAMES = {0: 'RANGING', 1: 'TRENDING', 2: 'VOLATILE'}
    
    def __init__(self, feature_columns: list):
        self.feature_columns = feature_columns
        self.scaler = StandardScaler()
        self.model = None
        self.is_fitted = False
        
    def _create_ensemble(self) -> VotingClassifier:
        """Create ensemble of models"""
        rf = RandomForestClassifier(
            n_estimators=100,
            max_depth=10,
            min_samples_split=20,
            min_samples_leaf=10,
            class_weight='balanced',
            random_state=42,
            n_jobs=-1
        )
        
        gb = GradientBoostingClassifier(
            n_estimators=100,
            max_depth=5,
            learning_rate=0.1,
            min_samples_split=20,
            random_state=42
        )
        
        # Voting ensemble
        ensemble = VotingClassifier(
            estimators=[
                ('rf', rf),
                ('gb', gb)
            ],
            voting='soft'
        )
        
        return ensemble
    
    def fit(self, X_train: np.ndarray, y_train: np.ndarray,
            X_val: Optional[np.ndarray] = None, 
            y_val: Optional[np.ndarray] = None) -> Dict:
        """Train the regime detector"""
        
        print("Training Regime Detector...")
        print(f"  Training samples: {len(X_train):,}")
        print(f"  Features: {X_train.shape[1]}")
        
        # Scale features
        X_train_scaled = self.scaler.fit_transform(X_train)
        
        # Create and train model
        self.model = self._create_ensemble()
        self.model.fit(X_train_scaled, y_train)
        self.is_fitted = True
        
        # Training accuracy
        train_pred = self.model.predict(X_train_scaled)
        train_acc = accuracy_score(y_train, train_pred)
        
        results = {
            'train_accuracy': train_acc,
            'train_samples': len(X_train)
        }
        
        print(f"  Training accuracy: {train_acc:.2%}")
        
        # Validation if provided
        if X_val is not None and y_val is not None:
            X_val_scaled = self.scaler.transform(X_val)
            val_pred = self.model.predict(X_val_scaled)
            val_acc = accuracy_score(y_val, val_pred)
            
            results['val_accuracy'] = val_acc
            results['val_samples'] = len(X_val)
            
            print(f"  Validation accuracy: {val_acc:.2%}")
            print("\nValidation Classification Report:")
            print(classification_report(
                y_val, val_pred,
                target_names=['RANGING', 'TRENDING', 'VOLATILE']
            ))
        
        return results
    
    def predict(self, X: np.ndarray) -> np.ndarray:
        """Predict regime"""
        if not self.is_fitted:
            raise ValueError("Model not fitted. Call fit() first.")
        X_scaled = self.scaler.transform(X)
        return self.model.predict(X_scaled)
    
    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        """Predict regime probabilities"""
        if not self.is_fitted:
            raise ValueError("Model not fitted. Call fit() first.")
        X_scaled = self.scaler.transform(X)
        return self.model.predict_proba(X_scaled)
    
    def evaluate(self, X_test: np.ndarray, y_test: np.ndarray) -> Dict:
        """Evaluate on test set"""
        X_test_scaled = self.scaler.transform(X_test)
        y_pred = self.model.predict(X_test_scaled)
        y_proba = self.model.predict_proba(X_test_scaled)
        
        accuracy = accuracy_score(y_test, y_pred)
        
        print("\n" + "="*60)
        print("TEST SET EVALUATION")
        print("="*60)
        print(f"Accuracy: {accuracy:.2%}")
        print("\nClassification Report:")
        print(classification_report(
            y_test, y_pred,
            target_names=['RANGING', 'TRENDING', 'VOLATILE']
        ))
        
        print("\nConfusion Matrix:")
        cm = confusion_matrix(y_test, y_pred)
        print("              Predicted")
        print("           RANG TREND VOLAT")
        for i, row in enumerate(cm):
            label = ['RANGING  ', 'TRENDING ', 'VOLATILE '][i]
            print(f"Actual {label} {row}")
        
        return {
            'accuracy': accuracy,
            'predictions': y_pred,
            'probabilities': y_proba,
            'confusion_matrix': cm
        }
    
    def save(self, filepath: str):
        """Save model and scaler"""
        save_dict = {
            'model': self.model,
            'scaler': self.scaler,
            'feature_columns': self.feature_columns,
            'is_fitted': self.is_fitted
        }
        joblib.dump(save_dict, filepath)
        print(f"Model saved to: {filepath}")
    
    @classmethod
    def load(cls, filepath: str) -> 'RegimeDetector':
        """Load saved model"""
        save_dict = joblib.load(filepath)
        detector = cls(save_dict['feature_columns'])
        detector.model = save_dict['model']
        detector.scaler = save_dict['scaler']
        detector.is_fitted = save_dict['is_fitted']
        print(f"Model loaded from: {filepath}")
        return detector
    
    def get_regime_name(self, regime_id: int) -> str:
        """Get human-readable regime name"""
        return self.REGIME_NAMES.get(regime_id, 'UNKNOWN')


def train_regime_detector(
    train_df: pd.DataFrame,
    val_df: pd.DataFrame,
    test_df: pd.DataFrame,
    feature_columns: list,
    save_path: Optional[str] = None
) -> Tuple[RegimeDetector, Dict]:
    """Full training pipeline"""
    
    # Prepare data
    X_train = train_df[feature_columns].values
    y_train = train_df['Regime'].values
    
    X_val = val_df[feature_columns].values
    y_val = val_df['Regime'].values
    
    X_test = test_df[feature_columns].values
    y_test = test_df['Regime'].values
    
    # Create and train detector
    detector = RegimeDetector(feature_columns)
    train_results = detector.fit(X_train, y_train, X_val, y_val)
    
    # Evaluate on test set
    test_results = detector.evaluate(X_test, y_test)
    
    # Save if path provided
    if save_path:
        detector.save(save_path)
    
    return detector, {**train_results, **test_results}


if __name__ == "__main__":
    # Test the detector
    from pathlib import Path
    import sys
    sys.path.insert(0, str(Path(__file__).parent.parent))
    
    from src.data_pipeline import load_mt5_csv, clean_data, create_time_features, split_data
    from src.features import prepare_features, get_feature_columns
    
    csv_path = Path(__file__).parent.parent / "XAUUSD_H1_201501020900_202512221100.csv"
    
    if csv_path.exists():
        # Load and prepare data
        df = load_mt5_csv(str(csv_path))
        df = clean_data(df)
        df = create_time_features(df)
        df = prepare_features(df)
        
        # Split data
        train_df, val_df, test_df = split_data(df)
        
        # Get feature columns
        feature_cols = get_feature_columns()
        feature_cols = [c for c in feature_cols if c in df.columns]
        
        # Train
        detector, results = train_regime_detector(
            train_df, val_df, test_df,
            feature_cols,
            save_path=str(Path(__file__).parent.parent / "models" / "regime_detector.joblib")
        )
        
        print(f"\nFinal Test Accuracy: {results['accuracy']:.2%}")

