// ignore_for_file: constant_identifier_names

/// PAYLOAD SIZE OPTIMIZATION NOTES:
/// ================================
/// 1. Encoding: JSON chosen over CBOR for debugging/human readability trade-off
///    - JSON: ~150-200 bytes per RawSensorPacket
///    - CBOR alternative would save ~30-40% (100-140 bytes)
/// 2. Key Abbreviations: 'sid'='senderId', 'ts'='timestamp', etc. save ~40 bytes/packet
/// 3. RawSensorPacket is the most frequent (10-20 Hz from Weak nodes)
///    - At 20 Hz: ~3-4 KB/s per node
///    - 10 nodes: ~30-40 KB/s total bandwidth
/// 4. Future optimizations if bandwidth constrained:
///    - Switch to CBOR or Protocol Buffers
///    - Use fixed-point encoding for lat/lon (8 bytes total vs 16)
///    - Delta encoding for sequential sensor readings
///    - Compress IMU streams (only send when change > threshold)
/// 5. Heartbeat/Election packets are infrequent (1 Hz): ~50 bytes, negligible impact

import 'dart:convert';
import 'dart:typed_data';

import '../../core/models/collision_alert.dart';
import '../capability_engine.dart';

/// Types of packets exchanged between nodes.
enum PacketType {
  CAPABILITY,
  RAW_SENSOR,
  LEADER_ALERT,
  LEADER_ELECTION,
  HEARTBEAT,
  CLUSTER_MODE,
}

/// Phases of the leader election process.
enum ElectionPhase {
  ANNOUNCEMENT,
  VOTING,
  VICTORY,
}

/// Operating modes of the cluster.
enum ClusterMode {
  STRONG_LEADER,
  MID_LEADER,
  WEAK_DISTRIBUTED,
  INITIALIZING,
}

/// Base class for all network packets.
abstract class BasePacket {
  static const int CURRENT_VERSION = 1;

  final int version;
  final PacketType type;
  final String senderId;
  final DateTime timestamp;

  BasePacket({
    required this.type,
    required this.senderId,
    int? version,
    DateTime? timestamp,
  })  : version = version ?? CURRENT_VERSION,
        timestamp = timestamp ?? DateTime.now();

  /// Serializes the packet to a JSON map.
  Map<String, dynamic> toJson();

  /// Validates the packet structure and version.
  bool validate() {
    if (version > CURRENT_VERSION) return false; // Forward compatibility check
    if (senderId.isEmpty) return false;
    // Reject packets older than 5 seconds (replay protection / stale data)
    if (DateTime.now().difference(timestamp).abs() > const Duration(seconds: 5)) {
      return false;
    }
    return true;
  }
}

/// Packet containing device capability information.
/// Used for initial handshake and periodic capability updates.
class CapabilityPacket extends BasePacket {
  final NodeTier tier;
  final int score;
  final Map<String, int> breakdown;

  CapabilityPacket({
    required String senderId,
    required this.tier,
    required this.score,
    required this.breakdown,
    int? version,
    DateTime? timestamp,
  }) : super(
          type: PacketType.CAPABILITY,
          senderId: senderId,
          version: version,
          timestamp: timestamp,
        );

  factory CapabilityPacket.fromJson(Map<String, dynamic> json) {
    return CapabilityPacket(
      senderId: json['sid'] as String,
      tier: NodeTier.values[json['tier'] as int],
      score: json['scr'] as int,
      breakdown: Map<String, int>.from(json['brk'] as Map),
      version: json['ver'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'ver': version,
      'type': type.index,
      'sid': senderId,
      'ts': timestamp.millisecondsSinceEpoch,
      'tier': tier.index,
      'scr': score,
      'brk': breakdown,
    };
  }
}

/// Packet containing raw sensor data (GNSS, IMU).
/// Sent by Weak/Mid nodes to the Strong leader.
class RawSensorPacket extends BasePacket {
  final double lat;
  final double lon;
  final double heading;
  final double speed;
  final double accX;
  final double accY;
  final double accZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final int rssi;

  RawSensorPacket({
    required String senderId,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.speed,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.rssi,
    int? version,
    DateTime? timestamp,
  }) : super(
          type: PacketType.RAW_SENSOR,
          senderId: senderId,
          version: version,
          timestamp: timestamp,
        );

  factory RawSensorPacket.fromJson(Map<String, dynamic> json) {
    return RawSensorPacket(
      senderId: json['sid'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      heading: (json['hdg'] as num).toDouble(),
      speed: (json['spd'] as num).toDouble(),
      accX: (json['ax'] as num).toDouble(),
      accY: (json['ay'] as num).toDouble(),
      accZ: (json['az'] as num).toDouble(),
      gyroX: (json['gx'] as num).toDouble(),
      gyroY: (json['gy'] as num).toDouble(),
      gyroZ: (json['gz'] as num).toDouble(),
      rssi: json['rssi'] as int,
      version: json['ver'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'ver': version,
      'type': type.index,
      'sid': senderId,
      'ts': timestamp.millisecondsSinceEpoch,
      // Use shorter keys for sensor data to save bandwidth
      'lat': lat,
      'lon': lon,
      'hdg': heading,
      'spd': speed,
      'ax': accX,
      'ay': accY,
      'az': accZ,
      'gx': gyroX,
      'gy': gyroY,
      'gz': gyroZ,
      'rssi': rssi,
    };
  }
}

/// Packet containing a collision alert computed by the leader.
/// Sent from Leader to specific peers.
class LeaderAlertPacket extends BasePacket {
  final String targetPeerId;
  final AlertLevel level;
  final double distance;
  final double ttc; // Time To Collision
  final double bearing;

  LeaderAlertPacket({
    required String senderId,
    required this.targetPeerId,
    required this.level,
    required this.distance,
    required this.ttc,
    required this.bearing,
    int? version,
    DateTime? timestamp,
  }) : super(
          type: PacketType.LEADER_ALERT,
          senderId: senderId,
          version: version,
          timestamp: timestamp,
        );

  factory LeaderAlertPacket.fromJson(Map<String, dynamic> json) {
    return LeaderAlertPacket(
      senderId: json['sid'] as String,
      targetPeerId: json['tid'] as String,
      level: AlertLevel.values[json['lvl'] as int],
      distance: (json['dst'] as num).toDouble(),
      ttc: (json['ttc'] as num).toDouble(),
      bearing: (json['brg'] as num).toDouble(),
      version: json['ver'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'ver': version,
      'type': type.index,
      'sid': senderId,
      'ts': timestamp.millisecondsSinceEpoch,
      'tid': targetPeerId,
      'lvl': level.index,
      'dst': distance,
      'ttc': ttc,
      'brg': bearing,
    };
  }
}

/// Packet used during the leader election process.
class LeaderElectionPacket extends BasePacket {
  final NodeTier candidateTier;
  final int score;
  final String candidateId;
  final ElectionPhase phase;

  LeaderElectionPacket({
    required String senderId,
    required this.candidateTier,
    required this.score,
    required this.candidateId,
    required this.phase,
    int? version,
    DateTime? timestamp,
  }) : super(
          type: PacketType.LEADER_ELECTION,
          senderId: senderId,
          version: version,
          timestamp: timestamp,
        );

  factory LeaderElectionPacket.fromJson(Map<String, dynamic> json) {
    return LeaderElectionPacket(
      senderId: json['sid'] as String,
      candidateTier: NodeTier.values[json['tier'] as int],
      score: json['scr'] as int,
      candidateId: json['cid'] as String,
      phase: ElectionPhase.values[json['phs'] as int],
      version: json['ver'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'ver': version,
      'type': type.index,
      'sid': senderId,
      'ts': timestamp.millisecondsSinceEpoch,
      'tier': candidateTier.index,
      'scr': score,
      'cid': candidateId,
      'phs': phase.index,
    };
  }
}

/// Periodic heartbeat packet to maintain cluster stability.
class HeartbeatPacket extends BasePacket {
  final NodeTier currentTier;
  final bool isLeader;
  final int leaderScore;

  HeartbeatPacket({
    required String senderId,
    required this.currentTier,
    required this.isLeader,
    required this.leaderScore,
    int? version,
    DateTime? timestamp,
  }) : super(
          type: PacketType.HEARTBEAT,
          senderId: senderId,
          version: version,
          timestamp: timestamp,
        );

  factory HeartbeatPacket.fromJson(Map<String, dynamic> json) {
    return HeartbeatPacket(
      senderId: json['sid'] as String,
      currentTier: NodeTier.values[json['tier'] as int],
      isLeader: json['isl'] as bool,
      leaderScore: json['lsc'] as int,
      version: json['ver'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'ver': version,
      'type': type.index,
      'sid': senderId,
      'ts': timestamp.millisecondsSinceEpoch,
      'tier': currentTier.index,
      'isl': isLeader,
      'lsc': leaderScore,
    };
  }
}

/// Packet indicating a change in the cluster's operating mode.
class ClusterModePacket extends BasePacket {
  final ClusterMode mode;
  final String? leaderId;
  final int peerCount;

  ClusterModePacket({
    required String senderId,
    required this.mode,
    this.leaderId,
    required this.peerCount,
    int? version,
    DateTime? timestamp,
  }) : super(
          type: PacketType.CLUSTER_MODE,
          senderId: senderId,
          version: version,
          timestamp: timestamp,
        );

  factory ClusterModePacket.fromJson(Map<String, dynamic> json) {
    return ClusterModePacket(
      senderId: json['sid'] as String,
      mode: ClusterMode.values[json['mod'] as int],
      leaderId: json['lid'] as String?,
      peerCount: json['pc'] as int,
      version: json['ver'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'ver': version,
      'type': type.index,
      'sid': senderId,
      'ts': timestamp.millisecondsSinceEpoch,
      'mod': mode.index,
      'lid': leaderId,
      'pc': peerCount,
    };
  }
}

/// Utility class for encoding and decoding packets.
class PacketCodec {
  /// Encodes a packet to a UTF-8 JSON byte array.
  static Uint8List encode(BasePacket packet) {
    final jsonMap = packet.toJson();
    final jsonString = jsonEncode(jsonMap);
    return utf8.encode(jsonString);
  }

  /// Decodes a byte array into a specific packet type.
  /// Throws [FormatException] if the packet is invalid or unknown.
  static BasePacket decode(Uint8List bytes) {
    try {
      final jsonString = utf8.decode(bytes);
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      
      final typeIndex = jsonMap['type'] as int;
      if (typeIndex < 0 || typeIndex >= PacketType.values.length) {
        throw FormatException('Unknown packet type index: $typeIndex');
      }
      
      final type = PacketType.values[typeIndex];

      switch (type) {
        case PacketType.CAPABILITY:
          return CapabilityPacket.fromJson(jsonMap);
        case PacketType.RAW_SENSOR:
          return RawSensorPacket.fromJson(jsonMap);
        case PacketType.LEADER_ALERT:
          return LeaderAlertPacket.fromJson(jsonMap);
        case PacketType.LEADER_ELECTION:
          return LeaderElectionPacket.fromJson(jsonMap);
        case PacketType.HEARTBEAT:
          return HeartbeatPacket.fromJson(jsonMap);
        case PacketType.CLUSTER_MODE:
          return ClusterModePacket.fromJson(jsonMap);
      }
    } catch (e) {
      throw FormatException('Failed to decode packet: $e');
    }
  }

  /// Validates a packet's integrity.
  static bool validate(BasePacket packet) {
    return packet.validate();
  }
}
