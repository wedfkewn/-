import 'illustrations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/game_controller.dart';
import '../domain/content.dart';
import '../domain/models.dart';
import 'ink_theme.dart';

class CreationPage extends ConsumerStatefulWidget {
  const CreationPage({super.key});
  @override
  ConsumerState<CreationPage> createState() => _CreationPageState();
}

class _CreationPageState extends ConsumerState<CreationPage> {
  final name = TextEditingController(text: '李长生'),
      seed = TextEditingController();
  CreationDraft? draft;
  int selected = 0, regions = 12, places = 24, npcs = 1200;
  List<int> points = [0, 0, 0, 0];
  bool busy = false;
  String error = '';
  Future<void> saving = Future.value();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    name.dispose();
    seed.dispose();
    super.dispose();
  }

  Future<void> load({bool change = false}) async {
    setState(() => busy = true);
    try {
      await saving;
      final db = ref.read(databaseProvider);
      final d = await db.creationDraft(seed: change ? seed.text : null);
      final choice = await db.appRecord('birthChoice');
      if (!mounted) return;
      setState(() {
        draft = d;
        seed.text = d.seed;
        selected = choice?['index'] ?? 0;
        points = List<int>.from(choice?['points'] ?? [0, 0, 0, 0]);
        error = '';
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void remember() {
    final db = ref.read(databaseProvider), d = draft!;
    final index = selected, allocations = List<int>.from(points);
    saving = saving
        .catchError((Object _) {})
        .then((_) => db.saveBirthChoice(d.id, index, allocations))
        .catchError((Object e) {
          if (mounted) setState(() => error = '分配保存失败，请重试：$e');
        });
  }

  Future<void> create() async {
    final d = draft!;
    if (seed.text.trim() != d.seed) {
      await load(change: true);
      return;
    }
    setState(() => busy = true);
    try {
      await saving;
      await ref
          .read(gameProvider.notifier)
          .create(
            name.text,
            d.seed,
            regionCount: regions,
            placesPerRegion: places,
            npcCount: npcs,
            draft: d,
            candidate: selected,
            allocation: points,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final remaining = d == null
        ? 0
        : d.entitlement.points - points.fold<int>(0, (a, b) => a + b);
    final values = d == null
        ? [5, 5, 5, 5]
        : List.generate(4, (i) => d.candidates[selected].values[i] + points[i]);
    final a = CharacterAttributes(values[0], values[1], values[2], values[3]);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('踏入仙途')),
        body: PaperSurface(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const InkIllustration(art: 'feature_birth'),
              TextField(
                controller: name,
                maxLength: 20,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '道号'),
              ),
              TextField(
                controller: seed,
                key: const Key('world-seed-input'),
                maxLength: 100,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '世界种子'),
              ),
              TextButton(
                onPressed: busy ? null : () => load(change: true),
                child: const Text('应用种子与资质'),
              ),
              const Text('三种天资，择一入世。改变种子会生成新的三套资质。'),
              if (busy) const LinearProgressIndicator(),
              if (error.isNotEmpty)
                Text(error, style: const TextStyle(color: InkTheme.cinnabar)),
              if (d == null && !busy)
                TextButton(onPressed: load, child: const Text('重试')),
              if (d != null) ...[
                const SizedBox(height: 16),
                for (var i = 0; i < 3; i++)
                  Card(
                    child: ListTile(
                      selected: selected == i,
                      title: Text(
                        '天资${['一', '二', '三'][i]}${selected == i ? ' · 已选择' : ''}',
                      ),
                      subtitle: Text(
                        List.generate(
                          4,
                          (j) =>
                              '${CharacterAttributes.labels[j]} ${d.candidates[i].values[j]}',
                        ).join('  '),
                      ),
                      onTap: busy
                          ? null
                          : () {
                              setState(() {
                                selected = i;
                                points = [0, 0, 0, 0];
                              });
                              remember();
                            },
                    ),
                  ),
                Text(
                  '上一世人生影响 ${d.entitlement.score} · 奖励 ${d.entitlement.points} 点 · 剩余 $remaining 点',
                ),
                for (var i = 0; i < 4; i++)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${CharacterAttributes.labels[i]} ${values[i]}\n${CharacterAttributes.descriptions[i]}',
                        ),
                      ),
                      IconButton(
                        tooltip: '减少${CharacterAttributes.labels[i]}',
                        onPressed: busy || points[i] == 0
                            ? null
                            : () {
                                setState(() => points[i]--);
                                remember();
                              },
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        tooltip: '增加${CharacterAttributes.labels[i]}',
                        onPressed: busy || remaining == 0 || values[i] >= 12
                            ? null
                            : () {
                                setState(() => points[i]++);
                                remember();
                              },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() => points = [0, 0, 0, 0]);
                          remember();
                        },
                  child: const Text('重置分配'),
                ),
                Text(
                  '入世气血 ${a.scale(100, a.physique, 4)} · 基础攻击 ${a.scale(18, a.physique, 2)}\n闭关 ${100 + (a.root - 5) * 4}% · 感悟要求 ${100 - (a.insight - 5) * 2}%\n战斗灵力 ${10 + a.awareness - 5} · 天机能力 ${100 + (a.awareness - 5) * 4}%',
                ),
                ExpansionTile(
                  title: const Text('世界规模'),
                  subtitle: Text(
                    '$regions州 · ${regions * places}处地点 · $npcs名NPC',
                  ),
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: regions,
                      items: [6, 12, 18]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v州')),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => regions = v!),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: places,
                      items: [16, 24, 32]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v处')),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => places = v!),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: npcs,
                      items: [600, 1200, 5000]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v名')),
                          )
                          .toList(),
                      onChanged: busy ? null : (v) => setState(() => npcs = v!),
                    ),
                  ],
                ),
                Text('初始境界：${Content.realms.first}初期。身死后这一世永久结束。'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy || remaining != 0 ? null : create,
                  child: const Text('开始修行'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
