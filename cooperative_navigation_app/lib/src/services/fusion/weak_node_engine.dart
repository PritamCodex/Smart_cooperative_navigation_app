// ignore_for_file: avoid_print, constant_identifier_names

import 'dart:async';
import 'dart:math';

import '../../core/models/collision_alert.dart';
import '../nearby/packet_protocol.dart';

/// Engine for WEAK nodes (low capability or legacy devices).
///
/// Responsibilities:
/// - Does NOT run EKF.
/// - Sends raw sensor data to the leader.
/// - Displays alerts received from the leader.
/// - Falls back to basic RSSI-based distance estimation if no leader is present.
class WeakNodeEngine {
  final String myDeviceId;
  final Function(BasePacket) onSendPacket;
  final StreamController<CollisionAlert> _alertController = StreamController.broadcast();

  Timer? _sensorTimer;
  Timer? _distributedModeTimer;
  
  // Cache of latest RSSI values from peers (for distributed mode)
  final Map<String, int> _peerRssi = {};

  // Constants
  static const double TX_POWER = -59.0; // Reference RSSI at 1m (approx)
  static const double PATH_LOSS_EXPONENT = 2.5; // Environmental factor

  WeakNodeEngine({
    required this.myDeviceId,
    required this.onSendPacket,
  });

  Stream<CollisionAlert> get alertStream => _alertController.stream;

  /// Starts the loop to send raw sensor data to the leader.
  /// Runs at 1-3 Hz to save battery/bandwidth.
  void startSendingSensorData() {
    print('Starting Weak Node Sensor Loop...');
    _sensorTimer?.cancel();
    _sensorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _collectAndSendSensorData();
    });
  }

  void stopSendingSensorData() {
    _sensorTimer?.cancel();
  }

  /// Handles an alert received from the Strong Leader.
  void handleLeaderAlert(LeaderAlertPacket packet) {
    if (packet.targetPeerId == myDeviceId) {
      // This alert is for me!
      _alertController.add(CollisionAlert(
        peerId: packet.senderId,
        level: packet.level,
        relativeDistance: packet.distance,
        closingSpeed: 0.0, // Not provided in packet, derived from TTC if needed
        timeToCollision: packet.ttc,
        lateralDelta: 0.0, // Unknown
        longitudinalDelta: packet.distance, // Approximation
        probability: 1.0, // Leader is authoritative
        timestamp: packet.timestamp,
      ));
    }
  }

  /// Starts the fallback distributed mode when no leader is present.
  /// Uses simple RSSI ranging to detect proximity.
  void startWeakDistributedMode() {
    print('Starting Weak Distributed Mode...');
    _distributedModeTimer?.cancel();
    _distributedModeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _computeBasicRSSIAlerts();
    });
  }

  void stopWeakDistributedMode() {
    _distributedModeTimer?.cancel();
  }

  /// Updates the RSSI value for a peer (called when any packet is received).
  void updatePeerRssi(String peerId, int rssi) {
    _peerRssi[peerId] = rssi;
  }

  void _collectAndSendSensorData() {
    // In a real implementation, this method would fetch data from the native SensorService
    // via MethodChannel ('sensor_service') or a repository.
    //
    // Example:
    // final data = await MethodChannel('sensor_service').invokeMethod('getSensorData');
    // final packet = RawSensorPacket.fromMap(data);
    // onSendPacket(packet);

    // For now, we create a dummy packet to demonstrate the flow.
    // This ensures the system can be tested without a physical device.
    final dummyPacket = RawSensorPacket(
      senderId: myDeviceId,
      lat: 0.0,
      lon: 0.0,
      heading: 0.0,
      speed: 0.0,
      accX: 0.0,
      accY: 0.0,
      accZ: 0.0,
      gyroX: 0.0,
      gyroY: 0.0,
      gyroZ: 0.0,
      rssi: -60,
      timestamp: DateTime.now(),
    );
    
    // print('WeakNode: Sending Raw Sensor Data...');
    onSendPacket(dummyPacket);
  }

  /// Computes distance based on RSSI using Log-Distance Path Loss model.
  double computeBasicRSSIDistance(int rssi) {
    return pow(10, (TX_POWER - rssi) / (10 * PATH_LOSS_EXPONENT)).toDouble();
  }

  void _computeBasicRSSIAlerts() {
    for (final entry in _peerRssi.entries) {
      final peerId = entry.key;
      final rssi = entry.value;
      final distance = computeBasicRSSIDistance(rssi);

      AlertLevel level;
      if (distance < 5.0) {
        level = AlertLevel.red;
      } else if (distance < 10.0) {
        level = AlertLevel.orange;
      } else if (distance < 20.0) {
        level = AlertLevel.yellow;
      } else {
        level = AlertLevel.green;
      }

      if (level != AlertLevel.green) {
        _alertController.add(CollisionAlert(
          peerId: peerId,
          level: level,
          relativeDistance: distance,
          closingSpeed: 0.0, // Unknown
          timeToCollision: -1.0, // Unknown
          lateralDelta: 0.0,
          longitudinalDelta: distance,
          probability: 0.5, // Low confidence (RSSI only)
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  void dispose() {
    _sensorTimer?.cancel();
    _distributedModeTimer?.cancel();
    _alertController.close();
  }
}
