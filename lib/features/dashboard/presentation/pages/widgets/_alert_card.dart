part of '../dashboard_tab.dart';


class _AlertCard extends StatefulWidget {
  final _AlertModel alert;
  final VoidCallback onComplete;

  const _AlertCard({required this.alert, required this.onComplete});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}
