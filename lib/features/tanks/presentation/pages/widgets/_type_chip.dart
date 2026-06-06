part of '../property_builder_page.dart';

class _TypeChip extends StatelessWidget {
  final String value;

  const _TypeChip([this.value = '']);

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'group') {
      return const SizedBox.shrink();
    }
    return const SizedBox.shrink();
  }
}
