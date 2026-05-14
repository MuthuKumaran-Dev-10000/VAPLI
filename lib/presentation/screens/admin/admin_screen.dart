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
import 'create_tank_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cloudinary config (shared across file)
// ─────────────────────────────────────────────────────────────────────────────
const String _cloudName = 'dummy-cloudinary-cloud-name';
const String _apiKey = 'dummy-cloudinary-api-key';
const String _apiSecret = 'dummy-cloudinary-api-secret';
const String _folderQr =
    'lubricationindicator_qr'; // same folder as create_tank_screen
const String _folderMain =
    'lubricationindicator'; // original folder kept for download share

// ─────────────────────────────────────────────────────────────────────────────
// Cloudinary helpers (module-level, shared by card + duplicate logic)
// ─────────────────────────────────────────────────────────────────────────────
String _cloudSignature(String timestamp, String folder) {
  final params = 'folder=$folder&timestamp=$timestamp';
  return sha1.convert(utf8.encode('$params$_apiSecret')).toString();
}

Future<String> _uploadBytesToCloudinary(Uint8List bytes,
    {String folder = _folderQr}) async {
  debugPrint('[Cloudinary] Uploading to folder=$folder bytes=${bytes.length}');
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
  return _uploadBytesToCloudinary(bytes, folder: _folderQr);
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminLoginScreen  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user =
          await AuthRepository().login(_userCtrl.text.trim(), _passCtrl.text);
      if (user.role != 'admin') throw Exception('Not an admin account');
      if (mounted) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => AdminDashboard(adminName: user.fullName)));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 16),
          TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password')),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _login,
            child: Text(_loading ? 'Loading…' : 'Login'),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboard
// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  final String adminName;
  const AdminDashboard({super.key, required this.adminName});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TankModel> _tanks = [];
  List<Map> _users = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  void _load() {
    debugPrint('[Dashboard] _load() — subscribing to tanks + users streams');

    TankRepository().watchTanks().listen((data) {
      debugPrint('[Dashboard] Tanks stream update: ${data.length} tanks');
      if (mounted) setState(() => _tanks = data);
    });

    FirebaseDatabase.instance.ref('users').onValue.listen((event) {
      final users = <Map>[];
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        for (final e in data.entries) {
          users.add({'id': e.key, ...Map<String, dynamic>.from(e.value)});
        }
      }
      debugPrint('[Dashboard] Users stream update: ${users.length} users');
      if (mounted) setState(() => _users = users);
    });
  }

  // ── helpers for duplicate naming ──────────────────────────────────────────

  /// Returns the lowest free "Base (n)" code among existing tanks.
  String _nextFreeCode(String base) {
    final existing = _tanks.map((t) => t.tankCode).toList();
    final stripped = base.replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim();
    for (int i = 1; i <= 99; i++) {
      final candidate = '$stripped ($i)';
      if (!existing.contains(candidate)) return candidate;
    }
    return '$stripped (${DateTime.now().millisecondsSinceEpoch})';
  }

  // ── tank actions ──────────────────────────────────────────────────────────

  Future<void> _openCreateTank() async {
    debugPrint('[Dashboard] FAB: open CreateTankScreen (new)');
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateTankScreen()),
    );
    debugPrint('[Dashboard] CreateTankScreen returned ok=$ok');
  }

  Future<void> _deleteTank(String id, String name) async {
    debugPrint('[Dashboard] Deleting tank id=$id name=$name');
    await FirebaseDatabase.instance.ref('tanks/$id').remove();
    debugPrint('[Dashboard] Tank deleted: $id');
  }

  // ── user actions (unchanged) ──────────────────────────────────────────────

  Future<void> _createUser() async {
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true, loading = false;
    String? error;
    String role = 'user';

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Create User'),
          content: SizedBox(
            width: 350,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 14),
              TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 14),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    onPressed: () => setDialog(() => obscure = !obscure),
                    icon:
                        Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'user', child: Text('User')),
                ],
                onChanged: (v) => setDialog(() => role = v!),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                setDialog(() {
                  loading = true;
                  error = null;
                });
                final snapshot =
                    await FirebaseDatabase.instance.ref('users').get();
                if (snapshot.value != null) {
                  final data = Map<String, dynamic>.from(snapshot.value as Map);
                  for (final u in data.values) {
                    if (u['username'].toString().toLowerCase() ==
                        userCtrl.text.trim().toLowerCase()) {
                      setDialog(() {
                        loading = false;
                        error = 'Username already exists';
                      });
                      return;
                    }
                  }
                }
                await AuthRepository().createUser(
                  username: userCtrl.text,
                  fullName: nameCtrl.text,
                  password: passCtrl.text,
                  role: role,
                );
                if (mounted) Navigator.pop(context);
              },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(String id) async {
    final snapshot = await FirebaseDatabase.instance.ref('users/$id').get();
    if (!snapshot.exists) return;
    final data = Map<String, dynamic>.from(snapshot.value as Map);
    final isRoot = data['username'] == 'admin' &&
        data['full_name'] == 'System Administrator';
    if (isRoot) return;
    await FirebaseDatabase.instance.ref('users/$id').remove();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Tanks'), Tab(text: 'Users')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (_tabController.index == 0) {
            await _openCreateTank();
          } else {
            await _createUser();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── TANKS TAB ─────────────────────────────────────────────────────
          _tanks.isEmpty
              ? const Center(child: Text('No tanks yet. Tap + to create one.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _tanks.length,
                  itemBuilder: (_, i) {
                    final tank = _tanks[i];
                    return _TankAdminCard(
                      tank: tank,
                      allTankCodes: _tanks.map((t) => t.tankCode).toList(),
                      nextFreeCode: _nextFreeCode,
                      onDelete: () {
                        debugPrint(
                            '[Dashboard] onDelete callback for ${tank.id}');
                        _deleteTank(tank.id, tank.tankName);
                      },
                    );
                  },
                ),

          // ── USERS TAB (unchanged) ─────────────────────────────────────────
          ListView.builder(
            itemCount: _users.length,
            itemBuilder: (_, i) {
              final user = _users[i];
              final isRoot = user['username'] == 'admin' &&
                  user['full_name'] == 'System Administrator';
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(user['full_name']),
                subtitle: Text('${user['username']} • ${user['role']}'),
                trailing: isRoot
                    ? null
                    : IconButton(
                        onPressed: () => _deleteUser(user['id']),
                        icon: const Icon(Icons.delete, color: Colors.red),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TankAdminCard
// Actions: [Duplicate] [Modify] [Download QR] [Delete]
// ─────────────────────────────────────────────────────────────────────────────

class _TankAdminCard extends StatefulWidget {
  final TankModel tank;
  final List<String> allTankCodes;
  final String Function(String base) nextFreeCode;
  final VoidCallback onDelete;

  const _TankAdminCard({
    required this.tank,
    required this.allTankCodes,
    required this.nextFreeCode,
    required this.onDelete,
  });

  @override
  State<_TankAdminCard> createState() => _TankAdminCardState();
}

class _TankAdminCardState extends State<_TankAdminCard> {
  final _shotCtrl = ScreenshotController();
  bool _busy = false; // prevents double-tap during async ops

  // ── busy guard wrapper ─────────────────────────────────────────────────────

  Future<void> _run(String tag, Future<void> Function() fn) async {
    if (_busy) {
      debugPrint('[$tag] Ignored — card is busy');
      return;
    }
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e, s) {
      debugPrint('[$tag] ERROR: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── DUPLICATE ─────────────────────────────────────────────────────────────

  Future<void> _duplicate() => _run('Duplicate', () async {
        final t = widget.tank;
        debugPrint('[Duplicate] Tapped for tank: ${t.tankCode} id=${t.id}');

        final newCode = widget.nextFreeCode(t.tankCode);
        debugPrint('[Duplicate] New code will be: $newCode');

        // Build a map that mirrors the existing tank, then override code + remove id
        final dupMap = <String, dynamic>{
          'tank_code': newCode,
          'tank_name': t.tankName,
          'location': t.location ?? '',
          'scale_max': t.scaleMax,
          'scale_side': t.scaleSide,
          'inspection_properties': t.inspectionProperties
                  ?.map((p) => Map<String, dynamic>.from(p))
                  .toList() ??
              [],
        };
        debugPrint('[Duplicate] Dup map built (no id — repo will assign one)');

        // Open CreateTankScreen pre-filled as a duplicate
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => CreateTankScreen(
              existingTank: dupMap,
              isDuplicate: true,
            ),
          ),
        );
        debugPrint('[Duplicate] CreateTankScreen returned ok=$ok');
        // Stream listener on parent will auto-refresh the list
      });

  // ── MODIFY ────────────────────────────────────────────────────────────────

  Future<void> _modify() => _run('Modify', () async {
        final t = widget.tank;
        debugPrint('[Modify] Tapped for tank: ${t.tankCode} id=${t.id}');

        // Convert TankModel → Map for CreateTankScreen
        final tankMap = <String, dynamic>{
          'id': t.id,
          'tank_code': t.tankCode,
          'tank_name': t.tankName,
          'location': t.location ?? '',
          'scale_max': t.scaleMax,
          'scale_side': t.scaleSide,
          'qr_image_url': t.qrImageUrl,
          'qr_json': t.qrJson,
          'inspection_properties': t.inspectionProperties
                  ?.map((p) => Map<String, dynamic>.from(p))
                  .toList() ??
              [],
        };

        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => CreateTankScreen(existingTank: tankMap),
          ),
        );
        debugPrint('[Modify] CreateTankScreen returned ok=$ok');
        // Stream listener on parent will auto-refresh the list
      });

  // ── DOWNLOAD QR ───────────────────────────────────────────────────────────

  Future<void> _downloadQr() => _run('Download', () async {
        final t = widget.tank;
        debugPrint('[Download] Generating printable QR for ${t.tankCode}');

        final imageBytes = await _shotCtrl.captureFromWidget(
          Material(
            color: Colors.white,
            child: _buildPrintableQr(),
          ),
          pixelRatio: 3.0,
        );
        debugPrint('[Download] Captured ${imageBytes.length} bytes');

        // Upload to Cloudinary and persist URL
        final qrUrl =
            await _uploadBytesToCloudinary(imageBytes, folder: _folderMain);
        debugPrint('[Download] Updating qr_image_url in Firebase for ${t.id}');
        await FirebaseDatabase.instance
            .ref('tanks/${t.id}')
            .update({'qr_image_url': qrUrl});

        // Save locally and share
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/qr_${t.tankCode}.png');
        await file.writeAsBytes(imageBytes);
        debugPrint('[Download] Saved locally → ${file.path}');

        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'QR for ${t.tankName}',
        );
        debugPrint('[Download] Share sheet opened');
      });

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    debugPrint('[Delete] Confirm dialog opened for ${widget.tank.tankCode}');
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Tank'),
        content:
            Text('Delete "${widget.tank.tankName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('[Delete] Cancelled');
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              debugPrint('[Delete] Confirmed');
              Navigator.pop(context, true);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (yes == true) {
      debugPrint('[Delete] Calling onDelete for ${widget.tank.id}');
      widget.onDelete();
    }
  }

  // ── printable QR widget (used by download) ─────────────────────────────────

  Widget _buildPrintableQr() {
    final t = widget.tank;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: t.qrJson ?? t.id,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 14),
          Text('Tank ID : ${t.tankCode}',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Name : ${t.tankName}',
              style: const TextStyle(color: Colors.black, fontSize: 15)),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = widget.tank;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── QR thumbnail ────────────────────────────────────────────────
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              padding: const EdgeInsets.all(4),
              child: t.qrImageUrl != null
                  ? Image.network(t.qrImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => QrImageView(
                          data: t.qrJson ?? t.id,
                          size: 52,
                          backgroundColor: Colors.white))
                  : QrImageView(
                      data: t.qrJson ?? t.id,
                      size: 52,
                      backgroundColor: Colors.white),
            ),
            const SizedBox(width: 12),

            // ── name + code + location ───────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.tankCode,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(t.tankName,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  if ((t.location ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 2),
                      Text(t.location!,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ]),
                  ],
                  if ((t.inspectionProperties ?? []).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${t.inspectionProperties!.length} param${t.inspectionProperties!.length == 1 ? '' : 's'}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.blue.shade400),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── action buttons ───────────────────────────────────────────────
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              _ActionBar(
                onDuplicate: _duplicate,
                onModify: _modify,
                onDownloadQr: _downloadQr,
                onDelete: _confirmDelete,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActionBar — the 4-button row shown on each tank card
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final VoidCallback onDuplicate;
  final VoidCallback onModify;
  final VoidCallback onDownloadQr;
  final VoidCallback onDelete;

  const _ActionBar({
    required this.onDuplicate,
    required this.onModify,
    required this.onDownloadQr,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Row 1: Duplicate + Modify
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SmallBtn(
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              color: const Color(0xFFFFB703),
              onTap: () {
                debugPrint('[ActionBar] Duplicate tapped');
                onDuplicate();
              },
            ),
            const SizedBox(width: 6),
            _SmallBtn(
              icon: Icons.edit_outlined,
              label: 'Modify',
              color: const Color(0xFF00B4D8),
              onTap: () {
                debugPrint('[ActionBar] Modify tapped');
                onModify();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Row 2: Download + Delete
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SmallBtn(
              icon: Icons.download_outlined,
              label: 'Download',
              color: const Color(0xFF06D6A0),
              onTap: () {
                debugPrint('[ActionBar] Download tapped');
                onDownloadQr();
              },
            ),
            const SizedBox(width: 6),
            _SmallBtn(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: const Color(0xFFEF233C),
              onTap: () {
                debugPrint('[ActionBar] Delete tapped');
                onDelete();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SmallBtn — compact icon+label chip button
// ─────────────────────────────────────────────────────────────────────────────

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      );
}
