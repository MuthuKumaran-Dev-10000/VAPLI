part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// AUTOFILL STATUS SECTION
// Shows: expression display, dependency status list, computed result / error
// ─────────────────────────────────────────────────────────────────────────────
class _AutofillStatusSection extends StatelessWidget {
  final String paramId;
  final List<Map<String, dynamic>> props;
  final Map<String, bool> depsStatus;
  final _AutofillResult? autofillResult;
  final bool isAutofillEnabled;
  final String expressionDisplay;

  const _AutofillStatusSection({
    required this.paramId,
    required this.props,
    required this.depsStatus,
    required this.autofillResult,
    required this.isAutofillEnabled,
    required this.expressionDisplay,
  });

  String _labelForId(String id) {
    final p = props.firstWhere((pp) => pp['id'] == id,
        orElse: () => {'label': id});
    return p['label'] as String? ?? id;
  }

  @override
  Widget build(BuildContext context) {
    if (!isAutofillEnabled) return const SizedBox.shrink();
    if (depsStatus.isEmpty) return const SizedBox.shrink();

    final allFilled = depsStatus.values.every((v) => v);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPurple.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPurple.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expression display
          if (expressionDisplay.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.functions_rounded, size: 13, color: _kPurple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  expressionDisplay,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: _kPurple,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 10),
          ],

          // Dependency status list
          Text('Required fields for calculation:',
              style: GoogleFonts.dmSans(
                  fontSize: 10, color: _kSub, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...depsStatus.entries.map((entry) {
            final filled = entry.value;
            final lbl = _labelForId(entry.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: filled
                        ? const Icon(Icons.check_circle_rounded,
                            size: 14,
                            color: _kSuccess,
                            key: ValueKey('filled'))
                        : const Icon(Icons.cancel_rounded,
                            size: 14,
                            color: _kDanger,
                            key: ValueKey('empty')),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    lbl,
                    style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: filled ? _kSuccess : _kDanger,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    filled ? 'filled' : 'not filled',
                    style: GoogleFonts.dmSans(
                        fontSize: 10,
                        color: filled
                            ? _kSuccess.withOpacity(0.7)
                            : _kDanger.withOpacity(0.7)),
                  ),
                ],
              ),
            );
          }),

          // Result / waiting / error
          const SizedBox(height: 8),
          if (!allFilled)
            Row(children: [
              const Icon(Icons.hourglass_empty_rounded,
                  size: 13, color: _kSub),
              const SizedBox(width: 6),
              Text('Fill all required fields to calculate',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
            ])
          else if (autofillResult == null)
            Row(children: [
              const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      color: _kPurple, strokeWidth: 1.5)),
              const SizedBox(width: 6),
              Text('Calculating…',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _kPurple)),
            ])
          else if (autofillResult!.hasError)
            _AutofillErrorCard(
              laymanMessage: autofillResult!.errorMessage ?? 'Unknown error',
              exceptionName: autofillResult!.exceptionName ?? '',
            )
          else
            _AutofillResultCard(value: autofillResult!.value!),
        ],
      ),
    );
  }
}
