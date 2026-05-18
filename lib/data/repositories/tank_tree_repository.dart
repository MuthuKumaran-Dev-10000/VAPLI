// lib/data/repositories/tank_tree_repository.dart
// ══════════════════════════════════════════════════════════════════════════════
// CRITICAL FIX:
//   Firebase RTDB does NOT support orderByChild().equalTo(null).
//   Root nodes (parent_id == null) must be fetched differently:
//     • Fetch ALL nodes, then filter client-side for parent_id == null
//   Child nodes (parent_id == someId) work fine with equalTo(id).
//
// This is the ONLY change needed to fix the "creates but doesn't show" bug.
// All other logic is preserved exactly.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/tank_node_model.dart';

class TankTreeRepository {
  static const _root = 'tank_tree';

  final DatabaseReference _ref = FirebaseDatabase.instance.ref(_root);

  // ── READ ──────────────────────────────────────────────────────────────────

  /// Returns a live stream of direct children of [parentId].
  ///
  /// IMPORTANT: Pass null for [parentId] to get root-level nodes.
  /// Firebase RTDB cannot query equalTo(null), so root nodes are fetched
  /// by listening to the entire collection and filtering client-side.
  /// Non-root children use the efficient orderByChild query.
  Stream<List<TankNode>> watchChildren(String? parentId) {
    if (parentId == null) {
      // ── ROOT: listen to entire collection, filter client-side ─────────────
      debugPrint(
          '[TankTree] watchChildren(ROOT) — full scan, filter parent_id==null');
      return _ref.onValue.map((event) {
        if (!event.snapshot.exists || event.snapshot.value == null) {
          debugPrint('[TankTree] Root: snapshot empty');
          return <TankNode>[];
        }
        final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final nodes = raw.entries
            .map((e) => TankNode.fromMap(
                  e.key.toString(),
                  Map<dynamic, dynamic>.from(e.value as Map),
                ))
            .where((n) => n.parentId == null) // ← client-side filter
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        debugPrint('[TankTree] Root nodes found: ${nodes.length}');
        return nodes;
      });
    } else {
      // ── NON-ROOT: use indexed query — efficient ───────────────────────────
      debugPrint(
          '[TankTree] watchChildren(parentId=$parentId) — indexed query');
      return _ref
          .orderByChild('parent_id')
          .equalTo(parentId)
          .onValue
          .map((event) {
        if (!event.snapshot.exists || event.snapshot.value == null) {
          debugPrint('[TankTree] Children of $parentId: snapshot empty');
          return <TankNode>[];
        }
        final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final nodes = raw.entries
            .map((e) => TankNode.fromMap(
                  e.key.toString(),
                  Map<dynamic, dynamic>.from(e.value as Map),
                ))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        debugPrint('[TankTree] Children of $parentId: ${nodes.length} nodes');
        return nodes;
      });
    }
  }

  /// One-shot fetch of all nodes (used for path computation + deleteNode).
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
      parentId: parentId, // null for root → stored as null in Firebase
      path: path,
      order: order,
      createdAt: DateTime.now().toIso8601String(),
    );

    // IMPORTANT: toMap() must NOT write the key 'parent_id' when parentId==null,
    // OR write it as null — both work for the client-side filter above.
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
    final updates = <String, Object?>{for (final nid in toDelete) nid: null};
    await _ref.update(updates);
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Future<int> _nextOrder(String? parentId) async {
    final all = await fetchAll();
    final siblings = all.where((n) => n.parentId == parentId);
    if (siblings.isEmpty) return 0;
    return siblings.map((n) => n.order).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<String> _buildPath(String? parentId, String name) async {
    if (parentId == null) return name;
    final parent = await fetchNode(parentId);
    if (parent == null) return name;
    return '${parent.path}/$name';
  }

  Future<void> _propagatePath(
      String nodeId, String oldPath, String newPath) async {
    final all = await fetchAll();
    final descendants = _collectDescendants(nodeId, all);
    if (descendants.isEmpty) return;
    final updates = <String, Object?>{};
    for (final did in descendants) {
      final d = all.firstWhere((n) => n.id == did);
      updates['$did/path'] = d.path.replaceFirst(oldPath, newPath);
    }
    await _ref.update(updates);
    debugPrint(
        '[TankTree] Propagated path to ${descendants.length} descendants');
  }

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

  // ─────────────────────────────────────────────────────────────
  // MOVE NODE
  //
  // Supports:
  //  root → folder
  //  folder → root
  //  folder → folder
  //  leaf → folder
  //
  // Also rebuilds full path recursively.
  // ─────────────────────────────────────────────────────────────
  Future<void> moveNode({
    required String nodeId,
    required String? newParentId,
  }) async {
    final nodeSnap = await _ref.child(nodeId).get();

    if (!nodeSnap.exists) {
      throw Exception('Node not found');
    }

    final node = TankNode.fromMap(
      nodeId,
      Map<dynamic, dynamic>.from(nodeSnap.value as Map),
    );

    // same parent → ignore
    if (node.parentId == newParentId) return;

    // prevent moving into itself
    if (node.id == newParentId) {
      throw Exception('Cannot move into itself');
    }

    String newPath = node.name;

    // build parent path
    if (newParentId != null) {
      final parentSnap = await _ref.child(newParentId).get();

      if (!parentSnap.exists) {
        throw Exception('Parent not found');
      }

      final parent = TankNode.fromMap(
        newParentId,
        Map<dynamic, dynamic>.from(parentSnap.value as Map),
      );

      // prevent cycles
      if (parent.path.startsWith(node.path)) {
        throw Exception('Cannot move into child folder');
      }

      newPath = '${parent.path}/${node.name}';
    }

    await _ref.child(nodeId).update({
      'parent_id': newParentId,
      'path': newPath,
    });

    // rebuild descendants
    await _updateDescendantPaths(
      parentId: nodeId,
      parentPath: newPath,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // REORDER SIBLINGS
  //
  // Input:
  // [id1,id2,id3,id4]
  // ─────────────────────────────────────────────────────────────
  Future<void> reorderNodes(List<String> nodeIds) async {
    final updates = <String, dynamic>{};

    for (int i = 0; i < nodeIds.length; i++) {
      updates['${nodeIds[i]}/order'] = i;
    }

    await _ref.update(updates);
  }

  // ─────────────────────────────────────────────────────────────
  // INTERNAL:
  // recursively fixes child paths
  //
  // Example:
  // A/B/C
  //
  // move B → X
  //
  // becomes:
  // X/B/C
  // ─────────────────────────────────────────────────────────────
  Future<void> _updateDescendantPaths({
    required String parentId,
    required String parentPath,
  }) async {
    final childrenSnap = await _ref.get();

    if (!childrenSnap.exists) return;

    final all = Map<dynamic, dynamic>.from(
      childrenSnap.value as Map,
    );

    for (final entry in all.entries) {
      final id = entry.key.toString();

      final node = TankNode.fromMap(
        id,
        Map<dynamic, dynamic>.from(entry.value),
      );

      if (node.parentId != parentId) {
        continue;
      }

      final childPath = '$parentPath/${node.name}';

      await _ref.child(id).update({
        'path': childPath,
      });

      await _updateDescendantPaths(
        parentId: id,
        parentPath: childPath,
      );
    }
  }

  Future<int> countChildren(String parentId) async {
    final snap = await _ref.orderByChild('parent_id').equalTo(parentId).get();

    if (!snap.exists) return 0;

    final map = Map<dynamic, dynamic>.from(snap.value as Map);

    return map.length;
  }
}
//
