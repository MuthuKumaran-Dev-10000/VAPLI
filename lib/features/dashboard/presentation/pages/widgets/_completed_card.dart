part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// COMPLETED TASK CARD
// ─────────────────────────────────────────────────────────────────────────────
class _CompletedCard extends StatefulWidget {
  final _CompletedTask task;
  const _CompletedCard({required this.task});

  @override
  State<_CompletedCard> createState() => _CompletedCardState();
}
