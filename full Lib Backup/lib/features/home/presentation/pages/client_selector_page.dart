
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/models/client_model.dart';
import 'package:lubrication_indicator/core/services/client_context_service.dart';
import 'package:lubrication_indicator/core/services/client_repository.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/home/presentation/pages/home_screen.dart';

class ClientSelectorPage extends StatefulWidget {
  final UserModel user;

  const ClientSelectorPage({
    super.key,
    required this.user,
  });

  @override
  State<ClientSelectorPage> createState() => _ClientSelectorPageState();
}

class _ClientSelectorPageState extends State<ClientSelectorPage> {
  final _repo = ClientRepository();

  bool _loading = true;
  List<ClientModel> _clients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _repo.getAllClients();

      final isSuper =
          widget.user.role.toLowerCase() ==
              AccessControlService.roleSuperAdmin;

      final visible = isSuper
          ? all
          : all
              .where((c) => widget.user.clientIds.contains(c.id))
              .toList();

      if (!mounted) return;

      // AUTO SELECT IF ONLY ONE CLIENT
      if (visible.length == 1) {
        await _select(visible.first);
        return;
      }

      setState(() {
        _clients = visible;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load clients: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _select(ClientModel c) async {
    try {
      await ClientContextService.setActiveClient(c);

      await DatabaseModeService.setClientScope(c.dbKey);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to select client: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.topBar,
        title: const Text('Select Client'),
      ),

      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )

          : _clients.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'You have not got any access to a client. Please wait.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )

              : RefreshIndicator(
                  onRefresh: _load,

                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),

                    itemCount: _clients.length,

                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),

                    itemBuilder: (_, i) {
                      final c = _clients[i];

                      return InkWell(
                        onTap: () => _select(c),

                        borderRadius: BorderRadius.circular(14),

                        child: Container(
                          padding: const EdgeInsets.all(16),

                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1D232B),
                                Color(0xFF243240),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),

                            borderRadius: BorderRadius.circular(14),

                            border: Border.all(
                              color: AppColors.border,
                            ),
                          ),

                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.apartment,
                                    color: AppColors.primary,
                                  ),

                                  const SizedBox(width: 8),

                                  Expanded(
                                    child: Text(
                                      c.name,

                                      style: GoogleFonts.inter(
                                        color:
                                            AppColors.textPrimary,
                                        fontWeight:
                                            FontWeight.w800,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              if (c.description
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),

                                Text(
                                  c.description,

                                  style: GoogleFonts.inter(
                                    color:
                                        AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
