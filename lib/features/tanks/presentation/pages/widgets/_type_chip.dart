part of '../property_builder_page.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _TypeChip
// ─────────────────────────────────────────────────────────────────────────────
class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  Color get _color => const {
        'number': _kAccent,
        'text': _kSuccess,
        'dropdown': Color(0xFFBB86FC),
        'dual_text': _kWarn,
        'slider': Color(0xFF03DAC6),
        'multiline': Color(0xFF7986CB),
      }[type] ??
      _kSub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: _color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _color.withOpacity(0.3))),
      child: Text(type,
          style: TextStyle(
              fontSize: 10,
              color: _color,
              fontWeight: FontWeight.w700)),
    );
  }
}
