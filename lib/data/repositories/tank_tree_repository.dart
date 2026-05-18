// lib/data/repositories/tank_tree_repository.dart
// ══════════════════════════════════════════════════════════════════════════════
// TankTreeRepository
//
// Firebase RTDB schema:
//   /tank_tree/{nodeId}/
//       type, name, description, zone, parent_id, path,
//       order, tank_id, created_at
//
// Design:
//   • Root nodes   → parent_id == null
//   • Children     → parent_id == parent's nodeId
//   • path field   → always maintained as full slash-chain; used in QR
//   • order        → position among siblings; repository reorders on demand
// ══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/tank_node_model.dart';

class TankTreeRepository {
  static const _root = 'tank_tree';

  final DatabaseReference _ref = FirebaseDatabase.instance.ref(_root);

  // ── READ ──────────────────────────────────────────────────────────────────

  /// Returns a live stream of direct children of [parentId].
  /// Pass null for [parentId] to get root-level nodes.
  Stream<List<TankNode>> watchChildren(String? parentId) {
    final query = parentId == null
        ? _ref.orderByChild('parent_id').equalTo(null)
        : _ref.orderByChild('parent_id').equalTo(parentId);

    return query.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final nodes = raw.entries
          .map((e) => TankNode.fromMap(
                e.key.toString(),
                Map<dynamic, dynamic>.from(e.value as Map),
              ))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      debugPrint(
          '[TankTree] watchChildren(parentId=$parentId) → ${nodes.length} nodes');
      return nodes;
    });
  }

  /// One-shot fetch of all nodes (used for path computation).
  Future<List<TankNode>> fetchAll() async {
    final snap = await _ref.get();
    if (!snap.exists || snap.value == null) return [];
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);
    return raw.entries
        .map((e) => TankNode.fromMap(
              e.key.toString(),
              Map<dynamic, dynamic>.from(e.value as Map),
            ))
        .toList();
  }

  /// Fetch a single node by id.
  Future<TankNode?> fetchNode(String id) async {
    final snap = await _ref.child(id).get();
    if (!snap.exists || snap.value == null) return null;
    return TankNode.fromMap(id, Map<dynamic, dynamic>.from(snap.value as Map));
  }

  // ── WRITE ─────────────────────────────────────────────────────────────────

  /// Creates a new folder node under [parentId] (null = root).
  Future<TankNode> createFolder({
    required String name,
    String? description,
    String? zone,
    String? parentId,
  }) async {
    debugPrint('[TankTree] createFolder name=$name parentId=$parentId');
    final order = await _nextOrder(parentId);
    final path = await _buildPath(parentId, name);
    final newRef = _ref.push();
    final id = newRef.key!;
    final node = TankNode(
      id: id,
      type: 'folder',
      name: name,
      description: description,
      zone: zone,
      parentId: parentId,
      path: path,
      order: order,
      createdAt: DateTime.now().toIso8601String(),
    );
    await newRef.set(node.toMap());
    debugPrint('[TankTree] Folder created: id=$id path=$path');
    return node;
  }

  /// Creates a new leaf node pointing at an existing tank record.
  Future<TankNode> createLeaf({
    required String name,
    required String tankId,
    String? zone,
    String? parentId,
  }) async {
    debugPrint(
        '[TankTree] createLeaf name=$name tankId=$tankId parentId=$parentId');
    final order = await _nextOrder(parentId);
    final path = await _buildPath(parentId, name);
    final newRef = _ref.push();
    final id = newRef.key!;
    final node = TankNode(
      id: id,
      type: 'leaf',
      name: name,
      zone: zone,
      parentId: parentId,
      path: path,
      order: order,
      tankId: tankId,
      createdAt: DateTime.now().toIso8601String(),
    );
    await newRef.set(node.toMap());
    debugPrint('[TankTree] Leaf created: id=$id path=$path tankId=$tankId');
    return node;
  }

  /// Renames / updates a folder node's name, description, or zone.
  /// Also propagates the path change to all descendants.
  Future<void> updateFolder({
    required String id,
    required String name,
    String? description,
    String? zone,
  }) async {
    debugPrint('[TankTree] updateFolder id=$id name=$name');
    final node = await fetchNode(id);
    if (node == null) throw Exception('Node $id not found');

    final newPath = await _buildPath(node.parentId, name);
    final oldPath = node.path;

    await _ref.child(id).update({
      'name': name,
      'description': description,
      'zone': zone,
      'path': newPath,
    });
    debugPrint('[TankTree] Folder updated: id=$id new path=$newPath');

    // Propagate path change to all descendants
    if (oldPath != newPath) {
      await _propagatePath(id, oldPath, newPath);
    }
  }

  /// Deletes a node and all its descendants (recursive).
  Future<void> deleteNode(String id) async {
    debugPrint('[TankTree] deleteNode id=$id');
    final all = await fetchAll();
    final toDelete = _collectDescendants(id, all)..add(id);
    debugPrint('[TankTree] Deleting ${toDelete.length} node(s)');
    final updates = <String, Object?>{
      for (final nid in toDelete) nid: null,
    };
    await _ref.update(updates);
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  /// Returns the next order value for a new sibling under [parentId].
  Future<int> _nextOrder(String? parentId) async {
    final all = await fetchAll();
    final siblings = all.where((n) => n.parentId == parentId);
    if (siblings.isEmpty) return 0;
    return siblings.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// Builds the full slash-path for a node: "Parent / GrandParent / name"
  Future<String> _buildPath(String? parentId, String name) async {
    if (parentId == null) return name;
    final parent = await fetchNode(parentId);
    if (parent == null) return name;
    return '${parent.path}/$name';
  }

  /// Propagates a path rename to every descendant of [nodeId].
  Future<void> _propagatePath(
      String nodeId, String oldPath, String newPath) async {
    final all = await fetchAll();
    final descendants = _collectDescendants(nodeId, all);
    if (descendants.isEmpty) return;
    final updates = <String, Object?>{};
    for (final did in descendants) {
      final d = all.firstWhere((n) => n.id == did);
      final updatedPath = d.path.replaceFirst(oldPath, newPath);
      updates['$did/path'] = updatedPath;
    }
    await _ref.update(updates);
    debugPrint(
        '[TankTree] Propagated path to ${descendants.length} descendants');
  }

  /// Returns ids of all descendants of [nodeId] (BFS).
  List<String> _collectDescendants(String nodeId, List<TankNode> all) {
    final result = <String>[];
    final queue = <String>[nodeId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final children = all.where((n) => n.parentId == current);
      for (final c in children) {
        result.add(c.id);
        queue.add(c.id);
      }
    }
    return result;
  }
}
