part of '../dashboard_tab.dart';


class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  static const _colors = <String, Color>{
    'number': _kTeal,
    'slider': Color(0xFF03DAC6),
    'dropdown': _kPurple,
    'text': _kSuccess,
    'multiline': Color(0xFF7986CB),
    'dual_text': _kWarn,
  };
  static const _labels = <String, String>{
    'number': 'NUM',
    'slider': 'SLIDE',
    'dropdown': 'DROP',
    'text': 'TEXT',
    'multiline': 'MULTI',
    'dual_text': 'DUAL',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type] ?? _kSub;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5)),
      child: Text(
        _labels[type] ?? type.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8),
      ),
    );
  }
}
