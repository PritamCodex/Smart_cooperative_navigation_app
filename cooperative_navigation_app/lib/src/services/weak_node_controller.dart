import 'dart:async';
import 'dart:math' as math;
import '../core/models/cluster_packet.dart';
import '../core/config/feature_flags.dart';

/// Weak Node Controller - Sensor packet transmission and alert reception
class WeakNodeController {
  String? _myDeviceId;
  String? _currentLeaderId;
  
  // Timers
  Timer? _sensorTransmitTimer;
  Timer? _leaderWatchdog;
  
  // Current mode
  bool _isReducedMode = false;
  
  // Stream controllers
  final _sensorPacketController = StreamController<SensorPacket>.broadcast();
  final _uiUpdateController = StreamController<WeakNodeUIUpdate>.broadcast();
  
  Stream<SensorPacket> get sensorPacketStream => _sensorPacketController.stream;
  Stream<WeakNodeUIUpdate> get uiUpdateStream => _uiUpdateController.stream;
  
  // Latest sensor data (from SensorService)
  GnssData? _latestGnss;
  ImuData? _latestImu;
  double? _latestRssi;
  int _batteryLevel = 100;
  
  // RSSI-only ranging (for reduced mode)
  final Map<String, double> _rssiDistances = {};
  
  // Constants
  static const Duration LEADER_TIMEOUT = Duration(seconds: 3);
  static const double RSSI0 = -59.0; // dBm at 1 meter
  static const double PATH_LOSS_EXPONENT = 2.2;
  
  void initialize(String myDeviceId) {
    _myDeviceId = myDeviceId;
    print('[WeakNode] Initialized for device $myDeviceId');
  }
  
  /// Start sensor transmission to leader
  void startTransmission(String leaderId) {
    _currentLeaderId = leaderId;
    _isReducedMode = false;
    
    // Start sensor transmission at adaptive rate
    _startSensorTransmission();
    
    // Start leader watchdog
    _resetLeaderWatchdog();
    
    print('[WeakNode] Started transmission to leader $leaderId');
    
    _uiUpdateController.add(WeakNodeUIUpdate(
      type: 'MODE_CHANGE',
      data: {'mode': 'FOLLOWER', 'leaderId': leaderId},
    ));
  }
  
  /// Stop transmission (leader lost)
  void stopTransmission() {
    _sensorTransmitTimer?.cancel();
    _leaderWatchdog?.cancel();
    _currentLeaderId = null;
    
    print('[WeakNode] Stopped transmission - entering REDUCED_MODE');
    _enterReducedMode();
  }
  
  /// Update sensor data from SensorService
  void updateSensorData({
    GnssData? gnss,
    ImuData? imu,
    double? rssi,
    int? batteryLevel,
  }) {
    if (gnss != null) _latestGnss = gnss;
    if (imu != null) _latestImu = imu;
    if (rssi != null) _latestRssi = rssi;
    if (batteryLevel != null) _batteryLevel = batteryLevel;
  }
  
  /// Handle incoming LeaderAlertPacket
  void onLeaderAlert(LeaderAlertPacket packet) {
    // Reset watchdog (leader is alive)
    _resetLeaderWatchdog();
    
    // Exit reduced mode if we were in it
    if (_isReducedMode) {
      _exitReducedMode();
    }
    
    // Update UI with alert data
    _uiUpdateController.add(WeakNodeUIUpdate(
      type: 'ALERT_UPDATE',
      data: {
        'globalState': packet.globalAlertState,
        'peers': packet.peers.map((p) => {
          'deviceId': p.deviceId,
          'distance': p.relativeDistance,
          'bearing': p.relativeBearing,
          'alertLevel': p.alertLevel,
          'ttc': p.ttc,
          'isLowConfidence': p.isLowConfidence,
        }).toList(),
        'leaderPosition': {
          'lat': packet.ownPosition.lat,
          'lon': packet.ownPosition.lon,
          'accuracy': packet.ownPosition.accuracy,
        },
      },
    ));
    
    // Trigger vibration/sound for critical alerts
    if (packet.globalAlertState == 'RED') {
      _uiUpdateController.add(WeakNodeUIUpdate(
        type: 'CRITICAL_ALERT',
        data: {'message': 'Collision Warning!'},
      ));
    }
  }
  
  /// Start sensor transmission loop
  void _startSensorTransmission() {
    _sensorTransmitTimer?.cancel();
    
    // Adaptive transmission rate based on speed
    final transmitInterval = _computeTransmitInterval();
    
    _sensorTransmitTimer = Timer.periodic(transmitInterval, (_) {
      _transmitSensorPacket();
    });
  }
  
  /// Compute transmission interval based on motion
  Duration _computeTransmitInterval() {
    final speed = _latestGnss?.speed ?? 0.0;
    
    if (speed > 2.0) {
      return const Duration(milliseconds: 100); // 10 Hz (moving)
    } else if (speed > 0.5) {
      return const Duration(milliseconds: 200); // 5 Hz (slow)
    } else {
      return const Duration(milliseconds: 500); // 2 Hz (stationary)
    }
  }
  
  /// Transmit sensor packet to leader
  void _transmitSensorPacket() {
    if (_latestGnss == null || _latestImu == null || _myDeviceId == null) {
      return;
    }
    
    final isStationary = (_latestGnss!.speed < 0.5);
    
    final packet = SensorPacket(
      deviceId: _myDeviceId!,
      gnss: _latestGnss!,
      imu: _latestImu!,
      rssi: _latestRssi,
      battery: _batteryLevel,
      isStationary: isStationary,
    );
    
    _sensorPacketController.add(packet);
  }
  
  /// Reset leader watchdog timer
  void _resetLeaderWatchdog() {
    _leaderWatchdog?.cancel();
    _leaderWatchdog = Timer(LEADER_TIMEOUT, () {
      print('[WeakNode] Leader watchdog timeout!');
      stopTransmission();
    });
  }
  
  /// Enter reduced mode (no leader available)
  void _enterReducedMode() {
    _isReducedMode = true;
    
    // Switch to RSSI-only estimation
    _uiUpdateController.add(WeakNodeUIUpdate(
      type: 'MODE_CHANGE',
      data: {
        'mode': 'REDUCED',
        'message': 'Low Accuracy Mode - No Network Leader',
      },
    ));
    
    // Start RSSI-only ranging (if peers visible)
    _startRSSIOnlyMode();
  }
  
  /// Exit reduced mode (leader recovered)
  void _exitReducedMode() {
    _isReducedMode = false;
    
    _uiUpdateController.add(WeakNodeUIUpdate(
      type: 'MODE_CHANGE',
      data: {
        'mode': 'FOLLOWER',
        'message': 'Network Leader Restored',
      },
    ));
  }
  
  /// Start RSSI-only ranging mode
  void _startRSSIOnlyMode() {
    // This would estimate distances using RSSI only
    // For now, just display reduced accuracy warning
    print('[WeakNode] RSSI-only mode active');
  }
  
  /// Estimate distance using RSSI formula
  double _estimateDistanceFromRSSI(double rssi) {
    return math.pow(10, (RSSI0 - rssi) / (10 * PATH_LOSS_EXPONENT)).toDouble();
  }
  
  /// Update RSSI distance for a peer
  void updatePeerRSSI(String peerId, double rssi) {
    final distance = _estimateDistanceFromRSSI(rssi);
    _rssiDistances[peerId] = distance;
    
    if (_isReducedMode) {
      // In reduced mode, show RSSI-based distances
      _uiUpdateController.add(WeakNodeUIUpdate(
        type: 'RSSI_DISTANCE',
        data: {
          'peerId': peerId,
          'distance': distance,
          'accuracy': '±3m', // RSSI is inherently inaccurate
        },
      ));
    }
  }
  
  void dispose() {
    _sensorTransmitTimer?.cancel();
    _leaderWatchdog?.cancel();
    _sensorPacketController.close();
    _uiUpdateController.close();
  }
}

/// UI update event for weak node
class WeakNodeUIUpdate {
  final String type;
  final Map<String, dynamic> data;
  
  WeakNodeUIUpdate({
    required this.type,
    required this.data,
  });
}
