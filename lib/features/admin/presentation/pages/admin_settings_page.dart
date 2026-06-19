import 'package:flutter/material.dart';
import 'package:lubrication_indicator/core/services/app_settings_service.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'report_format_config_screen.dart';

class AdminSettingsPage extends StatefulWidget {
  final Future<void> Function({
    required bool noTimeout,
    required int minutes,
  })? onSettingsSaved;
  final bool canEdit;

  const AdminSettingsPage({
    super.key,
    this.onSettingsSaved,
    this.canEdit = true,
  });

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  bool _loading = true;
  bool _noTimeout = false;
  int _minutes = 60;
  bool _saving = false;
  List<TankModel> _tanks = [];
  final _tankRepo = TankRepository();

  bool _showInspectionValues = true;
  bool _showCompletedAlerts = true;
  bool _showActiveAlerts = true;
  bool _showInspectionCompliance = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final timeout = await AppSettingsService.getSessionTimeout();
    final tanks = await _tankRepo.getAllTanks();
    final dashSettings = await AppSettingsService.getDashboardDisplaySettings();
    if (!mounted) return;
    setState(() {
      _noTimeout = timeout == null;
      _minutes = timeout?.inMinutes ?? 60;
      _tanks = tanks;
      _showInspectionValues = dashSettings['show_inspection_values'] ?? true;
      _showCompletedAlerts = dashSettings['show_completed_alerts'] ?? true;
      _showActiveAlerts = dashSettings['show_active_alerts'] ?? true;
      _showInspectionCompliance = dashSettings['show_inspection_compliance'] ?? true;
      _loading = false;
    });
  }

  String _freqLabel(TankModel t) {
    switch (t.inspectionFrequencyType) {
      case 'weekly_once':
        return 'Weekly once';
      case 'weekly_thrice':
        return 'Weekly thrice';
      case 'custom_days':
        return 'Custom (${t.inspectionFrequencyDays} day${t.inspectionFrequencyDays == 1 ? '' : 's'})';
      default:
        return 'Daily';
    }
  }

  Future<void> _setFreq(TankModel t, String v) async {
    int days = 1;
    if (v == 'weekly_once') days = 7;
    if (v == 'weekly_thrice') days = 2;
    if (v == 'custom_days') {
      final ctrl = TextEditingController(text: t.inspectionFrequencyDays.toString());
      final picked = await showDialog<int>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Custom days'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Days'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, int.tryParse(ctrl.text.trim()) ?? 1),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (picked == null) return;
      days = picked < 1 ? 1 : picked;
    }
    await _tankRepo.updateInspectionFrequency(tankId: t.id, type: v, days: days);
    await _load();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AppSettingsService.setSessionTimeout(
      noTimeout: _noTimeout,
      minutes: _minutes,
    );
    await AppSettingsService.setDashboardDisplaySettings(
      showInspectionValues: _showInspectionValues,
      showCompletedAlerts: _showCompletedAlerts,
      showActiveAlerts: _showActiveAlerts,
      showInspectionCompliance: _showInspectionCompliance,
    );
    await widget.onSettingsSaved?.call(
      noTimeout: _noTimeout,
      minutes: _minutes,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('No Session Timeout'),
            value: _noTimeout,
            onChanged: widget.canEdit ? (v) => setState(() => _noTimeout = v) : null,
          ),
          const SizedBox(height: 8),
          if (!_noTimeout)
            DropdownButtonFormField<int>(
              value: _minutes,
              items: const [
                DropdownMenuItem(value: 60, child: Text('60 minutes')),
                DropdownMenuItem(value: 120, child: Text('120 minutes')),
                DropdownMenuItem(value: 240, child: Text('240 minutes')),
                DropdownMenuItem(value: 480, child: Text('480 minutes')),
                DropdownMenuItem(value: 720, child: Text('720 minutes')),
                DropdownMenuItem(value: 1440, child: Text('1 day')),
              ],
              onChanged: widget.canEdit
                  ? (v) => setState(() => _minutes = v ?? 60)
                  : null,
              // Disabled for view-only settings privilege.
              disabledHint: Text('$_minutes minutes'),
              decoration: const InputDecoration(
                labelText: 'Session timeout',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Dashboard Display Settings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Show Inspection Averages & Last Values'),
            subtitle: const Text('Populates AVG strip and tank stats cards'),
            value: _showInspectionValues,
            onChanged: widget.canEdit
                ? (v) => setState(() => _showInspectionValues = v)
                : null,
          ),
          SwitchListTile(
            title: const Text('Display Alerts (Not Completed)'),
            subtitle: const Text('Populates Active Alerts section'),
            value: _showActiveAlerts,
            onChanged: widget.canEdit
                ? (v) => setState(() => _showActiveAlerts = v)
                : null,
          ),
          SwitchListTile(
            title: const Text('Display Alerts (Completed)'),
            subtitle: const Text('Populates Completed Tasks section'),
            value: _showCompletedAlerts,
            onChanged: widget.canEdit
                ? (v) => setState(() => _showCompletedAlerts = v)
                : null,
          ),
          SwitchListTile(
            title: const Text('Display Inspection Compliance'),
            subtitle: const Text('Populates compliance checklist'),
            value: _showInspectionCompliance,
            onChanged: widget.canEdit
                ? (v) => setState(() => _showInspectionCompliance = v)
                : null,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReportFormatConfigScreen(),
                ),
              );
            },
            icon: const Icon(Icons.edit_document),
            label: const Text('Modify Report Format'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFCB8C3E),
              side: const BorderSide(color: Color(0xFFCB8C3E)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (widget.canEdit && !_saving) ? _save : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save'),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Tank Inspection Frequency'),
          const SizedBox(height: 8),
          ..._tanks.map((t) => ListTile(
                dense: true,
                title: Text('${t.tankName} (${t.tankCode})'),
                subtitle: Text(_freqLabel(t)),
                trailing: DropdownButton<String>(
                  value: t.inspectionFrequencyType,
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly_once', child: Text('Weekly once')),
                    DropdownMenuItem(value: 'weekly_thrice', child: Text('Weekly thrice')),
                    DropdownMenuItem(value: 'custom_days', child: Text('Custom')),
                  ],
                  onChanged: (v) {
                    if (!widget.canEdit) return;
                    if (v == null) return;
                    _setFreq(t, v);
                  },
                ),
              )),
        ],
      ),
    );
  }
}
