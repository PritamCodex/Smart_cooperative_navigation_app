import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';
import 'package:cooperative_navigation_safety/src/providers/app_providers.dart';
import 'package:cooperative_navigation_safety/src/ui/widgets/glass_card.dart';

class ControlPanel extends ConsumerWidget {
  const ControlPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final systemCoordinator = ref.watch(systemCoordinatorProvider);
    
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CONTROLS',
            style: AppTheme.titleStyle,
          ),
          const SizedBox(height: 16),
          
          // Start/Stop Button
          ElevatedButton.icon(
            onPressed: () {
              if (appState.isSystemRunning) {
                systemCoordinator.stopSystem();
              } else {
                systemCoordinator.startSystem();
              }
            },
            icon: Icon(
              appState.isSystemRunning ? Icons.stop : Icons.play_arrow,
              size: 24,
            ),
            label: Text(
              appState.isSystemRunning ? 'STOP SYSTEM' : 'START SYSTEM',
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: appState.isSystemRunning 
                  ? Colors.white.withOpacity(0.1)
                  : AppTheme.primaryColor,
              foregroundColor: appState.isSystemRunning 
                  ? AppTheme.textPrimary 
                  : Colors.black, // Dark text on bright button
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: appState.isSystemRunning ? 0 : 8,
              shadowColor: AppTheme.primaryColor.withOpacity(0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          
          const SizedBox(height: 16),

          // Calibration Button
          OutlinedButton.icon(
            onPressed: () => _handleCalibration(context),
            icon: const Icon(Icons.compass_calibration, size: 20),
            label: const Text('CALIBRATE SENSORS'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentColor,
              side: const BorderSide(color: AppTheme.accentColor),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              textStyle: AppTheme.labelStyle.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Mode Selection
          Text(
            'OPERATING MODE',
            style: AppTheme.labelStyle.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              _buildModeButton(
                context,
                'NORMAL',
                appState.mode == 'normal',
                () => ref.read(appStateProvider.notifier).setMode('normal'),
              ),
              const SizedBox(width: 12),
              _buildModeButton(
                context,
                'ANCHOR',
                appState.mode == 'anchor',
                () => ref.read(appStateProvider.notifier).setMode('anchor'),
              ),
              const SizedBox(width: 12),
              _buildModeButton(
                context,
                'EMERGENCY',
                appState.mode == 'emergency',
                () => ref.read(appStateProvider.notifier).setMode('emergency'),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Report Incident Button
          OutlinedButton.icon(
            onPressed: () {
              _showReportIncidentDialog(context, ref);
            },
            icon: const Icon(Icons.report_problem, size: 20),
            label: const Text('REPORT INCIDENT'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.warningColor,
              side: const BorderSide(color: AppTheme.warningColor),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              textStyle: AppTheme.labelStyle.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _handleCalibration(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: GlassCard(
          width: 200,
          height: 180,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppTheme.accentColor),
              const SizedBox(height: 20),
              Text(
                'CALIBRATING...',
                style: AppTheme.titleStyle.copyWith(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );

    // Simulate calibration delay
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'SENSORS CALIBRATED',
            style: AppTheme.labelStyle.copyWith(color: Colors.black),
          ),
          backgroundColor: AppTheme.accentColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      );
    });
  }

  Widget _buildModeButton(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onPressed,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.4),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ] : [],
        ),
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: isSelected 
                ? AppTheme.primaryColor 
                : Colors.transparent,
            side: BorderSide(
              color: isSelected 
                  ? AppTheme.primaryColor 
                  : Colors.white12,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: AppTheme.labelStyle.copyWith(
                color: isSelected ? Colors.black : AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showReportIncidentDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Report Incident', style: TextStyle(color: Colors.white)),
          content: const Text(
            'This will immediately broadcast an emergency beacon to all nearby devices. '
            'Continue?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                // Trigger emergency broadcast
                ref.read(appStateProvider.notifier).setMode('emergency');
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Report Emergency'),
            ),
          ],
        );
      },
    );
  }
}