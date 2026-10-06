import 'ink_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/game_controller.dart';
import '../domain/content.dart';
import '../domain/engine.dart';
import '../domain/models.dart';
import 'ink_theme.dart';
import 'map_page.dart';

class GrowthPage extends ConsumerStatefulWidget {
  const GrowthPage({super.key});
  @override
  ConsumerState<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends ConsumerState<GrowthPage> {
  bool busy = false, pill = false;
  String? guard;
  Future<void> act(String kind, {String? target, String? item}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(gameProvider.notifier)
          .command(GameCommand(kind, target: target, item: item));
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

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(gameProvider).asData?.value;
    if (v == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (v.readOnly && v.map.places.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('修行档案')),
        body: PaperSurface(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Text('${v.realm}\n旧人生档案未记录小阶段、根基与感悟；原有历史保持只读。'),
          ),
        ),
      );
    }
    final g = ref
        .read(gameProvider.notifier)
        .previewGrowth(
          guard: v.growth.stage == 3 ? guard : null,
          pill: v.growth.stage == 3 && pill,
        );
    final disabled =
        v.readOnly ||
        busy ||
        v.battleName != null ||
        v.encounter != null ||
        v.secretStage != null;
    final current = v.map.places
        .where((p) => p.place.id == v.map.current)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('修行与突破')),
      body: PaperSurface(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(
              v.realm,
              style: const TextStyle(fontFamily: 'MaShan', fontSize: 34),
            ),
            const Text('初期 → 中期 → 后期 → 圆满 → 下一大境界初期'),
            Text(
              '修为 ${v.spirit}/${g.threshold} · 根基 ${g.foundation}/${g.rootRequired} · 感悟 ${g.insight}/${g.insightRequired}',
            ),
            Text('气血 ${v.hp}/${v.maxHp} · 寿元 ${v.age}/${v.lifespan}岁'),
            if (g.injured) const Text('突破伤势未愈：至少经过30日、稳固一次并恢复80%气血。'),
            const Divider(),
            Wrap(
              spacing: 10,
              children: [
                FilledButton(
                  onPressed: disabled ? null : () => act('cultivate'),
                  child: const Text('闭关 · 30日'),
                ),
                OutlinedButton(
                  onPressed: disabled ? null : () => act('stabilize'),
                  child: const Text('稳固根基 · 10日'),
                ),
                OutlinedButton(
                  onPressed: disabled ? null : () => act('contemplate'),
                  child: const Text('参悟此地 · 10日'),
                ),
                OutlinedButton(
                  onPressed: disabled ? null : () => act('practice'),
                  child: Text('训练${v.style} · 10日'),
                ),
              ],
            ),
            const Text('闭关积累修为；稳固与训练提升根基；首次探索、参悟、任务和有效实战提供感悟。相同来源在同一境界不重复领取。'),
            const Divider(),
            Text(
              g.stage < 3 ? '小阶段晋升' : '大境界准备',
              style: const TextStyle(fontFamily: 'MaShan', fontSize: 27),
            ),
            if (g.stage < 3) const Text('条件满足后必定提升一阶段，消耗门槛修为，耗时7日；寿元不变。'),
            if (g.stage == 3 && !g.terminal) ...[
              Text(
                '需 ${g.material} ×1，现有 ${v.inventory[g.material] ?? 0} · 初始准备7日',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('使用护脉丹'),
                subtitle: Text('持有 ${v.inventory['护脉丹'] ?? 0} · 雷劫+50护盾'),
                value: pill,
                onChanged: disabled
                    ? null
                    : (value) => setState(() => pill = value ?? false),
              ),
              const Text('选择真实护法：须在场、境界达标，并有师徒、好友或同宗关系。'),
              RadioGroup<String>(
                groupValue: guard ?? '',
                onChanged: disabled
                    ? (_) {}
                    : (value) =>
                          setState(() => guard = value == '' ? null : value),
                child: Column(
                  children: [
                    const RadioListTile<String>(
                      value: '',
                      title: Text('不邀请护法'),
                    ),
                    ...g.guards.map(
                      (id) => RadioListTile<String>(
                        value: id,
                        title: Text(
                          v.nearby
                                  .where((n) => n.id == id)
                                  .firstOrNull
                                  ?.displayName ??
                              '在场护法',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (g.highTrial) ...[
                Text(
                  '准备护盾 ${g.shield} · 通过雷劫后晋升${Content.realms[v.realmIndex + 1]}',
                ),
                Text(
                  '永久死亡风险：${v.realmIndex >= 6 ? '须在渡劫台' : '在合适突破地点'}承受${g.trialRounds}道雷劫，提前预告招式。开始后不能逃跑。',
                ),
                const Text('通过雷劫即突破，不额外抽取成功率；准备提高护盾，防御、功法和回春丹用于渡劫。'),
              ],
            ],
            if (g.missing.isNotEmpty) ...g.missing.map((s) => Text('· $s')),
            FilledButton(
              onPressed: disabled || g.missing.isNotEmpty
                  ? null
                  : () async {
                      if (g.highTrial) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => InkDialog(
                            title: const Text('确认渡劫'),
                            content: const Text('此劫可能永久陨落，开始后不能逃跑。材料与修为将立即消耗。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('继续准备'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('迎劫'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                      }
                      await act(
                        g.stage < 3 ? 'advanceStage' : 'breakthrough',
                        target: g.stage == 3 ? guard : null,
                        item: g.stage == 3 && pill ? '护脉丹' : null,
                      );
                      if (context.mounted &&
                          ref.read(gameProvider).asData?.value.inTribulation ==
                              true) {
                        Navigator.pop(context);
                      }
                    },
              child: Text(
                g.terminal
                    ? '渡劫圆满'
                    : g.stage < 3
                    ? '提升至${Content.stages[g.stage + 1]}'
                    : g.highTrial
                    ? '开始渡劫'
                    : '开始突破',
              ),
            ),
            const Divider(),
            const Text(
              '材料与历练',
              style: TextStyle(fontFamily: 'MaShan', fontSize: 27),
            ),
            if (current != null &&
                [PlaceKind.wild, PlaceKind.ruin].contains(current.place.kind))
              ...current.place.resources
                  .where(
                    (item) => item == '灵草' || MapRules.materials.contains(item),
                  )
                  .map(
                    (item) => OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () => act('gather', item: item),
                      child: Text('当地采集$item · 10日'),
                    ),
                  ),
            OutlinedButton(
              onPressed: disabled ? null : () => act('materialQuest'),
              child: const Text('宗门材料委托 · 5灵草＋1回春丹'),
            ),
            ...v.nearby.map(
              (n) => TextButton(
                onPressed: disabled
                    ? null
                    : () => act('instruction', target: n.id),
                child: Text('向${n.displayName}请教'),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MapPage()),
              ),
              child: const Text('查看山河，寻找材料与灵脉'),
            ),
          ],
        ),
      ),
    );
  }
}
