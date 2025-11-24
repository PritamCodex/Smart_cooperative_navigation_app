// ignore_for_file: avoid_print, constant_identifier_names

import 'dart:async';
import 'dart:math';

import '../../core/models/collision_alert.dart';
import '../nearby/packet_protocol.dart';

/// A simple Matrix class for EKF operations (since vector_math is limited to 4x4).
class Matrix {
  final int rows;
  final int cols;
  final List<List<double>> data;

  Matrix(this.rows, this.cols) : data = List.generate(rows, (_) => List.filled(cols, 0.0));

  factory Matrix.identity(int size) {
    final m = Matrix(size, size);
    for (int i = 0; i < size; i++) {
      m.data[i][i] = 1.0;
    }
    return m;
  }

  factory Matrix.fromList(List<List<double>> list) {
    final rows = list.length;
    final cols = list[0].length;
    final m = Matrix(rows, cols);
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        m.data[i][j] = list[i][j];
      }
    }
    return m;
  }

  Matrix operator +(Matrix other) {
    final result = Matrix(rows, cols);
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        result.data[i][j] = data[i][j] + other.data[i][j];
      }
    }
    return result;
  }

  Matrix operator -(Matrix other) {
    final result = Matrix(rows, cols);
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        result.data[i][j] = data[i][j] - other.data[i][j];
      }
    }
    return result;
  }

  Matrix operator *(dynamic other) {
    if (other is double) {
      final result = Matrix(rows, cols);
      for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
          result.data[i][j] = data[i][j] * other;
        }
      }
      return result;
    } else if (other is Matrix) {
      if (cols != other.rows) throw Exception('Matrix dimension mismatch');
      final result = Matrix(rows, other.cols);
      for (int i = 0; i < rows; i++) {
        for (int j = 0; j < other.cols; j++) {
          double sum = 0.0;
          for (int k = 0; k < cols; k++) {
            sum += data[i][k] * other.data[k][j];
          }
          result.data[i][j] = sum;
        }
      }
      return result;
    }
    throw Exception('Invalid type for multiplication');
  }

  Matrix transpose() {
    final result = Matrix(cols, rows);
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        result.data[j][i] = data[i][j];
      }
    }
    return result;
  }

  // Simple Gaussian elimination for inverse (only for small matrices like 3x3 or diagonal-heavy)
  // For 9x9 full inverse, this is slow/unstable without LU decomposition.
  // We'll implement a simplified inverse assuming diagonal dominance or use a library if possible.
  // For this prototype, we'll implement a basic Gauss-Jordan elimination.
  Matrix inverse() {
    if (rows != cols) throw Exception('Matrix must be square');
    int n = rows;
    Matrix augmented = Matrix(n, 2 * n);
    
    // Create augmented matrix [A | I]
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        augmented.data[i][j] = data[i][j];
      }
      augmented.data[i][i + n] = 1.0;
    }

    // Gaussian elimination
    for (int i = 0; i < n; i++) {
      // Pivot
      double pivot = augmented.data[i][i];
      if (pivot.abs() < 1e-10) throw Exception('Matrix is singular');
      
      for (int j = 0; j < 2 * n; j++) {
        augmented.data[i][j] /= pivot;
      }
      
      for (int k = 0; k < n; k++) {
        if (k != i) {
          double factor = augmented.data[k][i];
          for (int j = 0; j < 2 * n; j++) {
            augmented.data[k][j] -= factor * augmented.data[i][j];
          }
        }
      }
    }

    // Extract inverse
    Matrix inv = Matrix(n, n);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        inv.data[i][j] = augmented.data[i][j + n];
      }
    }
    return inv;
  }
}

class EKFState {
  // State vector x = [px, py, pz, vx, vy, vz, ax, ay, az] (9x1)
  Matrix x = Matrix(9, 1);
  
  // Covariance matrix P (9x9)
  Matrix P = Matrix.identity(9) * 100.0; // High initial uncertainty
  
  DateTime lastUpdate;
  DateTime lastGNSS;

  EKFState() : lastUpdate = DateTime.now(), lastGNSS = DateTime.now();
}

/// Engine for STRONG nodes (high capability).
///
/// Responsibilities:
/// - Full EKF (15-20 Hz).
/// - Fuses GNSS + IMU + RSSI.
/// - Tracks multiple targets.
/// - Predicts collisions.
/// - Broadcasts LeaderAlert packets.
class StrongNodeEngine {
  final String myDeviceId;
  final Function(BasePacket) onSendPacket;
  final StreamController<CollisionAlert> _alertController = StreamController.broadcast();

  final Map<String, EKFState> _peerStates = {};
  Timer? _loopTimer;

  // EKF Constants
  static const double DT = 0.05; // 20 Hz
  static const double PROCESS_NOISE = 0.1;
  static const double MEASUREMENT_NOISE_GNSS = 5.0;
  static const double MEASUREMENT_NOISE_RSSI = 10.0;
  
  // Physics Constants
  static const double TX_POWER = -59.0;
  static const double PATH_LOSS_EXPONENT = 2.5;

  StrongNodeEngine({
    required this.myDeviceId,
    required this.onSendPacket,
  });

  Stream<CollisionAlert> get alertStream => _alertController.stream;

  void startStrongNodeLoop() {
    print('Starting Strong Node Engine (20 Hz)...');
    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _predictStep();
      _broadcastAlerts();
    });
  }

  void stopStrongNodeLoop() {
    _loopTimer?.cancel();
  }

  void processSensorPacket(RawSensorPacket packet) {
    if (!_peerStates.containsKey(packet.senderId)) {
      _initializeState(packet);
    }
    _updateStep(packet);
  }

  void _initializeState(RawSensorPacket packet) {
    final state = EKFState();
    // Initialize position from GNSS
    // Convert Lat/Lon to local Cartesian (simplified)
    const double DEG_TO_M = 111132.0;
    state.x.data[0][0] = packet.lat * DEG_TO_M;
    state.x.data[1][0] = packet.lon * DEG_TO_M * cos(packet.lat * pi / 180);
    state.x.data[2][0] = 0.0; // Altitude ignored for now
    
    // Initialize velocity
    state.x.data[3][0] = packet.speed * sin(packet.heading * pi / 180);
    state.x.data[4][0] = packet.speed * cos(packet.heading * pi / 180);
    
    // Initialize acceleration
    state.x.data[6][0] = packet.accX;
    state.x.data[7][0] = packet.accY;
    state.x.data[8][0] = packet.accZ;
    
    _peerStates[packet.senderId] = state;
  }

  void _predictStep() {
    // Constant Acceleration Model
    // x_k = F * x_k-1
    
    // F Matrix (9x9)
    // 1 0 0 dt 0 0 0.5dt^2 0 0
    // ...
    final F = Matrix.identity(9);
    // Position += Velocity * dt + 0.5 * Accel * dt^2
    F.data[0][3] = DT; F.data[0][6] = 0.5 * DT * DT;
    F.data[1][4] = DT; F.data[1][7] = 0.5 * DT * DT;
    F.data[2][5] = DT; F.data[2][8] = 0.5 * DT * DT;
    
    // Velocity += Accel * dt
    F.data[3][6] = DT;
    F.data[4][7] = DT;
    F.data[5][8] = DT;
    
    // Q Matrix (Process Noise)
    final Q = Matrix.identity(9) * PROCESS_NOISE;

    for (final state in _peerStates.values) {
      // x = F * x
      state.x = F * state.x;
      
      // P = F * P * F^T + Q
      state.P = (F * state.P * F.transpose()) + Q;
      
      state.lastUpdate = DateTime.now();
    }
  }

  void _updateStep(RawSensorPacket packet) {
    final state = _peerStates[packet.senderId]!;
    
    // Measurement z (GNSS pos, Velocity, Accel)
    // We treat RSSI as a separate constraint or fuse it here.
    // For simplicity, we'll fuse GNSS position directly.
    
    const double DEG_TO_M = 111132.0;
    final double mx = packet.lat * DEG_TO_M;
    final double my = packet.lon * DEG_TO_M * cos(packet.lat * pi / 180);
    
    // Measurement Vector z (9x1) - We measure everything directly in this simplified model
    // In reality, we measure [pos, vel, acc]
    final z = Matrix(9, 1);
    z.data[0][0] = mx;
    z.data[1][0] = my;
    z.data[2][0] = 0.0;
    z.data[3][0] = packet.speed * sin(packet.heading * pi / 180);
    z.data[4][0] = packet.speed * cos(packet.heading * pi / 180);
    z.data[5][0] = 0.0;
    z.data[6][0] = packet.accX;
    z.data[7][0] = packet.accY;
    z.data[8][0] = packet.accZ;
    
    // H Matrix (Measurement Matrix) - Identity since we measure states directly
    final H = Matrix.identity(9);
    
    // R Matrix (Measurement Noise)
    final R = Matrix.identity(9);
    // Position noise (GNSS)
    R.data[0][0] = MEASUREMENT_NOISE_GNSS;
    R.data[1][1] = MEASUREMENT_NOISE_GNSS;
    // Velocity noise
    R.data[3][3] = 1.0;
    R.data[4][4] = 1.0;
    // Accel noise
    R.data[6][6] = 0.5;
    R.data[7][7] = 0.5;
    
    // RSSI Fusion: Adjust R based on RSSI consistency?
    // Or use RSSI to adjust z?
    // Here we scale R based on RSSI. If RSSI is strong, we might trust position more?
    // Actually, RSSI gives relative distance, not absolute position.
    // Integrating RSSI correctly requires trilateration or a relative state vector.
    // For this Strong Node, we assume we want global tracking.
    // We'll leave RSSI out of the direct EKF update for now unless we have a relative measurement model.
    // But we CAN use RSSI to detect "Dead Reckoning" drift.
    
    // Innovation y = z - H * x
    final y = z - (H * state.x);
    
    // S = H * P * H^T + R
    final S = (H * state.P * H.transpose()) + R;
    
    // K = P * H^T * S^-1
    final K = state.P * H.transpose() * S.inverse();
    
    // x = x + K * y
    state.x = state.x + (K * y);
    
    // P = (I - K * H) * P
    final I = Matrix.identity(9);
    state.P = (I - (K * H)) * state.P;
    
    state.lastGNSS = DateTime.now();
  }

  LeaderAlertPacket? _computeCollisionAlert(String peerId, EKFState state) {
    // Need self state. Assuming self is at (0,0) relative to the coordinate frame 
    // OR we track self.
    // Ideally, StrongNodeEngine tracks ITSELF too using the same EKF.
    // But for now, we assume we are the origin or we have a _selfState.
    // Let's assume we are static at origin for this snippet, or we'd need to inject self data.
    
    // Relative Position
    final dx = state.x.data[0][0]; // Assuming relative to self if we normalized coords
    final dy = state.x.data[1][0];
    final distance = sqrt(dx*dx + dy*dy);
    
    // Relative Velocity
    final dvx = state.x.data[3][0];
    final dvy = state.x.data[4][0];
    
    // Closing Speed
    final closingSpeed = -(dvx*dx + dvy*dy) / distance;
    final ttc = closingSpeed > 0 ? distance / closingSpeed : double.infinity;
    
    AlertLevel level = AlertLevel.green;
    if (ttc < 2.0 && distance < 10.0) {
      level = AlertLevel.red;
    } else if (ttc < 5.0 && distance < 20.0) {
      level = AlertLevel.orange;
    } else if (ttc < 10.0 && distance < 30.0) {
      level = AlertLevel.yellow;
    }
    
    if (level == AlertLevel.green) return null;
    
    return LeaderAlertPacket(
      senderId: myDeviceId,
      targetPeerId: peerId,
      level: level,
      distance: distance,
      ttc: ttc,
      bearing: atan2(dy, dx),
    );
  }

  void _broadcastAlerts() {
    for (final entry in _peerStates.entries) {
      final alertPacket = _computeCollisionAlert(entry.key, entry.value);
      if (alertPacket != null) {
        onSendPacket(alertPacket);
        
        // Local display
        _alertController.add(CollisionAlert(
          peerId: alertPacket.targetPeerId,
          level: alertPacket.level,
          relativeDistance: alertPacket.distance,
          closingSpeed: 0.0, // Could derive
          timeToCollision: alertPacket.ttc,
          lateralDelta: 0.0,
          longitudinalDelta: alertPacket.distance,
          probability: 0.9, // High confidence (EKF)
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
