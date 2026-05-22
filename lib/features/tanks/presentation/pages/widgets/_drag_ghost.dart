part of '../tank_browser_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// DRAG GHOST
// ─────────────────────────────────────────────────────────────────────────────
class _DragGhost extends StatelessWidget {
  final Widget child;
  final double width;
  const _DragGhost({required this.child, required this.width});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: 0.88,
        child: Material(
          color: Colors.transparent,
          elevation: 24,
          shadowColor: _kCopper.withOpacity(0.45),
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(width: width, child: child),
        ),
      );
}
