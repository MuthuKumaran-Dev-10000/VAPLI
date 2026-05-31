part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// DETAIL ROW
// ─────────────────────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  bool get _isImage {
    final v = value.toLowerCase();
    return v.contains('.png') ||
        v.contains('.jpg') ||
        v.contains('.jpeg') ||
        v.contains('firebasestorage') ||
        v.contains('http');
  }

  String _beautifyConstraint(String raw) {
    if (raw.trim().isEmpty) return '—';

    final v = raw
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();

    return v
        .split(' ')
        .map((e) =>
            e.isEmpty ? '' : '${e[0].toUpperCase()}${e.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final displayValue =
        label.toLowerCase().contains('constraint')
            ? _beautifyConstraint(value)
            : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                color: _kSub,
                fontSize: 11,
              ),
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: _isImage
                ? _ImageThumb(url: value)
                : Text(
                    displayValue,
                    style: GoogleFonts.dmSans(
                      color: _kText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
