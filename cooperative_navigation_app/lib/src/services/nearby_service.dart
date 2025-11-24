import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:cooperative_navigation_safety/src/core/models/beacon_packet.dart';
import 'package:location/location.dart';

class NearbyService {
  static const String _serviceId = 'cooperative_navigation_safety';
  static const MethodChannel _mainChannel = MethodChannel('cooperative_navigation_safety/main');
  
  // Use our custom native implementation instead of buggy plugin
  static const MethodChannel _nearbyChannel = MethodChannel('nearby_connections');
  
  final String _deviceId = const Uuid().v4();
  
  final StreamController<BeaconPacket> _beaconController = StreamController<BeaconPacket>.broadcast();
  final StreamController<String> _peerController = StreamController<String>.broadcast();
  final StreamController<String> _connectionController = StreamController<String>.broadcast();
  final List<String> _logBuffer = [];
  
  Stream<BeaconPacket> get beaconStream => _beaconController.stream;
  Stream<String> get peerStream => _peerController.stream;
  Stream<String> get connectionStream => _connectionController.stream;
  List<String> get logs => List.unmodifiable(_logBuffer);
  
  void _log(String message) {
    _logBuffer.insert(0, message); // Add to start
    if (_logBuffer.length > 50) _logBuffer.removeLast();
    _connectionController.add(message);
  }
  
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  final Set<String> _connectedPeers = {};
  Timer? _beaconTimer;
  Timer? _watchdogTimer;
  int _discoveryRetries = 0;
  int _advertisingRetries = 0;
  static const int _maxRetries = 5;
  
  String get deviceId => _deviceId;
  
  Future<void> initialize() async {
    try {
      _log('🚀 Initializing Nearby Service with native implementation...');
      
      // Setup method call handler for callbacks from native side
      _nearbyChannel.setMethodCallHandler(_handleNativeCallback);
      
      // 1. Request permissions
      try {
        await _mainChannel.invokeMethod('requestPermissions');
        _log('✅ Permissions requested');
      } catch (e) {
        _log('⚠️ Permission request failed: $e');
      }

      // 2. Ensure Location Service is enabled
      final location = Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          _log('❌ Location service not enabled');
        } else {
          _log('✅ Location service enabled');
        }
      } else {
        _log('✅ Location already enabled');
      }
      
      _log('✅ Nearby Service initialized successfully');
    } catch (e) {
      _log('❌ Initialization error: $e');
    }
  }
  
  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onConnected':
        final endpointId = call.arguments['endpointId'] as String;
        final endpointName = call.arguments['endpointName'] as String? ?? 'Unknown';
        _connectedPeers.add(endpointId);
        _log('✅ CONNECTED: $endpointName');
        _peerController.add('Connected: $endpointName');
        break;
        
      case 'onDisconnected':
        final endpointId = call.arguments['endpointId'] as String;
        _connectedPeers.remove(endpointId);
        _log('⚠️ Disconnected: ${endpointId.substring(0, 8)}...');
        break;
        
      case 'onPayloadReceived':
        final endpointId = call.arguments['endpointId'] as String;
        final bytes = call.arguments['bytes'] as Uint8List;
        _handleRawPayload(endpointId, bytes);
        break;
        
      default:
        _log('⚠️ Unknown callback: ${call.method}');
    }
  }
  
  void _handleRawPayload(String endpointId, Uint8List bytes) {
    try {
      final decoded = utf8.decode(bytes);
      final json = jsonDecode(decoded);
      final packet = BeaconPacket.fromJson(json);
      _beaconController.add(packet);
      _log('📦 Packet from ${packet.ephemeralId.substring(0, 8)}');
    } catch (e) {
      _log('❌ Payload decode error: $e');
    }
  }
  
  void startNearby() {
    startAdvertising();
    startDiscovery();
    _startWatchdog();
  }
  
  void stopNearby() {
    _stopWatchdog();
    stopAdvertising();
    stopDiscovery();
    stopBeaconTimer();
    disconnectFromAllPeers();
    _discoveryRetries = 0;
    _advertisingRetries = 0;
  }
  
  Future<void> startAdvertising() async {
    if (_isAdvertising) {
      _log('⚠️ Already advertising, skipping');
      return;
    }
    
    if (_advertisingRetries >= _maxRetries) {
      _log('❌ MAX RETRIES REACHED - Check permissions & settings!');
      _log('📝 Ensure: Location ON, Bluetooth ON, All permissions granted');
      return;
    }
    
    _log('📡 Starting advertising (native, attempt ${_advertisingRetries + 1}/$_maxRetries)...');
    
    try {
      // Call our native ConnectivityService
      await _nearbyChannel.invokeMethod('startAdvertising', {
        'deviceName': _deviceId,
      });
      
      _isAdvertising = true;
      _advertisingRetries = 0;
      _log('✅ ADVERTISING ACTIVE (native)');
      
      // Also acquire stability locks
      try {
        await _nearbyChannel.invokeMethod('requestBatteryExemption');
      } catch (e) {
        _log('⚠️ Battery exemption: $e');
      }
      
    } on PlatformException catch (e) {
      _log('❌ Platform error: ${e.code} - ${e.message}');
      _log('💡 Check: Settings > Apps > This App > Permissions');
      _advertisingRetries++;
      _retryAdvertising();
    } catch (e) {
      _log('❌ Unexpected error: ${e.toString()}');
      _advertisingRetries++;
      _retryAdvertising();
    }
  }
  
  void _retryAdvertising() {
    if (_advertisingRetries >= _maxRetries) {
      _log('⛔ Advertising retry limit reached');
      return;
    }
    final delay = Duration(seconds: math.min(_advertisingRetries * 2, 10));
    _log('🔄 Retry advertising in ${delay.inSeconds}s...');
    Future.delayed(delay, () {
      if (!_isAdvertising) startAdvertising();
    });
  }
  
  void stopAdvertising() {
    if (!_isAdvertising) return;
    try {
      _nearbyChannel.invokeMethod('stopAll');
      _isAdvertising = false;
      _log('🛑 Advertising stopped');
    } catch (e) {
      _log('❌ Stop advertising error: $e');
    }
  }
  
  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      _log('⚠️ Already discovering, skipping');
      return;
    }
    
    if (_discoveryRetries >= _maxRetries) {
      _log('❌ MAX DISCOVERY RETRIES - Check permissions!');
      _log('📝 Required: Location ON, Bluetooth ON, Nearby permissions');
      return;
    }
    
    _log('🔍 Starting discovery (native, attempt ${_discoveryRetries + 1}/$_maxRetries)...');
    
    try {
      // Call our native ConnectivityService
      await _nearbyChannel.invokeMethod('startDiscovery');
      
      _isDiscovering = true;
      _discoveryRetries = 0;
      _log('✅ DISCOVERY ACTIVE (native) - Scanning for peers...');
      
    } on PlatformException catch (e) {
      _log('❌ Platform error: ${e.code} - ${e.message}');
      if (e.code == 'BLUETOOTH_OFF') {
        _log('💡 Turn ON Bluetooth in device settings');
      } else if (e.code == 'LOCATION_OFF') {
        _log('💡 Turn ON Location in device settings');
      } else {
        _log('💡 Check app permissions in Settings');
      }
      _discoveryRetries++;
      _retryDiscovery();
    } catch (e) {
      _log('❌ Discovery error: ${e.toString()}');
      _discoveryRetries++;
      _retryDiscovery();
    }
  }
  
  void _retryDiscovery() {
    if (_discoveryRetries >= _maxRetries) {
      _log('⛔ Discovery retry limit reached');
      return;
    }
    final delay = Duration(seconds: math.min(_discoveryRetries * 2, 10));
    _log('🔄 Retry discovery in ${delay.inSeconds}s...');
    Future.delayed(delay, () {
      if (!_isDiscovering) startDiscovery();
    });
  }
  
  void _startWatchdog() {
    _stopWatchdog();
    // Check every 15 seconds if discovery/advertising is stuck
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!_isAdvertising && !_isDiscovering) {
        _log('Watchdog: Both advertising and discovery stopped, restarting...');
        startAdvertising();
        startDiscovery();
      } else if (_connectedPeers.isEmpty && _isDiscovering && _isAdvertising) {
        // If no peers after 30 seconds, restart discovery
        if (_discoveryRetries < 2) {
          _log('Watchdog: No peers found, recycling discovery...');
          stopDiscovery();
          Future.delayed(const Duration(seconds: 2), () => startDiscovery());
        }
      }
    });
  }
  
  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }
  
  void stopDiscovery() {
    if (!_isDiscovering) return;
    // stopAll handles both
    _isDiscovering = false;
    _log('🛑 Discovery stopped');
  }
  
  void startBeaconTimer(BeaconPacket Function() beaconGenerator) {
    stopBeaconTimer();
    
    _beaconTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      // Always generate and broadcast beacons, even if no peers yet
      // This ensures beacons are ready when peers connect
      final beacon = beaconGenerator();
      broadcastBeacon(beacon);
    });
  }
  
  void stopBeaconTimer() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
  }
  
  void broadcastBeacon(BeaconPacket beacon) {
    final bytes = utf8.encode(jsonEncode(beacon.toJson()));
    
    for (final peerId in _connectedPeers) {
      try {
        _nearbyChannel.invokeMethod('sendPayload', {
          'endpointId': peerId,
          'bytes': bytes,
        });
      } catch (e) {
        _log('❌ Send failed to $peerId: $e');
      }
    }
  }
  
  void _handlePayload(String endpointId, Uint8List bytes) {
    // This is actually handled by _handleRawPayload now
    // Keep for compatibility
  }
  
  void disconnectFromAllPeers() {
    try {
      _nearbyChannel.invokeMethod('stopAll');
      _connectedPeers.clear();
      _log('🛑 Disconnected all peers');
    } catch (e) {
      _log('❌ Disconnect error: $e');
    }
  }
  
  void dispose() {
    stopNearby();
    _beaconController.close();
    _peerController.close();
    _connectionController.close();
  }
}