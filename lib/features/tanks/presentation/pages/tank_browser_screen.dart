// lib/features/tanks/presentation/pages/tank_browser_screen.dart

import 'dart:async';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/features/admin/services/admin_cloudinary.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'package:lubrication_indicator/features/tanks/presentation/pages/create_tank_screen_main.dart';
import 'package:lubrication_indicator/features/tanks/presentation/widgets/create_tank_qr.dart';
part 'widgets/_fab_sheet.dart';
part 'widgets/_folder_card_content.dart';
part 'widgets/_leaf_card_content.dart';
part 'widgets/_leaf_card_content_state.dart';
part 'widgets/_drag_ghost.dart';
part 'widgets/_printable_qr.dart';
part 'widgets/_loading_pulse.dart';
part 'widgets/_loading_pulse_state.dart';
part 'widgets/_empty_state.dart';
part 'widgets/_back_row.dart';
part 'widgets/_sheet_option.dart';
part 'widgets/_move_target.dart';
part 'widgets/_action_chip.dart';
part 'widgets/_pill.dart';
part 'widgets/_styled_dialog.dart';
part 'widgets/_dark_field.dart';
part 'widgets/_error_text.dart';
part 'tank_browser_screen_state.dart';
part 'tank_browser_models/_drag_payload.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PALETTE
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF080909);
const _kSurface = Color(0xFF0F1012);
const _kCard = Color(0xFF151719);
const _kBorder = Color(0xFF222529);
const _kBorderH = Color(0xFF343840);
const _kCopper = Color(0xFFCB8C3E);
const _kCopperL = Color(0xFFE8A84E);
const _kCopperD = Color(0xFF7A5020);
const _kTeal = Color(0xFF1ABCBD);
const _kText = Color(0xFFEDEBE6);
const _kTextD = Color(0xFFB0AEA9);
const _kSub = Color(0xFF6B7080);
const _kSubL = Color(0xFF464C5C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kPurple = Color(0xFF9B7FE0);
const _kAmber = Color(0xFFD97706);

// ─────────────────────────────────────────────────────────────────────────────
// DRAG PAYLOAD
// ─────────────────────────────────────────────────────────────────────────────
class TankBrowserScreen extends StatefulWidget {
  const TankBrowserScreen({super.key});

  @override
  State<TankBrowserScreen> createState() => _TankBrowserScreenState();
}

