// ignore_for_file: avoid_print, constant_identifier_names

import 'dart:async';

import '../../core/models/collision_alert.dart';
import '../capability_engine.dart';
import '../fusion/mid_node_engine.dart';
import '../fusion/strong_node_engine.dart';
import '../fusion/weak_node_engine.dart';
import 'leader_election.dart';
import 'packet_protocol.dart';

/// Orchestrates the entire cluster: Tier detection, Mode selection, Leader tracking.
class ClusterManager {
  static final ClusterManager instance = ClusterManager._();
  ClusterManager._();

  // Services
  final CapabilityEngine _capabilityEngine = CapabilityEngine();
  late LeaderElectionService _electionService;
  
  // Engines (nullable, only one active at a time)
  StrongNodeEngine? _strongEngine;
  MidNodeEngine? _midEngine;
  WeakNodeEngine? _weakEngine;

  // State
  NodeTier _myTier = NodeTier.WEAK_NODE;
  int _myScore = 0;
  String _myDeviceId = '';
  ClusterMode _mode = ClusterMode.INITIALIZING;
  
  final _modeController = StreamController<ClusterMode>.broadcast();
  Stream<ClusterMode> get modeStream => _modeController.stream;

  // Packet Sender Callback (to be set by NearbyService)
  Function(BasePacket)? _sendPacketCallback;

  bool _isInitialized = false;

  /// Initializes the Cluster Manager.
  /// Must be called after NearbyService is ready.
  Future<void> initialize(String deviceId, Function(BasePacket) sendPacket) async {
    if (_isInitialized) return;
    
    _myDeviceId = deviceId;
    _sendPacketCallback = sendPacket;
    
    // 1. Detect Capability
    final cap = await _capabilityEngine.detectCapability();
    _myTier = cap.tier;
    _myScore = cap.score;
    print('ClusterManager: Initialized as $_myTier (Score: $_myScore)');

    // 2. Initialize Election Service
    _electionService = LeaderElectionService(
      myDeviceId: _myDeviceId,
      myTier: _myTier,
      myScore: _myScore,
      onSendPacket: _handleElectionPacketSend,
    );

    // 3. Listen to Election State
    _electionService.stateStream.listen(_handleElectionStateChange);

    // 4. Select Initial Mode
    _selectInitialMode();
    
    _isInitialized = true;
  }

  void _selectInitialMode() {
    if (_myTier == NodeTier.STRONG_NODE) {
      // Strong nodes immediately try to become leader
      _electionService.startElection();
    } else if (_myTier == NodeTier.MID_NODE) {
      // Mid nodes wait for a leader, or fallback if none found
      _transitionTo(ClusterMode.MID_LEADER); // Tentative, will yield if Strong appears
      // Actually, better to start in a passive state and wait for discovery?
      // For now, let's default to waiting (Weak Distributed) until we see a leader.
      _transitionTo(ClusterMode.WEAK_DISTRIBUTED);
    } else {
      // Weak nodes start in distributed mode
      _transitionTo(ClusterMode.WEAK_DISTRIBUTED);
    }
  }

  void _handleElectionPacketSend(BasePacket packet) {
    _sendPacketCallback?.call(packet);
  }

  void _handleElectionStateChange(LeaderState state) {
    print('ClusterManager: Election State Changed -> Phase: ${state.phase}, Leader: ${state.leaderId}');
    
    if (state.leaderId == _myDeviceId) {
      // I am the leader!
      if (_myTier == NodeTier.STRONG_NODE) {
        _transitionTo(ClusterMode.STRONG_LEADER);
      } else {
        _transitionTo(ClusterMode.MID_LEADER);
      }
    } else if (state.leaderId != null) {
      // Someone else is leader
      // I am a follower.
      // If I was running an engine, I should switch to follower mode.
      // For now, Followers just run WeakNodeEngine (passive) or MidNodeEngine (passive)?
      // Actually, Followers send sensor data.
      // WeakNodeEngine handles "sending sensor data".
      // So Followers should run WeakNodeEngine (or a "FollowerEngine").
      // Let's use WeakNodeEngine for followers as it has `startSendingSensorData`.
      _transitionTo(ClusterMode.WEAK_DISTRIBUTED); // Re-using this mode for "Follower" logic for now
      // Ideally we'd have a FOLLOWER mode.
      // But `ClusterMode` enum has STRONG_LEADER, MID_LEADER, WEAK_DISTRIBUTED.
      // WEAK_DISTRIBUTED implies "No Leader".
      // If there IS a leader, we are just a client.
      // Let's assume WEAK_DISTRIBUTED means "Not a Leader" for this simplified model,
      // OR we add a FOLLOWER mode.
      // The prompt says: "Weak -> Mid -> Strong".
      // Let's stick to the requested modes.
      // If I am NOT leader, I should behave as a sensor node.
      _startFollowerLogic();
    } else {
      // No leader (Election in progress or lost)
      if (_mode != ClusterMode.WEAK_DISTRIBUTED) {
        _transitionTo(ClusterMode.WEAK_DISTRIBUTED);
      }
    }
  }

  void _transitionTo(ClusterMode newMode) {
    if (_mode == newMode) return;
    print('ClusterManager: Transitioning $_mode -> $newMode');
    _mode = newMode;
    _modeController.add(newMode);

    // Stop all engines
    _strongEngine?.stopStrongNodeLoop();
    _strongEngine = null;
    _midEngine?.stopMidNodeLoop();
    _midEngine = null;
    _weakEngine?.stopSendingSensorData();
    _weakEngine?.stopWeakDistributedMode();
    _weakEngine = null;

    // Start new engine
    switch (newMode) {
      case ClusterMode.STRONG_LEADER:
        _strongEngine = StrongNodeEngine(
          myDeviceId: _myDeviceId,
          onSendPacket: (p) => _sendPacketCallback?.call(p),
        );
        _strongEngine!.startStrongNodeLoop();
        break;

      case ClusterMode.MID_LEADER:
        _midEngine = MidNodeEngine(
          myDeviceId: _myDeviceId,
          onSendPacket: (p) => _sendPacketCallback?.call(p),
        );
        _midEngine!.startMidNodeLoop();
        break;

      case ClusterMode.WEAK_DISTRIBUTED:
        _weakEngine = WeakNodeEngine(
          myDeviceId: _myDeviceId,
          onSendPacket: (p) => _sendPacketCallback?.call(p),
        );
        // If we have a leader, we send data. If not, we do distributed ranging.
        if (_electionService.currentLeaderId != null) {
           _weakEngine!.startSendingSensorData();
        } else {
           _weakEngine!.startWeakDistributedMode();
        }
        break;

      case ClusterMode.INITIALIZING:
        break;
    }
  }

  void _startFollowerLogic() {
    // Helper to switch to follower behavior (sending data)
    // We treat this as WEAK_DISTRIBUTED mode but with "Sending Data" active
    // instead of "Distributed Ranging".
    // The _transitionTo logic handles this check.
    if (_mode != ClusterMode.WEAK_DISTRIBUTED) {
      _transitionTo(ClusterMode.WEAK_DISTRIBUTED);
    } else {
      // Already in mode, just ensure we are sending data
      _weakEngine?.stopWeakDistributedMode();
      _weakEngine?.startSendingSensorData();
    }
  }

  // ---------------------------------------------------------------------------
  // Packet Handling
  // ---------------------------------------------------------------------------

  void handlePacket(BasePacket packet) {
    if (!_isInitialized) return;

    // 1. Election & Heartbeats (Always processed)
    if (packet is LeaderElectionPacket) {
      _electionService.handleElectionPacket(packet);
      return;
    }
    if (packet is HeartbeatPacket) {
      _electionService.handleHeartbeat(packet);
      return;
    }

    // 2. Capability Updates
    if (packet is CapabilityPacket) {
      // Could trigger re-election if a stronger node appears
      if (packet.tier.index < _myTier.index) { // Stronger tier (0 < 1)
         // We might want to yield or restart election
         // _electionService.startElection();
      }
      return;
    }

    // 3. Mode-Specific Handling
    switch (_mode) {
      case ClusterMode.STRONG_LEADER:
        if (packet is RawSensorPacket) {
          _strongEngine?.processSensorPacket(packet);
        }
        break;

      case ClusterMode.MID_LEADER:
        if (packet is RawSensorPacket) {
          _midEngine?.processRawPacket(packet);
        }
        break;

      case ClusterMode.WEAK_DISTRIBUTED:
        if (packet is LeaderAlertPacket) {
          _weakEngine?.handleLeaderAlert(packet);
        }
        // If in distributed mode (no leader), we might listen to other packets?
        // For now, WeakNodeEngine handles RSSI updates internally if we passed packets to it.
        // But WeakNodeEngine doesn't have a generic "handlePacket".
        // It has `updatePeerRssi`.
        if (packet is RawSensorPacket) {
           _weakEngine?.updatePeerRssi(packet.senderId, packet.rssi);
        }
        break;

      case ClusterMode.INITIALIZING:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Getters for UI
  // ---------------------------------------------------------------------------
  
  NodeTier get myTier => _myTier;
  ClusterMode get mode => _mode;
  String? get leaderId => _electionService.currentLeaderId;
  
  // Expose active engine streams for UI
  Stream<CollisionAlert>? get activeAlertStream {
    if (_strongEngine != null) return _strongEngine!.alertStream;
    if (_midEngine != null) return _midEngine!.alertStream;
    if (_weakEngine != null) return _weakEngine!.alertStream;
    return null;
  }
}
