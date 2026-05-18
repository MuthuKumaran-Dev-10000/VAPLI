import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lubrication_indicator/data/models/reading_model.dart';
import 'package:lubrication_indicator/data/repositories/reading_repository.dart';
import 'package:lubrication_indicator/presentation/screens/admin/admin_dashboard.dart';
import 'package:lubrication_indicator/presentation/screens/dashboard/dashboard_tab.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/session_manager.dart';
import '../../../data/models/tank_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/tank_repository.dart';
import '../auth/login_screen.dart';
import '../admin/admin_screen_not_used.dart';
import '../readings/reading_entry_screen.dart';
import '../trends/trends_screen.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  UserModel? _currentUser;

  List<TankModel> _tanks = [];

  TankModel? _selectedTank;

  bool _loadingTanks = true;

  @override
  void initState() {
    super.initState();

    _tabCtrl = TabController(
      length: 3,
      vsync: this,
    );

    _init();
  }

  Future<void> _init() async {
    _currentUser = await SessionManager.getCurrentUser();

    if (_currentUser == null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
      );

      return;
    }

    _loadTanks();

    _startSessionCheck();
  }

  void _startSessionCheck() {
    Future.delayed(
      const Duration(
        minutes: 1,
      ),
      () async {
        if (!mounted) {
          return;
        }

        final valid = await SessionManager.isSessionValid();

        if (!valid && mounted) {
          _showSessionExpiredDialog();
        } else {
          _startSessionCheck();
        }
      },
    );
  }

  void _showSessionExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Session Expired',
          style: GoogleFonts.inter(
            color: AppColors.warning,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Your session has expired after 60 minutes. Please login again.',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              await SessionManager.clearSession();

              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                  (_) => false,
                );
              }
            },
            child: const Text(
              'Login Again',
            ),
          ),
        ],
      ),
    );
  }

  void _loadTanks() {
    TankRepository().watchTanks().listen(
      (tanks) {
        if (mounted) {
          setState(() {
            _tanks = tanks;

            _loadingTanks = false;
          });
        }
      },
    );
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(),
      ),
    );

    if (result != null) {
      try {
        final data = jsonDecode(
          result,
        );

        final tankId = data['tank_id'] as String?;

        if (tankId != null) {
          final tank = _tanks.firstWhere(
            (t) => t.id == tankId,
            orElse: () => throw Exception(
              'Tank not found',
            ),
          );

          setState(() {
            _selectedTank = tank;
          });
        }
      } catch (e) {
        _showError(
          'Invalid QR code: $e',
        );
      }
    }
  }

  void _showError(
    String msg,
  ) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            10,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.topBar,

        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(
                  8,
                ),
              ),
              child: const Icon(
                Icons.oil_barrel_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            Text(
              'VAPLI',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),

        // ======================================
        // UPDATED HERE
        // ======================================
        actions: [
          if (_currentUser != null)
            Padding(
              padding: const EdgeInsets.only(
                right: 4,
              ),
              child: Center(
                child: Text(
                  _currentUser!.fullName
                      .split(
                        ' ',
                      )
                      .first,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          // ADMIN ONLY
          if (_currentUser != null && _currentUser!.role == "admin")
            IconButton(
              icon: const Icon(
                Icons.admin_panel_settings_outlined,
                color: AppColors.warning,
              ),
              tooltip: 'Admin',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminDashboard(
                      adminName: _currentUser!.fullName,
                    ),
                  ),
                );
              },
            ),

          // LOGOUT
          IconButton(
            icon: const Icon(
              Icons.logout_outlined,
              color: AppColors.textSecondary,
            ),
            onPressed: () async {
              await SessionManager.clearSession();

              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                );
              }
            },
          ),
        ],

        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: const [
            Tab(
              icon: Icon(
                Icons.input_outlined,
              ),
              text: 'Input',
            ),
            Tab(
              icon: Icon(
                Icons.trending_up_outlined,
              ),
              text: 'Trends',
            ),
            Tab(
              icon: Icon(
                Icons.dashboard_outlined,
              ),
              text: 'Dashboard',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _InputTab(
            tanks: _tanks,
            selectedTank: _selectedTank,
            loadingTanks: _loadingTanks,
            currentUser: _currentUser,
            onTankSelected: (t) {
              setState(() {
                _selectedTank = t;
              });
            },
            onScanQr: _scanQr,
          ),
          TrendsScreen(
            tanks: _tanks,
          ),
          const DashboardTab(),
        ],
      ),
    );
  }
}

// KEEP EVERYTHING BELOW EXACTLY SAME
// (_InputTab, _QrButton,
// _TankInfoCard, _InfoChip,
// _MainActionButton,
// QrScanScreen)

// DO NOT CHANGE ANYTHING BELOW.

class _InputTab extends StatelessWidget {
  final List<TankModel> tanks;
  final TankModel? selectedTank;
  final bool loadingTanks;
  final UserModel? currentUser;
  final ValueChanged<TankModel?> onTankSelected;
  final VoidCallback onScanQr;

  const _InputTab({
    required this.tanks,
    required this.selectedTank,
    required this.loadingTanks,
    required this.currentUser,
    required this.onTankSelected,
    required this.onScanQr,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Text(
            'SELECT TANK',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),

          // Dropdown + QR row
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: loadingTanks
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child:
                              LinearProgressIndicator(color: AppColors.primary),
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<TankModel>(
                            value: selectedTank,
                            isExpanded: true,
                            dropdownColor: AppColors.surface,
                            hint: Text(
                              'Choose a tank...',
                              style: GoogleFonts.inter(
                                  color: AppColors.disabled, fontSize: 14),
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down,
                                color: AppColors.textSecondary),
                            items: tanks.map((t) {
                              return DropdownMenuItem<TankModel>(
                                value: t,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t.tankName,
                                      style: GoogleFonts.inter(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      '${t.tankCode} · ${t.location ?? "—"}',
                                      style: GoogleFonts.inter(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: onTankSelected,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              _QrButton(onPressed: onScanQr),
            ],
          ),

          const SizedBox(height: 32),

          // Tank info card (shown when selected)
          if (selectedTank != null) ...[
            _TankInfoCard(tank: selectedTank!),
            const SizedBox(height: 32),
          ],

          // Take Readings CTA
          Center(
            child: Column(
              children: [
                _MainActionButton(
                  enabled: selectedTank != null,
                  onPressed: selectedTank == null
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReadingEntryScreen(
                                tank: selectedTank!,
                                currentUser: currentUser!,
                              ),
                            ),
                          );
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  selectedTank == null
                      ? 'Select a tank to enable readings'
                      : 'Ready to record reading for ${selectedTank!.tankName}',
                  style: GoogleFonts.inter(
                    color: selectedTank == null
                        ? AppColors.disabled
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _QrButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.secondary, Color(0xFF0E7490)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.qr_code_scanner_outlined,
            color: Colors.white, size: 26),
      ),
    );
  }
}

class _TankInfoCard extends StatelessWidget {
  final TankModel tank;
  const _TankInfoCard({required this.tank});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.water_outlined,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tank.tankName,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      tank.tankCode,
                      style: GoogleFonts.inter(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Text(
                  'ACTIVE',
                  style: GoogleFonts.inter(
                    color: AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoChip(
                  icon: Icons.location_on_outlined,
                  label: tank.location ?? '—'),
              const SizedBox(width: 10),
              _InfoChip(
                  icon: Icons.straighten_outlined,
                  label:
                      'Scale: ${tank.scaleMin.toInt()}–${tank.scaleMax.toInt()}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.topBar,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MainActionButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onPressed;
  const _MainActionButton({required this.enabled, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? const LinearGradient(
                  colors: [AppColors.primary, Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: enabled ? null : AppColors.surface,
          border: Border.all(
            color: enabled ? AppColors.primary : const Color(0xFF334155),
            width: 2,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.edit_note_outlined,
              color: enabled ? Colors.white : AppColors.disabled,
              size: 44,
            ),
            const SizedBox(height: 8),
            Text(
              'Take\nReading',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: enabled ? Colors.white : AppColors.disabled,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// QR Scan Screen
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.topBar,
        title: Text('Scan Tank QR',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _scanned = true;
                Navigator.pop(context, barcode!.rawValue);
              }
            },
          ),
          // Overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.secondary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Point camera at tank QR code',
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimary, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// class DashboardTab extends StatefulWidget {
//   final List<TankModel> tanks;

//   const DashboardTab({
//     super.key,
//     required this.tanks,
//   });

//   @override
//   State<DashboardTab> createState() => _DashboardTabState();
// }

// class _DashboardTabState extends State<DashboardTab> {
//   final _readingRepo = ReadingRepository();

//   bool _loading = true;

//   final Map<String, ReadingModel?> _latestReadings = {};

//   @override
//   void initState() {
//     super.initState();

//     _loadDashboard();
//   }

//   Future<void> _loadDashboard() async {
//     final allReadings = await _readingRepo.getAllReadings();

//     for (final tank in widget.tanks) {
//       final readings = allReadings
//           .where(
//             (r) => r.tankId == tank.id,
//           )
//           .toList()
//         ..sort(
//           (a, b) => b.capturedAt.compareTo(
//             a.capturedAt,
//           ),
//         );

//       _latestReadings[tank.id] = readings.isEmpty ? null : readings.first;
//     }

//     if (mounted) {
//       setState(() {
//         _loading = false;
//       });
//     }
//   }

//   @override
//   Widget build(
//     BuildContext context,
//   ) {
//     if (_loading) {
//       return const Center(
//         child: CircularProgressIndicator(),
//       );
//     }

//     return ListView.builder(
//       padding: const EdgeInsets.all(
//         16,
//       ),
//       itemCount: widget.tanks.length,
//       itemBuilder: (_, i) {
//         final tank = widget.tanks[i];

//         final latest = _latestReadings[tank.id];

//         String date = "Not Available";

//         String time = "Not Available";

//         String inspector = "Not Available";

//         if (latest != null) {
//           final dt = DateTime.parse(
//             latest.capturedAt,
//           );

//           date = DateFormat(
//             "dd/MM/yyyy",
//           ).format(
//             dt,
//           );

//           time = DateFormat(
//             "HH:mm:ss",
//           ).format(
//             dt,
//           );

//           inspector = latest.capturedByName;
//         }

//         return Container(
//           margin: const EdgeInsets.only(
//             bottom: 14,
//           ),
//           padding: const EdgeInsets.all(
//             16,
//           ),
//           decoration: BoxDecoration(
//             color: AppColors.surface,
//             borderRadius: BorderRadius.circular(
//               16,
//             ),
//           ),
//           child: Text(
//             "Tank ID : ${tank.tankCode}\n"
//             "Tank Name : ${tank.tankName}\n"
//             "Last Inspection Date and Time : "
//             "$date & $time\n"
//             "Captured By : $inspector",
//             style: GoogleFonts.inter(
//               fontSize: 14,
//               height: 1.6,
//               color: AppColors.textPrimary,
//             ),
//           ),
//         );
//       },
//     );
//   }
// }
