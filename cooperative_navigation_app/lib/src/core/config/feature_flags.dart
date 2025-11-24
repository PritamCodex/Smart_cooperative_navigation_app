class FeatureFlags {
  // Master toggle for the new fusion system
  static const bool FEATURE_DISTRIBUTED_FUSION = true;
  
  // Sub-features
  static const bool FEATURE_ACCURACY_FILTERING = true;
  static const bool FEATURE_RSSI_FUSION = true; // Will only activate if RSSI is available
  static const bool FEATURE_DEAD_RECKONING_STABILITY = true;
  static const bool FEATURE_INTERPOLATED_MOVEMENT = true;
  static const bool FEATURE_GPS_UNSTABLE_UI = true;
  static const bool FEATURE_CALIBRATION = true;

  // Thresholds
  static const double GPS_ACCURACY_THRESHOLD = 20.0; // meters
  static const double STATIONARY_SPEED_THRESHOLD = 0.5; // m/s
}
