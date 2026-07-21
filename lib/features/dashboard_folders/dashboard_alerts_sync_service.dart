// lib/features/dashboard_folders/dashboard_alerts_sync_service.dart

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'dashboard_alerts_display_model.dart';

class DashboardAlertsSyncService {
  static final DatabaseReference _dbRef =
      DatabaseModeService.ref('Dashboard_Alerts_display');

  static final DatabaseReference _completedDbRef =
      DatabaseModeService.ref('Dashboard_Alerts_completed');

  /// Compare live active alerts with stored folders metadata and perform updates if changes are detected.
  static Future<List<AlertFolderGroup>> syncAndGetFolders(
      List<DashboardAlertDisplayItem> liveActiveAlerts) async {
    try {
      final metaSnap = await _dbRef.child('metadata').get();
      
      String lastUpdatedDb = '';
      int totalActiveDb = 0;

      if (metaSnap.exists && metaSnap.value != null) {
        final meta = Map<dynamic, dynamic>.from(metaSnap.value as Map);
        lastUpdatedDb = meta['last_updated_timestamp']?.toString() ?? '';
        totalActiveDb = meta['total_active_alerts'] as int? ?? 0;
      }

      String latestLiveTimestamp = '';
      for (final a in liveActiveAlerts) {
        if (a.timestamp.compareTo(latestLiveTimestamp) > 0) {
          latestLiveTimestamp = a.timestamp;
        }
      }

      final bool needsRecalc = metaSnap.value == null ||
          latestLiveTimestamp.compareTo(lastUpdatedDb) > 0 ||
          liveActiveAlerts.length != totalActiveDb;

      if (needsRecalc) {
        debugPrint('[AlertsSync] Syncing active folders in DB. Live count: ${liveActiveAlerts.length}');
        final folders = _calculateFolders(liveActiveAlerts);
        
        await _dbRef.set({
          'metadata': {
            'last_updated_timestamp': latestLiveTimestamp.isEmpty
                ? DateTime.now().toIso8601String()
                : latestLiveTimestamp,
            'total_active_alerts': liveActiveAlerts.length,
          },
          'folders': folders.map((f) => f.toMap()).toList(),
        });
        return folders;
      } else {
        final foldersSnap = await _dbRef.child('folders').get();
        if (foldersSnap.exists && foldersSnap.value != null) {
          final rawList = foldersSnap.value as List;
          return rawList
              .map((item) => AlertFolderGroup.fromMap(
                  Map<dynamic, dynamic>.from(item as Map)))
              .toList();
        }
        return _calculateFolders(liveActiveAlerts);
      }
    } catch (e, stack) {
      debugPrint('[AlertsSync Error] $e\n$stack');
      return _calculateFolders(liveActiveAlerts);
    }
  }

  /// Compare live completed alerts with stored completed folders metadata and perform updates.
  static Future<List<AlertFolderGroup>> syncAndGetCompletedFolders(
      List<DashboardAlertDisplayItem> liveCompletedAlerts) async {
    try {
      final metaSnap = await _completedDbRef.child('metadata').get();
      
      String lastUpdatedDb = '';
      int totalCompletedDb = 0;

      if (metaSnap.exists && metaSnap.value != null) {
        final meta = Map<dynamic, dynamic>.from(metaSnap.value as Map);
        lastUpdatedDb = meta['last_updated_timestamp']?.toString() ?? '';
        totalCompletedDb = meta['total_completed_alerts'] as int? ?? 0;
      }

      String latestLiveTimestamp = '';
      for (final a in liveCompletedAlerts) {
        if (a.timestamp.compareTo(latestLiveTimestamp) > 0) {
          latestLiveTimestamp = a.timestamp;
        }
      }

      final bool needsRecalc = metaSnap.value == null ||
          latestLiveTimestamp.compareTo(lastUpdatedDb) > 0 ||
          liveCompletedAlerts.length != totalCompletedDb;

      if (needsRecalc) {
        debugPrint('[AlertsSync] Syncing completed folders in DB. Live count: ${liveCompletedAlerts.length}');
        final folders = _calculateFolders(liveCompletedAlerts);
        
        await _completedDbRef.set({
          'metadata': {
            'last_updated_timestamp': latestLiveTimestamp.isEmpty
                ? DateTime.now().toIso8601String()
                : latestLiveTimestamp,
            'total_completed_alerts': liveCompletedAlerts.length,
          },
          'folders': folders.map((f) => f.toMap()).toList(),
        });
        return folders;
      } else {
        final foldersSnap = await _completedDbRef.child('folders').get();
        if (foldersSnap.exists && foldersSnap.value != null) {
          final rawList = foldersSnap.value as List;
          return rawList
              .map((item) => AlertFolderGroup.fromMap(
                  Map<dynamic, dynamic>.from(item as Map)))
              .toList();
        }
        return _calculateFolders(liveCompletedAlerts);
      }
    } catch (e, stack) {
      debugPrint('[AlertsSync Completed Error] $e\n$stack');
      return _calculateFolders(liveCompletedAlerts);
    }
  }

  static String _cleanParamLabel(String label) {
    var l = label.trim();
    if (l.startsWith('.')) {
      l = l.substring(1).trim();
    }
    if (l.isEmpty || l.toLowerCase() == 'general' || l == '.') {
      return 'System Alert';
    }
    return l;
  }

  static String _cleanAssetName(String name, String code, String id) {
    final n = name.trim();
    if (n.isEmpty || n.toLowerCase() == 'unknown asset' || n == '.') {
      return 'Asset ${code.trim().isNotEmpty ? code.trim() : id}';
    }
    return n;
  }

  /// Locally computes the folder hierarchy: Parameter Name -> Asset -> Alerts list
  static List<AlertFolderGroup> _calculateFolders(
      List<DashboardAlertDisplayItem> alerts) {
    if (alerts.isEmpty) return [];

    // Group alerts by ParamLabel (Sanitized)
    final Map<String, List<DashboardAlertDisplayItem>> paramGroups = {};
    for (final a in alerts) {
      final label = _cleanParamLabel(a.paramLabel);
      paramGroups.putIfAbsent(label, () => []).add(a);
    }

    final List<AlertFolderGroup> folderGroups = [];

    for (final entry in paramGroups.entries) {
      final paramName = entry.key;
      final paramAlerts = entry.value;

      // Group these param alerts by Asset (tankId)
      final Map<String, List<DashboardAlertDisplayItem>> assetGroups = {};
      for (final a in paramAlerts) {
        assetGroups.putIfAbsent(a.tankId, () => []).add(a);
      }

      final List<AssetFolderGroup> assets = [];
      for (final assetEntry in assetGroups.entries) {
        final firstAlert = assetEntry.value.first;
        final assetAlerts = assetEntry.value;

        // Sort alerts within the asset folder by rankScore (descending) and then time
        assetAlerts.sort((a, b) {
          final rankCompare = b.rankScore.compareTo(a.rankScore);
          if (rankCompare != 0) return rankCompare;
          return b.timestamp.compareTo(a.timestamp); // Newest first
        });

        final cleanedAssetName = _cleanAssetName(
          firstAlert.tankName,
          firstAlert.tankCode,
          firstAlert.tankId,
        );

        assets.add(AssetFolderGroup(
          tankId: assetEntry.key,
          tankName: cleanedAssetName,
          tankCode: firstAlert.tankCode,
          alerts: assetAlerts,
          alertCount: assetAlerts.length,
        ));
      }

      // Sort assets by max rankScore and then latest timestamp
      assets.sort((a, b) {
        final aMaxRank = _getGroupMaxRank(a.alerts);
        final bMaxRank = _getGroupMaxRank(b.alerts);
        final rankCompare = bMaxRank.compareTo(aMaxRank);
        if (rankCompare != 0) return rankCompare;

        final aLatest = _getLatestTimestamp(a.alerts);
        final bLatest = _getLatestTimestamp(b.alerts);
        return bLatest.compareTo(aLatest);
      });

      folderGroups.add(AlertFolderGroup(
        paramLabel: paramName,
        assets: assets,
        totalAlerts: paramAlerts.length,
        totalAssets: assets.length,
      ));
    }

    // Sort top-level parameter folders by max rankScore and latest timestamp
    folderGroups.sort((a, b) {
      final aAllAlerts = a.assets.expand((asset) => asset.alerts).toList();
      final bAllAlerts = b.assets.expand((asset) => asset.alerts).toList();

      final aMaxRank = _getGroupMaxRank(aAllAlerts);
      final bMaxRank = _getGroupMaxRank(bAllAlerts);
      final rankCompare = bMaxRank.compareTo(aMaxRank);
      if (rankCompare != 0) return rankCompare;

      final aLatest = _getLatestTimestamp(aAllAlerts);
      final bLatest = _getLatestTimestamp(bAllAlerts);
      return bLatest.compareTo(aLatest);
    });

    return folderGroups;
  }

  static int _getGroupMaxRank(List<DashboardAlertDisplayItem> alerts) {
    if (alerts.isEmpty) return 0;
    int maxRank = 0;
    for (final a in alerts) {
      if (a.rankScore > maxRank) {
        maxRank = a.rankScore;
      }
    }
    return maxRank;
  }

  static int _sevOrder(String sev) {
    switch (sev.toLowerCase()) {
      case 'critical':
        return 0;
      case 'warning':
        return 1;
      case 'info':
        return 2;
      default:
        return 3;
    }
  }

  static String _getGroupMaxSeverity(List<DashboardAlertDisplayItem> alerts) {
    if (alerts.isEmpty) return 'info';
    bool hasWarning = false;
    for (final a in alerts) {
      final s = a.severity.toLowerCase();
      if (s == 'critical') return 'critical';
      if (s == 'warning') hasWarning = true;
    }
    return hasWarning ? 'warning' : 'info';
  }

  static String _getLatestTimestamp(List<DashboardAlertDisplayItem> alerts) {
    if (alerts.isEmpty) return '';
    String latest = '';
    for (final a in alerts) {
      if (a.timestamp.compareTo(latest) > 0) {
        latest = a.timestamp;
      }
    }
    return latest;
  }
}
