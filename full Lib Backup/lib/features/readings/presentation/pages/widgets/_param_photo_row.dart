part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// PER-PARAM PHOTO ROW
// ─────────────────────────────────────────────────────────────────────────────
class _ParamPhotoRow extends StatelessWidget {
  final File? image;
  final String? uploadedUrl;
  final bool uploading;
  final VoidCallback onCapture;

  const _ParamPhotoRow({
    required this.image,
    required this.uploadedUrl,
    required this.uploading,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    final captured = image != null;
    final hasUrl = uploadedUrl != null;

    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: uploading ? null : onCapture,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: hasUrl
                  ? _kSuccess.withOpacity(0.08)
                  : captured
                      ? _kCopper.withOpacity(0.08)
                      : _kTeal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: hasUrl
                      ? _kSuccess.withOpacity(0.4)
                      : captured
                          ? _kCopper.withOpacity(0.4)
                          : _kTeal.withOpacity(0.4)),
            ),
            child: uploading
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: _kCopper, strokeWidth: 2)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasUrl
                            ? Icons.cloud_done_rounded
                            : captured
                                ? Icons.camera_alt_rounded
                                : Icons.camera_alt_outlined,
                        color: hasUrl
                            ? _kSuccess
                            : captured
                                ? _kCopper
                                : _kTeal,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasUrl
                            ? 'Retake Photo'
                            : captured
                                ? 'Uploading…'
                                : 'Capture Photo',
                        style: GoogleFonts.dmSans(
                            color: hasUrl
                                ? _kSuccess
                                : captured
                                    ? _kCopper
                                    : _kTeal,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ],
                  ),
          ),
        ),
      ),
      if (captured) ...[
        const SizedBox(width: 12),
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(image!, width: 54, height: 54, fit: BoxFit.cover),
          ),
          if (hasUrl)
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                    color: _kSuccess, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 9, color: Colors.white),
              ),
            ),
        ]),
      ],
    ]);
  }
}
