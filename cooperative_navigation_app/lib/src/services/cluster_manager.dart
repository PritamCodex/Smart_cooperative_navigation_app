import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/core/models/cluster_packet.dart';
import 'package:cooperative_navigation_safety/src/services/capability_service.dart';
import 'package:cooperative_navigation_safety/src/services/nearby_service.dart';

final clusterManagerProvider = Provider<ClusterManager>((ref) {
  return ClusterManager(ref);
});

enum ClusterRole {
  SOLO,     // No peers
  LEADER,   // I am the Strong Node
  FOLLOWER, // I am a Weak Node (or a Strong Node following a stronger one)
  REDUCED   // No Leader available (fallback)
}

class ClusterManager {
  final Ref _ref;
  ClusterRole _role = ClusterRole.SOLO;
  String? _currentLeaderId;
  
  // Peer Capabilities
  final Map<String, CapabilityPacket> _peerCapabilities = {};
  
  // My Capability
  late CapabilityPacket _myCapability;
  
  ClusterRole get role => _role;
  String? get currentLeaderId => _currentLeaderId;
  
  ClusterManager(this._ref);
  
  Future<void> initialize() async {
    final capabilityService = _ref.read(capabilityServiceProvider);
    final nearbyService = _ref.read(nearbyServiceProvider);
    
    await capabilityService.assessCapability();
    
    _myCapability = CapabilityPacket(
      deviceId: nearbyService.deviceId,
      score: capabilityService.score,
      isStrongNode: capabilityService.isStrongNode,
      osVersion: 0, // TODO: Pass real version
    );
    
    // Listen to connection changes to reset state
    // Listen to packet stream to handle CAPABILITY packets
  }
  
  void handlePacket(ClusterPacket packet) {
    if (packet is CapabilityPacket) {
      _peerCapabilities[packet.deviceId] = packet;
      _runLeaderElection();
    }
  }
  
  void onPeerDisconnected(String deviceId) {
    _peerCapabilities.remove(deviceId);
    if (_currentLeaderId == deviceId) {
      print('Leader lost! Re-electing...');
      _currentLeaderId = null;
      _runLeaderElection();
    }
  }
  
  void _runLeaderElection() {
    // 1. Gather all candidates (myself + peers)
    final candidates = [
      _myCapability,
      ..._peerCapabilities.values
    ];
    
    // 2. Filter for Strong Nodes only
    final strongCandidates = candidates.where((c) => c.isStrongNode).toList();
    
    if (strongCandidates.isEmpty) {
      // No strong nodes -> Reduced Mode
      _role = ClusterRole.REDUCED;
      _currentLeaderId = null;
      print('Cluster State: REDUCED (No Strong Nodes)');
      return;
    }
    
    // 3. Sort by Score (Desc), then DeviceID (Asc)
    strongCandidates.sort((a, b) {
      if (a.score != b.score) {
        return b.score.compareTo(a.score); // Higher score first
      }
      return a.deviceId.compareTo(b.deviceId); // Lower ID first (tie-breaker)
    });
    
    final winner = strongCandidates.first;
    _currentLeaderId = winner.deviceId;
    
    // 4. Assign Role
    if (winner.deviceId == _myCapability.deviceId) {
      _role = ClusterRole.LEADER;
      print('Cluster State: LEADER (I am the Strongest)');
    } else {
      _role = ClusterRole.FOLLOWER;
      print('Cluster State: FOLLOWER (Leader is ${winner.deviceId})');
    }
  }
  
  CapabilityPacket get myCapability => _myCapability;
}
