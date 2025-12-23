//+------------------------------------------------------------------+
//|                                           RegimeModelConfig.mqh  |
//|                        Auto-generated from ML model export       |
//+------------------------------------------------------------------+
#property copyright "Regime Detector ML"
#property strict

// Model configuration
#define REGIME_MODEL_FEATURES 30
#define REGIME_RANGING   0
#define REGIME_TRENDING  1
#define REGIME_VOLATILE  2

// Feature scaling parameters (from StandardScaler)
double g_feature_mean[30] = {
   0.0024337108, 0.0024337277, 0.0024337083, 0.0014540864, 0.0015465251, 0.0016224135, 0.9105157345, 1.0064241520, 0.0024193810, 0.4362331921, 0.0000792495, 0.0002038128, 0.0000409934, 0.0000803846, 0.0361404441, 34.9417496186, -0.3413898686, 50.6072435181, 0.2768369086, 0.0002562581, 51.6378791636, 0.0000474723, 0.0000951919, 0.0001891296, 11.9189745633, 1.9968342521, 0.3067012021, 0.3505567732, 0.3921985345, 0.1314781608
};

double g_feature_scale[30] = {
   0.0014500670, 0.0012602382, 0.0010839082, 0.0011371632, 0.0010071218, 0.0008772400, 0.4336888002, 0.3729992815, 0.0019640126, 0.2525561149, 0.0044763707, 0.0072934827, 0.0019263906, 0.0024877891, 1.2326657853, 16.0832954760, 19.0201632602, 17.5093292521, 0.4474351737, 0.9311021166, 28.3672831693, 0.0040839786, 0.0057255958, 0.0080375150, 6.6003231528, 1.4081467355, 0.4611242509, 0.4771443408, 0.4882405596, 0.3379225562
};

// Regime-specific settings
struct RegimeSettings {
   double atr_sl_mult;
   double atr_tp_mult;
   int trailing_start;
   int min_confidence;
};

RegimeSettings g_regime_settings[3] = {
   { 1.0, 1.5, 8, 60 },  // RANGING
   { 1.5, 2.5, 15, 55 },  // TRENDING
   { 2.0, 2.0, 20, 70 }   // VOLATILE
};

// Scale features using saved scaler parameters
void ScaleFeatures(double &features[], double &scaled[]) {
   ArrayResize(scaled, REGIME_MODEL_FEATURES);
   for(int i = 0; i < REGIME_MODEL_FEATURES; i++) {
      scaled[i] = (features[i] - g_feature_mean[i]) / g_feature_scale[i];
   }
}

// Get regime name
string GetRegimeName(int regime) {
   switch(regime) {
      case REGIME_RANGING:  return "RANGING";
      case REGIME_TRENDING: return "TRENDING";
      case REGIME_VOLATILE: return "VOLATILE";
      default: return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+
