part of '../property_builder_page.dart';


class _DarkTextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;

  const _DarkTextField({
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder));
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: _kText, fontSize: 14),
      cursorColor: _kAccent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kSub, fontSize: 13),
        prefixIcon: maxLines == 1
            ? Icon(icon, size: 17, color: _kSub)
            : null,
        filled: true,
        fillColor: _kSurface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: _kAccent, width: 1.5)),
      ),
    );
  }
}
