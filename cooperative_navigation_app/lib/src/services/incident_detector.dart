import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';
import 'package:cooperative_navigation_safety/src/core/models/sensor_data.dart';
import 'package:cooperative_navigation_safety/src/core/models/beacon_packet.dart';

class IncidentDetector {
  static const double _suddenDecelerationThreshold = 15.0; // m/s²
  static const double _abnormalIMUThreshold = 20.0; // rad/s or m/s²
  static const double _tiltThreshold = 45.0; // degrees
  static const int _detectionWindowMs = 1000; // 1 second
  
  final StreamController<IncidentEvent> _incidentController = 
      StreamController<IncidentEvent>.broadcast();
  
  Stream<IncidentEvent> get incidentStream => _incidentController.stream;
  
  final List<SensorData> _sensorHistory = [];
  Timer? _cleanupTimer;
  
  void startDetection() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _cleanupOldData();
    });
  }
  
  void stopDetection() {
    _cleanupTimer?.cancel();
    _sensorHistory.clear();
    _incidentController.close();
  }
  
  void processSensorData(SensorData sensorData) {
    _sensorHistory.add(sensorData);
    
    // Check for various incident types
    _checkSuddenDeceleration(sensorData);
    _checkAbnormalIMU(sensorData);
    _checkVehicleTilt(sensorData);
    _checkRapidTurns(sensorData);
  }
  
  void triggerManualIncident(String type, String description) {
    final incident = IncidentEvent(
      type: type,
      timestamp: DateTime.now(),
      severity: _getSeverityFromType(type),
      description: description,
      sensorData: null,
    );
    
    _incidentController.add(incident);
  }
  
  void _checkSuddenDeceleration(SensorData sensorData) {
    if (sensorData.detectSuddenDeceleration(threshold: _suddenDecelerationThreshold)) {
      final incident = IncidentEvent(
        type: 'sudden_deceleration',
        timestamp: sensorData.timestamp,
        severity: IncidentSeverity.high,
        description: 'Sudden deceleration detected: ${sensorData.totalAcceleration.toStringAsFixed(2)} m/s²',
        sensorData: sensorData,
      );
      
      _incidentController.add(incident);
    }
  }
  
  void _checkAbnormalIMU(SensorData sensorData) {
    if (sensorData.detectAbnormalIMUSpike(threshold: _abnormalIMUThreshold)) {
      final incident = IncidentEvent(
        type: 'abnormal_imu',
        timestamp: sensorData.timestamp,
        severity: IncidentSeverity.medium,
        description: 'Abnormal IMU spike detected',
        sensorData: sensorData,
      );
      
      _incidentController.add(incident);
    }
  }
  
  void _checkVehicleTilt(SensorData sensorData) {
    final gravityVector = math.sqrt(
      sensorData.accelerometerX * sensorData.accelerometerX +
      sensorData.accelerometerY * sensorData.accelerometerY +
      sensorData.accelerometerZ * sensorData.accelerometerZ
    );
    
    if (gravityVector > 0) {
      // Calculate tilt angle from vertical
      final tiltAngle = math.acos(sensorData.accelerometerZ / gravityVector) * 180 / math.pi;
      
      if (tiltAngle > _tiltThreshold) {
        final incident = IncidentEvent(
          type: 'vehicle_tilt',
          timestamp: sensorData.timestamp,
          severity: IncidentSeverity.high,
          description: 'Excessive vehicle tilt: ${tiltAngle.toStringAsFixed(1)}°',
          sensorData: sensorData,
        );
        
        _incidentController.add(incident);
      }
    }
  }
  
  void _checkRapidTurns(SensorData sensorData) {
    // Analyze recent sensor data for rapid turn patterns
    final recentData = _getRecentSensorData(_detectionWindowMs);
    
    if (recentData.length >= 10) {
      final gyroscopeMagnitudes = recentData.map((d) => d.totalGyroscope).toList();
      final avgGyroscope = gyroscopeMagnitudes.reduce((a, b) => a + b) / gyroscopeMagnitudes.length;
      
      if (avgGyroscope > 5.0) { // Threshold for rapid turning
        final incident = IncidentEvent(
          type: 'rapid_turns',
          timestamp: sensorData.timestamp,
          severity: IncidentSeverity.medium,
          description: 'Rapid turning detected',
          sensorData: sensorData,
        );
        
        _incidentController.add(incident);
      }
    }
  }
  
  List<SensorData> _getRecentSensorData(int windowMs) {
    final now = DateTime.now();
    return _sensorHistory.where((data) {
      return now.difference(data.timestamp).inMilliseconds <= windowMs;
    }).toList();
  }
  
  void _cleanupOldData() {
    final now = DateTime.now();
    _sensorHistory.removeWhere((data) {
      return now.difference(data.timestamp).inSeconds > 30;
    });
  }
  
  IncidentSeverity _getSeverityFromType(String type) {
    switch (type) {
      case 'emergency_stop':
      case 'collision':
        return IncidentSeverity.critical;
      case 'sudden_deceleration':
      case 'vehicle_tilt':
        return IncidentSeverity.high;
      case 'abnormal_imu':
      case 'rapid_turns':
        return IncidentSeverity.medium;
      default:
        return IncidentSeverity.low;
    }
  }
  
  // Create emergency beacon for broadcast
  BeaconPacket createEmergencyBeacon(IncidentEvent incident, String deviceId) {
    return BeaconPacket(
      type: 'emergency',
      ephemeralId: deviceId,
      timestamp: incident.timestamp,
      latitude: 0.0, // Would be populated with actual GPS coordinates
      longitude: 0.0,
      altitude: 0.0,
      speed: 0.0,
      heading: 0.0,
      velocityX: 0.0,
      velocityY: 0.0,
      accuracy: 5.0,
      battery: 100,
      mode: 'emergency',
    );
  }
}

class IncidentEvent {
  final String type;
  final DateTime timestamp;
  final IncidentSeverity severity;
  final String description;
  final SensorData? sensorData;
  
  const IncidentEvent({
    required this.type,
    required this.timestamp,
    required this.severity,
    required this.description,
    this.sensorData,
  });
  
  bool get isCritical => severity == IncidentSeverity.critical;
  bool get isHighPriority => severity == IncidentSeverity.high;
}

enum IncidentSeverity {
  critical,
  high,
  medium,
  low;
  
  Color get color {
    switch (this) {
      case IncidentSeverity.critical:
        return AppTheme.alertRed;
      case IncidentSeverity.high:
        return AppTheme.alertOrange;
      case IncidentSeverity.medium:
        return AppTheme.alertYellow;
      case IncidentSeverity.low:
        return AppTheme.safeGreen;
    }
  }
}