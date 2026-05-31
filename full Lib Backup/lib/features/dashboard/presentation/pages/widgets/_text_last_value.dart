part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _TextLastValue — unchanged
// ─────────────────────────────────────────────────────────────────────────────
class _TextLastValue extends StatelessWidget {
  final String value;
  const _TextLastValue({required this.value});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.format_quote_rounded, size: 14, color: _kSubL),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _kText, fontStyle: FontStyle.italic)),
          ),
          Text('last',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, color: _kSubL, letterSpacing: 0.5)),
        ]),
      );
}
