part of '../property_builder_page.dart';

class _ExpressionDisplay extends StatelessWidget {
  final TextEditingController rawController;
  final TextEditingController displayController;
  final FocusNode focusNode;
  final String? error;
  final VoidCallback? onDeleteBackward;
  final VoidCallback? onDeleteForward;

  const _ExpressionDisplay({
    required this.rawController,
    required this.displayController,
    required this.focusNode,
    this.error,
    this.onDeleteBackward,
    this.onDeleteForward,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    final isEmpty = rawController.text.trim().isEmpty;
    final borderColor = hasError
        ? _kDanger
        : isEmpty
            ? _kBorder
            : _kAutoFill.withOpacity(0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(children: [
            if (displayController.text.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _kBorder)),
                ),
                child: _buildDisplayPreview(displayController.text),
              ),
            Focus(
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.backspace) {
                  onDeleteBackward?.call();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.delete) {
                  onDeleteForward?.call();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: rawController,
                focusNode: focusNode,
                style: GoogleFonts.sourceCodePro(color: _kText, fontSize: 13),
                cursorColor: _kAutoFill,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[\d\+\-\*\/\(\)\.\s\$\{\}:a-zA-Z_\-]'),
                  ),
                ],
                decoration: const InputDecoration(
                  hintText: r'e.g. ${123}+${456:right}',
                  hintStyle: TextStyle(color: _kSub, fontSize: 12, fontFamily: 'monospace'),
                  filled: true,
                  fillColor: _kBg,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 5),
        if (hasError)
          Row(children: [
            const Icon(Icons.error_outline, size: 12, color: _kDanger),
            const SizedBox(width: 4),
            Text(error!, style: const TextStyle(color: _kDanger, fontSize: 11)),
          ])
        else if (!isEmpty)
          Row(children: const [
            Icon(Icons.check_circle_outline, size: 12, color: _kSuccess),
            SizedBox(width: 4),
            Text('Expression looks valid - tap "Save Expression" to commit', style: TextStyle(color: _kSuccess, fontSize: 11)),
          ]),
      ],
    );
  }

  Widget _buildDisplayPreview(String expr) {
    final parts = <InlineSpan>[];
    final tokenRe = RegExp(r'\[([^\]]+)\]');
    int lastEnd = 0;
    for (final m in tokenRe.allMatches(expr)) {
      if (m.start > lastEnd) {
        parts.add(TextSpan(
          text: expr.substring(lastEnd, m.start),
          style: GoogleFonts.sourceCodePro(color: _kText, fontSize: 12),
        ));
      }
      parts.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _kAutoFill.withOpacity(0.15),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _kAutoFill.withOpacity(0.4)),
          ),
          child: Text(
            m.group(1) ?? '',
            style: GoogleFonts.sourceCodePro(color: _kAutoFill, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ));
      lastEnd = m.end;
    }
    if (lastEnd < expr.length) {
      parts.add(TextSpan(
        text: expr.substring(lastEnd),
        style: GoogleFonts.sourceCodePro(color: _kText, fontSize: 12),
      ));
    }
    return RichText(text: TextSpan(children: parts), overflow: TextOverflow.ellipsis);
  }
}
