part of '../tank_browser_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// PRINTABLE QR
// ─────────────────────────────────────────────────────────────────────────────
class _PrintableQr extends StatelessWidget {
  final TankNode node;
  final TankModel? tank;
  const _PrintableQr({required this.node, required this.tank});

  String get _data {
    final t = tank;
    return [
      'path:${node.path}',
      'tank_id:${node.tankId ?? ''}',
      'tank_code:${t?.tankCode ?? ''}',
      'tank_name:${t?.tankName ?? node.name}',
      'zone:${node.zone ?? t?.location ?? ''}',
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    final t = tank;
    final name = t?.tankName ?? node.name;
    final code = t?.tankCode ?? '';
    final zone = node.zone ?? t?.location ?? '';
    return Container(
      width: 280,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        QrImageView(
            data: _data,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero),
        Container(
          width: 220,
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0xFFCCCCCC), width: 0.8))),
          child: Column(children: [
            Text(name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900)),
            if (code.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('ID: $code',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8)),
            ],
            if (zone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Client: ${zone.isEmpty ? 'root' : zone}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ],
          ]),
        ),
      ]),
    );
  }
}
