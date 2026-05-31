part of '../property_builder_page.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _Numpad
// ─────────────────────────────────────────────────────────────────────────────
class _Numpad extends StatelessWidget {
  final void Function(String) onInsert;
  final VoidCallback onDelete;

  const _Numpad({required this.onInsert, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', 'DEL'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: row.map((key) {
              final isDel = key == 'DEL';
              return Expanded(
                child: GestureDetector(
                  onTap: isDel ? onDelete : () => onInsert(key),
                  child: Container(
                    margin: EdgeInsets.only(
                        right: key == row.last ? 0 : 6),
                    height: 46,
                    decoration: BoxDecoration(
                      color: isDel
                          ? _kDanger.withOpacity(0.1)
                          : _kSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isDel
                              ? _kDanger.withOpacity(0.3)
                              : _kBorder),
                    ),
                    child: Center(
                      child: isDel
                          ? const Icon(Icons.backspace_outlined,
                              size: 18, color: _kDanger)
                          : Text(key,
                              style: GoogleFonts.sourceCodePro(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: _kText)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
