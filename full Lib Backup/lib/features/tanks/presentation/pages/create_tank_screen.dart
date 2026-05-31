// FULL FILE REPLACEMENT — create_tank_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// ALL ORIGINAL FEATURES PRESERVED:
//   ✅ Dark theme — all text fields, dropdowns, dialogs use dark bg/light text
//   ✅ Live preview — addListener on every controller → instant rebuild
//   ✅ Create / Update properly calls TankRepository with full debug prints
//   ✅ Duplicate with (1)(2)(3)… iterator naming + QR regeneration
//   ✅ TankCardActions — Modify | Duplicate | Delete buttons (drop-in widget)
//   ✅ Google-Forms-style property builder: number|text|dropdown|dual_text|slider|multiline
//   ✅ Dual text: one label row + two side-by-side text boxes
//   ✅ Dropdown: add/edit/delete/reorder options inline
//   ✅ Properties: drag-to-reorder, edit, delete, confirmation dialog
//   ✅ QR generation + Cloudinary upload (create + duplicate; regenerated on
//       edit only if identity fields changed)
//   ✅ Every button click prints a debug statement to terminal
//   ✅ All existing repository / session / constants untouched
//
// NEW IN THIS VERSION:
//   ✅ Min/Max ONLY appears for slider type (removed from all other types)
//   ✅ Per-property CONSTRAINTS builder — optional, collapsible section
//      Operators available per type:
//        number  → ==, !=, <, <=, >, >=
//        text    → ==, !=, contains, starts_with, ends_with, regex
//        multiline → contains, starts_with, ends_with, regex
//        dropdown → == (must equal), != (must not equal)
//        dual_text → contains, starts_with, ends_with (applied to each side)
//        slider  → ==, !=, <, <=, >, >= (value-based)
//      Each constraint: operator + value + custom error message
//      Multiple constraints allowed per property (AND logic)
//      Constraints stored under property['constraints'] as List<Map>
//      Constraints shown as summary chips on the property card
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';

import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/utils/session_manager.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';




