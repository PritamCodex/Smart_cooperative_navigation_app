import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';
import 'package:cooperative_navigation_safety/src/providers/app_providers.dart';
import 'package:cooperative_navigation_safety/src/ui/widgets/radar_widget.dart';
import 'package:cooperative_navigation_safety/src/ui/widgets/developer_panel.dart';
import 'package:cooperative_navigation_safety/src/ui/widgets/alert_banner.dart';
import 'package:cooperative_navigation_safety/src/ui/widgets/status_card.dart';
import 'package:cooperative_navigation_safety/src/ui/widgets/control_panel.dart';
import 'package:cooperative_navigation_safety/src/core/config/feature_flags.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _initialized = false;
  bool _showDevPanel = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final systemCoordinator = ref.read(systemCoordinatorProvider);
      
      // Add timeout to prevent infinite waiting
      await systemCoordinator.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Initialization timeout - continuing anyway');
        },
      );
      
      setState(() {
        _initialized = true;
      });
    } catch (e) {
      print('Initialization error: $e');
      // Still mark as initialized so app can show - permissions can be requested later
      setState(() {
        _initialized = true;
      });
      ref.read(appStateProvider.notifier).setError('Initialization failed: $e. Please grant permissions manually.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    
    return Scaffold(
      extendBodyBehindAppBar: true, // Allow body to go behind AppBar
      appBar: AppBar(
        title: const Text('Cooperative Navigation Safety'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTheme.headerStyle.copyWith(
          fontSize: 20, 
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
        actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  _showSettingsDialog(context);
                },
              ),
              IconButton(
                icon: Icon(Icons.developer_mode,
                    color: _showDevPanel ? AppTheme.accentColor : Colors.white54),
                onPressed: () {
                  setState(() => _showDevPanel = !_showDevPanel);
                },
              ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F111A), // Deep Navy
              Color(0xFF1A1F35), // Lighter Navy
              Color(0xFF0F111A), // Deep Navy
            ],
          ),
        ),
        child: SafeArea(
          child: _initialized 
              ? _buildMainContent(context, appState)
              : _buildLoadingScreen(),
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, AppState appState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20), // Increased padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Alert Banner
          const AlertBanner(),
          const SizedBox(height: 20),
          
          // GPS Unstable Banner
          if (FeatureFlags.FEATURE_GPS_UNSTABLE_UI && 
              ref.watch(sensorDataStreamProvider).valueOrNull?.accuracy != null && 
              ref.watch(sensorDataStreamProvider).valueOrNull!.accuracy! > 20.0)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.warningColor.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.warningColor.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.gps_off, color: AppTheme.warningColor, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Low GPS Accuracy — Using fallback',
                      style: AppTheme.labelStyle.copyWith(
                        color: AppTheme.warningColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Radar Visualization
          const RadarWidget(),
          const SizedBox(height: 20),
          if (_showDevPanel) const DeveloperPanel(),
          if (_showDevPanel) const SizedBox(height: 20),
          
          // Status and Controls Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              const Expanded(
                flex: 2,
                child: StatusCard(),
              ),
              const SizedBox(width: 20),
              
              // Control Panel
              const Expanded(
                flex: 3,
                child: ControlPanel(),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Error Display
          if (appState.error != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.errorColor),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.errorColor.withOpacity(0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: AppTheme.errorColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      appState.error!,
                      style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.errorColor),
                    onPressed: () {
                      ref.read(appStateProvider.notifier).clearError();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppTheme.accentColor,
          ),
          SizedBox(height: 20),
          Text(
            'Initializing Cooperative Navigation Safety...',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Settings'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Beacon Interval: 300ms'),
              Text('Radar Update: 60 FPS'),
              Text('Max Range: 50m'),
              Text('Collision Threshold: 2s TTC'),
              SizedBox(height: 16),
              Text('App Version: 1.0.0'),
              Text('Android 14 Compatible'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}