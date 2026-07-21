// lib/features/dashboard_folders/fanned_card_layout.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dashboard_alerts_display_model.dart';

class FannedCardLayout extends StatelessWidget {
  final List<DashboardAlertDisplayItem> alerts;
  final double size;

  const FannedCardLayout({
    super.key,
    required this.alerts,
    this.size = 46.0,
  });

  @override
  Widget build(BuildContext context) {
    final List<SlideImageItem> allSlides = [];

    for (final a in alerts) {
      if (a.imageUrl.isNotEmpty) {
        allSlides.add(SlideImageItem(
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
          allSlides.add(SlideImageItem(
            url: u,
            categoryTag: 'COMPLETED PROOF',
            alert: a,
          ));
        }
      }
    }

    if (allSlides.isEmpty) {
      // Fallback: Premium folder icon
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1E222A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2E3440)),
        ),
        child: const Icon(
          Icons.folder_open_rounded,
          color: Color(0xFFCB8C3E),
          size: 22,
        ),
      );
    }

    // Display top 3 images fanned
    final imagesCount = allSlides.length;
    final displayItems = allSlides.take(3).toList();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FullScreenSlideViewer(slides: allSlides),
          ),
        );
      },
      child: SizedBox(
        width: size + 8,
        height: size + 4,
        child: Stack(
          children: [
            // 3rd Image (bottom of stack)
            if (imagesCount >= 3)
              Positioned(
                left: 8,
                top: 4,
                child: Transform.rotate(
                  angle: 0.12,
                  child: _buildThumbnailCard(displayItems[2].url, size - 4),
                ),
              ),
            // 2nd Image (middle of stack)
            if (imagesCount >= 2)
              Positioned(
                left: 4,
                top: 2,
                child: Transform.rotate(
                  angle: -0.06,
                  child: _buildThumbnailCard(displayItems[1].url, size - 2),
                ),
              ),
            // 1st Image (top of stack)
            Positioned(
              left: 0,
              top: 0,
              child: _buildThumbnailCard(displayItems[0].url, size, isTop: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailCard(String url, double cardSize, {bool isTop = false}) {
    return Container(
      width: cardSize,
      height: cardSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTop ? const Color(0xFFCB8C3E) : Colors.white70,
          width: isTop ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 4,
            offset: Offset(0, 1.5),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: const Color(0xFF141618),
            child: const Center(
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white30),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: const Color(0xFF1A1C20),
            child: const Icon(Icons.broken_image, size: 12, color: Colors.white30),
          ),
        ),
      ),
    );
  }
}

class SlideImageItem {
  final String url;
  final String categoryTag; // 'COMPLAINT IMAGE' or 'COMPLETED PROOF'
  final DashboardAlertDisplayItem? alert;

  SlideImageItem({
    required this.url,
    required this.categoryTag,
    this.alert,
  });
}

class FullScreenSlideViewer extends StatefulWidget {
  final List<DashboardAlertDisplayItem>? alerts;
  final List<SlideImageItem>? slides;
  final int initialIndex;

  const FullScreenSlideViewer({
    super.key,
    this.alerts,
    this.slides,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenSlideViewer> createState() => _FullScreenSlideViewerState();
}

class _FullScreenSlideViewerState extends State<FullScreenSlideViewer> {
  late PageController _pageController;
  int _currentIndex = 0;

  List<SlideImageItem> get _effectiveSlides {
    if (widget.slides != null && widget.slides!.isNotEmpty) {
      return widget.slides!;
    }
    if (widget.alerts != null) {
      return widget.alerts!
          .where((a) => a.imageUrl.isNotEmpty)
          .map((a) => SlideImageItem(
                url: a.imageUrl,
                categoryTag: 'COMPLAINT IMAGE',
                alert: a,
              ))
          .toList();
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Color _sevColor(String sev) {
    switch (sev.toLowerCase()) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'warning':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF1ABCBD);
    }
  }

  void _showAlertInfoPopup(DashboardAlertDisplayItem alert) {
    final color = _sevColor(alert.severity);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1C20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
        ),
        title: Row(
          children: [
            Icon(
              alert.severity.toLowerCase() == 'critical'
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                alert.alertTitle,
                style: GoogleFonts.dmSans(
                  color: const Color(0xFFF0EEE9),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPopupRow('Asset', '${alert.tankName} (${alert.tankCode})'),
              _buildPopupRow('Parameter', alert.paramLabel),
              _buildPopupRow('Value', alert.paramValue),
              _buildPopupRow('Message', alert.message),
              _buildPopupRow('Severity', alert.severity.toUpperCase(), valueColor: color),
              if (alert.completedDescription.isNotEmpty)
                _buildPopupRow('Resolution Proof', alert.completedDescription, valueColor: const Color(0xFF22C55E)),
              _buildPopupRow('Time', _formatDateTime(alert.timestamp)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.dmSans(color: const Color(0xFF8A8F9C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: GoogleFonts.dmSans(
                color: const Color(0xFF8A8F9C),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                color: valueColor ?? const Color(0xFFF0EEE9),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String isoStr) {
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = _effectiveSlides;
    if (slides.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No images available', style: TextStyle(color: Colors.white54))),
      );
    }

    final currentSlide = slides[_currentIndex.clamp(0, slides.length - 1)];
    final currentAlert = currentSlide.alert;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Slideshow page view
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (idx) {
                setState(() {
                  _currentIndex = idx;
                });
              },
              itemCount: slides.length,
              itemBuilder: (context, index) {
                final url = slides[index].url;
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 3.5,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(color: Color(0xFFCB8C3E)),
                      ),
                      errorWidget: (context, url, error) => const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 64, color: Colors.white30),
                          SizedBox(height: 8),
                          Text('Failed to load image', style: TextStyle(color: Colors.white30)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Upper Controls (Close Button, Counter & Category Tag)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48), // Spacer for centering
                  
                  // Counter x/n & Category Tag
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.60),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_currentIndex + 1}/${slides.length}',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: currentSlide.categoryTag == 'COMPLETED PROOF'
                              ? const Color(0xFF22C55E).withOpacity(0.25)
                              : const Color(0xFFEF4444).withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: currentSlide.categoryTag == 'COMPLETED PROOF'
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          currentSlide.categoryTag,
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Close button
                  CircleAvatar(
                    backgroundColor: Colors.black.withOpacity(0.50),
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Control (Info Button)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 20,
            child: FloatingActionButton(
              heroTag: 'alert_info_btn',
              backgroundColor: Colors.black.withOpacity(0.50),
              elevation: 4,
              shape: const CircleBorder(side: BorderSide(color: Colors.white30)),
              onPressed: currentAlert == null ? null : () => _showAlertInfoPopup(currentAlert),
              child: const Icon(Icons.info_outline_rounded, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}
