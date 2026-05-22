part of '../property_builder_page.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _ParamPickerSheet
// ─────────────────────────────────────────────────────────────────────────────
class _ParamPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> params;
  final Map<String, dynamic>? current;

  const _ParamPickerSheet({required this.params, this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.data_object_rounded,
                    size: 16, color: _kAutoFill),
                const SizedBox(width: 8),
                Text('Select Parameter',
                    style: GoogleFonts.inter(
                        color: _kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                  'The parameter\'s live value will be substituted into the expression at read time.',
                  style: const TextStyle(color: _kSub, fontSize: 11)),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: _kBorder),
            _PickerTile(
              icon: Icons.block_outlined,
              label: 'None',
              subtitle: 'Clear selection',
              typeColor: _kSub,
              isSelected: current == null,
              onTap: () => Navigator.pop(context, <String, dynamic>{}),
            ),
            if (params.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const Icon(Icons.inbox_outlined,
                      color: _kSub, size: 32),
                  const SizedBox(height: 8),
                  const Text('No other parameters in this session yet.',
                      style: TextStyle(color: _kSub, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text(
                      'Add more parameters first; they\'ll appear here.',
                      style: TextStyle(color: _kSub, fontSize: 11)),
                ]),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(context).size.height * 0.45),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: params.length,
                  itemBuilder: (_, i) {
                    final p = params[i];
                    final isSelected = current?['id'] == p['id'];
                    return _PickerTile(
                      icon: _iconForType(p['type']?.toString() ?? ''),
                      label: p['label']?.toString() ?? '',
                      subtitle: p['type']?.toString() ?? '',
                      typeColor:
                          _colorForType(p['type']?.toString() ?? ''),
                      isSelected: isSelected,
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String t) {
    switch (t) {
      case 'number':
        return Icons.pin_outlined;
      case 'slider':
        return Icons.linear_scale;
      case 'dual_text':
        return Icons.view_column_outlined;
      default:
        return Icons.text_fields;
    }
  }

  Color _colorForType(String t) => const {
        'number': _kAccent,
        'text': _kSuccess,
        'dropdown': Color(0xFFBB86FC),
        'dual_text': _kWarn,
        'slider': Color(0xFF03DAC6),
        'multiline': Color(0xFF7986CB),
      }[t] ??
      _kSub;
}
