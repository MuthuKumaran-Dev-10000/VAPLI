part of '../property_builder_page.dart';

class _ParamDropdownState extends State<_ParamDropdown> {
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final items = <MapEntry<String, Map<String, dynamic>>>[];
    for (var index = 0; index < widget.params.length; index++) {
      final param = widget.params[index];
      if (param.isEmpty) continue;
      final label = (param['label']?.toString().trim() ?? '');
      if (label.isEmpty) continue;
      final token = param['token']?.toString().trim();
      final id = param['id']?.toString().trim();
      final key = [
        label,
        if (token != null && token.isNotEmpty) token,
        if (id != null && id.isNotEmpty) id,
        index.toString(),
      ].join('|');
      items.add(MapEntry(key, param));
    }

    if (_selectedKey != null && !items.any((entry) => entry.key == _selectedKey)) {
      _selectedKey = null;
    }

    return DropdownButtonHideUnderline(
      child: DropdownButtonFormField<String>(
        value: _selectedKey,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        hint: const Text('Select parameter'),
        items: items
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.key, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          setState(() => _selectedKey = value);
          Map<String, dynamic>? match;
          for (final entry in items) {
            if (entry.key == value) {
              match = entry.value;
              break;
            }
          }
          widget.onSelected(match);
        },
      ),
    );
  }
}
