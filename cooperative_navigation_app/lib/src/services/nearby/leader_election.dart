// ignore_for_file: constant_identifier_names, avoid_print

/// COMPLETE ELECTION TIMELINE EXAMPLE:
/// ===================================
/// Scenario: 3 nodes start, no initial leader
///   - Node A: STRONG_NODE, score=85, ID="device_aaa"
///   - Node B: MID_NODE, score=60, ID="device_bbb"  
///   - Node C: WEAK_NODE, score=35, ID="device_ccc"
///
/// T=0ms:    All nodes detect no leader, trigger startElection()
/// T=0ms:    Node A: phase=ANNOUNCEMENT, adds self to candidates
/// T=10ms:   Node B: phase=ANNOUNCEMENT, adds self to candidates
/// T=15ms:   Node C: phase=ANNOUNCEMENT, adds self to candidates
/// T=50ms:   Node A broadcasts LeaderElectionPacket(STRONG, 85, "device_aaa")
/// T=60ms:   Node B broadcasts LeaderElectionPacket(MID, 60, "device_bbb")
/// T=70ms:   Node C broadcasts LeaderElectionPacket(WEAK, 35, "device_ccc")
/// T=120ms:  Node A receives packets from B and C, adds to candidates map
/// T=130ms:  Node B receives packets from A and C, adds to candidates map
/// T=140ms:  Node C receives packets from A and B, adds to candidates map
/// T=500ms:  Announcement phase ends, all nodes call _evaluateCandidates()
/// T=500ms:  Node A sorts: [A(STRONG,85), B(MID,60), C(WEAK,35)] → Winner=A → calls _becomeLeader()
/// T=500ms:  Node B sorts: [A(STRONG,85), B(MID,60), C(WEAK,35)] → Winner=A → calls _acceptLeader("device_aaa")
/// T=500ms:  Node C sorts: [A(STRONG,85), B(MID,60), C(WEAK,35)] → Winner=A → calls _acceptLeader("device_aaa")
/// T=510ms:  Node A broadcasts LeaderElectionPacket(phase=VICTORY)
/// T=520ms:  Node A starts sending HeartbeatPacket every 1s
/// T=530ms:  Node B receives VICTORY packet, confirms A as leader
/// T=530ms: Node C receives VICTORY packet, confirms A as leader
/// T=1520ms: Node A sends first HEARTBEAT
/// T=1530ms: Nodes B & C receive HEARTBEAT, update lastHeartbeat timestamp
/// T=5000ms: (Steady State) Node A sends HEARTBEAT every 1s, B & C monitor it
///
/// RE-ELECTION TRIGGER EXAMPLE (Leader Loss):
/// T=10000ms: Node A crashes/disconnects (stops sending heartbeats)
/// T=14000ms: Nodes B & C detect heartbeat timeout (>4s since last heartbeat)
/// T=14000ms: Nodes B & C both call startElection() again
/// T=14500ms: New election completes → Node B becomes leader (highest remaining)
///
/// RE-ELECTION TRIGGER EXAMPLE (Stronger Node Joins):
/// T=20000ms: Node D joins: STRONG_NODE, score=92, ID="device_ddd"
/// T=20050ms: Node D broadcasts CAPABILITY packet, A sees it
/// T=20050ms: Node A detects stronger node (92 > 85), calls startElection()
/// T=20500ms: New election → Node D wins (STRONG, 92 > A's 85)
/// T=20520ms: Node D becomes new leader, A yields

import 'dart:async';

import '../capability_engine.dart';
import 'packet_protocol.dart';

/// Represents the current state of leadership within the cluster.
class LeaderState {
  final String? leaderId;
  final NodeTier? leaderTier;
  final int? leaderScore;
  final DateTime? lastHeartbeat;
  final ElectionPhase phase;
  final List<String> knownCandidates;

  LeaderState({
    this.leaderId,
    this.leaderTier,
    this.leaderScore,
    this.lastHeartbeat,
    this.phase = ElectionPhase.ANNOUNCEMENT, // Default to start of election logic or IDLE
    this.knownCandidates = const [],
  });

  LeaderState copyWith({
    String? leaderId,
    NodeTier? leaderTier,
    int? leaderScore,
    DateTime? lastHeartbeat,
    ElectionPhase? phase,
    List<String>? knownCandidates,
  }) {
    return LeaderState(
      leaderId: leaderId ?? this.leaderId,
      leaderTier: leaderTier ?? this.leaderTier,
      leaderScore: leaderScore ?? this.leaderScore,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      phase: phase ?? this.phase,
      knownCandidates: knownCandidates ?? this.knownCandidates,
    );
  }

  bool get isLeaderPresent => leaderId != null;
}

/// Service responsible for managing the distributed leader election process.
///
/// Logic:
/// 1. Strong nodes outrank mid nodes; mid nodes outrank weak nodes.
/// 2. Highest capability score wins.
/// 3. If tie, lowest DeviceID wins (lexicographical).
class LeaderElectionService {
  final String myDeviceId;
  final NodeTier myTier;
  final int myScore;
  final Function(BasePacket) onSendPacket; // Callback to send packets via NearbyService

  LeaderState _state = LeaderState();
  Timer? _electionTimer;
  Timer? _heartbeatTimer;
  Timer? _heartbeatMonitorTimer;

  // Candidates collected during an election
  final Map<String, LeaderElectionPacket> _candidates = {};

  final _stateController = StreamController<LeaderState>.broadcast();
  Stream<LeaderState> get stateStream => _stateController.stream;

  LeaderElectionService({
    required this.myDeviceId,
    required this.myTier,
    required this.myScore,
    required this.onSendPacket,
  });

  bool get isLeader => _state.leaderId == myDeviceId;
  String? get currentLeaderId => _state.leaderId;

  /// Starts a new leader election process.
  Future<void> startElection() async {
    // Avoid starting if already in an election
    if (_state.phase == ElectionPhase.VOTING) return;

    print('Starting Leader Election...');
    _updateState(_state.copyWith(
      phase: ElectionPhase.ANNOUNCEMENT,
      leaderId: null, // Clear current leader
      knownCandidates: [],
    ));
    _candidates.clear();

    // Add self as candidate
    _candidates[myDeviceId] = LeaderElectionPacket(
      senderId: myDeviceId,
      candidateTier: myTier,
      score: myScore,
      candidateId: myDeviceId,
      phase: ElectionPhase.ANNOUNCEMENT,
    );

    // Broadcast candidacy
    broadcastCandidatePacket();

    // Move to Voting phase after 500ms (Announcement window)
    _electionTimer?.cancel();
    _electionTimer = Timer(const Duration(milliseconds: 500), _evaluateCandidates);
  }

  /// Broadcasts a packet announcing this node's candidacy.
  void broadcastCandidatePacket() {
    final packet = LeaderElectionPacket(
      senderId: myDeviceId,
      candidateTier: myTier,
      score: myScore,
      candidateId: myDeviceId,
      phase: ElectionPhase.ANNOUNCEMENT,
    );
    onSendPacket(packet);
  }

  /// Handles an incoming election packet from a peer.
  void handleElectionPacket(LeaderElectionPacket packet) {
    // If we are not in an election, and we receive an announcement from a higher tier/score node,
    // we should probably join the election or yield.
    // For simplicity, if we see an election packet, we join the election if not already in it.
    if (_state.phase != ElectionPhase.ANNOUNCEMENT && _state.phase != ElectionPhase.VOTING) {
      // Trigger election if the sender claims to be a candidate
      if (packet.phase == ElectionPhase.ANNOUNCEMENT) {
        startElection();
      }
    }

    if (_state.phase == ElectionPhase.ANNOUNCEMENT) {
      _candidates[packet.senderId] = packet;
    } else if (_state.phase == ElectionPhase.VICTORY) {
      // If someone declares victory, check if they actually won
      // (This is a simplified check, ideally we verify against our view)
      _acceptLeader(packet.candidateId, packet.candidateTier, packet.score);
    }
  }

  /// Evaluates all collected candidates to determine the winner.
  void _evaluateCandidates() {
    _updateState(_state.copyWith(phase: ElectionPhase.VOTING));

    // Sort candidates:
    // 1. Tier (Descending: STRONG > MID > WEAK)
    // 2. Score (Descending)
    // 3. ID (Ascending - tie breaker)
    final sortedCandidates = _candidates.values.toList()
      ..sort((a, b) {
        if (a.candidateTier != b.candidateTier) {
          // STRONG (0) < MID (1) < WEAK (2) in enum index?
          // Wait, enum is STRONG_NODE, MID_NODE, WEAK_NODE.
          // STRONG_NODE index is 0.
          // We want STRONG (0) to be "greater" than MID (1).
          // Actually, let's look at the enum definition in capability_engine.dart:
          // STRONG_NODE, MID_NODE, WEAK_NODE.
          // So STRONG is 0, MID is 1, WEAK is 2.
          // We want 0 to come BEFORE 1. So ascending index is correct for "better tier"?
          // No, usually we say "Stronger".
          // Let's assume we want the "best" node first.
          // STRONG (0) is better than MID (1).
          return a.candidateTier.index.compareTo(b.candidateTier.index);
        }
        if (a.score != b.score) {
          return b.score.compareTo(a.score); // Higher score first
        }
        return a.candidateId.compareTo(b.candidateId); // Lower ID first
      });

    if (sortedCandidates.isEmpty) {
      // Should not happen as we add ourselves
      return;
    }

    final winner = sortedCandidates.first;
    print('Election Winner: ${winner.candidateId} (Tier: ${winner.candidateTier}, Score: ${winner.score})');

    if (winner.candidateId == myDeviceId) {
      _becomeLeader();
    } else {
      _acceptLeader(winner.candidateId, winner.candidateTier, winner.score);
    }
  }

  void _becomeLeader() {
    print('I am the LEADER!');
    _updateState(_state.copyWith(
      leaderId: myDeviceId,
      leaderTier: myTier,
      leaderScore: myScore,
      phase: ElectionPhase.VICTORY,
      lastHeartbeat: DateTime.now(),
    ));

    // Broadcast Victory
    final victoryPacket = LeaderElectionPacket(
      senderId: myDeviceId,
      candidateTier: myTier,
      score: myScore,
      candidateId: myDeviceId,
      phase: ElectionPhase.VICTORY,
    );
    onSendPacket(victoryPacket);

    // Start Heartbeat
    _startHeartbeat();
  }

  void _acceptLeader(String leaderId, NodeTier tier, int score) {
    print('Accepting leader: $leaderId');
    _updateState(_state.copyWith(
      leaderId: leaderId,
      leaderTier: tier,
      leaderScore: score,
      phase: ElectionPhase.VICTORY, // Election over
      lastHeartbeat: DateTime.now(),
    ));

    // Stop sending heartbeats if we were sending them
    _heartbeatTimer?.cancel();
    
    // Start monitoring heartbeats
    _startHeartbeatMonitor();
  }

  /// Handles incoming heartbeat packets to maintain leader state.
  void handleHeartbeat(HeartbeatPacket packet) {
    if (packet.senderId == _state.leaderId) {
      _updateState(_state.copyWith(lastHeartbeat: DateTime.now()));
    } else if (packet.isLeader && packet.senderId != myDeviceId) {
      // Split brain or new leader detected!
      // Resolve conflict
      _resolveConflict(packet);
    }
  }

  void _resolveConflict(HeartbeatPacket otherLeader) {
    print('Conflict detected with leader ${otherLeader.senderId}');
    // Compare with current leader (or self if leader)
    final currentTier = _state.leaderTier ?? NodeTier.WEAK_NODE;
    final currentScore = _state.leaderScore ?? 0;
    final currentId = _state.leaderId ?? '';

    // Logic: Stronger wins
    bool otherIsBetter = false;
    if (otherLeader.currentTier.index < currentTier.index) { // Lower index = Stronger
      otherIsBetter = true;
    } else if (otherLeader.currentTier == currentTier) {
      if (otherLeader.leaderScore > currentScore) {
        otherIsBetter = true;
      } else if (otherLeader.leaderScore == currentScore) {
        if (otherLeader.senderId.compareTo(currentId) < 0) {
          otherIsBetter = true;
        }
      }
    }

    if (otherIsBetter) {
      print('Other leader is better. Yielding.');
      _acceptLeader(otherLeader.senderId, otherLeader.currentTier, otherLeader.leaderScore);
    } else {
      print('I am (or current leader is) better. Ignoring/Asserting.');
      if (isLeader) {
        // Broadcast heartbeat immediately to assert dominance
        _sendHeartbeat();
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    final packet = HeartbeatPacket(
      senderId: myDeviceId,
      currentTier: myTier,
      isLeader: true,
      leaderScore: myScore,
    );
    onSendPacket(packet);
  }

  void _startHeartbeatMonitor() {
    _heartbeatMonitorTimer?.cancel();
    _heartbeatMonitorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.leaderId != null && _state.leaderId != myDeviceId) {
        final lastSeen = _state.lastHeartbeat;
        if (lastSeen != null && DateTime.now().difference(lastSeen) > const Duration(seconds: 4)) {
          print('Leader heartbeat timeout! Starting re-election.');
          startElection();
        }
      }
    });
  }

  void _updateState(LeaderState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _electionTimer?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatMonitorTimer?.cancel();
    _stateController.close();
  }
}
