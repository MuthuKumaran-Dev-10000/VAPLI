// lib/features/dashboard_folders/folder_alerts_view.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_alerts_display_model.dart';
import 'fanned_card_layout.dart';

class FolderAlertsView extends StatefulWidget {
  final List<AlertFolderGroup> folders;
  final Widget Function(DashboardAlertDisplayItem) alertCardBuilder;
  final bool isCompleted;

  const FolderAlertsView({
    super.key,
    required this.folders,
    required this.alertCardBuilder,
    this.isCompleted = false,
  });

  @override
  State<FolderAlertsView> createState() => _FolderAlertsViewState();
}

class _FolderAlertsViewState extends State<FolderAlertsView> {
  // Stateful navigation variables for page-in/page-out system
  String? _selectedParam;
  String? _selectedAssetId;

  // Palette constants
  static const _kBorder = Color(0xFF252830);
  static const _kSuccess = Color(0xFF22C55E); // Green
  static const _kCopper = Color(0xFFCB8C3E);
  static const _kDanger = Color(0xFFEF4444);
  static const _kSub = Color(0xFF8A8F9C);
  static const _kText = Color(0xFFF0EEE9);

  Color get _themeColor => widget.isCompleted ? _kSuccess : _kCopper;

  @override
  void didUpdateWidget(FolderAlertsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the folder list is empty or doesn't contain current selected param, reset navigation
    if (widget.folders.isEmpty) {
      _selectedParam = null;
      _selectedAssetId = null;
    } else if (_selectedParam != null) {
      final paramExists = widget.folders.any((f) => f.paramLabel == _selectedParam);
      if (!paramExists) {
        _selectedParam = null;
        _selectedAssetId = null;
      } else if (_selectedAssetId != null) {
        final currentParam = widget.folders.firstWhere((f) => f.paramLabel == _selectedParam);
        final assetExists = currentParam.assets.any((a) => a.tankId == _selectedAssetId);
        if (!assetExists) {
          _selectedAssetId = null;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.folders.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_selectedParam == null) {
      // ───────────────────────────────────────────────────────────────────────
      // LEVEL 1: PARAMETER FOLDERS LIST (ROOT)
      // ───────────────────────────────────────────────────────────────────────
      return Column(
        children: widget.folders.map((paramFolder) {
          final allAlertsInParam =
              paramFolder.assets.expand((a) => a.alerts).toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF141618),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _themeColor.withOpacity(0.35)),
              boxShadow: [
                BoxShadow(
                  color: _themeColor.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedParam = paramFolder.paramLabel;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    FannedCardLayout(alerts: allAlertsInParam),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            paramFolder.paramLabel,
                            style: GoogleFonts.spaceGrotesk(
                              color: _kText,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '${paramFolder.totalAssets} Assets',
                                style: GoogleFonts.dmSans(
                                  color: _kSub,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: _kSub,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.isCompleted
                                    ? '${paramFolder.totalAlerts} Completed'
                                    : '${paramFolder.totalAlerts} Alerts',
                                style: GoogleFonts.dmSans(
                                  color: widget.isCompleted ? _kSuccess : _kDanger,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _kSub,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    }

    // Get currently navigated parameter group
    final currentParamGroup =
        widget.folders.firstWhere((f) => f.paramLabel == _selectedParam);

    if (_selectedAssetId == null) {
      // ───────────────────────────────────────────────────────────────────────
      // LEVEL 2: ASSET FOLDERS LIST INSIDE PARAMETER
      // ───────────────────────────────────────────────────────────────────────
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Navigation Back Header
          _buildBackHeader(
            title: currentParamGroup.paramLabel,
            onBack: () {
              setState(() {
                _selectedParam = null;
              });
            },
          ),
          const SizedBox(height: 10),

          ...currentParamGroup.assets.map((assetFolder) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141618),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _themeColor.withOpacity(0.25)),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedAssetId = assetFolder.tankId;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      FannedCardLayout(
                        alerts: assetFolder.alerts,
                        size: 40.0,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              assetFolder.tankName,
                              style: GoogleFonts.dmSans(
                                color: _kText,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.isCompleted
                                  ? '${assetFolder.alertCount} Completed'
                                  : '${assetFolder.alertCount} Alerts',
                              style: GoogleFonts.dmSans(
                                color: widget.isCompleted ? _kSuccess : _kDanger,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _kSub,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      );
    }

    // Get currently navigated asset folder
    final currentAssetFolder =
        currentParamGroup.assets.firstWhere((a) => a.tankId == _selectedAssetId);

    // ───────────────────────────────────────────────────────────────────────
    // LEVEL 3: LEAF NODE ALERTS INSIDE SELECTED ASSET
    // ───────────────────────────────────────────────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Navigation Back Header
        _buildBackHeader(
          title: currentAssetFolder.tankName,
          subtitle: currentParamGroup.paramLabel,
          onBack: () {
            setState(() {
              _selectedAssetId = null;
            });
          },
        ),
        const SizedBox(height: 10),

        // List leaf node alerts
        ...currentAssetFolder.alerts.map((a) {
          if (widget.isCompleted) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProofEvidenceHeader(a),
                widget.alertCardBuilder(a),
              ],
            );
          }
          return widget.alertCardBuilder(a);
        }),
      ],
    );
  }

  Widget _buildProofEvidenceHeader(DashboardAlertDisplayItem a) {
    final List<SlideImageItem> allMediaItems = [];

    if (a.imageUrl.isNotEmpty) {
      allMediaItems.add(SlideImageItem(
        url: a.imageUrl,
        categoryTag: 'COMPLAINT IMAGE',
        alert: a,
      ));
    }

    final proofUrls = a.completedPhotoUrls.isNotEmpty
        ? a.completedPhotoUrls
        : (a.completedPhotoUrl.isNotEmpty ? [a.completedPhotoUrl] : <String>[]);

    for (final u in proofUrls) {
      if (u.isNotEmpty) {
        allMediaItems.add(SlideImageItem(
          url: u,
          categoryTag: 'COMPLETED PROOF',
          alert: a,
        ));
      }
    }

    if (allMediaItems.isEmpty && a.completedDescription.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF142219),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kSuccess.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: _kSuccess, size: 14),
              const SizedBox(width: 6),
              Text(
                'COMPLETION PROOF & VERIFICATION',
                style: GoogleFonts.spaceGrotesk(
                  color: _kSuccess,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (allMediaItems.isNotEmpty)
                Text(
                  '${allMediaItems.length} Photo${allMediaItems.length > 1 ? "s" : ""}',
                  style: GoogleFonts.spaceGrotesk(
                    color: _kSuccess,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          if (a.completedDescription.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              a.completedDescription,
              style: GoogleFonts.dmSans(
                color: _kText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (allMediaItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: allMediaItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final item = allMediaItems[i];
                  final isComplaint = item.categoryTag == 'COMPLAINT IMAGE';

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => FullScreenSlideViewer(
                            slides: allMediaItems,
                            initialIndex: i,
                          ),
                        ),
                      );
                    },
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isComplaint ? _kDanger : _kSuccess,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Image.network(
                              item.url,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 60,
                                height: 60,
                                color: const Color(0xFF252830),
                                child: const Icon(Icons.broken_image_rounded, color: _kSub, size: 20),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: isComplaint ? _kDanger : _kSuccess,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              isComplaint ? 'ALERT' : 'PROOF',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBackHeader({
    required String title,
    String? subtitle,
    required VoidCallback onBack,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E3440)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _kCopper, size: 16),
            onPressed: onBack,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null)
                  Text(
                    subtitle.toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      color: _kSub,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                Text(
                  title,
                  style: GoogleFonts.spaceGrotesk(
                    color: _kText,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
