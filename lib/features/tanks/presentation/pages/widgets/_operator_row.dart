part of '../property_builder_page.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _OperatorRow
// ─────────────────────────────────────────────────────────────────────────────
class _OperatorRow extends StatelessWidget {
  final void Function(String) onInsert;

  const _OperatorRow({required this.onInsert});

  static const _ops = [
    ('+', 'Add'),
    ('-', 'Sub'),
    ('*', 'Mul'),
    ('/', 'Div'),
    ('(', 'Open'),
    (')', 'Close'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _ops.map((op) {
        return Expanded(
          child: GestureDetector(
            onTap: () => onInsert(op.$1),
            child: Container(
              margin: EdgeInsets.only(right: op == _ops.last ? 0 : 6),
              height: 44,
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(op.$1,
                          style: GoogleFonts.sourceCodePro(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _kAutoFill)),
                      Text(op.$2,
                          style: const TextStyle(
                              fontSize: 8, color: _kSub)),
                    ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
