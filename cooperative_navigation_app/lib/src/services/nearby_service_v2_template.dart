import 'dart:async';
import 'dart:convert';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:cooperative_navigation_safety/src/core/models/cluster_packet.dart';
import 'package:cooperative_navigation_safety/src/services/cluster_manager.dart';

// This is a TEMPLATE for the updated NearbyService
// Integrate this into your existing NearbyService class

class NearbyServiceV2 {
  final Nearby _nearby = Nearby();
  final ClusterManager _clusterManager;
  
  // Stream Controllers
  final StreamController<ClusterPacket> _packetController = StreamController<ClusterPacket>.broadcast();
  Stream<ClusterPacket> get packetStream => _packetController.stream;

  NearbyServiceV2(this._clusterManager);

  // 1. Send Capability on Connection
  void onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      // Send my capability immediately
      final myCap = _clusterManager.myCapability;
      sendPacket(endpointId, myCap);
    }
  }

  // 2. Generic Send Packet
  void sendPacket(String endpointId, ClusterPacket packet) {
    final json = packet.toJson();
    final String data = jsonEncode(json);
    _nearby.sendBytesPayload(endpointId, Uint8List.fromList(utf8.encode(data)));
  }

  // 3. Broadcast to All (for Leader)
  void broadcastPacket(ClusterPacket packet, Set<String> connectedPeers) {
    final json = packet.toJson();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    for (final peerId in connectedPeers) {
      _nearby.sendBytesPayload(peerId, bytes);
    }
  }

  // 4. Handle Incoming Payload
  void onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      try {
        final String data = utf8.decode(payload.bytes!);
        final Map<String, dynamic> json = jsonDecode(data);
        
        // Parse using the unified factory
        final packet = ClusterPacket.fromJson(json);
        
        // Add to stream for ClusterManager and FusionEngine to consume
        _packetController.add(packet);
        
      } catch (e) {
        print('Error parsing packet from $endpointId: $e');
      }
    }
  }
}
