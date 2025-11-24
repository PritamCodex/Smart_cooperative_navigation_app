import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';
import 'package:cooperative_navigation_safety/src/providers/app_providers.dart';
import 'package:cooperative_navigation_safety/src/core/models/collision_alert.dart';
import 'package:cooperative_navigation_safety/src/ui/widgets/glass_card.dart';

class DeveloperPanel extends ConsumerWidget {
  const DeveloperPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensorData = ref.watch(sensorDataStreamProvider);
    final currentLocation = ref.watch(currentLocationProvider);
    final peerBeacons = ref.watch(peerBeaconsProvider);
    final alerts = ref.watch(collisionAlertsProvider);
    final appState = ref.watch(appStateProvider);

    return GlassCard(
      borderColor: AppTheme.warningColor.withOpacity(0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal, color: AppTheme.warningColor, size: 24),
              const SizedBox(width: 12),
              Text(
                'SYSTEM LOGS',
                style: AppTheme.titleStyle.copyWith(
                  color: AppTheme.warningColor,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // System Status
          _buildSection('SYSTEM STATUS', [
            _buildDataRow('SERVICE', appState.isSystemRunning ? 'RUNNING' : 'STOPPED'),
            _buildDataRow('PERMISSIONS', appState.hasPermissions ? 'GRANTED' : 'DENIED'),
            _buildDataRow('MODE', appState.mode.toUpperCase()),
            _buildDataRow('ERROR', appState.error ?? 'NONE'),
          ]),
          
          const SizedBox(height: 16),
          
          // Sensor Data
          _buildSection('SENSOR DATA', [
            sensorData.when(
              data: (data) => Column(
                children: [
                  _buildDataRow('LOCATION', '${data.latitude?.toStringAsFixed(6) ?? 'N/A'}, ${data.longitude?.toStringAsFixed(6) ?? 'N/A'}'),
                  _buildDataRow('SPEED', '${data.speed?.toStringAsFixed(2) ?? 'N/A'} m/s'),
                  _buildDataRow('HEADING', '${data.heading?.toStringAsFixed(1) ?? 'N/A'}°'),
                  _buildDataRow('ACCURACY', '${data.accuracy?.toStringAsFixed(1) ?? 'N/A'}m'),
                ],
              ),
              loading: () => _buildDataRow('STATUS', 'LOADING...'),
              error: (e, _) => _buildDataRow('ERROR', 'FAILED'),
            ),
          ]),
          
          const SizedBox(height: 16),
          
          // Current Beacon
          _buildSection('BEACON OUT', [
            if (currentLocation != null) ...[
              _buildDataRow('ID', currentLocation.ephemeralId.substring(0, 8) + '...'),
              _buildDataRow('POS', '${currentLocation.latitude.toStringAsFixed(6)}, ${currentLocation.longitude.toStringAsFixed(6)}'),
            ] else
              _buildDataRow('STATUS', 'NO DATA'),
          ]),
          
          const SizedBox(height: 16),
          
          // Nearby Peers
          _buildSection('PEERS (${peerBeacons.length})', [
            if (peerBeacons.isEmpty)
              _buildDataRow('STATUS', 'SCANNING...')
            else
              ...peerBeacons.take(3).map((peer) => 
                _buildDataRow(
                  peer.ephemeralId.substring(0, 8),
                  '${peer.latitude.toStringAsFixed(4)}, ${peer.longitude.toStringAsFixed(4)}',
                ),
              ),
          ]),
          
          const SizedBox(height: 16),
          
          // Collision Alerts
          _buildSection('ALERTS (${alerts.length})', [
            if (alerts.isEmpty)
              _buildDataRow('STATUS', 'SAFE')
            else
              ...alerts.take(3).map((alert) {
                return _buildDataRow(
                  alert.peerId.substring(0, 8),
                  '${alert.relativeDistance.toStringAsFixed(1)}m / ${alert.timeToCollision.toStringAsFixed(1)}s',
                  color: alert.level.color,
                );
              }),
          ]),
          
          const SizedBox(height: 16),
          
          // Connection Logs
          _buildSection('CONNECTION LOGS', [
            if (ref.watch(connectionLogsProvider).isEmpty)
              _buildDataRow('LOGS', 'NO ACTIVITY')
            else
              ...ref.watch(connectionLogsProvider).map((log) => 
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '> $log',
                    style: AppTheme.labelStyle.copyWith(fontSize: 11, fontFamily: 'Courier'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  final nearby = ref.read(nearbyServiceProvider);
                  nearby.stopDiscovery();
                  nearby.startDiscovery();
                  nearby.stopAdvertising();
                  nearby.startAdvertising();
                },
                icon: const Icon(Icons.refresh, size: 16, color: AppTheme.errorColor),
                label: Text('RESTART DISCOVERY', style: AppTheme.labelStyle.copyWith(color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  backgroundColor: AppTheme.errorColor.withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.labelStyle.copyWith(
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildDataRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                color: color ?? AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
