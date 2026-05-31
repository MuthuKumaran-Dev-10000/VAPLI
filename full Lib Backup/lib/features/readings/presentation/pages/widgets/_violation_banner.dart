part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// VIOLATION BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _ViolationBanner extends StatelessWidget {
  final _Violation violation;
  final File? violationPhoto;
  final bool isUploading;
  final bool hasUploadedUrl;
  final VoidCallback? onCapturePhoto;

  const _ViolationBanner({
    required this.violation,
    required this.violationPhoto,
    required this.isUploading,
    required this.hasUploadedUrl,
    this.onCapturePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(violation.severity);
    final icon = _severityIcon(violation.severity);

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(violation.alertTitle,
                  style: GoogleFonts.dmSans(
                      color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            if (violation.blockSubmission)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _kDanger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('BLOCKED',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 8,
                        color: _kDanger,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 3),
                Text('LIVE',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 7,
                        color: color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 5),
          Text(violation.message,
              style: GoogleFonts.dmSans(color: _kText, fontSize: 12)),

          if (violation.captureImageOnViolation) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCapturePhoto,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: hasUploadedUrl
                          ? _kSuccess.withOpacity(0.08)
                          : violationPhoto != null
                              ? _kCopper.withOpacity(0.08)
                              : _kDanger.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: hasUploadedUrl
                              ? _kSuccess.withOpacity(0.4)
                              : violationPhoto != null
                                  ? _kCopper.withOpacity(0.4)
                                  : _kDanger.withOpacity(0.5)),
                    ),
                    child: isUploading
                        ? const Center(
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: _kCopper, strokeWidth: 2)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                hasUploadedUrl
                                    ? Icons.cloud_done_rounded
                                    : violationPhoto != null
                                        ? Icons.camera_alt_rounded
                                        : Icons.camera_alt_outlined,
                                size: 18,
                                color: hasUploadedUrl
                                    ? _kSuccess
                                    : violationPhoto != null
                                        ? _kCopper
                                        : _kDanger,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                hasUploadedUrl
                                    ? 'Retake Evidence Photo'
                                    : violationPhoto != null
                                        ? 'Uploading…'
                                        : 'Capture Evidence Photo *',
                                style: GoogleFonts.dmSans(
                                  color: hasUploadedUrl
                                      ? _kSuccess
                                      : violationPhoto != null
                                          ? _kCopper
                                          : _kDanger,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              if (violationPhoto != null) ...[
                const SizedBox(width: 10),
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(violationPhoto!,
                        width: 46, height: 46, fit: BoxFit.cover),
                  ),
                  if (hasUploadedUrl)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: const BoxDecoration(
                            color: _kSuccess, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 8, color: Colors.white),
                      ),
                    ),
                ]),
              ],
            ]),
          ],

          if (violation.playSoundOnViolation ||
              violation.showDashboardAlert ||
              violation.storeHistory) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              if (violation.playSoundOnViolation)
                _ActionChip(
                    icon: Icons.volume_up_rounded,
                    label: 'Sound',
                    color: color),
              if (violation.showDashboardAlert)
                _ActionChip(
                    icon: Icons.dashboard_customize_outlined,
                    label: 'Dashboard Alert',
                    color: color),
              if (violation.storeHistory)
                _ActionChip(
                    icon: Icons.history_rounded, label: 'Logged', color: color),
            ]),
          ],
        ],
      ),
    );
  }
}
