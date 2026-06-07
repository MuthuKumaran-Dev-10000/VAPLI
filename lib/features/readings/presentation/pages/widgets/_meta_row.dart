part of '../reading_entry_screen.dart';


class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? suffixIcon; // 🔖 Added for Historical Upload Permission

  const _MetaRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.suffixIcon, // 🔖 Added for Historical Upload Permission
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110, // 🔖 Increased width for longer labels (Historical Upload Permission)
            child: Text(label,
                style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      style: GoogleFonts.dmSans(
                          color: valueColor ?? _kText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ),
                if (suffixIcon != null) ...[
                  const SizedBox(width: 4),
                  Icon(suffixIcon, size: 14, color: _kCopper),
                ],
              ],
            ),
          ),
        ]),
      );
}
