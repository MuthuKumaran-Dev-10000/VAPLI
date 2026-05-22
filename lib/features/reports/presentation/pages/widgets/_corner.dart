part of '../trends_screen.dart';


class _Corner extends StatelessWidget {
  final double? top, left, right, bottom;
  final double rotate;
  const _Corner(
      {this.top, this.left, this.right, this.bottom, required this.rotate});

  @override
  Widget build(BuildContext context) => Positioned(
        top: top,
        left: left,
        right: right,
        bottom: bottom,
        child: Transform.rotate(
          angle: rotate * 3.14159 / 180,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: _kCopperL, width: 3),
                left: BorderSide(color: _kCopperL, width: 3),
              ),
            ),
          ),
        ),
      );
}
