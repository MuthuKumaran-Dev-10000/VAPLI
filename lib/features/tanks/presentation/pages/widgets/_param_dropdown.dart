part of '../property_builder_page.dart';


class _ParamDropdown extends StatefulWidget {
  final List<Map<String, dynamic>> params;
  final Future<void> Function(Map<String, dynamic>? param) onSelected;

  const _ParamDropdown({required this.params, required this.onSelected});

  @override
  State<_ParamDropdown> createState() => _ParamDropdownState();
}
