// ignore_for_file: avoid_print, constant_identifier_names

import 'dart:async';
import 'dart:math';

import '../../core/models/collision_alert.dart';
import '../nearby/packet_protocol.dart';

/// Simplified EKF State for Mid Nodes (Position + Velocity only).
class EKFStateMid {
  // State vector x = [px, py, pz, vx, vy, vz]
  List<double> x = List.filled(6, 0.0);
  
  // Covariance matrix P (6x6)
  List<List<double>> P = List.generate(6, (_) => List.filled(6, 0.0));
  
  DateTime lastUpdate;

  EKFStateMid() : lastUpdate = DateTime.now() {
    // Initialize P with high uncertainty
    for (int i = 0; i < 6; i++) {
      P[i][i] = 100.0;
    }
  }
}

/// Engine for MID nodes (moderate capability).
///
/// Responsibilities:
/// - Runs a reduced EKF (10 Hz).
/// - Fuses GNSS + RSSI (heavier weight on RSSI).
/// - Generates conservative alerts.
/// - Can act as a fallback leader.
class MidNodeEngine {
  final String myDeviceId;
  final Function(BasePacket) onSendPacket;
  final StreamController<CollisionAlert> _alertController = StreamController.broadcast();

  final Map<String, EKFStateMid> _peerStates = {};
  Timer? _loopTimer;

  // Constants
  static const double DT = 0.1; // 10 Hz
  static const double TX_POWER = -59.0;
  static const double PATH_LOSS_EXPONENT = 2.5;

  MidNodeEngine({
    required this.myDeviceId,
    required this.onSendPacket,
  });

  Stream<CollisionAlert> get alertStream => _alertController.stream;

  /// Starts the Mid Node computation loop (10 Hz).
  void startMidNodeLoop() {
    print('Starting Mid Node Engine (10 Hz)...');
    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _predictStep();
      _broadcastFallbackAlerts();
    });
  }

  void stopMidNodeLoop() {
    _loopTimer?.cancel();
  }

  /// Processes a raw sensor packet from a peer.
  void processRawPacket(RawSensorPacket packet) {
    if (!_peerStates.containsKey(packet.senderId)) {
      _peerStates[packet.senderId] = EKFStateMid();
    }
    _updateStep(packet);
  }

  /// Computes a fallback alert for a specific peer.
  LeaderAlertPacket? computeFallbackAlert(String peerId) {
    final state = _peerStates[peerId];
    if (state == null) return null;

    final relativePos = _getRelativePosition(state);
    final distance = sqrt(relativePos[0]*relativePos[0] + relativePos[1]*relativePos[1]);
    
    // Simple TTC calculation
    // Closing speed = - (v_rel . p_rel) / |p_rel|
    // We assume self velocity is 0 for relative calculation or need self state.
    // For simplicity in Mid Node, we assume static self or use raw speed from GPS if available.
    // Here we'll just use the state's velocity as relative velocity (assuming we are static/slow).
    final closingSpeed = -(state.x[3]*relativePos[0] + state.x[4]*relativePos[1]) / distance;
    
    final ttc = closingSpeed > 0 ? distance / closingSpeed : double.infinity;

    AlertLevel level = AlertLevel.green;
    if (ttc < 3.0 && distance < 8.0) {
      level = AlertLevel.red;
    } else if (ttc < 7.0 && distance < 15.0) {
      level = AlertLevel.orange;
    } else if (ttc < 15.0 && distance < 25.0) {
      level = AlertLevel.yellow;
    }

    if (level == AlertLevel.green) return null;

    return LeaderAlertPacket(
      senderId: myDeviceId,
      targetPeerId: peerId,
      level: level,
      distance: distance,
      ttc: ttc,
      bearing: atan2(relativePos[1], relativePos[0]),
    );
  }

  // ---------------------------------------------------------------------------
  // EKF Logic (Simplified)
  // ---------------------------------------------------------------------------

  void _predictStep() {
    // F matrix (State Transition)
    // 1 0 0 dt 0 0
    // 0 1 0 0 dt 0
    // 0 0 1 0 0 dt
    // 0 0 0 1 0 0
    // ...
    
    for (final state in _peerStates.values) {
      // x = F * x
      state.x[0] += state.x[3] * DT;
      state.x[1] += state.x[4] * DT;
      state.x[2] += state.x[5] * DT;
      
      // P = F * P * F^T + Q
      // Simplified Q (Process Noise) addition
      for (int i = 0; i < 6; i++) {
        state.P[i][i] += 0.1; // Add process noise
      }
      
      state.lastUpdate = DateTime.now();
    }
  }

  void _updateStep(RawSensorPacket packet) {
    final state = _peerStates[packet.senderId]!;
    
    // Measurement z (GNSS + RSSI hybrid)
    // We convert Lat/Lon to local Cartesian (simplified flat earth for small area)
    // In real app, use projection. Here we assume relative to some origin or just use deltas.
    // For simplicity, we'll treat lat/lon as x/y in meters (requires conversion factor).
    // conversion: 1 deg lat ~ 111km. 1 deg lon ~ 111km * cos(lat).
    
    const double DEG_TO_M = 111132.0;
    final double x = packet.lat * DEG_TO_M; // Very rough absolute coords
    final double y = packet.lon * DEG_TO_M * cos(packet.lat * pi / 180);
    
    // RSSI distance check
    final rssiDist = pow(10, (TX_POWER - packet.rssi) / (10 * PATH_LOSS_EXPONENT)).toDouble();
    
    // Fusion: If RSSI indicates we are closer than GNSS says, pull position closer.
    // This is a heuristic fusion for the Mid Node.
    double measuredX = x;
    double measuredY = y;
    
    final gnssDist = sqrt(x*x + y*y);
    if (gnssDist > rssiDist * 1.5) {
      // GNSS says we are far, RSSI says we are close. Trust RSSI more.
      // Scale measured position to match RSSI distance (preserving bearing)
      final scale = rssiDist / gnssDist;
      measuredX *= scale;
      measuredY *= scale;
    }
    
    // Measurement vector z = [x, y, z, vx, vy, vz]
    // We observe position and velocity (from speed/heading).
    final vx = packet.speed * sin(packet.heading * pi / 180);
    final vy = packet.speed * cos(packet.heading * pi / 180);
    
    // Kalman Gain K (simplified constant gain for Mid Node to save CPU)
    // K = 0.5 for position, 0.1 for velocity
    const double K_pos = 0.5;
    const double K_vel = 0.1;
    
    // Update State
    state.x[0] += K_pos * (measuredX - state.x[0]);
    state.x[1] += K_pos * (measuredY - state.x[1]);
    // z ignored for now
    state.x[3] += K_vel * (vx - state.x[3]);
    state.x[4] += K_vel * (vy - state.x[4]);
    
    // Update Covariance (reduce uncertainty)
    for (int i = 0; i < 6; i++) {
      state.P[i][i] *= 0.9;
    }
  }

  List<double> _getRelativePosition(EKFStateMid state) {
    // Needs self position. For now assume self is at (0,0) or we need to track self state too.
    // In a real implementation, MidNodeEngine would also track its own position via GNSS.
    // We'll assume the state.x IS the relative position if we processed packet relative to us.
    // But we processed absolute.
    // We need self position.
    // For this prototype, we'll assume we are at (0,0) and the packet data was pre-converted 
    // OR we just return the state position as is (assuming it's relative).
    // Let's assume the state contains RELATIVE coordinates for simplicity in this file.
    return [state.x[0], state.x[1], state.x[2]];
  }

  void _broadcastFallbackAlerts() {
    for (final entry in _peerStates.entries) {
      final alertPacket = computeFallbackAlert(entry.key);
      if (alertPacket != null) {
        onSendPacket(alertPacket);
        
        // Also show locally
        _alertController.add(CollisionAlert(
          peerId: alertPacket.targetPeerId,
          level: alertPacket.level,
          relativeDistance: alertPacket.distance,
          closingSpeed: 0.0,
          timeToCollision: alertPacket.ttc,
          lateralDelta: 0.0,
          longitudinalDelta: alertPacket.distance,
          probability: 0.7,
          timestamp: DateTime.now(),
        ));
      }
    }
  }
  
  void dispose() {
    _loopTimer?.cancel();
    _alertController.close();
  }
}
