"""
Export Regime Detector to ONNX
==============================
Converts the trained model to ONNX format for use in MT5.
"""

import numpy as np
import joblib
import json
from pathlib import Path
from sklearn.ensemble import VotingClassifier

# ONNX conversion
try:
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType
    ONNX_AVAILABLE = True
except ImportError:
    ONNX_AVAILABLE = False
    print("Warning: skl2onnx not installed. Run: pip install skl2onnx")


def export_to_onnx(
    model_path: str,
    onnx_path: str,
    config_path: str
) -> bool:
    """
    Export sklearn model to ONNX format for MT5.
    
    Args:
        model_path: Path to saved .joblib model
        onnx_path: Output path for .onnx file
        config_path: Output path for config .json file
    
    Returns:
        True if successful
    """
    if not ONNX_AVAILABLE:
        print("ERROR: skl2onnx not available")
        return False
    
    # Load model
    save_dict = joblib.load(model_path)
    model = save_dict['model']
    scaler = save_dict['scaler']
    feature_columns = save_dict['feature_columns']
    
    n_features = len(feature_columns)
    
    print(f"Exporting model with {n_features} features...")
    
    # For ensemble, we need to export the underlying estimators
    # MT5 ONNX support is limited, so we'll export the RandomForest component
    if isinstance(model, VotingClassifier):
        # Get the Random Forest (more ONNX-compatible)
        rf_model = model.named_estimators_['rf']
        export_model = rf_model
        print("  Using RandomForest component for ONNX export")
    else:
        export_model = model
    
    # Define input type
    initial_type = [('float_input', FloatTensorType([None, n_features]))]
    
    # Convert to ONNX
    try:
        onnx_model = convert_sklearn(
            export_model,
            initial_types=initial_type,
            target_opset=12  # MT5 compatible opset
        )
        
        # Save ONNX model
        with open(onnx_path, "wb") as f:
            f.write(onnx_model.SerializeToString())
        print(f"  ONNX model saved: {onnx_path}")
        
    except Exception as e:
        print(f"  ONNX conversion failed: {e}")
        print("  Falling back to joblib-only export")
        return False
    
    # Save configuration for MT5
    config = {
        'model_file': Path(onnx_path).name,
        'feature_columns': feature_columns,
        'n_features': n_features,
        'scaler': {
            'mean': scaler.mean_.tolist(),
            'scale': scaler.scale_.tolist()
        },
        'regime_map': {
            0: 'RANGING',
            1: 'TRENDING', 
            2: 'VOLATILE'
        },
        'regime_settings': {
            'RANGING': {
                'atr_sl_mult': 1.0,
                'atr_tp_mult': 1.5,
                'trailing_start': 8,
                'min_confidence': 60,
                'description': 'Mean-reversion, tight stops'
            },
            'TRENDING': {
                'atr_sl_mult': 1.5,
                'atr_tp_mult': 2.5,
                'trailing_start': 15,
                'min_confidence': 55,
                'description': 'Trend following, let profits run'
            },
            'VOLATILE': {
                'atr_sl_mult': 2.0,
                'atr_tp_mult': 2.0,
                'trailing_start': 20,
                'min_confidence': 70,
                'description': 'High volatility, be cautious'
            }
        }
    }
    
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"  Config saved: {config_path}")
    
    return True


def create_mt5_include(config_path: str, output_path: str):
    """
    Create MQL5 include file with model configuration.
    
    This allows the EA to read model settings without external files.
    """
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    # Generate MQL5 code
    mql_code = f'''//+------------------------------------------------------------------+
//|                                           RegimeModelConfig.mqh  |
//|                        Auto-generated from ML model export       |
//+------------------------------------------------------------------+
#property copyright "Regime Detector ML"
#property strict

// Model configuration
#define REGIME_MODEL_FEATURES {config['n_features']}
#define REGIME_RANGING   0
#define REGIME_TRENDING  1
#define REGIME_VOLATILE  2

// Feature scaling parameters (from StandardScaler)
double g_feature_mean[{config['n_features']}] = {{
   {", ".join([f"{x:.10f}" for x in config['scaler']['mean']])}
}};

double g_feature_scale[{config['n_features']}] = {{
   {", ".join([f"{x:.10f}" for x in config['scaler']['scale']])}
}};

// Regime-specific settings
struct RegimeSettings {{
   double atr_sl_mult;
   double atr_tp_mult;
   int trailing_start;
   int min_confidence;
}};

RegimeSettings g_regime_settings[3] = {{
   {{ {config['regime_settings']['RANGING']['atr_sl_mult']}, {config['regime_settings']['RANGING']['atr_tp_mult']}, {config['regime_settings']['RANGING']['trailing_start']}, {config['regime_settings']['RANGING']['min_confidence']} }},  // RANGING
   {{ {config['regime_settings']['TRENDING']['atr_sl_mult']}, {config['regime_settings']['TRENDING']['atr_tp_mult']}, {config['regime_settings']['TRENDING']['trailing_start']}, {config['regime_settings']['TRENDING']['min_confidence']} }},  // TRENDING
   {{ {config['regime_settings']['VOLATILE']['atr_sl_mult']}, {config['regime_settings']['VOLATILE']['atr_tp_mult']}, {config['regime_settings']['VOLATILE']['trailing_start']}, {config['regime_settings']['VOLATILE']['min_confidence']} }}   // VOLATILE
}};

// Scale features using saved scaler parameters
void ScaleFeatures(double &features[], double &scaled[]) {{
   ArrayResize(scaled, REGIME_MODEL_FEATURES);
   for(int i = 0; i < REGIME_MODEL_FEATURES; i++) {{
      scaled[i] = (features[i] - g_feature_mean[i]) / g_feature_scale[i];
   }}
}}

// Get regime name
string GetRegimeName(int regime) {{
   switch(regime) {{
      case REGIME_RANGING:  return "RANGING";
      case REGIME_TRENDING: return "TRENDING";
      case REGIME_VOLATILE: return "VOLATILE";
      default: return "UNKNOWN";
   }}
}}
//+------------------------------------------------------------------+
'''
    
    with open(output_path, 'w') as f:
        f.write(mql_code)
    print(f"  MQL5 include saved: {output_path}")


if __name__ == "__main__":
    from pathlib import Path
    
    model_dir = Path(__file__).parent.parent / "models"
    model_path = model_dir / "regime_detector.joblib"
    
    if model_path.exists():
        export_to_onnx(
            str(model_path),
            str(model_dir / "regime_detector.onnx"),
            str(model_dir / "regime_config.json")
        )
        
        create_mt5_include(
            str(model_dir / "regime_config.json"),
            str(model_dir / "RegimeModelConfig.mqh")
        )
    else:
        print(f"Model not found: {model_path}")
        print("Run train_regime.py first to train the model.")

