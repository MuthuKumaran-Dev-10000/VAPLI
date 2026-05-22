part of '../trends_screen.dart';


class _QrScanPageState extends State<_QrScanPage>
    with SingleTickerProviderStateMixin {
  bool _scanned = false;
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('Scan Tank QR',
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700, color: _kText, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kBorder),
        ),
      ),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_scanned) return;
            final raw = capture.barcodes.firstOrNull?.rawValue;
            if (raw != null) {
              _scanned = true;
              Navigator.pop(context, raw);
            }
          },
        ),
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _OverlayPainter(),
          ),
        ),
        Center(
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: _kCopper, width: 2.5),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ),
        Center(
          child: SizedBox(
            width: 240,
            height: 240,
            child: Stack(children: [
              _Corner(top: 0, left: 0, rotate: 0),
              _Corner(top: 0, right: 0, rotate: 90),
              _Corner(bottom: 0, right: 0, rotate: 180),
              _Corner(bottom: 0, left: 0, rotate: 270),
            ]),
          ),
        ),
        Positioned(
          bottom: 56,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: _kCard.withOpacity(0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBorder),
              ),
              child: Text('Point at tank QR code',
                  style: GoogleFonts.dmSans(color: _kText, fontSize: 13)),
            ),
          ),
        ),
      ]),
    );
  }
}
