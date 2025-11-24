import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/app.dart';
import 'package:cooperative_navigation_safety/src/ui/screens/main_screen.dart';
import 'package:cooperative_navigation_safety/src/services/sensor_service.dart';
import 'package:cooperative_navigation_safety/src/services/nearby_service.dart';
import 'package:cooperative_navigation_safety/src/providers/app_providers.dart';
import 'package:cooperative_navigation_safety/src/core/models/sensor_data.dart';
import 'package:cooperative_navigation_safety/src/core/models/beacon_packet.dart';

class MockSensorService extends SensorService {
  @override
  Future<void> initialize() async {}

  @override
  Stream<SensorData> get sensorStream => const Stream.empty();
  
  @override
  void startSensors() {}
  
  @override
  void stopSensors() {}
}

class MockNearbyService extends NearbyService {
  @override
  Future<void> initialize() async {}

  @override
  Stream<BeaconPacket> get beaconStream => const Stream.empty();

  @override
  String get deviceId => 'test_device_id';
  
  @override
  void startNearby() {}
  
  @override
  void stopNearby() {}
  
  @override
  void startBeaconTimer(BeaconPacket Function() beaconGenerator) {}
}

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensorServiceProvider.overrideWithValue(MockSensorService()),
          nearbyServiceProvider.overrideWithValue(MockNearbyService()),
        ],
        child: const CooperativeNavigationApp(),
      ),
    );
    
    // Allow the async initialization to complete
    await tester.pumpAndSettle();

    expect(find.byType(MainScreen), findsOneWidget);
  });
}
