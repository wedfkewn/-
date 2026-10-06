import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/game_controller.dart';
import '../domain/content.dart';
import '../domain/engine.dart';
import 'details.dart';
import 'karma_page.dart';
import 'cultivation_page.dart';
import 'ink_theme.dart';

class GameShell extends ConsumerStatefulWidget {
  const GameShell({super.key, required this.toggleTheme});
  final VoidCallback toggleTheme;
  @override
  ConsumerState<GameShell> createState() => _GameShellState();
}

class _GameShellState extends ConsumerState<GameShell> {
  int tab = 0, activity = -1;
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is RuleViolation ? error.message : '操作未能保存，请稍后重试。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void command(
    String kind, {
    String? target,
    String? item,
    int amount = 1,
    bool secret = false,
  }) => run(
    () => ref
        .read(gameProvider.notifier)
        .command(
          GameCommand(
            kind,
            target: target,
            item: item,
            amount: amount,
            secret: secret,
          ),
        ),
  );
  Widget button(
    GameView view,
    String text,
    String kind, {
    String? target,
    String? item,
    int amount = 1,
    bool secret = false,
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8, bottom: 8),
    child: OutlinedButton(
      onPressed: view.readOnly || busy
          ? null
          : () => command(
              kind,
              target: target,
              item: item,
              amount: amount,
              secret: secret,
            ),
      child: Text(text),
    ),
  );
  Future<void> create() async {
    final name = TextEditingController(text: '李长生');
    final seed = TextEditingController();
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('踏入仙途'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 20,
              decoration: const InputDecoration(labelText: '道号'),
            ),
            TextField(
              controller: seed,
              maxLength: 100,
              decoration: const InputDecoration(labelText: '世界种子（留空随机）'),
            ),
            const Text('种子决定初始条件，行动决定后续历史。\n身死后这一世永久结束。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始修行'),
          ),
        ],
      ),
    );
    final chosenName = name.text, chosenSeed = seed.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      seed.dispose();
    });
    if (choice == true && mounted) {
      await run(
        () => ref.read(gameProvider.notifier).create(chosenName, chosenSeed),
      );
      if (mounted) {
        setState(() {
          tab = 0;
          activity = -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    return Scaffold(
      appBar: tab == 0 && activity < 0 && game.asData?.value.exists == true
          ? null
          : AppBar(
              leading: tab == 0 && activity >= 0
                  ? IconButton(
                      tooltip: '回到修行录',
                      onPressed: () => setState(() => activity = -1),
                      icon: const Icon(Icons.arrow_back),
                    )
                  : null,
              title: Text(
                tab == 0 ? '修行杂记' : const ['修行录', '山河志', '因果录', '万世碑'][tab],
              ),
              actions: [
                IconButton(
                  tooltip: '切换深浅主题',
                  onPressed: widget.toggleTheme,
                  icon: const Icon(Icons.brightness_6_outlined),
                ),
              ],
            ),
      body: SafeArea(
        child: PaperSurface(
          child: game.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('存档读取失败：$e'),
                    const Text('原存档保留，不会自动覆盖。'),
                    TextButton(
                      onPressed: () => ref.invalidate(gameProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
            data: (v) {
              if (!v.exists) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.landscape_outlined, size: 80),
                      const SizedBox(height: 24),
                      Text(
                        '山河有因，众生有缘',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text('一场可追溯的文字修仙人生'),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy ? null : create,
                        child: const Text('踏入仙途'),
                      ),
                    ],
                  ),
                );
              }
              return Stack(
                children: [
                  switch (tab) {
                    0 =>
                      activity < 0
                          ? CultivationPage(
                              view: v,
                              repository: ref
                                  .read(gameProvider.notifier)
                                  .repository!,
                              busy: busy,
                              onCommand: (kind) => command(
                                kind,
                                item: kind == 'useItem' ? '回春丹' : null,
                              ),
                              onWorld: () => setState(() => tab = 1),
                              onWorkshop: (index) =>
                                  setState(() => activity = index),
                              onTheme: widget.toggleTheme,
                            )
                          : cultivation(v),
                    1 => world(v),
                    2 => const KarmaPage(),
                    _ => archives(v),
                  },
                  if (busy)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: InkNavigation(
        index: tab,
        onChanged: (value) => setState(() {
          tab = value;
          if (value == 0) activity = -1;
        }),
      ),
    );
  }

  Widget heading(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget cultivation(GameView v) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('功法背包')),
            ButtonSegment(value: 1, label: Text('炼丹坊市')),
            ButtonSegment(value: 2, label: Text('奇遇委托')),
          ],
          selected: {activity},
          onSelectionChanged: (s) => setState(() => activity = s.first),
        ),
      ),
      if (activity == 0) ...[
        heading('修行功法'),
        Text(v.techniques.join(' · ')),
        heading('行囊'),
        ...v.inventory.entries
            .where((e) => e.value > 0)
            .map(
              (entry) => Card(
                child: ListTile(
                  title: Text('${entry.key} × ${entry.value}'),
                  trailing: v.readOnly
                      ? null
                      : TextButton(
                          onPressed:
                              busy ||
                                  (!Content.techniques.containsKey(entry.key) &&
                                      !Content.recipes.containsKey(entry.key) &&
                                      !['青锋剑', '玄铁甲'].contains(entry.key))
                              ? null
                              : () => command(
                                  Content.techniques.containsKey(entry.key)
                                      ? 'learn'
                                      : ['青锋剑', '玄铁甲'].contains(entry.key)
                                      ? 'equip'
                                      : 'useItem',
                                  item: entry.key,
                                ),
                          child: Text(
                            Content.techniques.containsKey(entry.key)
                                ? '参悟'
                                : ['青锋剑', '玄铁甲'].contains(entry.key)
                                ? '装备'
                                : Content.recipes.containsKey(entry.key)
                                ? '服用'
                                : '原料',
                          ),
                        ),
                ),
              ),
            ),
      ] else if (activity == 1) ...[
        heading('炼丹'),
        Wrap(
          children: Content.recipes.entries
              .map(
                (e) => button(
                  v,
                  '${e.key}（${e.value}灵草＋3灵石）',
                  'craft',
                  item: e.key,
                ),
              )
              .toList(),
        ),
        heading('坊市'),
        ...Content.prices.entries.map(
          (e) => Card(
            child: ListTile(
              title: Text(e.key),
              subtitle: Text('${e.value}灵石 · 出售半价'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '购买${e.key}',
                    onPressed: v.readOnly || busy
                        ? null
                        : () => command('trade', item: e.key),
                    icon: const Icon(Icons.add_shopping_cart),
                  ),
                  IconButton(
                    tooltip: '出售${e.key}',
                    onPressed:
                        v.readOnly || busy || (v.inventory[e.key] ?? 0) < 1
                        ? null
                        : () => command('trade', item: e.key, amount: -1),
                    icon: const Icon(Icons.sell_outlined),
                  ),
                ],
              ),
            ),
          ),
        ),
      ] else ...[
        heading('奇遇与宗门委托'),
        if (v.quests.isEmpty) const Text('探索可能发现古碑；加入宗门可领取委托。'),
        ...v.quests.entries.map(
          (e) => Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(e.key),
                  subtitle: Text(
                    e.value >= 3
                        ? '已了结'
                        : '阶段 ${e.value + 1}/3 · ${Content.questDescriptions[e.key]?[e.value] ?? '追寻线索'}',
                  ),
                ),
                if (e.value < 3)
                  Wrap(
                    children: [
                      button(v, '继续推进', 'quest', item: e.key),
                      if (e.key == '古碑' && e.value == 1)
                        button(
                          v,
                          '放弃此缘',
                          'quest',
                          item: e.key,
                          target: 'leave',
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
      heading('近日见闻'),
      ...ref
          .read(gameProvider.notifier)
          .repository!
          .recent(limit: 8)
          .map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.title),
              subtitle: Text(Content.date(e.time)),
              onTap: () => showEventDetails(
                context,
                ref.read(gameProvider.notifier).repository!,
                e,
              ),
            ),
          ),
      Text('世界种子：${v.seed}', style: Theme.of(context).textTheme.bodySmall),
    ],
  );
  Widget world(GameView v) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text(
        v.location,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontSize: 38),
      ),
      const SizedBox(height: 8),
      const Text('行过山河，方知众生因缘。'),
      const SizedBox(height: 18),
      const Divider(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '寻访机缘',
                style: TextStyle(fontFamily: 'MaShan', fontSize: 26),
              ),
            ),
            InkAction(
              label: '探索 · 3日',
              onPressed: v.readOnly || busy ? null : () => command('explore'),
            ),
          ],
        ),
      ),
      const Divider(),
      heading('山河行旅'),
      Wrap(
        spacing: 4,
        children: v.places
            .map((n) => button(v, n.displayName, 'travel', target: n.id))
            .toList(),
      ),
      heading('宗门'),
      ...v.sects.map(
        (n) => Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(n.displayName),
              onTap: () => showNodeDetails(context, n),
              trailing: TextButton(
                onPressed: v.readOnly || busy || !n.alive
                    ? null
                    : () => command('joinSect', target: n.id),
                child: const Text('拜入 · 20灵石'),
              ),
            ),
            const Divider(),
          ],
        ),
      ),
      heading('附近修士'),
      const Text('轻触姓名，展开这一场相逢。', style: TextStyle(fontSize: 13)),
      if (v.nearby.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('此地暂未遇到修士。'),
        ),
      ...v.nearby.map(
        (n) => Column(
          children: [
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: Text(n.displayName, style: const TextStyle(fontSize: 20)),
              subtitle: Text(n.description),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    children: [
                      for (final action in const {
                        '救助': 'rescue',
                        '结交': 'befriend',
                        '拜师': 'apprentice',
                        '立诺': 'promise',
                        '借款': 'borrow',
                        '还款': 'repay',
                        '道侣': 'companion',
                        '调查': 'investigate',
                        '交战': 'startBattle',
                      }.entries)
                        button(v, action.key, action.value, target: n.id),
                      button(
                        v,
                        '秘密交战',
                        'startBattle',
                        target: n.id,
                        secret: true,
                      ),
                      TextButton(
                        onPressed: () => showNodeDetails(context, n),
                        child: const Text('查看人物'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
          ],
        ),
      ),
      const SizedBox(height: 20),
    ],
  );
  Widget archives(GameView v) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      heading('万世碑'),
      const Text('每一世的山河与因果独立封存。'),
      if (v.assessment != null) ...[
        heading('一世因果'),
        ...{
          '结识修士': 'knownCultivators',
          '建立善缘': 'good',
          '建立恶缘': 'bad',
          '重大因果': 'major',
          '已了结': 'settled',
          '尚未了结': 'unsettled',
          '最深善缘': 'deepestGood',
          '最深恶缘': 'deepestBad',
          '最大世界影响': 'worldImpact',
          '人生影响评分': 'score',
        }.entries.map(
          (e) => ListTile(
            title: Text(e.key),
            trailing: SizedBox(
              width: 170,
              child: Text(
                '${v.assessment![e.value] ?? '无已知记录'}',
                textAlign: TextAlign.end,
              ),
            ),
          ),
        ),
        const Text('评分依据强度、结果、了结与世界影响，统计数量不直接决定分数。'),
      ],
      if (v.readOnly)
        FilledButton(
          onPressed: busy ? null : create,
          child: const Text('开启新一世'),
        ),
      TextButton(
        onPressed: busy
            ? null
            : () =>
                  run(() => ref.read(gameProvider.notifier).returnToCurrent()),
        child: const Text('回到当前人生'),
      ),
      ...v.archives.map(
        (a) => Card(
          child: ListTile(
            title: Text(a.name),
            subtitle: Text('${Content.date(a.day)} · 评分 ${a.score}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                run(() => ref.read(gameProvider.notifier).openArchive(a.id)),
          ),
        ),
      ),
      if (v.archives.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('这一世尚未结束，碑上尚无刻痕。'),
        ),
    ],
  );
}
