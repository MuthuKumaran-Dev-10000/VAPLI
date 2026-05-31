part of '../property_builder_page.dart';


class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color typeColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.typeColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: isSelected
            ? _kAutoFill.withOpacity(0.07)
            : Colors.transparent,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 15, color: typeColor),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _kText)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: _kSub)),
              ])),
          if (isSelected)
            const Icon(Icons.check_rounded,
                size: 16, color: _kAutoFill),
        ]),
      ),
    );
  }
}
