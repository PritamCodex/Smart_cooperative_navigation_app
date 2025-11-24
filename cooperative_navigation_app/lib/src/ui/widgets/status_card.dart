import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cooperative_navigation_safety/src/core/theme/app_theme.dart';
import 'package:cooperative_navigation_safety/src/providers/app_providers.dart';

import 'package:cooperative_navigation_safety/src/ui/widgets/glass_card.dart';

class StatusCard extends ConsumerWidget {
  const StatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final peerCount = ref.watch(peerBeaconsProvider).length;
    
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SYSTEM STATUS',
            style: AppTheme.titleStyle,
          ),
          const SizedBox(height: 16),
          _buildStatusRow(
            'SERVICE',
            appState.isSystemRunning ? 'ACTIVE' : 'STOPPED',
            appState.isSystemRunning ? AppTheme.accentColor : AppTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            'MODE',
            appState.mode.toUpperCase(),
            AppTheme.primaryColor,
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            'NEARBY',
            peerCount.toString(),
            peerCount > 0 ? AppTheme.accentColor : AppTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            'PERMISSIONS',
            appState.hasPermissions ? 'GRANTED' : 'REQUIRED',
            appState.hasPermissions ? AppTheme.accentColor : AppTheme.warningColor,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: AppTheme.labelStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: valueColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20), // Fluffy pill
            border: Border.all(color: valueColor.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: valueColor.withOpacity(0.2),
                blurRadius: 8,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Text(
            value,
            style: AppTheme.labelStyle.copyWith(
              color: valueColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}