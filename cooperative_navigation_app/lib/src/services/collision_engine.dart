import 'dart:math' as math;
import 'package:cooperative_navigation_safety/src/core/models/beacon_packet.dart';
import 'fusion/distributed_fusion_engine.dart';
import 'package:cooperative_navigation_safety/src/core/models/collision_alert.dart';

class CollisionEngine {
  final DistributedFusionEngine? _fusionEngine;
  
  CollisionEngine([this._fusionEngine]);

  List<CollisionAlert> processMultiplePeers(BeaconPacket self, List<BeaconPacket> peers) {
    final alerts = <CollisionAlert>[];
    final now = DateTime.now();
    
    for (final peer in peers) {
      // 1. Filter stale data (older than 5 seconds)
      if (now.difference(peer.timestamp).inSeconds > 5) continue;
      
      // 2. Calculate accurate distance (Haversine)
      final distance = _calculateHaversineDistance(
        self.latitude, self.longitude,
        peer.latitude, peer.longitude
      );
      
      // 3. Calculate relative speed
      final relativeSpeed = (self.speed - peer.speed).abs();
      
      // 4. Calculate Time To Collision (TTC)
      // Improved Closing Speed Estimate:
      // If distance < 15m, assume closing speed is at least 1.0 m/s to trigger alert
      double closingSpeed = relativeSpeed;
      if (distance < 15 && closingSpeed < 0.5) closingSpeed = 1.0; 
      
      double ttc = 999.0;
      if (closingSpeed > 0.1) {
        ttc = distance / closingSpeed;
      }
      
      // 5. Determine Alert Level
      AlertLevel level = AlertLevel.green;
      
      if (distance < 5.0) {
        // CRITICAL: Extremely close (< 5m)
        level = AlertLevel.red;
      } else if (distance < 15.0) {
        // WARNING: Very close (< 15m)
        level = AlertLevel.orange;
      } else if (distance < 30.0 && ttc < 5.0) {
        // WARNING: Close and closing fast
        level = AlertLevel.orange;
      } else if (distance < 50.0 && ttc < 10.0) {
        // CAUTION: Approaching
        level = AlertLevel.yellow;
      }
      
      // Always add alert if within 50m so it shows on radar
      if (distance < 50.0) {
        alerts.add(CollisionAlert(
          peerId: peer.ephemeralId,
          level: level,
          relativeDistance: distance,
          closingSpeed: closingSpeed,
          timeToCollision: ttc,
          lateralDelta: 0.0, // Not used in simple logic
          longitudinalDelta: 0.0, // Not used in simple logic
          probability: level == AlertLevel.red ? 0.9 : (level == AlertLevel.orange ? 0.7 : 0.3),
          timestamp: now,
        ));
      }
    }
    
    // Sort by severity (Critical first, then closest)
    alerts.sort((a, b) {
      if (a.level != b.level) {
        return b.level.index.compareTo(a.level.index); // Higher index = more severe
      }
      return a.relativeDistance.compareTo(b.relativeDistance);
    });
    
    return alerts;
  }

  // Haversine Formula for accurate distance in meters
  double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
              
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
  
  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }
}