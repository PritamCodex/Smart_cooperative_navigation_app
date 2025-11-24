import 'package:flutter/material.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';

enum AlertLevel {
  green,
  yellow,
  orange,
  red;

  Color get color {
    switch (this) {
      case AlertLevel.green:
        return AppTheme.safeGreen;
      case AlertLevel.yellow:
        return AppTheme.alertYellow;
      case AlertLevel.orange:
        return AppTheme.alertOrange;
      case AlertLevel.red:
        return AppTheme.alertRed;
    }
  }

  String get label {
    switch (this) {
      case AlertLevel.green:
        return 'Safe';
      case AlertLevel.yellow:
        return 'Caution';
      case AlertLevel.orange:
        return 'Warning';
      case AlertLevel.red:
        return 'Emergency';
    }
  }

  bool get isCritical => this == AlertLevel.red || this == AlertLevel.orange;
}

class CollisionAlert {
  final String peerId;
  final AlertLevel level;
  final double relativeDistance;
  final double closingSpeed;
  final double timeToCollision;
  final double lateralDelta;
  final double longitudinalDelta;
  final double probability;
  final DateTime timestamp;

  CollisionAlert({
    required this.peerId,
    required this.level,
    required this.relativeDistance,
    required this.closingSpeed,
    required this.timeToCollision,
    required this.lateralDelta,
    required this.longitudinalDelta,
    required this.probability,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isActive => level != AlertLevel.green;

  bool get shouldTriggerAlert => level.isCritical;

  String get description {
    if (timeToCollision < 0) {
      return 'No collision risk';
    }
    
    final ttcText = timeToCollision < 60 
        ? '${timeToCollision.toStringAsFixed(1)}s'
        : '${(timeToCollision / 60).toStringAsFixed(1)}min';
        
    return 'TTC: $ttcText | Distance: ${relativeDistance.toStringAsFixed(1)}m';
  }

  CollisionAlert copyWith({
    String? peerId,
    AlertLevel? level,
    double? relativeDistance,
    double? closingSpeed,
    double? timeToCollision,
    double? lateralDelta,
    double? longitudinalDelta,
    double? probability,
    DateTime? timestamp,
  }) {
    return CollisionAlert(
      peerId: peerId ?? this.peerId,
      level: level ?? this.level,
      relativeDistance: relativeDistance ?? this.relativeDistance,
      closingSpeed: closingSpeed ?? this.closingSpeed,
      timeToCollision: timeToCollision ?? this.timeToCollision,
      lateralDelta: lateralDelta ?? this.lateralDelta,
      longitudinalDelta: longitudinalDelta ?? this.longitudinalDelta,
      probability: probability ?? this.probability,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}