import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/cluster_packet.dart';

final leaderElectionProvider = Provider<LeaderElectionEngine>((ref) {
  return LeaderElectionEngine();
});

enum ElectionState {
  DISCOVERING,
  CAPABILITY_EXCHANGE,
  LEADER_CANDIDATE,
  LEADER,
  FOLLOWER,
  REDUCED_MODE
}

class PeerState {
  final String deviceId;
  final int capabilityScore;
  final bool isStrongNode;
  final DateTime lastSeenTimestamp;
  final bool isAlive;

  PeerState({
    required this.deviceId,
    required this.capabilityScore,
    required this.isStrongNode,
    required this.lastSeenTimestamp,
    required this.isAlive,
  });

  PeerState copyWith({
    DateTime? lastSeenTimestamp,
    bool? isAlive,
  }) {
    return PeerState(
      deviceId: deviceId,
      capabilityScore: capabilityScore,
      isStrongNode: isStrongNode,
      lastSeenTimestamp: lastSeenTimestamp ?? this.lastSeenTimestamp,
      isAlive: isAlive ?? this.isAlive,
    );
  }
}

class ClusterState {
  final int currentTerm;
  final String? currentLeader;
  final ElectionState myRole;
  final Map<String, PeerState> peers;

  ClusterState({
    required this.currentTerm,
    this.currentLeader,
    required this.myRole,
    required this.peers,
  });

  ClusterState copyWith({
    int? currentTerm,
    String? currentLeader,
    ElectionState? myRole,
    Map<String, PeerState>? peers,
  }) {
    return ClusterState(
      currentTerm: currentTerm ?? this.currentTerm,
      currentLeader: currentLeader ?? this.currentLeader,
      myRole: myRole ?? this.myRole,
      peers: peers ?? this.peers,
    );
  }
}

/// Leader Election Engine implementing the complete election algorithm
class LeaderElectionEngine {
  // Constants
  static const Duration HEARTBEAT_INTERVAL = Duration(milliseconds: 500);
  static const Duration HEARTBEAT_TIMEOUT = Duration(seconds: 3);
  static const Duration CHALLENGE_WINDOW = Duration(seconds: 2);
  static const int STRONG_NODE_THRESHOLD = 70;

  // State
  ClusterState _state = ClusterState(
    currentTerm: 0,
    myRole: ElectionState.DISCOVERING,
    peers: {},
  );

  String? _myDeviceId;
  int _myCapabilityScore = 0;
  bool _amIStrongNode = false;

  // Timers
  Timer? _heartbeatTimer;
  Timer? _heartbeatWatchdog;
  Timer? _challengeTimer;

  // Stream controllers
  final _stateController = StreamController<ClusterState>.broadcast();
  final _electionEventsController = StreamController<ElectionEvent>.broadcast();

  Stream<ClusterState> get stateStream => _stateController.stream;
  Stream<ElectionEvent> get electionEventsStream => _electionEventsController.stream;

  ClusterState get state => _state;

  /// Initialize with device ID and capability
  void initialize(String deviceId, int capabilityScore) {
    _myDeviceId = deviceId;
    _myCapabilityScore = capabilityScore;
    _amIStrongNode = capabilityScore >= STRONG_NODE_THRESHOLD;

    _updateState(_state.copyWith(myRole: ElectionState.CAPABILITY_EXCHANGE));
    print('[Election] Initialized: deviceId=$deviceId, score=$capabilityScore, strong=$_amIStrongNode');
  }

  /// Handle incoming capability packet
  void onCapabilityPacket(CapabilityPacket packet) {
    // Store peer capability
    _state.peers[packet.deviceId] = PeerState(
      deviceId: packet.deviceId,
      capabilityScore: packet.score,
      isStrongNode: packet.isStrongNode,
      lastSeenTimestamp: DateTime.now(),
      isAlive: true,
    );

    print('[Election] Capability received from ${packet.deviceId}: score=${packet.score}');

    // Trigger election
    _runElection();
  }

  /// Handle incoming heartbeat packet
  void onHeartbeatPacket(HeartbeatPacket packet) {
    // Update peer state
    if (_state.peers.containsKey(packet.leaderId)) {
      _state.peers[packet.leaderId] = _state.peers[packet.leaderId]!.copyWith(
        lastSeenTimestamp: DateTime.now(),
        isAlive: true,
      );
    }

    // If this is from the current leader, reset watchdog
    if (_state.currentLeader == packet.leaderId) {
      _resetHeartbeatWatchdog();
    } else if (packet.electionTerm > _state.currentTerm) {
      // Higher term leader discovered
      print('[Election] Higher term leader discovered: ${packet.leaderId} (term ${packet.electionTerm})');
      _state = _state.copyWith(
        currentTerm: packet.electionTerm,
        currentLeader: packet.leaderId,
        myRole: ElectionState.FOLLOWER,
      );
      _resetHeartbeatWatchdog();
      _updateState(_state);
    } else if (packet.electionTerm == _state.currentTerm && 
               packet.leaderId != _state.currentLeader) {
      // Split-brain detected
      _resolveSplitBrain(packet);
    }
  }

  /// Handle incoming election packet
  void onElectionPacket(ElectionPacket packet) {
    if (packet.electionTerm > _state.currentTerm) {
      // Higher term election
      print('[Election] Higher term election from ${packet.deviceId}: term=${packet.electionTerm}');
      _state = _state.copyWith(currentTerm: packet.electionTerm);
    }

    if (packet.electionTerm == _state.currentTerm && 
        _state.myRole == ElectionState.LEADER_CANDIDATE) {
      // Challenge during my candidacy
      if (packet.capabilityScore > _myCapabilityScore) {
        // Lost election
        print('[Election] Lost election to ${packet.deviceId} (${packet.capabilityScore} > $_myCapabilityScore)');
        _becomeFollower(packet.deviceId);
      } else if (packet.capabilityScore == _myCapabilityScore) {
        // Tie-breaker: lower deviceId wins
        if (packet.deviceId.compareTo(_myDeviceId!) < 0) {
          print('[Election] Lost election to ${packet.deviceId} (tie-breaker)');
          _becomeFollower(packet.deviceId);
        }
      }
    }
  }

  /// Handle peer disconnection
  void onPeerDisconnected(String deviceId) {
    _state.peers.remove(deviceId);

    if (_state.currentLeader == deviceId) {
      print('[Election] Leader lost! Triggering re-election');
      _state = _state.copyWith(currentLeader: null);
      _heartbeatTimer?.cancel();
      _runElection();
    }
  }

  /// Run the complete election algorithm
  void _runElection() {
    // Step 1: Gather all candidates
    final candidates = [
      if (_amIStrongNode)
        PeerState(
          deviceId: _myDeviceId!,
          capabilityScore: _myCapabilityScore,
          isStrongNode: true,
          lastSeenTimestamp: DateTime.now(),
          isAlive: true,
        ),
      ..._state.peers.values.where((p) => p.isStrongNode),
    ];

    // Step 2: Check if any strong nodes exist
    if (candidates.isEmpty) {
      print('[Election] No strong nodes available - entering REDUCED_MODE');
      _updateState(_state.copyWith(
        myRole: ElectionState.REDUCED_MODE,
        currentLeader: null,
      ));
      _electionEventsController.add(ElectionEvent.enteredReducedMode());
      return;
    }

    // Step 3: Sort by score (desc), then deviceId (asc)
    candidates.sort((a, b) {
      if (a.capabilityScore != b.capabilityScore) {
        return b.capabilityScore.compareTo(a.capabilityScore);
      }
      return a.deviceId.compareTo(b.deviceId);
    });

    final winner = candidates.first;

    // Step 4: Determine my role
    if (winner.deviceId == _myDeviceId) {
      _becomeLeaderCandidate();
    } else {
      _becomeFollower(winner.deviceId);
    }
  }

  /// Become leader candidate and start challenge window
  void _becomeLeaderCandidate() {
    final newTerm = _state.currentTerm + 1;
    print('[Election] Becoming LEADER_CANDIDATE (term $newTerm)');

    _updateState(_state.copyWith(
      currentTerm: newTerm,
      myRole: ElectionState.LEADER_CANDIDATE,
    ));

    // Broadcast election packet
    _electionEventsController.add(ElectionEvent.broadcastElection(
      term: newTerm,
      score: _myCapabilityScore,
    ));

    // Start challenge window
    _challengeTimer?.cancel();
    _challengeTimer = Timer(CHALLENGE_WINDOW, () {
      // No challenges received - become leader
      _becomeLeader();
    });
  }

  /// Become the cluster leader
  void _becomeLeader() {
    print('[Election] Won election - becoming LEADER (term ${_state.currentTerm})');

    _updateState(_state.copyWith(
      currentLeader: _myDeviceId,
      myRole: ElectionState.LEADER,
    ));

    _electionEventsController.add(ElectionEvent.becameLeader());

    // Start heartbeat transmission
    _startHeartbeat();
  }

  /// Become a follower
  void _becomeFollower(String leaderId) {
    print('[Election] Becoming FOLLOWER (leader: $leaderId)');

    _challengeTimer?.cancel();
    _heartbeatTimer?.cancel();

    _updateState(_state.copyWith(
      currentLeader: leaderId,
      myRole: ElectionState.FOLLOWER,
    ));

    _electionEventsController.add(ElectionEvent.becameFollower(leaderId));

    // Start watchdog for leader heartbeat
    _resetHeartbeatWatchdog();
  }

  /// Start sending heartbeat packets
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(HEARTBEAT_INTERVAL, (_) {
      _electionEventsController.add(ElectionEvent.sendHeartbeat(
        term: _state.currentTerm,
        clusterSize: _state.peers.length + 1,
      ));
    });
  }

  /// Reset the heartbeat watchdog timer
  void _resetHeartbeatWatchdog() {
    _heartbeatWatchdog?.cancel();
    _heartbeatWatchdog = Timer(HEARTBEAT_TIMEOUT, () {
      print('[Election] Heartbeat timeout - leader presumed dead');
      _state = _state.copyWith(currentLeader: null);
      _runElection();
    });
  }

  /// Resolve split-brain scenario
  void _resolveSplitBrain(HeartbeatPacket packet) {
    print('[Election] Split-brain detected with ${packet.leaderId}');

    final myScore = _myCapabilityScore;
    final peerScore = _state.peers[packet.leaderId]?.capabilityScore ?? 0;

    if (peerScore > myScore || 
        (peerScore == myScore && packet.leaderId.compareTo(_myDeviceId!) < 0)) {
      // Step down
      print('[Election] Stepping down from leadership');
      _becomeFollower(packet.leaderId);
    }
    // Otherwise, maintain leadership (peer should step down)
  }

  /// Update state and notify listeners
  void _updateState(ClusterState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatWatchdog?.cancel();
    _challengeTimer?.cancel();
    _stateController.close();
    _electionEventsController.close();
  }
}

/// Events emitted by the election engine
class ElectionEvent {
  final String type;
  final Map<String, dynamic> data;

  ElectionEvent._(this.type, this.data);

  factory ElectionEvent.broadcastElection({required int term, required int score}) {
    return ElectionEvent._('BROADCAST_ELECTION', {'term': term, 'score': score});
  }

  factory ElectionEvent.sendHeartbeat({required int term, required int clusterSize}) {
    return ElectionEvent._('SEND_HEARTBEAT', {'term': term, 'clusterSize': clusterSize});
  }

  factory ElectionEvent.becameLeader() {
    return ElectionEvent._('BECAME_LEADER', {});
  }

  factory ElectionEvent.becameFollower(String leaderId) {
    return ElectionEvent._('BECAME_FOLLOWER', {'leaderId': leaderId});
  }

  factory ElectionEvent.enteredReducedMode() {
    return ElectionEvent._('ENTERED_REDUCED_MODE', {});
  }
}
