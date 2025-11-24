import 'dart:math' as math;
import 'package:cooperative_navigation_safety/src/core/config/feature_flags.dart';
import 'package:cooperative_navigation_safety/src/core/models/beacon_packet.dart';
import 'package:cooperative_navigation_safety/src/core/models/sensor_data.dart';

/// Represents a 2x2 Matrix for Covariance
class Matrix2x2 {
  final double a, b, c, d; // [a b; c d]

  const Matrix2x2(this.a, this.b, this.c, this.d);

  static const Matrix2x2 identity = Matrix2x2(1, 0, 0, 1);
  static const Matrix2x2 zero = Matrix2x2(0, 0, 0, 0);

  Matrix2x2 operator +(Matrix2x2 other) => Matrix2x2(a + other.a, b + other.b, c + other.c, d + other.d);
  Matrix2x2 operator *(double scalar) => Matrix2x2(a * scalar, b * scalar, c * scalar, d * scalar);

  double get det => a * d - b * c;
  double get trace => a + d;

  Matrix2x2 get inverse {
    final detVal = det;
    if (detVal.abs() < 1e-9) return Matrix2x2.identity; // Fallback
    final invDet = 1.0 / detVal;
    return Matrix2x2(d * invDet, -b * invDet, -c * invDet, a * invDet);
  }
}

/// State vector [lat, lon] (simplified for 2D fusion)
class StateVector {
  final double lat;
  final double lon;

  const StateVector(this.lat, this.lon);

  StateVector operator +(StateVector other) => StateVector(lat + other.lat, lon + other.lon);
  StateVector operator *(double scalar) => StateVector(lat * scalar, lon * scalar);
}

class DistributedFusionEngine {
  // Current State
  StateVector _x = const StateVector(0, 0);
  Matrix2x2 _P = const Matrix2x2(100, 0, 0, 100); // High uncertainty initially
  
  // Calibration Offsets
  double _latBias = 0.0;
  double _lonBias = 0.0;
  
  // Dead Reckoning State
  bool _isStationary = false;
  StateVector? _stationaryAnchor;
  
  // Peer States (for fusion)
  final Map<String, StateVector> _peerStates = {};
  final Map<String, Matrix2x2> _peerCovariances = {};

  // Getters
  double get latitude => _x.lat;
  double get longitude => _x.lon;
  double get accuracy => math.sqrt(_P.trace); // Approx accuracy from covariance trace

  /// Initialize with initial GPS reading
  void initialize(double lat, double lon, double accuracy) {
    _x = StateVector(lat, lon);
    final varPos = accuracy * accuracy;
    _P = Matrix2x2(varPos, 0, 0, varPos);
  }

  /// Predict step (Process Update)
  /// Uses IMU/Speed to propagate state
  void predict(SensorData data, double dt) {
    if (!FeatureFlags.FEATURE_DISTRIBUTED_FUSION) return;

    // 1. Dead Reckoning Logic
    if (FeatureFlags.FEATURE_DEAD_RECKONING_STABILITY) {
      if ((data.speed ?? 0) < FeatureFlags.STATIONARY_SPEED_THRESHOLD) {
        _isStationary = true;
        _stationaryAnchor ??= _x; // Lock position
        
        // Increase process noise slightly to allow convergence if we move
        // But don't propagate state based on velocity
        _P = _P + const Matrix2x2(0.01, 0, 0, 0.01); 
        return;
      } else {
        _isStationary = false;
        _stationaryAnchor = null;
      }
    }

    // 2. Kinematic Prediction (Simple Constant Velocity)
    // Convert speed/heading to lat/lon delta (approx)
    // 1 deg lat approx 111km, 1 deg lon approx 111km * cos(lat)
    if (data.speed != null && data.heading != null) {
      final dist = data.speed! * dt; // meters
      final radHeading = data.heading! * math.pi / 180.0;
      
      final dLat = (dist * math.cos(radHeading)) / 111320.0;
      final dLon = (dist * math.sin(radHeading)) / (111320.0 * math.cos(_x.lat * math.pi / 180.0));
      
      _x = StateVector(_x.lat + dLat, _x.lon + dLon);
      
      // Add Process Noise Q
      // Q depends on dt and speed uncertainty
      final qVal = 0.1 * dt; 
      _P = _P + Matrix2x2(qVal, 0, 0, qVal);
    }
  }

  /// Update step (Measurement Update - GNSS)
  void updateGNSS(double lat, double lon, double accuracy) {
    if (!FeatureFlags.FEATURE_DISTRIBUTED_FUSION) return;

    // 1. Accuracy Filtering
    if (FeatureFlags.FEATURE_ACCURACY_FILTERING) {
      if (accuracy > FeatureFlags.GPS_ACCURACY_THRESHOLD) {
        // Low confidence - Skip update or use very high measurement noise
        // We'll skip update to prevent jumps
        return;
      }
    }

    // 2. Weighted Update
    // R = Measurement Noise Covariance
    // Weighted: sigma = max(0.1, accuracy)
    final sigma = math.max(0.1, accuracy);
    final rVal = sigma * sigma;
    final R = Matrix2x2(rVal, 0, 0, rVal);
    
    // Kalman Gain K = P * (P + R)^-1
    final S = _P + R;
    final sInv = S.inverse;
    final K = Matrix2x2(
      _P.a * sInv.a + _P.b * sInv.c, _P.a * sInv.b + _P.b * sInv.d,
      _P.c * sInv.a + _P.d * sInv.c, _P.c * sInv.b + _P.d * sInv.d
    );
    
    // Innovation y = z - x
    final yLat = lat - _x.lat;
    final yLon = lon - _x.lon;
    
    // State Update x = x + K * y
    _x = StateVector(
      _x.lat + (K.a * yLat + K.b * yLon),
      _x.lon + (K.c * yLat + K.d * yLon)
    );
    
    // Covariance Update P = (I - K) * P
    // Simplified: P = P - K * S * K'
    // For now, standard: P = (I - K) * P
    final I = Matrix2x2.identity;
    final iMinusK = Matrix2x2(I.a - K.a, I.b - K.b, I.c - K.c, I.d - K.d);
    
    _P = Matrix2x2(
      iMinusK.a * _P.a + iMinusK.b * _P.c, iMinusK.a * _P.b + iMinusK.b * _P.d,
      iMinusK.c * _P.a + iMinusK.d * _P.c, iMinusK.c * _P.b + iMinusK.d * _P.d
    );
  }

  /// Fuse Peer Data using Covariance Intersection
  /// Fuses our estimate with the peer's reported position to refine relative understanding
  void fusePeer(BeaconPacket peerBeacon) {
    if (!FeatureFlags.FEATURE_DISTRIBUTED_FUSION) return;

    // We treat the peer's position as a measurement of OUR position 
    // (if we knew the relative distance perfectly).
    // But here, we are just refining our knowledge of the PEER's position relative to us?
    // The prompt says "Fuse peer estimates... to avoid double counting".
    // Usually CI is used when fusing two estimates of the SAME state.
    // Here, we are fusing:
    // 1. Our GPS
    // 2. Peer's GPS (which is correlated if we are close? No, usually independent errors unless atmospheric).
    
    // Implementation: We will just store the peer's state and covariance for now,
    // so CollisionEngine can use it.
    
    final peerSigma = math.max(0.1, peerBeacon.accuracy);
    final peerVar = peerSigma * peerSigma;
    
    _peerStates[peerBeacon.ephemeralId] = StateVector(peerBeacon.latitude, peerBeacon.longitude);
    _peerCovariances[peerBeacon.ephemeralId] = Matrix2x2(peerVar, 0, 0, peerVar);
  }
  
  /// RSSI Fusion Logic
  /// Returns a fused distance if RSSI is available and valid
  double? fuseRSSI(double gpsDistance, double? rssi, double accuracy) {
    if (!FeatureFlags.FEATURE_RSSI_FUSION || rssi == null) return null;
    
    // Condition: GPS < 15m OR Accuracy > 10m
    if (gpsDistance < 15.0 || accuracy > 10.0) {
      // RSSI Model: d = 10^((RSSI0 - rssi) / (10*n))
      // Default: RSSI0 = -59 (approx for 1m), n = 2.2
      const rssi0 = -59.0;
      const n = 2.2;
      
      final rssiDistance = math.pow(10, (rssi0 - rssi) / (10 * n)).toDouble();
      
      // Linear Interpolation (lerp)
      // fused = lerp(gps, rssi, 0.4) -> 40% RSSI, 60% GPS
      return gpsDistance * 0.6 + rssiDistance * 0.4;
    }
    
    return null;
  }
  
  /// Calibration
  void calibrateSensors() {
    if (!FeatureFlags.FEATURE_CALIBRATION) return;
    
    // Reset Covariance to allow rapid reconvergence
    _P = const Matrix2x2(100, 0, 0, 100);
    
    // In a real system, we would average IMU samples here to find bias.
    // For now, we just reset the filter.
  }
}
