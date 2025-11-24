import 'dart:async';
import 'dart:math' as math;
import 'package:collection/collection.dart';
import '../core/models/cluster_packet.dart';
import '../core/config/feature_flags.dart';

/// Buffer for storing sensor packets with timestamp-based querying
class SensorBuffer {
  final int capacity;
  final List<SensorPacket> _buffer = [];

  SensorBuffer({this.capacity = 50}); // 5 seconds at 10 Hz

  void push(SensorPacket packet) {
    _buffer.add(packet);
    if (_buffer.length > capacity) {
      _buffer.removeAt(0);
    }
  }

  SensorPacket? getLatest() {
    return _buffer.isNotEmpty ? _buffer.last : null;
  }

  List<SensorPacket> getRange(DateTime startTime, DateTime endTime) {
    return _buffer
        .where((p) => 
            p.timestamp.isAfter(startTime) && p.timestamp.isBefore(endTime))
        .toList();
  }

  void clear() {
    _buffer.clear();
  }

  int get length => _buffer.length;
}

/// Extended Kalman Filter state for a single device
class EKFState {
  final List<double> x; // State vector [lat, lon, vx, vy]
  final List<List<double>> P; // Covariance matrix 4x4

  EKFState({
    required this.x,
    required this.P,
  });

  factory EKFState.initial() {
    return EKFState(
      x: [0.0, 0.0, 0.0, 0.0],
      P: [
        [100.0, 0.0, 0.0, 0.0],
        [0.0, 100.0, 0.0, 0.0],
        [0.0, 0.0, 10.0, 0.0],
        [0.0, 0.0, 0.0, 10.0],
      ],
    );
  }

  EKFState copyWith({
    List<double>? x,
    List<List<double>>? P,
  }) {
    return EKFState(
      x: x ?? List.from(this.x),
      P: P ?? this.P.map((row) => List<double>.from(row)).toList(),
    );
  }
}

/// Strong Node Controller - Centralized fusion and collision detection
class StrongNodeController {
  // Sensor buffers per device
  final Map<String, SensorBuffer> _sensorBuffers = {};
  
  // EKF states per device
  final Map<String, EKFState> _ekfStates = {};
  
  // Own device ID
  String? _myDeviceId;
  
  // Fusion loop timer
  Timer? _fusionTimer;
  
  // Alert broadcast timer
  Timer? _alertBroadcastTimer;
  
  // Stream controllers
  final _alertController = StreamController<LeaderAlertPacket>.broadcast();
  
  Stream<LeaderAlertPacket> get alertStream => _alertController.stream;
  
  // Constants
  static const double GPS_ACCURACY_THRESHOLD = 20.0; // meters
  static const double STATIONARY_SPEED_THRESHOLD = 0.5; // m/s
  static const double RSSI_FUSION_DISTANCE_THRESHOLD = 15.0; // meters
  static const double RSSI_FUSION_ACCURACY_THRESHOLD = 10.0; // meters
  static const double RSSI0 = -59.0; // dBm at 1 meter
  static const double PATH_LOSS_EXPONENT = 2.2;
  
  void initialize(String myDeviceId) {
    _myDeviceId = myDeviceId;
    _sensorBuffers[myDeviceId] = SensorBuffer();
    _ekfStates[myDeviceId] = EKFState.initial();
    
    // Start fusion loop at 10 Hz
    _fusionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _runFusionCycle();
    });
    
    // Start alert broadcast at 10-20 Hz
    _alertBroadcastTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _broadcastAlerts();
    });
    
    print('[StrongNode] Initialized for device $myDeviceId');
  }
  
  /// Add sensor packet (from self or peer)
  void addSensorPacket(SensorPacket packet) {
    // Create buffer if new peer
    _sensorBuffers.putIfAbsent(packet.deviceId, () => SensorBuffer());
    _ekfStates.putIfAbsent(packet.deviceId, () => EKFState.initial());
    
    // Add to buffer
    _sensorBuffers[packet.deviceId]!.push(packet);
  }
  
  /// Main fusion cycle (runs at 10 Hz)
  void _runFusionCycle() {
    // For each device, update EKF
    for (final deviceId in _sensorBuffers.keys) {
      final buffer = _sensorBuffers[deviceId]!;
      final latest = buffer.getLatest();
      
      if (latest != null) {
        _updateEKF(deviceId, latest);
      }
    }
  }
  
  /// Update EKF for a single device
  void _updateEKF(String deviceId, SensorPacket packet) {
    final ekf = _ekfStates[deviceId]!;
    
    // Prediction step
    final dt = 0.1; // 100ms interval
    final F = [
      [1.0, 0.0, dt, 0.0],
      [0.0, 1.0, 0.0, dt],
      [0.0, 0.0, 1.0, 0.0],
      [0.0, 0.0, 0.0, 1.0],
    ];
    
    // State prediction: x = F * x
    final xPred = _matrixVectorMultiply(F, ekf.x);
    
    // Covariance prediction: P = F * P * F^T + Q
    final Q = [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 0.5, 0.0],
      [0.0, 0.0, 0.0, 0.5],
    ];
    
    final PPred = _matrixAdd(
      _matrixMultiply(_matrixMultiply(F, ekf.P), _transpose(F)),
      Q,
    );
    
    // Measurement update (if GPS is good enough)
    if (packet.gnss.accuracy < GPS_ACCURACY_THRESHOLD) {
      // Measurement: z = [lat, lon]
      final z = [packet.gnss.lat, packet.gnss.lon];
      
      // Measurement matrix H
      final H = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
      ];
      
      // Measurement covariance R
      final sigma = math.max(0.1, packet.gnss.accuracy);
      final R = [
        [sigma * sigma, 0.0],
        [0.0, sigma * sigma],
      ];
      
      // Innovation: y = z - H * x_pred
      final Hx = _matrixVectorMultiply(H, xPred);
      final y = [z[0] - Hx[0], z[1] - Hx[1]];
      
      // Innovation covariance: S = H * P * H^T + R
      final S = _matrixAdd(
        _matrixMultiply(_matrixMultiply(H, PPred), _transpose(H)),
        R,
      );
      
      // Kalman gain: K = P * H^T * S^-1
      final K = _matrixMultiply(
        _matrixMultiply(PPred, _transpose(H)),
        _matrixInverse2x2(S),
      );
      
      // State update: x = x_pred + K * y
      final Ky = _matrixVectorMultiply(K, y);
      final xUpdate = [
        xPred[0] + Ky[0],
        xPred[1] + Ky[1],
        xPred[2] + Ky[2],
        xPred[3] + Ky[3],
      ];
      
      // Covariance update: P = (I - K * H) * P_pred
      final I = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
      ];
      final KH = _matrixMultiply(K, H);
      final IminusKH = _matrixSubtract(I, KH);
      final PUpdate = _matrixMultiply(IminusKH, PPred);
      
      // Update state
      _ekfStates[deviceId] = EKFState(x: xUpdate, P: PUpdate);
    } else {
      // GPS too poor, just use prediction
      _ekfStates[deviceId] = EKFState(x: xPred, P: PPred);
    }
  }
  
  /// Broadcast alerts to all devices
  void _broadcastAlerts() {
    if (_myDeviceId == null || _sensorBuffers[_myDeviceId] == null) return;
    
    final myBuffer = _sensorBuffers[_myDeviceId]!;
    final myLatest = myBuffer.getLatest();
    if (myLatest == null) return;
    
    final myEkf = _ekfStates[_myDeviceId]!;
    final myLat = myEkf.x[0];
    final myLon = myEkf.x[1];
    
    // Compute alerts for each peer
    final peers = <PeerAlertInfo>[];
    String globalState = 'SAFE';
    
    for (final peerId in _sensorBuffers.keys) {
      if (peerId == _myDeviceId) continue;
      
      final peerEkf = _ekfStates[peerId]!;
      final peerLat = peerEkf.x[0];
      final peerLon = peerEkf.x[1];
      final peerBuffer = _sensorBuffers[peerId]!;
      final peerLatest = peerBuffer.getLatest();
      
      if (peerLatest == null) continue;
      
      // Compute relative distance (Haversine)
      double distance = _haversineDistance(myLat, myLon, peerLat, peerLon);
      
      // RSSI fusion (if close range and GPS poor)
      if (peerLatest.rssi != null &&
          (distance < RSSI_FUSION_DISTANCE_THRESHOLD ||
           myLatest.gnss.accuracy > RSSI_FUSION_ACCURACY_THRESHOLD)) {
        final rssiDistance = _rssiToDistance(peerLatest.rssi!);
        distance = _lerp(distance, rssiDistance, 0.4); // 40% RSSI weight
      }
      
      // Compute relative bearing
      final bearing = _computeBearing(myLat, myLon, peerLat, peerLon);
      
      // Compute relative velocity
      final myVx = myEkf.x[2];
      final myVy = myEkf.x[3];
      final peerVx = peerEkf.x[2];
      final peerVy = peerEkf.x[3];
      final relVx = peerVx - myVx;
      final relVy = peerVy - myVy;
      final relSpeed = math.sqrt(relVx * relVx + relVy * relVy);
      
      // Compute TTC (time to collision)
      double? ttc;
      if (relSpeed > 0.1) {
        // Approaching
        final closingRate = (relVx * (peerLon - myLon) + relVy * (peerLat - myLat)) / distance;
        if (closingRate < 0) {
          ttc = -distance / closingRate;
        }
      }
      
      // Classify alert level
      final alertLevel = _classifyAlertLevel(distance, ttc);
      
      // Update global state
      globalState = _updateGlobalState(globalState, alertLevel);
      
      // Add to peers list
      peers.add(PeerAlertInfo(
        deviceId: peerId,
        relativeDistance: distance,
        relativeBearing: bearing,
        relativeSpeed: relSpeed,
        ttc: ttc,
        alertLevel: alertLevel,
        isLowConfidence: myLatest.gnss.accuracy > GPS_ACCURACY_THRESHOLD,
      ));
    }
    
    // Create alert packet
    final alert = LeaderAlertPacket(
      leaderId: _myDeviceId!,
      globalAlertState: globalState,
      peers: peers,
      ownPosition: OwnPositionData(
        lat: myLat,
        lon: myLon,
        accuracy: myLatest.gnss.accuracy,
      ),
    );
    
    _alertController.add(alert);
  }
  
  /// Classify alert level based on distance and TTC
  String _classifyAlertLevel(double distance, double? ttc) {
    if (distance < 5.0) return 'RED'; // Critical
    if (ttc != null && ttc < 3.0) return 'RED';
    if (distance < 10.0) return 'ORANGE'; // Warning
    if (ttc != null && ttc < 5.0) return 'ORANGE';
    if (distance < 20.0) return 'YELLOW'; // Caution
    if (ttc != null && ttc < 10.0) return 'YELLOW';
    return 'GREEN'; // Safe
  }
  
  /// Update global alert state
  String _updateGlobalState(String current, String peerLevel) {
    const levels = ['GREEN', 'YELLOW', 'ORANGE', 'RED'];
    final currentIdx = levels.indexOf(current);
    final peerIdx = levels.indexOf(peerLevel);
    return levels[math.max(currentIdx, peerIdx)];
  }
  
  /// Haversine distance calculation
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
  
  /// Compute bearing between two points
  double _computeBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _toRadians(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(_toRadians(lat2));
    final x = math.cos(_toRadians(lat1)) * math.sin(_toRadians(lat2)) -
        math.sin(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.cos(dLon);
    final bearing = math.atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360;
  }
  
  /// Convert RSSI to distance
  double _rssiToDistance(double rssi) {
    return math.pow(10, (RSSI0 - rssi) / (10 * PATH_LOSS_EXPONENT)).toDouble();
  }
  
  /// Linear interpolation
  double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }
  
  double _toRadians(double degrees) => degrees * math.pi / 180.0;
  double _toDegrees(double radians) => radians * 180.0 / math.pi;
  
  // Matrix operations (simplified for 4x4 and 2x2)
  
  List<double> _matrixVectorMultiply(List<List<double>> A, List<double> x) {
    final result = List<double>.filled(A.length, 0.0);
    for (int i = 0; i < A.length; i++) {
      for (int j = 0; j < x.length; j++) {
        result[i] += A[i][j] * x[j];
      }
    }
    return result;
  }
  
  List<List<double>> _matrixMultiply(List<List<double>> A, List<List<double>> B) {
    final rows = A.length;
    final cols = B[0].length;
    final inner = B.length;
    final result = List.generate(rows, (_) => List<double>.filled(cols, 0.0));
    
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        for (int k = 0; k < inner; k++) {
          result[i][j] += A[i][k] * B[k][j];
        }
      }
    }
    return result;
  }
  
  List<List<double>> _matrixAdd(List<List<double>> A, List<List<double>> B) {
    final result = List.generate(
      A.length,
      (i) => List.generate(A[0].length, (j) => A[i][j] + B[i][j]),
    );
    return result;
  }
  
  List<List<double>> _matrixSubtract(List<List<double>> A, List<List<double>> B) {
    final result = List.generate(
      A.length,
      (i) => List.generate(A[0].length, (j) => A[i][j] - B[i][j]),
    );
    return result;
  }
  
  List<List<double>> _transpose(List<List<double>> A) {
    final rows = A[0].length;
    final cols = A.length;
    final result = List.generate(rows, (i) => List.generate(cols, (j) => A[j][i]));
    return result;
  }
  
  List<List<double>> _matrixInverse2x2(List<List<double>> A) {
    final det = A[0][0] * A[1][1] - A[0][1] * A[1][0];
    if (det.abs() < 1e-10) {
      // Singular matrix, return identity
      return [[1.0, 0.0], [0.0, 1.0]];
    }
    return [
      [A[1][1] / det, -A[0][1] / det],
      [-A[1][0] / det, A[0][0] / det],
    ];
  }
  
  void dispose() {
    _fusionTimer?.cancel();
    _alertBroadcastTimer?.cancel();
    _alertController.close();
  }
}
