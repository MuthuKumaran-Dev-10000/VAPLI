import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';

import 'package:lubrication_indicator/features/tanks/presentation/pages/create_tank_screen_main.dart';
import 'package:lubrication_indicator/features/tanks/presentation/widgets/create_tank_screen_helpers.dart';
import 'package:lubrication_indicator/features/tanks/presentation/widgets/types_and_small_widgets.dart';

const _kBg = Color(0xFF0C0D0F);

const _kSurface = Color(0xFF141618);

const _kCard = Color(0xFF1A1C20);

// Accent (teal/live data)
const _kAccent = Color(0xFF1ABCBD);

// Border
const _kBorder = Color(0xFF252830);

// Text
const _kText = Color(0xFFF0EEE9);

const _kSub = Color(0xFF8A8F9C);

// States
const _kSuccess = Color(0xFF22C55E);

const _kWarn = Color(0xFFF59E0B);

const _kDanger = Color(0xFFEF4444);
// ─────────────────────────────────────────────────────────────────────────────
// TankCardActions  ──  drop-in widget for the tanks list / panel screen
//
// Shows:  [Modify]  [Duplicate]  [Delete]
//
// USAGE (drop this into your tank list row / card):
//
//   TankCardActions(
//     tank: tankMap,
//     allExistingCodes: _tanks.map((t) => t['tank_code'] as String).toList(),
//     onDeleted: _loadTanks,
//     onChanged: _loadTanks,
//   )
//
// Place this next to your existing Download and Delete buttons.
// ─────────────────────────────────────────────────────────────────────────────

class TankCardActions extends StatelessWidget {
  final Map<String, dynamic> tank;
  final List<String> allExistingCodes;
  final VoidCallback onDeleted;
  final VoidCallback onChanged;

  const TankCardActions({
    super.key,
    required this.tank,
    required this.allExistingCodes,
    required this.onDeleted,
    required this.onChanged,
  });

  String _nextFreeCode(String base) {
    final stripped = base.replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim();
    for (int i = 1; i <= 99; i++) {
      final candidate = '$stripped ($i)';
      if (!allExistingCodes.contains(candidate)) return candidate;
    }
    return '$stripped (${DateTime.now().millisecondsSinceEpoch})';
  }

  Future<void> _openModify(BuildContext ctx) async {
    debugPrint('[TankCardActions] Modify tapped — tank=${tank['tank_code']}');
    final safeTank = deepCast(tank) as Map<String, dynamic>;
    final ok = await Navigator.push<bool>(
      ctx,
      MaterialPageRoute(
          builder: (_) => CreateTankScreen(existingTank: safeTank)),
    );
    debugPrint('[TankCardActions] Modify returned: ok=$ok');
    if (ok == true) onChanged();
  }

  Future<void> _openDuplicate(BuildContext ctx) async {
    debugPrint(
        '[TankCardActions] Duplicate tapped — original=${tank['tank_code']}');
    final newCode = _nextFreeCode(tank['tank_code'] as String);
    debugPrint('[TankCardActions] New duplicate code will be: $newCode');
    final dup = (deepCast(tank) as Map<String, dynamic>)
      ..['tank_code'] = newCode
      ..remove('id');

    final ok = await Navigator.push<bool>(
      ctx,
      MaterialPageRoute(
        builder: (_) => CreateTankScreen(existingTank: dup, isDuplicate: true),
      ),
    );
    debugPrint('[TankCardActions] Duplicate returned: ok=$ok');
    if (ok == true) onChanged();
  }

  Future<void> _confirmDelete(BuildContext ctx) async {
    debugPrint('[TankCardActions] Delete tapped — tank=${tank['tank_code']}');
    final yes = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Delete Tank',
            style:
                GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600)),
        content: Text('Delete "${tank['tank_name']}"? This cannot be undone.',
            style: const TextStyle(color: _kSub)),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('[TankCardActions] Delete cancelled');
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancel', style: TextStyle(color: _kSub)),
          ),
          TextButton(
            onPressed: () {
              debugPrint('[TankCardActions] Delete confirmed');
              Navigator.pop(ctx, true);
            },
            child: const Text('Delete', style: TextStyle(color: _kDanger)),
          ),
        ],
      ),
    );

    if (yes == true) {
      debugPrint(
          '[TankCardActions] Calling TankRepository.deleteTank id=${tank['id']}');
      await TankRepository().deleteTank(tank['id']);
      debugPrint('[TankCardActions] deleteTank SUCCESS — calling onDeleted()');
      onDeleted();
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Btn(
          icon: Icons.edit_outlined,
          label: 'Modify',
          color: _kAccent,
          onTap: () => _openModify(ctx),
        ),
        const SizedBox(width: 8),
        Btn(
          icon: Icons.copy_outlined,
          label: 'Duplicate',
          color: _kWarn,
          onTap: () => _openDuplicate(ctx),
        ),
        const SizedBox(width: 8),
        Btn(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: _kDanger,
          onTap: () => _confirmDelete(ctx),
        ),
      ],
    );
  }
}
