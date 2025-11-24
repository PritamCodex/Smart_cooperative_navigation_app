import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/cluster_packet.dart';
import 'capability_detector.dart';
import 'leader_election_engine.dart';
import 'strong_node_controller.dart';
import 'weak_node_controller.dart';

final clusterOrchestratorProvider = Provider<ClusterOrchestrator>((ref) {
  return ClusterOrchestrator(ref);
});

/// Main orchestrator coordinating the entire strong/weak node system
class ClusterOrchestrator {
  final Ref _ref;
  
  // Core components
  late final CapabilityDetector _capabilityDetector;
  late final LeaderElectionEngine _electionEngine;
  StrongNodeController? _strongNodeController;
  WeakNodeController? _weakNodeController;
  
  // State
  String? _myDeviceId;
  CapabilityDetail? _myCapability;
  ElectionState _currentRole = ElectionState.DISCOVERING;
  
  // Stream subscriptions
  StreamSubscription? _electionStateSubscription;
  StreamSubscription? _electionEventsSubscription;
  StreamSubscription? _strongNodeAlertSubscription;
  StreamSubscription? _weakNodeSensorSubscription;
  StreamSubscription? _weakNodeUISubscription;
  
  // Stream controllers for app-wide events
  final _roleChangeController = StreamController<RoleChangeEvent>.broadcast();
  final _packetOutController = StreamController<ClusterPacket>.broadcast();
  
  Stream<RoleChangeEvent> get roleChangeStream => _roleChangeController.stream;
  Stream<ClusterPacket> get packetOutStream => _packetOutController.stream;
  
  ClusterOrchestrator(this._ref) {
    _capabilityDetector = _ref.read(capabilityDetectorProvider);
    _electionEngine = _ref.read(leaderElectionProvider);
  }
  
  /// Initialize the entire system
  Future<void> initialize(String myDeviceId) async {
    _myDeviceId = myDeviceId;
    print('[Orchestrator] Initializing for device $myDeviceId');
    
    // Step 1: Assess device capability
    _myCapability = await _capabilityDetector.assessCapability();
    print('[Orchestrator] Capability assessed: score=${_myCapability!.capabilityScore}');
    
    // Step 2: Initialize leader election
    _electionEngine.initialize(myDeviceId, _myCapability!.capabilityScore);
    
    // Step 3: Listen to election state changes
    _electionStateSubscription = _electionEngine.stateStream.listen(_onElectionStateChange);
    _electionEventsSubscription = _electionEngine.electionEventsStream.listen(_onElectionEvent);
    
    // Step 4: Broadcast capability packet
    _broadcastCapabilityPacket();
    
    print('[Orchestrator] Initialization complete');
  }
  
  /// Handle incoming packets from Nearby Service
  void handleIncomingPacket(ClusterPacket packet) {
    // Route packet to appropriate handler
    if (packet is CapabilityPacket) {
      _electionEngine.onCapabilityPacket(packet);
    } else if (packet is HeartbeatPacket) {
      _electionEngine.onHeartbeatPacket(packet);
    } else if (packet is ElectionPacket) {
      _electionEngine.onElectionPacket(packet);
    } else if (packet is SensorPacket) {
      _onSensorPacket(packet);
    } else if (packet is LeaderAlertPacket) {
      _onLeaderAlertPacket(packet);
    }
  }
  
  /// Handle peer disconnection
  void onPeerDisconnected(String deviceId) {
    _electionEngine.onPeerDisconnected(deviceId);
  }
  
  /// Update sensor data from SensorService
  void updateSensorData({
    GnssData? gnss,
    ImuData? imu,
    double? rssi,
    int? batteryLevel,
  }) {
    // Update appropriate controller based on role
    if (_currentRole == ElectionState.LEADER) {
      // Add own sensor data to strong node controller
      if (_strongNodeController != null && gnss != null && imu != null) {
        final packet = SensorPacket(
          deviceId: _myDeviceId!,
          gnss: gnss,
          imu: imu,
          rssi: rssi,
          battery: batteryLevel ?? 100,
          isStationary: (gnss.speed < 0.5),
        );
        _strongNodeController!.addSensorPacket(packet);
      }
    } else if (_currentRole == ElectionState.FOLLOWER) {
      // Update weak node controller
      _weakNodeController?.updateSensorData(
        gnss: gnss,
        imu: imu,
        rssi: rssi,
        batteryLevel: batteryLevel,
      );
    }
  }
  
  /// Handle election state change
  void _onElectionStateChange(ClusterState state) {
    final newRole = state.myRole;
    
    if (newRole != _currentRole) {
      print('[Orchestrator] Role transition: $_currentRole → $newRole');
      _currentRole = newRole;
      
      // Tear down old controller
      _tearDownControllers();
      
      // Setup new controller
      if (newRole == ElectionState.LEADER) {
        _becomeStrongNode();
      } else if (newRole == ElectionState.FOLLOWER) {
        _becomeWeakNode(state.currentLeader!);
      } else if (newRole == ElectionState.REDUCED_MODE) {
        _enterReducedMode();
      }
      
      // Notify app
      _roleChangeController.add(RoleChangeEvent(
        newRole: newRole,
        leaderId: state.currentLeader,
        term: state.currentTerm,
      ));
    }
  }
  
  /// Handle election events
  void _onElectionEvent(ElectionEvent event) {
    if (event.type == 'BROADCAST_ELECTION') {
      final packet = ElectionPacket(
        deviceId: _myDeviceId!,
        capabilityScore: _myCapability!.capabilityScore,
        electionTerm: event.data['term'],
        electionState: 'CANDIDATE',
      );
      _packetOutController.add(packet);
    } else if (event.type == 'SEND_HEARTBEAT') {
      final packet = HeartbeatPacket(
        leaderId: _myDeviceId!,
        electionTerm: event.data['term'],
        clusterSize: event.data['clusterSize'],
      );
      _packetOutController.add(packet);
    }
  }
  
  /// Handle incoming sensor packet (as leader)
  void _onSensorPacket(SensorPacket packet) {
    if (_currentRole == ElectionState.LEADER && _strongNodeController != null) {
      _strongNodeController!.addSensorPacket(packet);
    }
  }
  
  /// Handle incoming leader alert packet (as follower)
  void _onLeaderAlertPacket(LeaderAlertPacket packet) {
    if (_currentRole == ElectionState.FOLLOWER && _weakNodeController != null) {
      _weakNodeController!.onLeaderAlert(packet);
    }
  }
  
  /// Become strong node (leader)
  void _becomeStrongNode() {
    print('[Orchestrator] Becoming STRONG_NODE (leader)');
    
    _strongNodeController = StrongNodeController();
    _strongNodeController!.initialize(_myDeviceId!);
    
    // Forward alerts to network
    _strongNodeAlertSubscription = _strongNodeController!.alertStream.listen((alert) {
      _packetOutController.add(alert);
    });
  }
  
  /// Become weak node (follower)
  void _becomeWeakNode(String leaderId) {
    print('[Orchestrator] Becoming WEAK_NODE (follower of $leaderId)');
    
    _weakNodeController = WeakNodeController();
    _weakNodeController!.initialize(_myDeviceId!);
    _weakNodeController!.startTransmission(leaderId);
    
    // Forward sensor packets to network
    _weakNodeSensorSubscription = _weakNodeController!.sensorPacketStream.listen((packet) {
      _packetOutController.add(packet);
    });
    
    // Forward UI updates to app
    _weakNodeUISubscription = _weakNodeController!.uiUpdateStream.listen((update) {
      // This would be handled by the UI layer
      print('[Orchestrator] UI Update: ${update.type} - ${update.data}');
    });
  }
  
  /// Enter reduced mode (no leader)
  void _enterReducedMode() {
    print('[Orchestrator] Entering REDUCED_MODE');
    
    // Keep weak node controller but notify it
    if (_weakNodeController != null) {
      _weakNodeController!.stopTransmission();
    } else {
      _weakNodeController = WeakNodeController();
      _weakNodeController!.initialize(_myDeviceId!);
      _weakNodeController!.stopTransmission();
    }
  }
  
  /// Tear down existing controllers
  void _tearDownControllers() {
    _strongNodeAlertSubscription?.cancel();
    _weakNodeSensorSubscription?.cancel();
    _weakNodeUISubscription?.cancel();
    
    _strongNodeController?.dispose();
    _strongNodeController = null;
    
    // Don't dispose weak node controller on role change (might reuse)
  }
  
  /// Broadcast capability packet to all peers
  void _broadcastCapabilityPacket() {
    if (_myCapability == null || _myDeviceId == null) return;
    
    final isStrongNode = _capabilityDetector.isStrongNode(_myCapability!.capabilityScore);
    final initialRole = _capabilityDetector.determineInitialRole(_myCapability!.capabilityScore);
    
    final packet = CapabilityPacket(
      deviceId: _myDeviceId!,
      score: _myCapability!.capabilityScore,
      isStrongNode: isStrongNode,
      currentRole: initialRole,
      capability: _myCapability!,
    );
    
    _packetOutController.add(packet);
    print('[Orchestrator] Broadcasted capability: score=${_myCapability!.capabilityScore}, strong=$isStrongNode');
  }
  
  void dispose() {
    _electionStateSubscription?.cancel();
    _electionEventsSubscription?.cancel();
    _strongNodeAlertSubscription?.cancel();
    _weakNodeSensorSubscription?.cancel();
    _weakNodeUISubscription?.cancel();
    
    _strongNodeController?.dispose();
    _weakNodeController?.dispose();
    _electionEngine.dispose();
    
    _roleChangeController.close();
    _packetOutController.close();
  }
}

/// Role change event
class RoleChangeEvent {
  final ElectionState newRole;
  final String? leaderId;
  final int term;
  
  RoleChangeEvent({
    required this.newRole,
    this.leaderId,
    required this.term,
  });
}
