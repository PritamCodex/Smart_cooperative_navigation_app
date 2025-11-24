import 'dart:async';
import 'dart:math' as math;
import 'package:cooperative_navigation_safety/src/core/models/cluster_packet.dart';
import 'package:cooperative_navigation_safety/src/core/models/collision_alert.dart';

class CentralizedFusionEngine {
  // State for each device in the cluster
  final Map<String, DeviceState> _deviceStates = {};
  
  // Configuration
  static const double _alertDistance = 10.0;
  static const double _warningDistance = 5.0;
  
  void updateSensorData(SensorPacket packet) {
    // 1. Get or create state for device
    if (!_deviceStates.containsKey(packet.deviceId)) {
      _deviceStates[packet.deviceId] = DeviceState(packet.deviceId);
    }
    
    final state = _deviceStates[packet.deviceId]!;
    
    // 2. Update State (Simple EKF or Direct Update for now)
    // In a full implementation, this would run the EKF predict/update cycle
    state.latitude = packet.latitude;
    state.longitude = packet.longitude;
    state.heading = packet.heading;
    state.speed = packet.speed;
    state.accuracy = packet.accuracy;
    state.lastUpdate = packet.timestamp;
  }
  
  LeaderAlertPacket computeGlobalAlerts(String leaderId) {
    final List<PeerAlertInfo> peerAlerts = [];
    String globalState = "SAFE";
    
    final leaderState = _deviceStates[leaderId];
    if (leaderState == null) return LeaderAlertPacket(
      deviceId: leaderId, 
      globalState: "SAFE", 
      peers: []
    );
    
    // Compare Leader vs All Peers
    _deviceStates.forEach((deviceId, peerState) {
      if (deviceId == leaderId) return;
      
      // Calculate Distance
      final dist = _calculateDistance(
        leaderState.latitude, leaderState.longitude,
        peerState.latitude, peerState.longitude
      );
      
      // Determine Alert Level
      String level = "GREEN";
      if (dist < _warningDistance) {
        level = "RED";
        globalState = "DANGER";
      } else if (dist < _alertDistance) {
        level = "YELLOW";
        if (globalState != "DANGER") globalState = "WARNING";
      }
      
      // Calculate Azimuth
      final azimuth = _calculateBearing(
        leaderState.latitude, leaderState.longitude,
        peerState.latitude, peerState.longitude
      );
      
      peerAlerts.add(PeerAlertInfo(
        deviceId: deviceId,
        relativeDistance: dist,
        alertLevel: level,
        azimuth: azimuth,
      ));
    });
    
    // Also compute Peer vs Peer collisions (for their benefit)
    // In this simplified version, we only broadcast Leader-centric alerts 
    // or alerts relevant to the specific node. 
    // The LeaderAlertPacket structure I defined sends a list of peers *relative to the receiver*?
    // No, the current definition sends a list of peers. 
    // Ideally, the Leader should send a specific packet to EACH weak node, 
    // OR broadcast a "World State" that everyone parses.
    // For bandwidth efficiency, broadcasting "World State" is better.
    
    return LeaderAlertPacket(
      deviceId: leaderId,
      globalState: globalState,
      peers: peerAlerts,
    );
  }
  
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2 * math.pi / 180);
    final x = math.cos(lat1 * math.pi / 180) * math.sin(lat2 * math.pi / 180) -
        math.sin(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (brng * 180 / math.pi + 360) % 360;
  }
}

class DeviceState {
  final String deviceId;
  double latitude = 0;
  double longitude = 0;
  double heading = 0;
  double speed = 0;
  double accuracy = 0;
  DateTime lastUpdate;
  
  DeviceState(this.deviceId) : lastUpdate = DateTime.now();
}
