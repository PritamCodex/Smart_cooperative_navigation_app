import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/core/models/beacon_packet.dart';
import 'package:cooperative_navigation_safety/src/core/models/sensor_data.dart';
import 'package:cooperative_navigation_safety/src/core/models/collision_alert.dart';
import 'package:cooperative_navigation_safety/src/services/sensor_service.dart';
import 'package:cooperative_navigation_safety/src/services/nearby_service.dart';
import 'package:cooperative_navigation_safety/src/services/collision_engine.dart';
import 'package:cooperative_navigation_safety/src/services/fusion/distributed_fusion_engine.dart';

// Services (keeping old system for now, native Nearby Connections still active)
final fusionEngineProvider = Provider<DistributedFusionEngine>((ref) => DistributedFusionEngine());

final sensorServiceProvider = Provider<SensorService>((ref) {
  final fusionEngine = ref.watch(fusionEngineProvider);
  return SensorService(fusionEngine);
});
final nearbyServiceProvider = Provider<NearbyService>((ref) => NearbyService());
final collisionEngineProvider = Provider<CollisionEngine>((ref) {
  final fusionEngine = ref.watch(fusionEngineProvider);
  return CollisionEngine(fusionEngine);
});

// App state
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier(ref);
});

class AppState {
  final bool isSystemRunning;
  final bool hasPermissions;
  final String mode;
  final String? error;
  
  const AppState({
    this.isSystemRunning = false,
    this.hasPermissions = false,
    this.mode = 'normal',
    this.error,
  });
  
  AppState copyWith({
    bool? isSystemRunning,
    bool? hasPermissions,
    String? mode,
    String? error,
  }) {
    return AppState(
      isSystemRunning: isSystemRunning ?? this.isSystemRunning,
      hasPermissions: hasPermissions ?? this.hasPermissions,
      mode: mode ?? this.mode,
      error: error ?? this.error,
    );
  }
}

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier(Ref ref) : super(const AppState());
  
  void startSystem() {
    state = state.copyWith(isSystemRunning: true, error: null);
  }
  
  void stopSystem() {
    state = state.copyWith(isSystemRunning: false);
  }
  
  void setPermissionsGranted() {
    state = state.copyWith(hasPermissions: true);
  }
  
  void setMode(String mode) {
    state = state.copyWith(mode: mode);
  }
  
  void setError(String error) {
    state = state.copyWith(error: error);
  }
  
  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Sensor data stream
final sensorDataStreamProvider = StreamProvider<SensorData>((ref) {
  final sensorService = ref.watch(sensorServiceProvider);
  return sensorService.sensorStream;
});

// Nearby beacons stream
final beaconStreamProvider = StreamProvider<BeaconPacket>((ref) {
  final nearbyService = ref.watch(nearbyServiceProvider);
  return nearbyService.beaconStream;
});

// Current location provider
final currentLocationProvider = Provider<BeaconPacket?>((ref) {
  final sensorData = ref.watch(sensorDataStreamProvider);
  final appState = ref.watch(appStateProvider);
  
  return sensorData.when(
    data: (data) {
      if (!appState.isSystemRunning) return null;
      
      // Create a BeaconPacket representing the current user
      return BeaconPacket(
        type: 'self',
        ephemeralId: ref.read(nearbyServiceProvider).deviceId,
        timestamp: data.timestamp,
        latitude: data.latitude ?? 0.0,
        longitude: data.longitude ?? 0.0,
        altitude: data.altitude ?? 0.0,
        speed: data.speed ?? 0.0,
        heading: data.heading ?? 0.0,
        velocityX: (data.speed ?? 0.0) * math.sin((data.heading ?? 0.0) * math.pi / 180),
        velocityY: (data.speed ?? 0.0) * math.cos((data.heading ?? 0.0) * math.pi / 180),
        accuracy: data.accuracy ?? 0.0,
        battery: 100,
        mode: appState.mode,
      );
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// Peer beacons provider
final peerBeaconsProvider = StateProvider<List<BeaconPacket>>((ref) => []);

// Collision alerts provider
final collisionAlertsProvider = Provider<List<CollisionAlert>>((ref) {
  final currentLocation = ref.watch(currentLocationProvider);
  final peerBeacons = ref.watch(peerBeaconsProvider);
  final collisionEngine = ref.watch(collisionEngineProvider);
  
  if (currentLocation == null || peerBeacons.isEmpty) {
    return [];
  }
  
  return collisionEngine.processMultiplePeers(currentLocation, peerBeacons);
});

// Critical alert provider
final criticalAlertProvider = Provider<CollisionAlert?>((ref) {
  final alerts = ref.watch(collisionAlertsProvider);
  return alerts.isEmpty ? null : alerts.first;
});

// Connection logs provider
final connectionLogsProvider = StateNotifierProvider<ConnectionLogsNotifier, List<String>>((ref) {
  return ConnectionLogsNotifier(ref);
});

class ConnectionLogsNotifier extends StateNotifier<List<String>> {
  StreamSubscription? _subscription;

  ConnectionLogsNotifier(Ref ref) : super([]) {
    final nearbyService = ref.read(nearbyServiceProvider);
    
    // Load initial logs
    state = [...nearbyService.logs];
    
    _subscription = nearbyService.connectionStream.listen((log) {
      // Keep last 10 logs, newest first
      state = [log, ...state].take(10).toList();
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

// System coordinator
final systemCoordinatorProvider = Provider<SystemCoordinator>((ref) {
  return SystemCoordinator(ref);
});

class SystemCoordinator {
  final Ref _ref;
  StreamSubscription? _sensorSubscription;
  StreamSubscription? _beaconSubscription;
  Timer? _cleanupTimer;
  
  SystemCoordinator(this._ref);
  
  Future<void> initialize() async {
    try {
      final sensorService = _ref.read(sensorServiceProvider);
      final nearbyService = _ref.read(nearbyServiceProvider);
      
      await sensorService.initialize();
      await nearbyService.initialize();
      
      _ref.read(appStateProvider.notifier).setPermissionsGranted();
    } catch (e) {
      _ref.read(appStateProvider.notifier).setError('Failed to initialize: $e');
      rethrow;
    }
  }
  
  void startSystem() {
    final sensorService = _ref.read(sensorServiceProvider);
    final nearbyService = _ref.read(nearbyServiceProvider);
    final appState = _ref.read(appStateProvider);
    
    if (!appState.hasPermissions) {
      _ref.read(appStateProvider.notifier).setError('Permissions not granted');
      return;
    }
    
    // Start sensors
    sensorService.startSensors();
    
    // Start nearby connections
    nearbyService.startNearby();
    
    // Setup beacon timer
    nearbyService.startBeaconTimer(() => _generateBeacon());
    
    // Setup subscriptions
    _setupSubscriptions();
    
    // Start periodic cleanup of stale beacons
    _startCleanupTimer();
    
    _ref.read(appStateProvider.notifier).startSystem();
  }
  
  void stopSystem() {
    final sensorService = _ref.read(sensorServiceProvider);
    final nearbyService = _ref.read(nearbyServiceProvider);
    
    _sensorSubscription?.cancel();
    _beaconSubscription?.cancel();
    _cleanupTimer?.cancel();
    
    sensorService.stopSensors();
    nearbyService.stopNearby();
    
    _ref.read(appStateProvider.notifier).stopSystem();
    _ref.read(peerBeaconsProvider.notifier).state = [];
  }
  
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    // Run cleanup every second to remove stale beacons
    _cleanupTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentPeers = _ref.read(peerBeaconsProvider);
      final now = DateTime.now();
      
      // Remove beacons older than 2 seconds
      final freshPeers = currentPeers.where((p) => 
        now.difference(p.timestamp).inSeconds < 2
      ).toList();
      
      // Only update if changed to avoid unnecessary rebuilds
      if (freshPeers.length != currentPeers.length) {
        _ref.read(peerBeaconsProvider.notifier).state = freshPeers;
      }
    });
  }
  
  void _setupSubscriptions() {
    final sensorService = _ref.read(sensorServiceProvider);
    final nearbyService = _ref.read(nearbyServiceProvider);
    
    // Listen to sensor data
    _sensorSubscription = sensorService.sensorStream.listen(
      (sensorData) {
        // Process sensor data and update current location
        // This would integrate with the beacon generation
      },
      onError: (error) {
        print('Sensor stream error: $error');
        // Don't cancel, stream should auto-recover
      },
    );
    
    // Listen to incoming beacons
    _beaconSubscription = nearbyService.beaconStream.listen(
      (beacon) {
        final currentPeers = _ref.read(peerBeaconsProvider);
        
        // Update or add peer beacon
        final updatedPeers = currentPeers.where((p) => p.ephemeralId != beacon.ephemeralId).toList();
        updatedPeers.add(beacon);
        
        // Remove stale beacons (older than 2 seconds - reduced from 5)
        final now = DateTime.now();
        final freshPeers = updatedPeers.where((p) => 
          now.difference(p.timestamp).inSeconds < 2
        ).toList();
        
        _ref.read(peerBeaconsProvider.notifier).state = freshPeers;
      },
      onError: (error) {
        print('Beacon stream error: $error');
        // Don't cancel subscription, let it auto-recover
      },
      cancelOnError: false, // Keep subscription alive
    );
  }
  
  BeaconPacket _generateBeacon() {
    final appState = _ref.read(appStateProvider);
    final sensorDataValue = _ref.read(sensorDataStreamProvider);
    final nearbyService = _ref.read(nearbyServiceProvider);
    
    final sensorData = sensorDataValue.value;
    
    return BeaconPacket(
      type: 'beacon',
      ephemeralId: nearbyService.deviceId, // Use consistent device ID from nearby service
      timestamp: DateTime.now(),
      latitude: sensorData?.latitude ?? 0.0,
      longitude: sensorData?.longitude ?? 0.0,
      altitude: sensorData?.altitude ?? 0.0,
      speed: sensorData?.speed ?? 0.0,
      heading: sensorData?.heading ?? 0.0,
      velocityX: (sensorData?.speed ?? 0.0) * math.sin((sensorData?.heading ?? 0.0) * math.pi / 180),
      velocityY: (sensorData?.speed ?? 0.0) * math.cos((sensorData?.heading ?? 0.0) * math.pi / 180),
      accuracy: sensorData?.accuracy ?? 0.0,
      battery: 100, // TODO: Get real battery level
      mode: appState.mode,
    );
  }
}