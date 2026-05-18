import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:flutter/material.dart';
import 'create_tank_screen.dart';
// ── Cloudinary helpers ─────────────────────────────────────────────────────

final _qrShot = ScreenshotController();

// Cloudinary credentials
const _cloudName = 'dummy-cloudinary-cloud-name';
const _apiKey = 'dummy-cloudinary-api-key';
const _apiSecret = 'dummy-cloudinary-api-secret';
const _folder = 'lubricationindicator_qr';

String _signature(String timestamp) {
  final params = 'folder=$_folder&timestamp=$timestamp';
  return sha1.convert(utf8.encode('$params$_apiSecret')).toString();
}

Future<String> _uploadQr(Uint8List bytes) async {
  debugPrint('[QR] Uploading QR image to Cloudinary…');
  final dir = await getTemporaryDirectory();
  final file =
      File('${dir.path}/tank_qr_${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes);

  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final req = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload'),
  );
  req.fields['api_key'] = _apiKey;
  req.fields['timestamp'] = ts;
  req.fields['folder'] = _folder;
  req.fields['signature'] = _signature(ts);
  req.files.add(await http.MultipartFile.fromPath(
    'file',
    file.path,
    contentType: MediaType.parse(lookupMimeType(file.path) ?? 'image/png'),
  ));

  final res = await http.Response.fromStream(await req.send());
  debugPrint('[QR] Cloudinary response: ${res.statusCode} '
      '${res.body.substring(0, res.body.length.clamp(0, 200))}');
  if (res.statusCode != 200) {
    throw Exception('QR upload failed (${res.statusCode}): ${res.body}');
  }
  final url = (json.decode(res.body) as Map)['secure_url'] as String;
  debugPrint('[QR] Uploaded successfully → $url');
  return url;
}

Future<String> generateAndUploadQr({
  required String tankCode,
  required String tankName,
  required String location,
}) async {
  debugPrint(
      '[QR] Generating QR for code=$tankCode name=$tankName loc=$location');
  final qrData = jsonEncode({
    'tank_code': tankCode,
    'tank_name': tankName,
    'location': location,
  });
  final bytes = await _qrShot.captureFromWidget(
    Material(color: Colors.white, child: QrImageView(data: qrData, size: 320)),
  );
  debugPrint('[QR] QR captured, size=${bytes.length} bytes');
  return _uploadQr(bytes);
}
