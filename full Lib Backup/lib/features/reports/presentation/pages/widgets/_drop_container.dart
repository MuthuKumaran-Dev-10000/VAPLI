part of '../trends_screen.dart';


class _DropContainer extends StatelessWidget {
  final Widget child;
  const _DropContainer({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: child,
      );
}
