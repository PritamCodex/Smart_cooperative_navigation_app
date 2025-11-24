// ignore_for_file: avoid_print, unnecessary_import, constant_identifier_names

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'cluster_manager.dart';
import 'packet_protocol.dart';

/// Handles all Nearby Connections logic on the Flutter side.
/// Acts as the bridge between the Android native layer and the Dart application logic.
class NearbyService {
  static final NearbyService instance = NearbyService._();
  NearbyService._();

  static const MethodChannel _channel = MethodChannel('nearby_connections');

  final ClusterManager _clusterManager = ClusterManager.instance;

  // State
  final Map<String, String> _connectedPeers = {}; // EndpointID -> EndpointName
  final Map<String, int> _disconnectedPeers = {}; // EndpointID -> Retry count
  final Set<String> _reconnectionInProgress = {};
  Timer? _reconnectionTimer;
  
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  String _myDeviceId = 'Unknown';

  final _peersController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get connectedPeersStream => _peersController.stream;
  
  // Reconnection constants
  static const int MAX_RECONNECTION_ATTEMPTS = 5;
  static const Duration INITIAL_RETRY_DELAY = Duration(seconds: 2);
  static const Duration MAX_RETRY_DELAY = Duration(seconds: 60);

  /// Initializes the service and the ClusterManager.
  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
    
    // Get Device ID from native side (or generate one)
    try {
      _myDeviceId = await _channel.invokeMethod('getDeviceId') ?? 'Device_${DateTime.now().millisecondsSinceEpoch}';
    } on PlatformException {
      _myDeviceId = 'Device_${DateTime.now().millisecondsSinceEpoch}';
    }

    print('NearbyService: Initialized with ID $_myDeviceId');

    // Initialize ClusterManager
    await _clusterManager.initialize(_myDeviceId, sendPayload);
  }

  /// Starts advertising this device to nearby peers.
  Future<void> startAdvertising() async {
    if (_isAdvertising) return;
    try {
      await _channel.invokeMethod('startAdvertising', {'deviceName': _myDeviceId});
      _isAdvertising = true;
      print('NearbyService: Advertising started');
    } on PlatformException catch (e) {
      print('NearbyService: Failed to start advertising: ${e.message}');
    }
  }

  /// Starts discovering nearby peers.
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    try {
      await _channel.invokeMethod('startDiscovery');
      _isDiscovering = true;
      print('NearbyService: Discovery started');
    } on PlatformException catch (e) {
      print('NearbyService: Failed to start discovery: ${e.message}');
    }
  }

  /// Stops both advertising and discovery.
  Future<void> stopAll() async {
    try {
      await _channel.invokeMethod('stopAll');
      _isAdvertising = false;
      _isDiscovering = false;
      _connectedPeers.clear();
      _peersController.add([]);
      print('NearbyService: Stopped all');
    } on PlatformException catch (e) {
      print('NearbyService: Failed to stop: ${e.message}');
    }
  }

  /// Sends a packet to a specific peer (or all if broadcast).
  /// Note: Nearby Connections is P2P. "Broadcast" usually means sending to all connected endpoints.
  Future<void> sendPayload(BasePacket packet) async {
    final bytes = PacketCodec.encode(packet);
    
    // If packet is intended for a specific target (e.g. LeaderAlert), we could optimize.
    // But for simplicity, and since we might not know the routing path, we broadcast to all connected peers
    // unless the packet has a specific target logic handled by the caller.
    // However, the `sendPayload` signature here takes a Packet.
    // If the packet is P2P, we should send to one.
    // But `BasePacket` doesn't enforce a target. `LeaderAlertPacket` has `targetPeerId`.
    
    // Strategy: Broadcast to ALL connected peers.
    // The protocol is flood-fill or direct-link.
    // In Star topology (Cluster), usually we send to everyone or just the Leader.
    
    if (_connectedPeers.isEmpty) return;

    for (final endpointId in _connectedPeers.keys) {
      try {
        await _channel.invokeMethod('sendPayload', {
          'endpointId': endpointId,
          'bytes': bytes,
        });
      } on PlatformException catch (e) {
        print('NearbyService: Failed to send to $endpointId: ${e.message}');
      }
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onConnected':
        final String endpointId = call.arguments['endpointId'];
        final String endpointName = call.arguments['endpointName'] ?? 'Unknown';
        _connectedPeers[endpointId] = endpointName;
        _peersController.add(_connectedPeers.keys.toList());
        print('NearbyService: Connected to $endpointId ($endpointName)');
        
        // Send Capability Packet immediately upon connection
        // _clusterManager.sendCapabilityUpdate(); // TODO: Implement this in ClusterManager
        break;

      case 'onDisconnected':
        final String endpointId = call.arguments['endpointId'];
        final String endpointName = _connectedPeers[endpointId] ?? 'Unknown';
        _connectedPeers.remove(endpointId);
        _peersController.add(_connectedPeers.keys.toList());
        print('NearbyService: Disconnected from $endpointId');
        
        // Add to disconnected peers for reconnection attempt
        _disconnectedPeers[endpointId] = 0;
        _attemptReconnection(endpointId, endpointName);
        break;

      case 'onPayloadReceived':
        final String endpointId = call.arguments['endpointId'];
        final Uint8List bytes = call.arguments['bytes'];
        try {
          final packet = PacketCodec.decode(bytes);
          // print('NearbyService: Received ${packet.type} from $endpointId');
          _clusterManager.handlePacket(packet);
        } catch (e) {
          print('NearbyService: Error decoding packet from $endpointId: $e');
        }
        break;
        
      default:
        print('NearbyService: Unknown method ${call.method}');
    }
  }
  
  /// Attempts to reconnect to a disconnected peer with exponential backoff.
  void _attemptReconnection(String endpointId, String endpointName) {
    if (_reconnectionInProgress.contains(endpointId)) {
      return; // Already attempting reconnection
    }
    
    final retryCount = _disconnectedPeers[endpointId] ?? 0;
    if (retryCount >= MAX_RECONNECTION_ATTEMPTS) {
      print('NearbyService: Max reconnection attempts reached for $endpointId');
      _disconnectedPeers.remove(endpointId);
      return;
    }
    
    _reconnectionInProgress.add(endpointId);
    
    // Exponential backoff: 2s, 4s, 8s, 16s, 32s (capped at 60s)
    final delayMs = (INITIAL_RETRY_DELAY.inMilliseconds * (1 << retryCount))
        .clamp(INITIAL_RETRY_DELAY.inMilliseconds, MAX_RETRY_DELAY.inMilliseconds);
    
    print('NearbyService: Reconnecting to $endpointId in ${delayMs}ms (attempt ${retryCount + 1})');
    
    Future.delayed(Duration(milliseconds: delayMs), () async {
      try {
        // Request connection via Android side
        await _channel.invokeMethod('requestConnection', {
          'endpointId': endpointId,
          'endpointName': endpointName,
        });
        
        _disconnectedPeers[endpointId] = retryCount + 1;
      } catch (e) {
        print('NearbyService: Reconnection attempt failed: $e');
        _disconnectedPeers[endpointId] = retryCount + 1;
        
        // Schedule next retry
        _attemptReconnection(endpointId, endpointName);
      } finally {
        _reconnectionInProgress.remove(endpointId);
      }
    });
  }
  
  /// Cleans up all timers and state.
  void dispose() {
    _reconnectionTimer?.cancel();
    _peersController.close();
  }
}
