import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/cluster_orchestrator.dart';
import '../services/leader_election_engine.dart';

/// Example integration showing how to wire the orchestrator to your app
/// 
/// This demonstrates:
/// 1. Initializing the orchestrator
/// 2. Listening to role changes
/// 3. Handling incoming packets from Nearby Service
/// 4. Feeding sensor data from SensorService
/// 5. Displaying UI updates
class ClusterIntegrationExample extends ConsumerStatefulWidget {
  const ClusterIntegrationExample({super.key});

  @override
  ConsumerState<ClusterIntegrationExample> createState() => _ClusterIntegrationExampleState();
}

class _ClusterIntegrationExampleState extends ConsumerState<ClusterIntegrationExample> {
  late final ClusterOrchestrator _orchestrator;
  
  ElectionState _currentRole = ElectionState.DISCOVERING;
  String? _leaderId;
  int _electionTerm = 0;
  
  @override
  void initState() {
    super.initState();
    _initializeCluster();
  }
  
  Future<void> _initializeCluster() async {
    // Get orchestrator from provider
    _orchestrator = ref.read(clusterOrchestratorProvider);
    
    // Initialize with device ID (from Nearby Service)
    final myDeviceId = 'device-${DateTime.now().millisecondsSinceEpoch}';
    await _orchestrator.initialize(myDeviceId);
    
    // Listen to role changes
    _orchestrator.roleChangeStream.listen((event) {
      setState(() {
        _currentRole = event.newRole;
        _leaderId = event.leaderId;
        _electionTerm = event.term;
      });
      
      _handleRoleChange(event);
    });
    
    // Listen to outgoing packets and send via Nearby Service
    _orchestrator.packetOutStream.listen((packet) {
      // TODO: Send via NearbyService
      // nearbyService.sendToAll(jsonEncode(packet.toJson()));
      print('[Integration] Outgoing packet: ${packet.runtimeType}');
    });
  }
  
  void _handleRoleChange(RoleChangeEvent event) {
    switch (event.newRole) {
      case ElectionState.LEADER:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎯 You are now the cluster leader'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        break;
        
      case ElectionState.FOLLOWER:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('👥 Following leader: ${event.leaderId}'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
        break;
        
      case ElectionState.REDUCED_MODE:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Reduced Mode - No Network Leader'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        break;
        
      default:
        break;
    }
  }
  
  // Call this when Nearby Service receives a packet
  void onNearbyPacketReceived(Map<String, dynamic> json) {
    try {
      final packet = ClusterPacket.fromJson(json);
      _orchestrator.handleIncomingPacket(packet);
    } catch (e) {
      print('[Integration] Error parsing packet: $e');
    }
  }
  
  // Call this when SensorService updates
  void onSensorUpdate({
    required GnssData gnss,
    required ImuData imu,
    double? rssi,
    int? battery,
  }) {
    _orchestrator.updateSensorData(
      gnss: gnss,
      imu: imu,
      rssi: rssi,
      batteryLevel: battery,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cluster Status'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRoleCard(),
            const SizedBox(height: 16),
            _buildStatsCard(),
            const SizedBox(height: 16),
            _buildInstructions(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRoleCard() {
    final roleColor = _getRoleColor(_currentRole);
    final roleIcon = _getRoleIcon(_currentRole);
    final roleText = _getRoleText(_currentRole);
    
    return Card(
      color: roleColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(roleIcon, size: 48, color: roleColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roleText,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: roleColor,
                    ),
                  ),
                  if (_leaderId != null)
                    Text(
                      'Leader: ${_leaderId!.substring(0, 8)}...',
                      style: const TextStyle(fontSize: 14),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cluster Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Election Term: $_electionTerm'),
            Text('Current Role: ${_currentRole.name}'),
            if (_currentRole == ElectionState.LEADER)
              const Text('Mode: STRONG NODE (Fusion Active)'),
            if (_currentRole == ElectionState.FOLLOWER)
              const Text('Mode: WEAK NODE (Sensor Transmission)'),
            if (_currentRole == ElectionState.REDUCED_MODE)
              const Text('Mode: RSSI-Only Fallback'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInstructions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Integration Steps',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('1. Wire NearbyService to orchestrator.packetOutStream'),
            const Text('2. Route NearbyService.onReceive → orchestrator.handleIncomingPacket()'),
            const Text('3. Feed SensorService data → orchestrator.updateSensorData()'),
            const Text('4. Listen to orchestrator.roleChangeStream for UI updates'),
            const Text('5. Listen to weakNodeController.uiUpdateStream for alerts'),
            const SizedBox(height: 8),
            const Text(
              '✅ All core components are ready!',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
  
  Color _getRoleColor(ElectionState role) {
    switch (role) {
      case ElectionState.LEADER:
        return Colors.green;
      case ElectionState.FOLLOWER:
        return Colors.blue;
      case ElectionState.REDUCED_MODE:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getRoleIcon(ElectionState role) {
    switch (role) {
      case ElectionState.LEADER:
        return Icons.stars;
      case ElectionState.FOLLOWER:
        return Icons.people;
      case ElectionState.REDUCED_MODE:
        return Icons.warning;
      default:
        return Icons.circle;
    }
  }
  
  String _getRoleText(ElectionState role) {
    switch (role) {
      case ElectionState.DISCOVERING:
        return 'Discovering...';
      case ElectionState.CAPABILITY_EXCHANGE:
        return 'Negotiating...';
      case ElectionState.LEADER_CANDIDATE:
        return 'Candidate';
      case ElectionState.LEADER:
        return 'Leader';
      case ElectionState.FOLLOWER:
        return 'Follower';
      case ElectionState.REDUCED_MODE:
        return 'Reduced Mode';
    }
  }
  
  @override
  void dispose() {
    _orchestrator.dispose();
    super.dispose();
  }
}

// Example of importing and using in main.dart:
/*
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/examples/cluster_integration_example.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MaterialApp(
        home: ClusterIntegrationExample(),
      ),
    ),
  );
}
*/
