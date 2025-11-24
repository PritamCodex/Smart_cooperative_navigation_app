import 'dart:math' as math;

class SensorData {
  final DateTime timestamp;
  final double accelerometerX;
  final double accelerometerY;
  final double accelerometerZ;
  final double gyroscopeX;
  final double gyroscopeY;
  final double gyroscopeZ;
  final double magnetometerX;
  final double magnetometerY;
  final double magnetometerZ;
  final double? heading;
  
  // Location data
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? speed;
  final double? accuracy;

  SensorData({
    required this.timestamp,
    required this.accelerometerX,
    required this.accelerometerY,
    required this.accelerometerZ,
    required this.gyroscopeX,
    required this.gyroscopeY,
    required this.gyroscopeZ,
    required this.magnetometerX,
    required this.magnetometerY,
    required this.magnetometerZ,
    this.heading,
    this.latitude,
    this.longitude,
    this.altitude,
    this.speed,
    this.accuracy,
  });

  double get totalAcceleration => 
      math.sqrt(accelerometerX * accelerometerX + accelerometerY * accelerometerY + accelerometerZ * accelerometerZ);

  double get totalGyroscope => 
      math.sqrt(gyroscopeX * gyroscopeX + gyroscopeY * gyroscopeY + gyroscopeZ * gyroscopeZ);

  bool detectSuddenDeceleration({double threshold = 15.0}) {
    return totalAcceleration > threshold;
  }

  bool detectAbnormalIMUSpike({double threshold = 20.0}) {
    return totalGyroscope > threshold || totalAcceleration > threshold;
  }

  SensorData copyWith({
    DateTime? timestamp,
    double? accelerometerX,
    double? accelerometerY,
    double? accelerometerZ,
    double? gyroscopeX,
    double? gyroscopeY,
    double? gyroscopeZ,
    double? magnetometerX,
    double? magnetometerY,
    double? magnetometerZ,
    double? heading,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    double? accuracy,
  }) {
    return SensorData(
      timestamp: timestamp ?? this.timestamp,
      accelerometerX: accelerometerX ?? this.accelerometerX,
      accelerometerY: accelerometerY ?? this.accelerometerY,
      accelerometerZ: accelerometerZ ?? this.accelerometerZ,
      gyroscopeX: gyroscopeX ?? this.gyroscopeX,
      gyroscopeY: gyroscopeY ?? this.gyroscopeY,
      gyroscopeZ: gyroscopeZ ?? this.gyroscopeZ,
      magnetometerX: magnetometerX ?? this.magnetometerX,
      magnetometerY: magnetometerY ?? this.magnetometerY,
      magnetometerZ: magnetometerZ ?? this.magnetometerZ,
      heading: heading ?? this.heading,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
    );
  }
}