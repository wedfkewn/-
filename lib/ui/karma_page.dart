import 'ink_overlays.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/game_controller.dart';
import '../domain/karma_repository.dart';
import '../domain/models.dart';
import 'details.dart';
import 'timeline.dart';

class KarmaPage extends ConsumerStatefulWidget {
  const KarmaPage({super.key});
  @override
  ConsumerState<KarmaPage> createState() => _KarmaPageState();
}

class _KarmaPageState extends ConsumerState<KarmaPage> {
  int scope = 0, hops = 1, view = 0, limit = 80;
  String? center, relation;
  Set<KarmaRelationType> types = {};
  Set<RelationStatus> statuses = {};
  int strength = 0;
  final canvas = GlobalKey<GraphCanvasState>();
  void reset() {
    setState(() {
      center = null;
      scope = 0;
      hops = 1;
      limit = 80;
      relation = null;
    });
    canvas.currentState?.reset();
  }

  Future<void> search() async {
    final repository = ref.read(gameProvider.notifier).repository!;
    final controller = TextEditingController();
    final result = await showDialog<KarmaNode>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final matches = repository.search(
            controller.text,
            type: scope == 1 ? KarmaNodeType.npc : null,
          );
          return InkDialog(
            title: const Text('搜索已知实体'),
            content: SizedBox(
              width: 360,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '姓名或名称'),
                    onChanged: (_) => update(() {}),
                  ),
                  Expanded(
                    child: ListView(
                      children: matches
                          .map(
                            (n) => ListTile(
                              title: Text(n.displayName),
                              subtitle: Text(n.visibility),
                              onTap: () => Navigator.pop(context, n),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  if (matches.isEmpty) const Text('没有已知结果'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
    // Dialog route finishes disposing its text field after the pop animation.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (result != null && mounted) {
      setState(() {
        center = result.id;
        scope = result.type == KarmaNodeType.npc ? 1 : 0;
        relation = null;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => canvas.currentState?.reset(),
      );
    }
  }

  Future<void> filters() async {
    await showInkSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('筛选因果', style: Theme.of(context).textTheme.titleLarge),
                Wrap(
                  spacing: 6,
                  children: KarmaRelationType.values
                      .map(
                        (type) => FilterChip(
                          label: Text(relationLabel(type)),
                          selected: types.contains(type),
                          onSelected: (yes) => update(() {
                            yes ? types.add(type) : types.remove(type);
                          }),
                        ),
                      )
                      .toList(),
                ),
                const Divider(),
                Text('最低强度：$strength'),
                Slider(
                  value: strength.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 10,
                  onChanged: (v) => update(() => strength = v.round()),
                ),
                Wrap(
                  spacing: 6,
                  children: RelationStatus.values
                      .map(
                        (s) => FilterChip(
                          label: Text(statusLabel(s)),
                          selected: statuses.contains(s),
                          onSelected: (yes) => update(() {
                            yes ? statuses.add(s) : statuses.remove(s);
                          }),
                        ),
                      )
                      .toList(),
                ),
                TextButton(
                  onPressed: () => update(() {
                    types.clear();
                    statuses.clear();
                    strength = 0;
                  }),
                  child: const Text('清空筛选'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('应用'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider).asData?.value;
    final repository = ref.read(gameProvider.notifier).repository;
    if (state == null || repository == null) {
      return const Center(child: Text('请先踏入仙途'));
    }
    if (center != null && repository.node(center!) == null) {
      center = null;
      relation = null;
    }
    final graph = repository.query(
      GraphQuery(
        center: center,
        hops: hops,
        limit: limit,
        types: types,
        minimumStrength: strength,
        statuses: statuses,
        worldView: scope == 2,
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '天机因果图',
                  style: TextStyle(fontFamily: 'MaShan', fontSize: 28),
                ),
              ),
              if (state.readOnly) const Chip(label: Text('历史只读')),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('我的因果')),
                  ButtonSegment(value: 1, label: Text('人物')),
                  ButtonSegment(value: 2, label: Text('天下')),
                ],
                selected: {scope},
                onSelectionChanged: (s) {
                  if (s.first == 1) {
                    setState(() => scope = 1);
                    search();
                  } else {
                    setState(() {
                      scope = s.first;
                      center = null;
                      relation = null;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: filters,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('筛选'),
                ),
                TextButton.icon(
                  onPressed: search,
                  icon: const Icon(Icons.search),
                  label: const Text('搜索'),
                ),
                TextButton.icon(
                  onPressed: reset,
                  icon: const Icon(Icons.my_location),
                  label: const Text('回到玩家'),
                ),
                DropdownButton<int>(
                  value: hops,
                  items: List.generate(
                    5,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text('${i + 1}跳'),
                    ),
                  ),
                  onChanged: (v) => setState(() => hops = v!),
                ),
                IconButton(
                  tooltip: '自动整理布局',
                  onPressed: () => canvas.currentState?.organize(),
                  icon: const Icon(Icons.auto_awesome),
                ),
              ],
            ),
          ),
        ),
        if (center != null) Text('中心：${repository.node(center!)!.displayName}'),
        Expanded(
          child: view == 0
              ? Stack(
                  children: [
                    GraphCanvas(
                      key: canvas,
                      graph: graph,
                      center: center ?? state.playerId,
                      onNode: (node) => showNodeDetails(context, node),
                      onEdge: (edge) => showEdgeDetails(
                        context,
                        repository,
                        edge,
                        onTimeline: () => setState(() {
                          view = 1;
                          relation = edge.id;
                        }),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Column(
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'zoom-in',
                            tooltip: '放大',
                            onPressed: () => canvas.currentState?.zoom(1.25),
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom-out',
                            tooltip: '缩小',
                            onPressed: () => canvas.currentState?.zoom(.8),
                            child: const Icon(Icons.remove),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Text(
                        '${graph.nodes.length} 个已知节点 · ${graph.edges.length} 条关系',
                      ),
                    ),
                  ],
                )
              : CausalTimeline(
                  repository: repository,
                  entity: scope == 1 ? center : null,
                  relation: relation,
                  key: ValueKey(
                    '${state.playerId}:${state.revision}:$center:$relation',
                  ),
                ),
        ),
        if (view == 0 && graph.truncated)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('子图已截断'),
              TextButton(
                onPressed: limit < 200
                    ? () => setState(() => limit = (limit + 40).clamp(80, 200))
                    : null,
                child: Text(limit < 200 ? '继续加载' : '请缩小筛选范围'),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('图谱'),
                    icon: Icon(Icons.hub_outlined),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('因果长河'),
                    icon: Icon(Icons.history),
                  ),
                ],
                selected: {view},
                onSelectionChanged: (v) => setState(() {
                  view = v.first;
                  relation = null;
                }),
              ),
              IconButton(
                tooltip: '关系图例',
                icon: const Icon(Icons.info_outline),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => InkDialog(
                    title: const Text('因果图例'),
                    content: const Text(
                      '青绿实线：善缘\n暗红实线：仇怨／竞争\n金色细线：师徒\n双线：血缘\n粉色实线：道侣\n蓝灰细线：宗门\n琥珀虚线：债务／承诺\n灰色虚线：纠缠／事件参与\n淡线：历史或已了结\n\n箭头表示方向，线宽表示强度。\n未经确认的关系不传入画布。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GraphCanvas extends StatefulWidget {
  const GraphCanvas({
    super.key,
    required this.graph,
    required this.center,
    required this.onNode,
    required this.onEdge,
  });
  final KarmaGraph graph;
  final String center;
  final ValueChanged<KarmaNode> onNode;
  final ValueChanged<KarmaEdge> onEdge;
  @override
  State<GraphCanvas> createState() => GraphCanvasState();
}

class GraphCanvasState extends State<GraphCanvas> {
  final transform = TransformationController();
  final Map<String, Offset> positions = {};
  List<EdgeGeometry> geometries = [];
  Size viewport = Size.zero;
  String signature = '';
  @override
  void initState() {
    super.initState();
    _layout();
    WidgetsBinding.instance.addPostFrameCallback((_) => reset());
  }

  @override
  void didUpdateWidget(GraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _layout();
    if (oldWidget.center != widget.center) {
      WidgetsBinding.instance.addPostFrameCallback((_) => reset());
    }
  }

  void _layout({bool force = false}) {
    final key =
        '${widget.center}:${widget.graph.nodes.map((n) => '${n.id}:${widget.graph.depths[n.id]}').join(',')}';
    if (force || signature != key) {
      signature = key;
      positions.clear();
      final levels = <int, List<KarmaNode>>{};
      for (final node in widget.graph.nodes) {
        levels
            .putIfAbsent(widget.graph.depths[node.id] ?? 1, () => [])
            .add(node);
      }
      if (widget.graph.nodes.any((n) => n.id == widget.center)) {
        positions[widget.center] = const Offset(1200, 1200);
      }
      for (final entry in levels.entries) {
        final nodes = entry.value.where((n) => n.id != widget.center).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        for (var i = 0; i < nodes.length; i++) {
          final ring = i ~/ 24;
          final count = math.min(24, nodes.length - ring * 24);
          final radius = 180.0 + math.max(0, entry.key - 1) * 150 + ring * 110;
          final angle = (i % 24) * math.pi * 2 / count - math.pi / 2;
          positions[nodes[i].id] = Offset(
            1200 + math.cos(angle) * radius,
            1200 + math.sin(angle) * radius,
          );
        }
      }
    }
    final pairs = <String, List<KarmaEdge>>{};
    for (final edge in widget.graph.edges) {
      final ends = [edge.sourceNodeId, edge.targetNodeId]..sort();
      pairs.putIfAbsent(ends.join('|'), () => []).add(edge);
    }
    geometries = [];
    for (final pair in pairs.values) {
      pair.sort((a, b) => a.id.compareTo(b.id));
      for (var i = 0; i < pair.length; i++) {
        final edge = pair[i];
        final a = positions[edge.sourceNodeId]!,
            b = positions[edge.targetNodeId]!;
        final canonical = edge.sourceNodeId.compareTo(edge.targetNodeId) < 0
            ? 1
            : -1;
        geometries.add(
          EdgeGeometry(
            edge,
            a,
            b,
            (i - (pair.length - 1) / 2) * 36 * canonical,
          ),
        );
      }
    }
  }

  void reset() {
    if (!mounted || viewport == Size.zero) {
      return;
    }
    final p = positions[widget.center] ?? const Offset(1200, 1200);
    var width = 100.0, height = 100.0;
    for (final position in positions.values) {
      width = math.max(width, (position.dx - p.dx).abs() * 2 + 100);
      height = math.max(height, (position.dy - p.dy).abs() * 2 + 100);
    }
    final scale = math
        .min(1.0, math.min(viewport.width / width, viewport.height / height))
        .clamp(.25, 1.0);
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setTranslationRaw(
        viewport.width / 2 - p.dx * scale,
        viewport.height / 2 - p.dy * scale,
        0,
      );
  }

  void organize() {
    setState(() => _layout(force: true));
    reset();
  }

  void zoom(double factor) {
    final oldScale = transform.value.getMaxScaleOnAxis();
    final newScale = (oldScale * factor).clamp(.25, 3.0);
    final origin = transform.toScene(
      Offset(viewport.width / 2, viewport.height / 2),
    );
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setTranslationRaw(
        viewport.width / 2 - origin.dx * newScale,
        viewport.height / 2 - origin.dy * newScale,
        0,
      );
  }

  void tap(Offset point) {
    for (final node in widget.graph.nodes.reversed) {
      if ((positions[node.id]! - point).distance < 36) {
        widget.onNode(node);
        return;
      }
    }
    final threshold = 10 / transform.value.getMaxScaleOnAxis();
    EdgeGeometry? selected;
    var closest = double.infinity;
    for (final edge in geometries) {
      for (var i = 1; i < edge.samples.length; i++) {
        final d = _segmentDistance(point, edge.samples[i - 1], edge.samples[i]);
        if (d < threshold && d < closest) {
          closest = d;
          selected = edge;
        }
      }
    }
    if (selected != null) {
      widget.onEdge(selected.edge);
    }
  }

  static double _segmentDistance(Offset p, Offset a, Offset b) {
    final d = b - a;
    final length = d.dx * d.dx + d.dy * d.dy;
    if (length == 0) {
      return (p - a).distance;
    }
    final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / length).clamp(
      0.0,
      1.0,
    );
    return (p - (a + d * t)).distance;
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      viewport = constraints.biggest;
      return InteractiveViewer(
        transformationController: transform,
        constrained: false,
        minScale: .25,
        maxScale: 3,
        boundaryMargin: const EdgeInsets.all(1000),
        child: GestureDetector(
          onTapUp: (details) => tap(details.localPosition),
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size(2400, 2400),
              painter: KarmaPainter(
                widget.graph,
                positions,
                geometries,
                transform,
                viewport,
                Theme.of(context).colorScheme,
                Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class EdgeGeometry {
  EdgeGeometry(this.edge, this.a, this.b, double bend) {
    final delta = b - a;
    final length = delta.distance;
    control =
        (a + b) / 2 +
        (length == 0
            ? Offset.zero
            : Offset(-delta.dy / length, delta.dx / length) * bend);
    samples = List.generate(33, (i) => point(i / 32));
    bounds = Rect.fromPoints(
      a,
      b,
    ).expandToInclude(Rect.fromCircle(center: control, radius: 35)).inflate(40);
  }
  final KarmaEdge edge;
  final Offset a, b;
  late final Offset control;
  late final List<Offset> samples;
  late final Rect bounds;
  Offset point(double t) =>
      a * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + b * (t * t);
}

class KarmaPainter extends CustomPainter {
  KarmaPainter(
    this.graph,
    this.positions,
    this.edges,
    this.transform,
    this.viewport,
    this.colors,
    this.fontFamily,
  ) : super(repaint: transform);
  final KarmaGraph graph;
  final Map<String, Offset> positions;
  final List<EdgeGeometry> edges;
  final TransformationController transform;
  final Size viewport;
  final ColorScheme colors;
  final String? fontFamily;
  final Map<String, TextPainter> labels = {};
  Color color(KarmaRelationType type) => switch (type) {
    KarmaRelationType.gratitude ||
    KarmaRelationType.friendship => const Color(0xff3f927d),
    KarmaRelationType.hatred ||
    KarmaRelationType.rivalry => const Color(0xffa34748),
    KarmaRelationType.masterDisciple => const Color(0xffbd9a4c),
    KarmaRelationType.kinship => const Color(0xff9280a4),
    KarmaRelationType.daoCompanion => const Color(0xffcb879a),
    KarmaRelationType.sectAffiliation => const Color(0xff6b899a),
    KarmaRelationType.debt ||
    KarmaRelationType.promise => const Color(0xffb48135),
    _ => colors.outline,
  };
  TextPainter label(String id, String text, {double size = 12}) =>
      labels.putIfAbsent(
        id,
        () => TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: size,
              fontFamily: fontFamily,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 120),
      );
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(
      transform.toScene(Offset.zero),
      transform.toScene(Offset(viewport.width, viewport.height)),
    ).inflate(100);
    for (final geometry in edges) {
      if (!rect.overlaps(geometry.bounds)) {
        continue;
      }
      final e = geometry.edge;
      final faded = e.status != RelationStatus.active;
      final paint = Paint()
        ..color = color(e.relationType).withValues(alpha: faded ? .32 : .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            (e.relationType == KarmaRelationType.masterDisciple ||
                    e.relationType == KarmaRelationType.sectAffiliation
                ? .7
                : 1) +
            e.strength / 45;
      final dashed = [
        KarmaRelationType.debt,
        KarmaRelationType.promise,
        KarmaRelationType.karmicEntanglement,
        KarmaRelationType.eventParticipation,
      ].contains(e.relationType);
      final path = Path()
        ..moveTo(geometry.a.dx, geometry.a.dy)
        ..quadraticBezierTo(
          geometry.control.dx,
          geometry.control.dy,
          geometry.b.dx,
          geometry.b.dy,
        );
      if (dashed) {
        for (var i = 1; i < geometry.samples.length; i += 2) {
          canvas.drawLine(geometry.samples[i - 1], geometry.samples[i], paint);
        }
      } else {
        canvas.drawPath(path, paint);
      }
      if (e.relationType == KarmaRelationType.kinship) {
        canvas.save();
        canvas.translate(3, 3);
        canvas.drawPath(path, paint);
        canvas.restore();
      }
      void arrow(double t, bool reverse) {
        final p = geometry.point(t);
        var d = geometry.point(t + .01) - geometry.point(t - .01);
        if (reverse) {
          d = -d;
        }
        if (d.distance == 0) {
          return;
        }
        final unit = d / d.distance;
        final normal = Offset(-unit.dy, unit.dx);
        canvas.drawLine(p, p - unit * 10 + normal * 5, paint);
        canvas.drawLine(p, p - unit * 10 - normal * 5, paint);
      }

      arrow(.72, false);
      if (e.bidirectional) {
        arrow(.28, true);
      }
      final text = label('edge:${e.id}', relationLabel(e.relationType));
      final middle = geometry.point(.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: middle,
            width: text.width + 8,
            height: text.height + 4,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = colors.surface.withValues(alpha: .9),
      );
      text.paint(canvas, middle - Offset(text.width / 2, text.height / 2));
    }
    for (final node in graph.nodes) {
      final p = positions[node.id]!;
      if (!rect.contains(p)) {
        continue;
      }
      final isPlayer = node.type == KarmaNodeType.player;
      final paint = Paint()
        ..color = isPlayer
            ? colors.primaryContainer
            : colors.surfaceContainerHigh;
      if (node.type == KarmaNodeType.sect ||
          node.type == KarmaNodeType.family) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: p, width: 48, height: 48),
            const Radius.circular(8),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(p, isPlayer ? 28 : 23, paint);
      }
      canvas.drawCircle(
        p,
        isPlayer ? 29 : 24,
        Paint()
          ..color = node.alive ? colors.primary : colors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPlayer ? 2 : 1,
      );
      final glyph = label(
        'glyph:${node.id}',
        isPlayer ? '你' : node.displayName.substring(0, 1),
        size: 18,
      );
      glyph.paint(canvas, p - Offset(glyph.width / 2, glyph.height / 2));
      final text = label(
        node.id,
        '${node.displayName}${node.alive ? '' : ' †'}',
      );
      text.paint(canvas, p + Offset(-text.width / 2, 32));
    }
  }

  @override
  bool shouldRepaint(KarmaPainter old) =>
      old.graph != graph || old.colors != colors || old.viewport != viewport;
}
