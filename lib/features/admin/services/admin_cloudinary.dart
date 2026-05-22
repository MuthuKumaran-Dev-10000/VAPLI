import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:lubrication_indicator/core/services/env_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cloudinary config (shared across file)
// ─────────────────────────────────────────────────────────────────────────────
const String _folderQr =
    'lubricationindicator_qr'; // same folder as create_tank_screen
const String folderMain =
    'lubricationindicator'; // original folder kept for download share

// ─────────────────────────────────────────────────────────────────────────────
// Cloudinary helpers (module-level, shared by card + duplicate logic)
// ─────────────────────────────────────────────────────────────────────────────
String _cloudSignature(String timestamp, String folder) {
  final params = 'folder=$folder&timestamp=$timestamp';
  return sha1
      .convert(utf8.encode('$params${EnvConfig.cloudinaryApiSecret}'))
      .toString();
}

Future<String> uploadBytesToCloudinary(Uint8List bytes,
    {String folder = _folderQr}) async {
  debugPrint('[Cloudinary] Uploading to folder=$folder bytes=${bytes.length}');
  final dir = await getTemporaryDirectory();
  final file =
      File('${dir.path}/tank_qr_${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes);

  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final req = http.MultipartRequest(
    'POST',
    Uri.parse(
      'https://api.cloudinary.com/v1_1/${EnvConfig.cloudinaryCloudName}/image/upload',
    ),
  );
  req.fields['api_key'] = EnvConfig.cloudinaryApiKey;
  req.fields['timestamp'] = ts;
  req.fields['folder'] = folder;
  req.fields['signature'] = _cloudSignature(ts, folder);
  req.files.add(await http.MultipartFile.fromPath(
    'file',
    file.path,
    contentType: MediaType.parse(lookupMimeType(file.path) ?? 'image/png'),
  ));

  final res = await http.Response.fromStream(await req.send());
  debugPrint(
      '[Cloudinary] Response ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 300))}');
  if (res.statusCode != 200)
    throw Exception('QR upload failed (${res.statusCode})');
  final url = (json.decode(res.body) as Map)['secure_url'] as String;
  debugPrint('[Cloudinary] Uploaded → $url');
  return url;
}

/// Renders a QR from identity data, uploads to Cloudinary, returns the URL.
Future<String> _generateQrAndUpload({
  required ScreenshotController shotCtrl,
  required String tankCode,
  required String tankName,
  required String location,
}) async {
  debugPrint('[QR] Generating QR: code=$tankCode name=$tankName loc=$location');
  final qrData = jsonEncode({
    'tank_code': tankCode,
    'tank_name': tankName,
    'location': location,
  });
  final bytes = await shotCtrl.captureFromWidget(
    Material(color: Colors.white, child: QrImageView(data: qrData, size: 320)),
  );
  debugPrint('[QR] Captured ${bytes.length} bytes');
  return uploadBytesToCloudinary(bytes, folder: _folderQr);
}
