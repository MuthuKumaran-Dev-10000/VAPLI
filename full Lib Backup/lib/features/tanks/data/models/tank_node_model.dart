// lib/features/tanks/data/models/tank_node_model.dart
// ══════════════════════════════════════════════════════════════════════════════
// TankNode — one node in the infinite hierarchical tank tree.
//
// Two node types:
//   'folder'  — a container; holds other folders or leaf nodes
//   'leaf'    — an actual tank; holds a reference to tanks/{tankId}
//
// Firebase RTDB path:  tank_tree/{nodeId}
//
// Each node stores:
//   id          — Firebase push-key (set by repository)
//   type        — 'folder' | 'leaf'
//   name        — display name  (folder name OR tank name)
//   description — optional subtitle (shown for folders)
//   zone        — optional zone/location string
//   parent_id   — parent node id, or null for root nodes
//   path        — slash-separated chain of names from root → this node
//                 e.g.  "Factory A/Zone 2/Gear Box"
//                 Used in QR payload so scanners always know full context.
//   order       — integer position among siblings (for consistent ordering)
//   tank_id     — only present for leaf nodes; references tanks/{tankId}
//   created_at  — ISO timestamp
// ══════════════════════════════════════════════════════════════════════════════

class TankNode {
  final String id;
  final String type; // 'folder' | 'leaf'
  final String name;
  final String? description;
  final String? zone;
  final String? parentId; // null = root
  final String path; // full slash-path from root
  final int order;
  final String? tankId; // leaf only → tanks/{tankId}
  final String createdAt;

  const TankNode({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.zone,
    this.parentId,
    required this.path,
    required this.order,
    this.tankId,
    required this.createdAt,
  });

  bool get isFolder => type == 'folder';
  bool get isLeaf => type == 'leaf';

  // ── serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'description': description,
        'zone': zone,
        'parent_id': parentId,
        'path': path,
        'order': order,
        'tank_id': tankId,
        'created_at': createdAt,
      };

  factory TankNode.fromMap(String id, Map<dynamic, dynamic> m) => TankNode(
        id: id,
        type: m['type']?.toString() ?? 'folder',
        name: m['name']?.toString() ?? '',
        description: m['description']?.toString(),
        zone: m['zone']?.toString(),
        parentId: m['parent_id']?.toString(),
        path: m['path']?.toString() ?? '',
        order: (m['order'] as num?)?.toInt() ?? 0,
        tankId: m['tank_id']?.toString(),
        createdAt:
            m['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      );

  TankNode copyWith({
    String? name,
    String? description,
    String? zone,
    String? path,
    int? order,
  }) =>
      TankNode(
        id: id,
        type: type,
        name: name ?? this.name,
        description: description ?? this.description,
        zone: zone ?? this.zone,
        parentId: parentId,
        path: path ?? this.path,
        order: order ?? this.order,
        tankId: tankId,
        createdAt: createdAt,
      );
}
