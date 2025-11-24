import 'dart:convert';

enum PacketType {
  CAPABILITY,
  SENSOR,
  LEADER_ALERT,
  HEARTBEAT,
  ELECTION
}

abstract class ClusterPacket {
  final int version;
  final PacketType type;
  final String deviceId;
  final DateTime timestamp;

  ClusterPacket({
    this.version = 2, // Protocol version
    required this.type,
    required this.deviceId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson();

  static ClusterPacket fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = PacketType.values.firstWhere((e) => e.toString().split('.').last == typeStr);

    switch (type) {
      case PacketType.CAPABILITY:
        return CapabilityPacket.fromJson(json);
      case PacketType.SENSOR:
        return SensorPacket.fromJson(json);
      case PacketType.LEADER_ALERT:
        return LeaderAlertPacket.fromJson(json);
      case PacketType.HEARTBEAT:
        return HeartbeatPacket.fromJson(json);
      case PacketType.ELECTION:
        return ElectionPacket.fromJson(json);
      default:
        throw UnimplementedError('Packet type $typeStr not implemented');
    }
  }
}

class CapabilityPacket extends ClusterPacket {
  final int score;
  final bool isStrongNode;
  final String currentRole; // LEADER_CANDIDATE, FOLLOWER, etc.
  final CapabilityDetail capability;

  CapabilityPacket({
    int version = 2,
    required String deviceId,
    required this.score,
    required this.isStrongNode,
    required this.currentRole,
    required this.capability,
  }) : super(
          version: version,
          type: PacketType.CAPABILITY,
          deviceId: deviceId,
          timestamp: DateTime.now(),
        );

  @override
  Map<String, dynamic> toJson() => {
        'version': version,
        'type': 'CAPABILITY',
        'deviceId': deviceId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'capability': capability.toJson(),
        'isStrongNode': isStrongNode,
        'currentRole': currentRole,
      };

  factory CapabilityPacket.fromJson(Map<String, dynamic> json) {
    return CapabilityPacket(
      version: json['version'] ?? 2,
      deviceId: json['deviceId'],
      score: json['capability']['capabilityScore'],
      isStrongNode: json['isStrongNode'],
      currentRole: json['currentRole'],
      capability: CapabilityDetail.fromJson(json['capability']),
    );
  }
}

class CapabilityDetail {
  final int osVersion;
  final String gnssCapability; // DUAL_BAND_L1L5, SINGLE_BAND
  final double avgGnssAccuracy;
  final String cpuTier; // HIGH, MID, LOW
  final int batteryLevel; // 0-100
  final bool isThermalThrottling;
  final bool isBlacklisted;
  final int capabilityScore;

  CapabilityDetail({
    required this.osVersion,
    required this.gnssCapability,
    required this.avgGnssAccuracy,
    required this.cpuTier,
    required this.batteryLevel,
    required this.isThermalThrottling,
    required this.isBlacklisted,
    required this.capabilityScore,
  });

  Map<String, dynamic> toJson() => {
        'osVersion': osVersion,
        'gnssCapability': gnssCapability,
        'avgGnssAccuracy': avgGnssAccuracy,
        'cpuTier': cpuTier,
        'batteryLevel': batteryLevel,
        'isThermalThrottling': isThermalThrottling,
        'isBlacklisted': isBlacklisted,
        'capabilityScore': capabilityScore,
      };

  factory CapabilityDetail.fromJson(Map<String, dynamic> json) {
    return CapabilityDetail(
      osVersion: json['osVersion'],
      gnssCapability: json['gnssCapability'],
      avgGnssAccuracy: (json['avgGnssAccuracy'] as num).toDouble(),
      cpuTier: json['cpuTier'],
      batteryLevel: json['batteryLevel'],
      isThermalThrottling: json['isThermalThrottling'],
      isBlacklisted: json['isBlacklisted'],
      capabilityScore: json['capabilityScore'],
    );
  }
}

class SensorPacket extends ClusterPacket {
  final GnssData gnss;
  final ImuData imu;
  final double? rssi;
  final int battery;
  final bool isStationary;

  SensorPacket({
    int version = 2,
    required String deviceId,
    required this.gnss,
    required this.imu,
    this.rssi,
    required this.battery,
    this.isStationary = false,
  }) : super(
          version: version,
          type: PacketType.SENSOR,
          deviceId: deviceId,
          timestamp: DateTime.now(),
        );

  @override
  Map<String, dynamic> toJson() => {
        'version': version,
        'type': 'SENSOR',
        'deviceId': deviceId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'gnss': gnss.toJson(),
        'imu': imu.toJson(),
        'rssi': rssi,
        'battery': battery,
        'isStationary': isStationary,
      };

  factory SensorPacket.fromJson(Map<String, dynamic> json) {
    return SensorPacket(
      version: json['version'] ?? 2,
      deviceId: json['deviceId'],
      gnss: GnssData.fromJson(json['gnss']),
      imu: ImuData.fromJson(json['imu']),
      rssi: json['rssi'] != null ? (json['rssi'] as num).toDouble() : null,
      battery: json['battery'],
      isStationary: json['isStationary'] ?? false,
    );
  }
}

class GnssData {
  final double lat;
  final double lon;
  final double altitude;
  final double accuracy;
  final double speed;
  final double speedAccuracy;
  final double bearing;
  final double bearingAccuracy;
  final int gnssTimestamp; // GNSS system time in milliseconds

  GnssData({
    required this.lat,
    required this.lon,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    required this.speedAccuracy,
    required this.bearing,
    required this.bearingAccuracy,
    required this.gnssTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'altitude': altitude,
        'accuracy': accuracy,
        'speed': speed,
        'speedAccuracy': speedAccuracy,
        'bearing': bearing,
        'bearingAccuracy': bearingAccuracy,
        'gnssTimestamp': gnssTimestamp,
      };

  factory GnssData.fromJson(Map<String, dynamic> json) {
    return GnssData(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      altitude: (json['altitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      speedAccuracy: (json['speedAccuracy'] as num).toDouble(),
      bearing: (json['bearing'] as num).toDouble(),
      bearingAccuracy: (json['bearingAccuracy'] as num).toDouble(),
      gnssTimestamp: json['gnssTimestamp'],
    );
  }
}

class ImuData {
  final List<double> accel; // [x, y, z] in m/s²
  final List<double> gyro; // [x, y, z] in rad/s
  final List<double> mag; // [x, y, z] in µT
  final int imuTimestamp; // IMU capture time in milliseconds

  ImuData({
    required this.accel,
    required this.gyro,
    required this.mag,
    required this.imuTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'accel': accel,
        'gyro': gyro,
        'mag': mag,
        'imuTimestamp': imuTimestamp,
      };

  factory ImuData.fromJson(Map<String, dynamic> json) {
    return ImuData(
      accel: (json['accel'] as List).map((e) => (e as num).toDouble()).toList(),
      gyro: (json['gyro'] as List).map((e) => (e as num).toDouble()).toList(),
      mag: (json['mag'] as List).map((e) => (e as num).toDouble()).toList(),
      imuTimestamp: json['imuTimestamp'],
    );
  }
}

class LeaderAlertPacket extends ClusterPacket {
  final String leaderId;
  final String globalAlertState; // SAFE, CAUTION, WARNING, DANGER
  final List<PeerAlertInfo> peers;
  final OwnPositionData ownPosition;

  LeaderAlertPacket({
    int version = 2,
    required this.leaderId,
    required this.globalAlertState,
    required this.peers,
    required this.ownPosition,
  }) : super(
          version: version,
          type: PacketType.LEADER_ALERT,
          deviceId: leaderId,
          timestamp: DateTime.now(),
        );

  @override
  Map<String, dynamic> toJson() => {
        'version': version,
        'type': 'ALERT',
        'leaderId': leaderId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'globalAlertState': globalAlertState,
        'peers': peers.map((p) => p.toJson()).toList(),
        'ownPosition': ownPosition.toJson(),
      };

  factory LeaderAlertPacket.fromJson(Map<String, dynamic> json) {
    return LeaderAlertPacket(
      version: json['version'] ?? 2,
      leaderId: json['leaderId'],
      globalAlertState: json['globalAlertState'],
      peers: (json['peers'] as List).map((e) => PeerAlertInfo.fromJson(e)).toList(),
      ownPosition: OwnPositionData.fromJson(json['ownPosition']),
    );
  }
}

class OwnPositionData {
  final double lat;
  final double lon;
  final double accuracy;

  OwnPositionData({
    required this.lat,
    required this.lon,
    required this.accuracy,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'accuracy': accuracy,
      };

  factory OwnPositionData.fromJson(Map<String, dynamic> json) {
    return OwnPositionData(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
    );
  }
}

class PeerAlertInfo {
  final String deviceId;
  final double relativeDistance;
  final double relativeBearing;
  final double relativeSpeed;
  final double? ttc; // Time to collision in seconds
  final String alertLevel; // GREEN, YELLOW, ORANGE, RED
  final bool isLowConfidence;

  PeerAlertInfo({
    required this.deviceId,
    required this.relativeDistance,
    required this.relativeBearing,
    required this.relativeSpeed,
    this.ttc,
    required this.alertLevel,
    this.isLowConfidence = false,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'relativeDistance': relativeDistance,
        'relativeBearing': relativeBearing,
        'relativeSpeed': relativeSpeed,
        'ttc': ttc,
        'alertLevel': alertLevel,
        'isLowConfidence': isLowConfidence,
      };

  factory PeerAlertInfo.fromJson(Map<String, dynamic> json) {
    return PeerAlertInfo(
      deviceId: json['deviceId'],
      relativeDistance: (json['relativeDistance'] as num).toDouble(),
      relativeBearing: (json['relativeBearing'] as num).toDouble(),
      relativeSpeed: (json['relativeSpeed'] as num).toDouble(),
      ttc: json['ttc'] != null ? (json['ttc'] as num).toDouble() : null,
      alertLevel: json['alertLevel'],
      isLowConfidence: json['isLowConfidence'] ?? false,
    );
  }
}

// Heartbeat packet sent by leader every 500ms
class HeartbeatPacket extends ClusterPacket {
  final String leaderId;
  final int electionTerm;
  final int clusterSize;

  HeartbeatPacket({
    int version = 2,
    required this.leaderId,
    required this.electionTerm,
    required this.clusterSize,
  }) : super(
          version: version,
          type: PacketType.HEARTBEAT,
          deviceId: leaderId,
          timestamp: DateTime.now(),
        );

  @override
  Map<String, dynamic> toJson() => {
        'version': version,
        'type': 'HEARTBEAT',
        'leaderId': leaderId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'electionTerm': electionTerm,
        'clusterSize': clusterSize,
      };

  factory HeartbeatPacket.fromJson(Map<String, dynamic> json) {
    return HeartbeatPacket(
      version: json['version'] ?? 2,
      leaderId: json['leaderId'],
      electionTerm: json['electionTerm'],
      clusterSize: json['clusterSize'],
    );
  }
}

// Election packet for leader election process
class ElectionPacket extends ClusterPacket {
  final int capabilityScore;
  final int electionTerm;
  final String electionState; // CANDIDATE, CHALLENGE, etc.

  ElectionPacket({
    int version = 2,
    required String deviceId,
    required this.capabilityScore,
    required this.electionTerm,
    required this.electionState,
  }) : super(
          version: version,
          type: PacketType.ELECTION,
          deviceId: deviceId,
          timestamp: DateTime.now(),
        );

  @override
  Map<String, dynamic> toJson() => {
        'version': version,
        'type': 'ELECTION',
        'deviceId': deviceId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'capabilityScore': capabilityScore,
        'electionTerm': electionTerm,
        'electionState': electionState,
      };

  factory ElectionPacket.fromJson(Map<String, dynamic> json) {
    return ElectionPacket(
      version: json['version'] ?? 2,
      deviceId: json['deviceId'],
      capabilityScore: json['capabilityScore'],
      electionTerm: json['electionTerm'],
      electionState: json['electionState'],
    );
  }
}
