import 'package:uuid/uuid.dart';

class BeaconPacket {
  final String id;
  final String type;
  final String ephemeralId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double heading;
  final double velocityX;
  final double velocityY;
  final double accuracy;
  final int battery;
  final String mode;
  final double? rssi;

  BeaconPacket({
    required this.type,
    required this.ephemeralId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.velocityX,
    required this.velocityY,
    required this.accuracy,
    required this.battery,
    required this.mode,
    this.rssi,
  }) : id = const Uuid().v4();

  factory BeaconPacket.fromJson(Map<String, dynamic> json) {
    return BeaconPacket(
      type: json['type'] ?? 'beacon',
      ephemeralId: json['id'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] ?? 0),
      latitude: json['lat']?.toDouble() ?? 0.0,
      longitude: json['lon']?.toDouble() ?? 0.0,
      altitude: json['alt']?.toDouble() ?? 0.0,
      speed: json['speed']?.toDouble() ?? 0.0,
      heading: json['heading']?.toDouble() ?? 0.0,
      velocityX: json['vx']?.toDouble() ?? 0.0,
      velocityY: json['vy']?.toDouble() ?? 0.0,
      accuracy: json['accuracy']?.toDouble() ?? 0.0,
      battery: json['battery'] ?? 0,
      mode: json['mode'] ?? 'normal',
      rssi: json['rssi']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': ephemeralId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'lat': latitude,
      'lon': longitude,
      'alt': altitude,
      'speed': speed,
      'heading': heading,
      'vx': velocityX,
      'vy': velocityY,
      'accuracy': accuracy,
      'battery': battery,
      'mode': mode,
      if (rssi != null) 'rssi': rssi,
    };
  }

  BeaconPacket copyWith({
    String? type,
    String? ephemeralId,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    double? heading,
    double? velocityX,
    double? velocityY,
    double? accuracy,
    int? battery,
    String? mode,
    double? rssi,
  }) {
    return BeaconPacket(
      type: type ?? this.type,
      ephemeralId: ephemeralId ?? this.ephemeralId,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      velocityX: velocityX ?? this.velocityX,
      velocityY: velocityY ?? this.velocityY,
      accuracy: accuracy ?? this.accuracy,
      battery: battery ?? this.battery,
      mode: mode ?? this.mode,
      rssi: rssi ?? this.rssi,
    );
  }
}