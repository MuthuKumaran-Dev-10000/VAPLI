part of '../property_builder_page.dart';


class _RangeRow extends StatelessWidget {
  final TextEditingController minCtrl;
  final TextEditingController avgCtrl;
  final TextEditingController maxCtrl;
  final TextInputType keyboardType;

  const _RangeRow({
    required this.minCtrl,
    required this.avgCtrl,
    required this.maxCtrl,
    required this.keyboardType,
  });

  InputDecoration _dec(String label) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF252830)));
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: Color(0xFF8A8F9C), fontSize: 11),
      hintStyle:
          const TextStyle(color: Color(0xFF8A8F9C), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF0C0D0F),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
              color: Color(0xFF1ABCBD), width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: TextField(
        controller: minCtrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFF0EEE9), fontSize: 13),
        cursorColor: const Color(0xFF1ABCBD),
        decoration: _dec('Min'),
      )),
      const SizedBox(width: 8),
      Expanded(
          child: TextField(
        controller: avgCtrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFF0EEE9), fontSize: 13),
        cursorColor: const Color(0xFF1ABCBD),
        decoration: _dec('Avg'),
      )),
      const SizedBox(width: 8),
      Expanded(
          child: TextField(
        controller: maxCtrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFF0EEE9), fontSize: 13),
        cursorColor: const Color(0xFF1ABCBD),
        decoration: _dec('Max'),
      )),
    ]);
  }
}
