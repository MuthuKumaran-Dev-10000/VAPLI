// admin_panel_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// CHANGES vs previous version:
//   ✅ Each tank card now has 4 actions: Duplicate | Modify | Download | Delete
//   ✅ Duplicate: copies all fields + properties, auto-names code as "X (1)" "(2)"…
//   ✅ Duplicate/Modify: if tank_code, tank_name, or location changed → new QR
//       generated, uploaded to Cloudinary, stored in Firebase, shown in card
//   ✅ Full debug prints on every action for easy terminal tracing
//   ✅ Users tab untouched
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/tank_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/tank_repository.dart';

// import 'create_tank_screen.dart';
// import 'package:lubrication_indicator/presentation/screens/admin/create_tank_screen.dart';
import 'admin_cloudinary.dart';
import 'admin_login.dart';
import 'admin_dashboard.dart';
import 'admin_tank_card.dart';
import 'admin_action_bar.dart';
import 'admin_user_dialogs.dart';

import 'create_tank_screen_main.dart';
