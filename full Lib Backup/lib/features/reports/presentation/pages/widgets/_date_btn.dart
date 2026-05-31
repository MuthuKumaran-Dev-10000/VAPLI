part of '../trends_screen.dart';


class _DateBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _DateBtn(
      {required this.label,
      required this.icon,
      required this.onTap,
      required this.active});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: active ? _kCopper.withOpacity(0.08) : _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? _kCopper.withOpacity(0.4) : _kBorder),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: active ? _kCopper : _kSub),
            const SizedBox(width: 7),
            Text(label,
                style: GoogleFonts.dmSans(
                    color: active ? _kCopper : _kSub,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 12)),
          ]),
        ),
      );
}
