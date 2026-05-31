part of '../property_builder_page.dart';


class _ParamDropdownState extends State<_ParamDropdown> {
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(children: [
          const Icon(Icons.data_object_rounded, size: 15, color: _kSub),
          const SizedBox(width: 8),
          Expanded(
            child: _selected == null
                ? const Text('Select a parameter to insert…',
                    style: TextStyle(color: _kSub, fontSize: 13))
                : Row(children: [
                    Text(
                        _selected!['label']?.toString() ?? '',
                        style: const TextStyle(
                            color: _kText, fontSize: 13)),
                    const SizedBox(width: 8),
                    _TypeChip(
                        type: _selected!['type']?.toString() ?? ''),
                  ]),
          ),
          const Icon(Icons.arrow_drop_down, color: _kSub, size: 20),
        ]),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _ParamPickerSheet(params: widget.params, current: _selected),
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      setState(() => _selected = null);
      return;
    }
    setState(() => _selected = picked);
    await widget.onSelected(picked);
  }
}
