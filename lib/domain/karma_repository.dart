import 'dart:collection';
import 'content.dart';
import 'models.dart';

/// Presentation contracts contain only already-discovered information.
class KarmaNode {
  const KarmaNode({
    required this.id,
    required this.entityId,
    required this.type,
    required this.displayName,
    required this.importance,
    required this.alive,
    required this.createdGameTime,
    required this.lastUpdatedGameTime,
    required this.description,
    this.visibility = '已知',
  });
  final String id, entityId, displayName, description, visibility;
  final KarmaNodeType type;
  final int importance, createdGameTime, lastUpdatedGameTime;
  final bool alive;
  bool get discovered => true;
}

class KarmaEdge {
  const KarmaEdge({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.relationType,
    required this.strength,
    required this.status,
    this.resolved = false,
    required this.bidirectional,
    required this.createdGameTime,
    required this.updatedGameTime,
    required this.relatedEventIds,
    required this.visibilityLevel,
    this.inheritedFrom,
  });
  final String id, sourceNodeId, targetNodeId, visibilityLevel;
  final KarmaRelationType relationType;
  final int strength, createdGameTime, updatedGameTime;
  final RelationStatus status;
  final bool resolved;
  final bool bidirectional;
  final List<String> relatedEventIds;
  final String? inheritedFrom;
}

class VisibleEvent {
  const VisibleEvent({
    required this.id,
    required this.time,
    required this.title,
    required this.description,
    required this.locationName,
    required this.participants,
    required this.causes,
    required this.consequences,
    required this.relations,
    required this.importance,
  });
  final String id, title, description, locationName;
  final int time, importance;
  final List<KarmaNode> participants;
  final List<Cause> causes;
  final List<Cause> consequences;
  final List<KarmaEdge> relations;
}

class GraphQuery {
  const GraphQuery({
    this.center,
    this.hops = 1,
    this.limit = 80,
    this.types = const {},
    this.minimumStrength = 0,
    this.statuses = const {},
    this.worldView = false,
  });
  final String? center;
  final int hops, limit, minimumStrength;
  final Set<KarmaRelationType> types;
  final Set<RelationStatus> statuses;
  final bool worldView;
}

class KarmaGraph {
  const KarmaGraph(
    this.nodes,
    this.edges,
    this.depths, {
    this.truncated = false,
    this.revision = 0,
  });
  final List<KarmaNode> nodes;
  final List<KarmaEdge> edges;
  final Map<String, int> depths;
  final bool truncated;
  final int revision;
}

class KarmaRepository {
  KarmaRepository(this._world, {String? observer})
    : _observer = observer ?? _world.playerId {
    for (final k in _world.knowledge.values) {
      if (k.observer != _observer || !k.confirmed) {
        continue;
      }
      _known.add(k.subject);
    }
    for (final id in _known) {
      final r = _world.relations[id];
      if (r != null && _visibleRelation(r)) {
        _adjacency.putIfAbsent(r.source, () => []).add(r);
        _adjacency.putIfAbsent(r.target, () => []).add(r);
      }
    }
    // Prefer unresolved social obligations over old event participation when
    // a bounded subgraph must choose which neighbors to include.
    for (final edges in _adjacency.values) {
      edges.sort((a, b) {
        int priority(Relation r) =>
            (r.type == KarmaRelationType.eventParticipation ? 0 : 1000) +
            (_status(r) == RelationStatus.active ? 200 : 0) +
            _strength(r);
        final result = priority(b).compareTo(priority(a));
        return result != 0 ? result : a.id.compareTo(b.id);
      });
    }
    for (final id in _known) {
      final e = _world.events[id];
      if (e != null) {
        _timeIndex.add(e);
      }
      final n = _world.entities[id];
      if (n != null) {
        _searchIndex.add(n);
      }
    }
    _timeIndex.sort((a, b) {
      final t = a.time.compareTo(b.time);
      return t != 0 ? t : _sequence(a.id).compareTo(_sequence(b.id));
    });
    for (final e in _timeIndex) {
      for (final c in e.causes) {
        if (_known.contains(c.eventId)) {
          _consequences
              .putIfAbsent(c.eventId, () => [])
              .add(Cause(e.id, c.kind));
        }
      }
    }
    _searchIndex.sort((a, b) => a.id.compareTo(b.id));
  }
  final World _world;
  final String _observer;
  final Map<String, List<Relation>> _adjacency = {};
  final Map<String, List<Cause>> _consequences = {};
  final Set<String> _known = {};
  final List<GameEvent> _timeIndex = [];
  final List<Entity> _searchIndex = [];
  int _sequence(String id) => int.tryParse(id.split(':').last) ?? 0;
  bool _visibleRelation(Relation r) =>
      _known.contains(r.id) &&
      _known.contains(r.source) &&
      _known.contains(r.target);
  KarmaNode? node(String id) {
    final n = _world.entities[id];
    if (n == null || !_known.contains(id)) {
      return null;
    }
    final k = _world.knowledge['$_observer|$id']!;
    final character =
        n.type == KarmaNodeType.npc || n.type == KarmaNodeType.player;
    // Current remote stats/position are not omnisciently exposed. Knowledge of
    // a name permits graph lookup, not live tracking of that character.
    final present = id == _observer || n.location == _world.player.location;
    return KarmaNode(
      id: n.id,
      entityId: n.id,
      type: n.type,
      displayName: n.name,
      importance: n.importance,
      alive: present ? n.alive : (k.snapshot['alive'] as bool? ?? true),
      createdGameTime: n.created,
      lastUpdatedGameTime: present ? n.updated : k.time,
      visibility: k.channel == InformationChannel.divination ? '天机已确认' : '已知',
      description: character
          ? (present
                ? '${Content.realms[n.realm]}${Content.stages[n.stage]} · ${n.personality} · ${_world.entities[n.location]?.name ?? '远方'}'
                : '曾经结识的修士 · 当前行踪未确认')
          : n.type == KarmaNodeType.sect
          ? '修仙势力 · ${(k.snapshot['alive'] as bool? ?? true) ? '传承延续' : '已覆灭'}'
          : n.type == KarmaNodeType.family
          ? '修仙家族'
          : n.type == KarmaNodeType.location
          ? '已知地点'
          : '历史事件',
    );
  }

  int _strength(Relation r) =>
      _world.knowledge['$_observer|${r.id}']?.snapshot['strength'] as int? ?? 0;
  RelationStatus _status(Relation r) => RelationStatus.values.byName(
    _world.knowledge['$_observer|${r.id}']?.snapshot['status'] as String? ??
        'active',
  );
  KarmaEdge? edge(String id) {
    final r = _world.relations[id];
    if (r == null || !_visibleRelation(r)) {
      return null;
    }
    return _edge(r);
  }

  KarmaEdge _edge(Relation r) => KarmaEdge(
    id: r.id,
    sourceNodeId: r.source,
    targetNodeId: r.target,
    relationType: r.type,
    strength: _strength(r),
    status: _status(r),
    resolved:
        _world.knowledge['$_observer|${r.id}']?.snapshot['resolved'] as bool? ??
        _status(r) == RelationStatus.settled,
    bidirectional: r.bidirectional,
    createdGameTime: r.created,
    updatedGameTime: _world.knowledge['$_observer|${r.id}']?.time ?? r.created,
    relatedEventIds: List.unmodifiable(r.events.where(_known.contains)),
    inheritedFrom: _known.contains(r.inheritedFrom) ? r.inheritedFrom : null,
    visibilityLevel:
        _world.knowledge['$_observer|${r.id}']?.channel ==
            InformationChannel.divination
        ? '推演确认'
        : '已发现',
  );
  List<KarmaNode> search(String text, {KarmaNodeType? type, int limit = 40}) =>
      List.unmodifiable(
        _searchIndex
            .where(
              (n) =>
                  (type == null || n.type == type) &&
                  n.name.contains(text.trim()),
            )
            .take(limit.clamp(1, 80))
            .map((n) => node(n.id)!),
      );
  KarmaGraph query(GraphQuery query) {
    final limit = query.limit.clamp(1, 200);
    final hops = query.hops.clamp(1, 5);
    final center = query.center ?? _world.playerId;
    if (!_known.contains(center)) {
      return const KarmaGraph([], [], {});
    }
    bool match(Relation r) =>
        _visibleRelation(r) &&
        _strength(r) >= query.minimumStrength &&
        (query.types.isEmpty || query.types.contains(r.type)) &&
        (query.statuses.isEmpty || query.statuses.contains(_status(r))) &&
        (!query.worldView ||
            _strength(r) >= 50 ||
            r.type == KarmaRelationType.sectAffiliation ||
            r.type == KarmaRelationType.eventParticipation);
    final depths = <String, int>{};
    final queue = Queue<String>();
    final selected = <String, Relation>{};
    final edgeLimit = limit * 6;
    var truncated = false;
    final roots = query.worldView
        ? _searchIndex
              .where(
                (n) =>
                    n.type == KarmaNodeType.sect ||
                    n.type == KarmaNodeType.worldEvent ||
                    n.type == KarmaNodeType.historicalEvent &&
                        n.importance >= 4,
              )
              .map((n) => n.id)
              .take(limit)
              .toList()
        : [center];
    for (final root in roots) {
      depths[root] = 0;
      queue.add(root);
    }
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final depth = depths[current]!;
      if (depth >= hops) {
        continue;
      }
      for (final r in _adjacency[current] ?? <Relation>[]) {
        if (!match(r)) {
          continue;
        }
        if (selected.length >= edgeLimit && !selected.containsKey(r.id)) {
          truncated = true;
          continue;
        }
        final other = r.source == current ? r.target : r.source;
        if (!depths.containsKey(other)) {
          if (depths.length >= limit) {
            truncated = true;
            continue;
          }
          depths[other] = depth + 1;
          queue.add(other);
        }
        selected[r.id] = r;
      }
    }
    // Keep edges between selected nodes without expanding any further.
    for (final id in depths.keys) {
      for (final r in _adjacency[id] ?? <Relation>[]) {
        if (depths.containsKey(r.source) &&
            depths.containsKey(r.target) &&
            match(r)) {
          if (selected.length >= edgeLimit && !selected.containsKey(r.id)) {
            truncated = true;
            continue;
          }
          selected[r.id] = r;
        }
      }
    }
    return KarmaGraph(
      List.unmodifiable(depths.keys.map((id) => node(id)!)),
      List.unmodifiable(selected.values.map(_edge)),
      Map.unmodifiable(depths),
      truncated: truncated,
      revision: _world.revision,
    );
  }

  VisibleEvent? event(String id) {
    final e = _world.events[id];
    if (e == null || !_known.contains(id)) {
      return null;
    }
    final relations = <String, KarmaEdge>{};
    for (final p in e.participants) {
      for (final r in _adjacency[p] ?? <Relation>[]) {
        if (r.events.contains(id) && _visibleRelation(r)) {
          relations[r.id] = _edge(r);
        }
      }
    }
    return VisibleEvent(
      id: e.id,
      time: e.time,
      title: e.title,
      description: e.description,
      locationName: _known.contains(e.location)
          ? _world.entities[e.location]?.name ?? '未确认地点'
          : '未确认地点',
      participants: List.unmodifiable(
        e.participants.map(node).whereType<KarmaNode>(),
      ),
      causes: List.unmodifiable(
        e.causes.where((c) => _known.contains(c.eventId)),
      ),
      consequences: List.unmodifiable(_consequences[id] ?? []),
      relations: List.unmodifiable(relations.values),
      importance: e.importance,
    );
  }

  List<VisibleEvent> timeline({
    int offset = 0,
    int limit = 30,
    String? entity,
    String? relation,
  }) {
    if (entity != null && !_known.contains(entity) ||
        relation != null && edge(relation) == null) {
      return [];
    }
    final ids = relation == null
        ? null
        : edge(relation)!.relatedEventIds.toSet();
    return List.unmodifiable(
      _timeIndex
          .where(
            (e) =>
                (entity == null || e.participants.contains(entity)) &&
                (ids == null || ids.contains(e.id)),
          )
          .skip(offset < 0 ? 0 : offset)
          .take(limit.clamp(1, 100))
          .map((e) => event(e.id)!),
    );
  }

  List<VisibleEvent> recent({int limit = 8}) => List.unmodifiable(
    _timeIndex.reversed.take(limit.clamp(1, 30)).map((e) => event(e.id)!),
  );
  List<VisibleEvent> causalChain(String id, {int limit = 100}) {
    if (event(id) == null) {
      return [];
    }
    final seen = <String>{};
    final queue = Queue<String>()..add(id);
    while (queue.isNotEmpty && seen.length < limit.clamp(1, 200)) {
      final next = queue.removeFirst();
      if (!seen.add(next)) {
        continue;
      }
      final e = event(next)!;
      queue.addAll(
        [
          ...e.causes,
          ...e.consequences,
        ].map((c) => c.eventId).where((id) => !seen.contains(id)),
      );
    }
    return List.unmodifiable(
      _timeIndex.where((e) => seen.contains(e.id)).map((e) => event(e.id)!),
    );
  }
}
