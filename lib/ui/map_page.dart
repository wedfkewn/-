import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/game_controller.dart';
import '../domain/engine.dart';
import '../domain/map_repository.dart';
import '../domain/models.dart';
import '../domain/content.dart';
import 'ink_theme.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final transform = TransformationController();
  int? region;
  PlaceKind? kind;
  String search = '';
  bool busy = false;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Future<void> act(String command, {String? target, String? item}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(gameProvider.notifier)
          .command(GameCommand(command, target: target, item: item));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is RuleViolation ? e.message : '行动未能保存')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> details(KnownPlace known, GameView view) async {
    final p = known.place;
    final path = known.confirmed
        ? ref.read(gameProvider.notifier).previewRoute(p.id)
        : null;
    var cursor = view.map.current;
    final segments = (path ?? <MapRoad>[]).map((road) {
      cursor = road.other(cursor);
      final destination = view.map.places.firstWhere(
        (p) => p.place.id == cursor,
      );
      return '${destination.name} · ${road.kind} · ${road.travelDays(view.realmIndex)}日 · ${road.fee}灵石 · 推荐${Content.realms[destination.place.danger]}';
    }).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  known.name,
                  style: const TextStyle(fontFamily: 'MaShan', fontSize: 30),
                ),
                Text('${p.regionName} · ${p.kind.label} · ${p.terrain}'),
                if (!known.confirmed) const Text('待查证：尚不能规划行旅'),
                Text(
                  '情报：${Content.date(known.time)} · ${const ['目击', '调查', '传闻', '天机推演', '宗门情报', '人物告知'][known.channel.index]}',
                ),
                if (known.confirmed)
                  Text('危险：推荐${Content.realms[p.danger]} · 灵气 ${p.aura}'),
                if (known.confirmed)
                  Text(
                    '已知资源：${p.resources.isEmpty ? '暂无采集资源' : p.resources.join('、')}',
                  ),
                if (known.confirmed && p.kind == PlaceKind.secret)
                  Text(
                    p.open(view.day)
                        ? '秘境开放中，本期开启20日'
                        : '下次开放：${Content.date(p.nextOpening(view.day))}',
                  ),
                if (known.confirmed && p.kind == PlaceKind.vein)
                  const Text('灵脉闭关每次需5灵石；本宗驻地灵脉可免费使用'),
                if (path != null && path.isNotEmpty) ...[
                  Text(
                    '路线：${path.length}段 · ${path.fold<int>(0, (s, r) => s + r.travelDays(view.realmIndex))}日 · ${path.fold<int>(0, (s, r) => s + r.fee)}灵石',
                  ),
                  ...segments.map((text) => Text(text)),
                  FilledButton(
                    onPressed: view.readOnly || busy || view.map.paused
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            act('planRoute', target: p.id);
                          },
                    child: const Text('规划逐段行旅'),
                  ),
                ] else if (p.id != view.map.current && known.confirmed)
                  const Text('尚无已知连通路线，请调查或获取地图'),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('返回地图'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(gameProvider).asData?.value;
    if (v == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final m = v.map;
    final regions = {
      for (final p in m.places) p.place.region: p.place.regionName,
    };
    final visible = m.places
        .where(
          (p) =>
              (region == null || p.place.region == region) &&
              p.name.contains(search) &&
              (kind == null || p.place.kind == kind),
        )
        .toList();
    final disabled =
        v.readOnly ||
        busy ||
        m.paused ||
        v.secretStage != null ||
        v.inTribulation;
    final here = m.places.where((p) => p.place.id == m.current).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('山河图'),
        actions: [
          IconButton(
            tooltip: '回到当前位置',
            icon: const Icon(Icons.my_location),
            onPressed: () {
              final current = m.places
                  .where((p) => p.place.id == m.current)
                  .firstOrNull;
              setState(() {
                region = current?.place.region;
                search = '';
                kind = null;
                transform.value = Matrix4.identity()
                  ..translateByDouble(
                    -(current?.place.x ?? 0) + 160,
                    -(current?.place.y ?? 0) + 140,
                    0,
                    1,
                  );
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: m.destination == null
          ? null
          : SafeArea(
              child: PaperSurface(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '剩余行旅：${m.remaining.length}段 · ${m.remaining.fold<int>(0, (s, r) => s + r.travelDays(v.realmIndex))}日',
                      ),
                      if (m.paused) const Text('行旅暂停，请先返回处理奇遇或战斗'),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: disabled ? null : () => act('moveStep'),
                            child: const Text('前进一段'),
                          ),
                          TextButton(
                            onPressed: disabled
                                ? null
                                : () => act('cancelRoute'),
                            child: const Text('取消剩余路线'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: PaperSurface(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              region == null ? '天下概览' : regions[region] ?? '州域地图',
              style: const TextStyle(fontFamily: 'MaShan', fontSize: 32),
            ),
            if (region != null)
              TextButton(
                onPressed: () => setState(() => region = null),
                child: const Text('返回天下'),
              ),
            Text('所在：${v.location} · ${Content.date(v.day)}'),
            TextField(
              decoration: const InputDecoration(labelText: '搜索已知地点'),
              onChanged: (s) => setState(() => search = s),
            ),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: kind == null,
                  onSelected: (_) => setState(() => kind = null),
                ),
                ...PlaceKind.values.map(
                  (k) => ChoiceChip(
                    label: Text(k.label),
                    selected: kind == k,
                    onSelected: (_) => setState(() => kind = k),
                  ),
                ),
              ],
            ),
            if (m.places.isEmpty) const Text('这份旧人生档案没有山河地图，原有历史保持不变。'),
            if (region == null && search.isEmpty && kind == null)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: regions.entries
                    .map(
                      (e) => OutlinedButton(
                        onPressed: () => setState(() => region = e.key),
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
              ),
            if (region != null)
              SizedBox(
                height: 370,
                child: InteractiveViewer(
                  key: const Key('shanhe-viewer'),
                  transformationController: transform,
                  constrained: false,
                  minScale: .3,
                  maxScale: 3,
                  boundaryMargin: const EdgeInsets.all(250),
                  child: SizedBox(
                    width: 1000,
                    height: 1450,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RoadPainter(
                              visible,
                              m.roads,
                              Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        ...visible.map(
                          (p) => Positioned(
                            left: p.place.x - 50,
                            top: p.place.y - 22,
                            width: 115,
                            child: InkWell(
                              onTap: () => details(p, v),
                              child: Column(
                                children: [
                                  Icon(
                                    p.place.id == m.current
                                        ? Icons.push_pin
                                        : p.confirmed
                                        ? Icons.circle_outlined
                                        : Icons.help_outline,
                                    color: p.place.id == m.current
                                        ? InkTheme.cinnabar
                                        : null,
                                    size: 22,
                                  ),
                                  Text(
                                    p.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    p.confirmed
                                        ? '危险 ${p.place.danger}'
                                        : '待查证',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Text('朱印：当前位置 · 墨线：已知道路 · 问号：传闻待查证'),
            ...visible
                .take(48)
                .map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.place.kind.label} · ${p.confirmed ? '推荐${Content.realms[p.place.danger]}' : '待查证'}',
                    ),
                    onTap: () => details(p, v),
                  ),
                ),
            if (here != null) ...[
              const Divider(),
              Text(
                '当地行动 · ${here.name}',
                style: const TextStyle(fontFamily: 'MaShan', fontSize: 25),
              ),
              if ([PlaceKind.wild, PlaceKind.ruin].contains(here.place.kind))
                ...here.place.resources.map(
                  (item) => OutlinedButton(
                    onPressed: disabled
                        ? null
                        : () => act('gather', item: item),
                    child: Text('采集$item · 10日'),
                  ),
                ),
              if (here.place.kind == PlaceKind.secret && v.secretStage == null)
                OutlinedButton(
                  onPressed: disabled || !here.place.open(v.day)
                      ? null
                      : () => act('enterSecret'),
                  child: Text(
                    here.place.open(v.day)
                        ? '进入秘境 · 10灵石'
                        : '下次开放 ${Content.date(here.place.nextOpening(v.day))}',
                  ),
                ),
              if (v.secretStage != null) ...[
                Text(
                  '秘境阶段 ${v.secretStage! + 1}/3 · 下一步${v.secretStage == 1
                      ? '遗阵考验，将损失${30 + here.place.danger * 20}气血，气血不足可能永久陨落'
                      : v.secretStage == 2
                      ? '获取秘藏'
                      : '调查入口'}',
                ),
                FilledButton(
                  onPressed: v.readOnly || busy || m.paused
                      ? null
                      : () => act('secretStep'),
                  child: const Text('继续秘境 · 5日'),
                ),
                TextButton(
                  onPressed: v.readOnly || busy || m.paused
                      ? null
                      : () => act('leaveSecret'),
                  child: const Text('安全离开秘境'),
                ),
                OutlinedButton(
                  onPressed: v.readOnly || busy
                      ? null
                      : () => act('useItem', item: '回春丹'),
                  child: const Text('服回春丹'),
                ),
              ],
            ],
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton(
                  onPressed: disabled ? null : () => act('survey'),
                  child: const Text('调查邻路 · 3日'),
                ),
                OutlinedButton(
                  onPressed: disabled ? null : () => act('buyMap'),
                  child: const Text('购买州图 · 10灵石'),
                ),
                OutlinedButton(
                  onPressed: disabled ? null : () => act('sectMap'),
                  child: const Text('领取宗门情报'),
                ),
              ],
            ),
            ...v.nearby.map(
              (n) => TextButton(
                onPressed: disabled
                    ? null
                    : () => act('askDirections', target: n.id),
                child: Text('向${n.displayName}问路'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoadPainter extends CustomPainter {
  _RoadPainter(this.places, this.roads, this.color);
  final List<KnownPlace> places;
  final List<MapRoad> roads;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final known = {
      for (final p in places.where((p) => p.confirmed))
        p.place.id: Offset(p.place.x + 7, p.place.y - 10),
    };
    final paint = Paint()
      ..color = color.withValues(alpha: .3)
      ..strokeWidth = 2;
    for (final r in roads) {
      if (known.containsKey(r.a) && known.containsKey(r.b)) {
        canvas.drawLine(known[r.a]!, known[r.b]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.places != places || old.roads != roads || old.color != color;
}
