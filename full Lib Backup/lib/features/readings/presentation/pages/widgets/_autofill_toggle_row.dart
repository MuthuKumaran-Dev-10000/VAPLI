part of '../reading_entry_screen.dart';


class _AutofillToggleRow extends StatelessWidget {
  final bool isAutofillEnabled;
  final ValueChanged<bool> onToggle;

  const _AutofillToggleRow({
    required this.isAutofillEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kPurple.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPurple.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high_rounded, size: 14, color: _kPurple),
          const SizedBox(width: 8),
          Text('Autofill',
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: _kPurple,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text('(auto-calculate)',
              style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
          const Spacer(),
          // Autofill ON radio
          GestureDetector(
            onTap: () => onToggle(true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: isAutofillEnabled,
                  onChanged: (v) => onToggle(true),
                  activeColor: _kPurple,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Text('ON',
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: isAutofillEnabled ? _kPurple : _kSub,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Manual (autofill OFF) radio
          GestureDetector(
            onTap: () => onToggle(false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<bool>(
                  value: false,
                  groupValue: isAutofillEnabled,
                  onChanged: (v) => onToggle(false),
                  activeColor: _kCopper,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Text('Manual',
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: !isAutofillEnabled ? _kCopper : _kSub,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
