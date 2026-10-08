import 'illustrations.dart';
import 'ink_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/ai_service.dart';
import '../application/game_controller.dart';
import '../domain/engine.dart';
import 'ink_theme.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});
  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final base = TextEditingController(),
      model = TextEditingController(),
      key = TextEditingController();
  bool enabled = false,
      world = false,
      consent = false,
      loading = true,
      busy = false,
      hasKey = false,
      loadFailed = false;
  String previousOrigin = '', message = '';
  List<Map<String, dynamic>> usage = [];
  Map<String, int> totals = {};
  AiContentService? detectingService, testingService;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        loadFailed = false;
      });
    }
    try {
      final service = ref.read(aiServiceProvider);
      final s = await service.settings();
      final saved = await service.secrets.read();
      final records = await ref.read(databaseProvider).usage();
      final total = await ref.read(databaseProvider).usageTotals();
      if (!mounted) return;
      setState(() {
        base.text = s.base;
        model.text = s.model;
        enabled = s.enabled;
        world = s.world;
        consent = s.consent;
        hasKey = saved?.isNotEmpty == true;
        previousOrigin = s.base.isEmpty
            ? ''
            : Uri.tryParse(s.base)?.origin ?? '';
        usage = records;
        totals = total;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = true;
          message = '无法读取天机设置或安全密钥，请重试。';
        });
      }
    }
  }

  @override
  void dispose() {
    detectingService?.cancel();
    testingService?.cancel();
    base.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  Future<void> detectModels() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '正在检测模型…';
    });
    final service = ref.read(aiServiceProvider);
    detectingService = service;
    try {
      final models = await service.detectModels(
        AiSettings(base: base.text.trim()),
        key.text,
      );
      detectingService = null;
      if (!mounted) return;
      var query = '';
      final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) {
            final filtered = models
                .where((id) => id.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return InkDialog(
              title: Text('选择模型 · ${models.length} 个'),
              content: SizedBox(
                width: 420,
                height: 360,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(labelText: '搜索模型'),
                      onChanged: (value) => update(() => query = value),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('没有匹配的模型'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) => ListTile(
                                title: Text(filtered[i]),
                                onTap: () => Navigator.pop(ctx, filtered[i]),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('返回'),
                ),
              ],
            );
          },
        ),
      );
      if (!mounted) return;
      if (selected != null) model.text = selected;
      message = selected == null
          ? '已检测到 ${models.length} 个模型'
          : '已选择 $selected，请保存设置；可用性可通过测试连接确认。';
    } on AiFailure catch (e) {
      message = e.message;
    } catch (_) {
      message = '模型检测失败，可手动填写模型名称';
    } finally {
      detectingService = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> perform(bool test) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final settings = AiSettings(
        base: base.text.trim(),
        model: model.text.trim(),
        enabled: enabled,
        world: world,
        consent: consent,
      );
      settings.endpoint;
      var confirmed = false;
      final newOrigin = Uri.parse(settings.base).origin;
      if (previousOrigin.isNotEmpty && newOrigin != previousOrigin) {
        confirmed =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => InkDialog(
                title: const Text('确认服务商变更'),
                content: Text('新的 API 服务商为 $newOrigin。原密钥会移除，请输入用于该服务商的密钥后保存。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('返回'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('确认'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!mounted || !confirmed) return;
        if (key.text.trim().isEmpty) throw const AiFailure('请为新的服务商输入密钥');
      }
      final service = ref.read(aiServiceProvider);
      final db = ref.read(databaseProvider);
      if (test) {
        if (previousOrigin.isNotEmpty &&
            previousOrigin != newOrigin &&
            key.text.isEmpty) {
          throw const AiFailure('新服务商不能使用原密钥');
        }
        testingService = service;
        await service.test(settings, key.text);
        if (!mounted) return;
        message = '连接成功 · 测试请求可能产生 token 消耗';
      } else {
        await service.saveSettings(
          settings,
          key.text,
          hostConfirmed: confirmed,
        );
        if (!mounted) return;
        previousOrigin = newOrigin;
        hasKey = (await service.secrets.read())?.isNotEmpty == true;
        if (!mounted) return;
        key.clear();
        message = '设置已保存';
      }
      usage = await db.usage();
      totals = await db.usageTotals();
    } on AiFailure catch (e) {
      message = e.message;
    } catch (_) {
      message = test ? '连接测试失败，请重试' : '设置未能保存，请重试';
    } finally {
      testingService = null;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final input = totals['input'] ?? 0,
        output = totals['output'] ?? 0,
        unknown = totals['unknown'] ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('天机设置')),
      body: PaperSurface(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : loadFailed
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message),
                    TextButton(onPressed: load, child: const Text('重试')),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  const Text(
                    '借天机，添万象',
                    style: TextStyle(fontFamily: 'MaShan', fontSize: 34),
                  ),
                  const Text('配置自己的 OpenAI 兼容 API。关闭 AI 后，仍可完整游历与修行。'),
                  const SizedBox(height: 18),
                  TextField(
                    controller: base,
                    enabled: !busy,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'API 基础地址',
                      hintText: 'https://服务商地址/v1',
                    ),
                  ),
                  TextField(
                    controller: key,
                    enabled: !busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API 密钥',
                      hintText: hasKey ? '已安全保存，留空保留' : '只保存在本机安全存储',
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy ? null : detectModels,
                        icon: const Icon(Icons.search),
                        label: const Text('检测模型'),
                      ),
                      if (detectingService != null)
                        TextButton(
                          onPressed: () => detectingService?.cancel(),
                          child: const Text('取消检测'),
                        ),
                    ],
                  ),
                  TextField(
                    controller: model,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: '点击检测选择，或手动填写',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 AI 奇遇与人物对话'),
                    subtitle: const Text('探索和每轮交谈自动请求，可能产生 API 费用'),
                    value: enabled,
                    onChanged: busy ? null : (v) => setState(() => enabled = v),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同意发送相关游戏背景和对话'),
                    subtitle: const Text('内容将发送给你填写的 API 服务商。密钥不写入游戏存档。'),
                    value: consent,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('AI 世界事件'),
                    subtitle: const Text('每30游戏日最多额外请求一次，会消耗更多 token；默认关闭。'),
                    value: world,
                    onChanged: busy ? null : (v) => setState(() => world = v),
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: busy ? null : () => perform(false),
                        child: const Text('保存设置'),
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : () => perform(true),
                        child: const Text('测试连接'),
                      ),
                      if (busy)
                        TextButton(
                          onPressed: () => ref.read(aiServiceProvider).cancel(),
                          child: const Text('取消请求'),
                        ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await ref.read(secretStoreProvider).delete();
                                final s = await ref
                                    .read(aiServiceProvider)
                                    .settings();
                                await ref.read(databaseProvider).saveSettings({
                                  ...s.toJson(),
                                  'enabled': false,
                                });
                                if (mounted) {
                                  setState(() {
                                    hasKey = false;
                                    enabled = false;
                                    message = '密钥已删除，AI已关闭';
                                  });
                                }
                              },
                        child: const Text('删除密钥'),
                      ),
                    ],
                  ),
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(message),
                    ),
                  const Divider(),
                  const Text(
                    '天机用量',
                    style: TextStyle(fontFamily: 'MaShan', fontSize: 27),
                  ),
                  Text(
                    '请求 ${totals['requests'] ?? 0} 次 · 已知输入 $input token · 已知输出 $output token${unknown > 0 ? '\n$unknown 次请求的用量未知' : ''}',
                  ),
                  const Text('按服务商返回的用量记录；不估算金额。取消请求也可能已产生费用。'),
                  ...usage
                      .take(12)
                      .map(
                        (e) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${e['kind']} · ${e['model']}'),
                          subtitle: Text('${e['time']}'),
                          trailing: Text(
                            e['input'] == null || e['output'] == null
                                ? '未知'
                                : '${e['input']} / ${e['output']}',
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

class EncounterPage extends ConsumerStatefulWidget {
  const EncounterPage({super.key});
  @override
  ConsumerState<EncounterPage> createState() => _EncounterPageState();
}

class _EncounterPageState extends ConsumerState<EncounterPage> {
  bool busy = false;
  String error = '';
  Future<void> choose(String id) async {
    setState(() => busy = true);
    try {
      await ref
          .read(gameProvider.notifier)
          .command(GameCommand('chooseEncounter', item: id));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is RuleViolation ? e.message : '行动未能保存');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(gameProvider).asData?.value;
    final e = v?.encounter;
    return Scaffold(
      appBar: AppBar(title: const Text('山河奇遇')),
      body: PaperSurface(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            if (e == null)
              const Text('此缘已了结。')
            else ...[
              Text(
                e.title,
                style: const TextStyle(fontFamily: 'MaShan', fontSize: 36),
              ),
              Text(e.source == 'ai' ? '天机所述 · 结果经本地规则校验' : '山河所见'),
              const SizedBox(height: 18),
              InkIllustration(art: IllustrationResolver.encounter(e, v!.map)),
              ExpandableNarrative(e.text),
              const SizedBox(height: 22),
              ...e.options.map((o) {
                final disabled =
                    v.readOnly ||
                    busy ||
                    v.coins < o.cost ||
                    o.pill && (v.inventory['回春丹'] ?? 0) < 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton(
                        onPressed: disabled ? null : () => choose(o.id),
                        child: Text(o.label),
                      ),
                      Text(
                        '${o.requirements}${v.coins < o.cost ? ' · 灵石不足' : ''}${o.pill && (v.inventory['回春丹'] ?? 0) < 1 ? ' · 回春丹不足' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (error.isNotEmpty) Text(error),
          ],
        ),
      ),
    );
  }
}

class DialoguePage extends ConsumerStatefulWidget {
  const DialoguePage({super.key, required this.npc, required this.name});
  final String npc, name;
  @override
  ConsumerState<DialoguePage> createState() => _DialoguePageState();
}

class _DialoguePageState extends ConsumerState<DialoguePage> {
  final input = TextEditingController();
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send(String text) async {
    if (busy || text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await ref
          .read(gameProvider.notifier)
          .command(GameCommand('talk', target: widget.npc, item: text));
      if (mounted) input.clear();
    } catch (e) {
      error = e is RuleViolation ? e.message : '交谈未能保存';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(gameProvider).asData?.value;
    final request = ref.watch(aiRequestProvider);
    final knownNpc = ref
        .read(gameProvider.notifier)
        .repository
        ?.node(widget.npc);
    final turns = v?.dialogue.where((t) => t.npc == widget.npc).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: Text('与${widget.name}交谈')),
      body: PaperSurface(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text(
              '言语留痕，行动结缘',
              style: TextStyle(fontFamily: 'MaShan', fontSize: 28),
            ),
            const Text('每轮交谈耗时1日。人物言论不等于事实，结交与交易请使用正式行动。'),
            if (knownNpc != null)
              InkIllustration(
                art: IllustrationResolver.node(knownNpc),
                height: 120,
              ),
            if (turns.length > 2)
              ExpansionTile(
                title: Text('此前交谈 · ${turns.length - 2}轮'),
                children: turns
                    .take(turns.length - 2)
                    .map(
                      (t) => ListTile(
                        title: Text('你：${t.input}'),
                        subtitle: ExpandableNarrative(
                          '${widget.name}：${t.reply}',
                          label: '展开言论',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ...turns
                .skip((turns.length - 2).clamp(0, turns.length))
                .map(
                  (t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('你：${t.input}'),
                        const SizedBox(height: 8),
                        Text('${widget.name}：${t.reply}'),
                        const Divider(),
                      ],
                    ),
                  ),
                ),
            if (request != null)
              Row(
                children: [
                  Expanded(child: Text(request)),
                  TextButton(
                    onPressed: () => ref.read(gameProvider.notifier).cancelAi(),
                    child: const Text('取消生成'),
                  ),
                ],
              ),
            if (v?.aiNotice.isNotEmpty == true) Text(v!.aiNotice),
            Wrap(
              spacing: 6,
              children: ['此地近来有什么见闻？', '你的修行近况如何？', '你对世间因缘有何看法？']
                  .map(
                    (s) => ActionChip(
                      label: Text(s),
                      onPressed: busy || v?.readOnly == true
                          ? null
                          : () => send(s),
                    ),
                  )
                  .toList(),
            ),
            TextField(
              controller: input,
              maxLength: 300,
              enabled: !busy && v?.readOnly != true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '想对他说的话'),
            ),
            FilledButton(
              onPressed: busy || v?.readOnly == true
                  ? null
                  : () => send(input.text),
              child: const Text('交谈 · 1日'),
            ),
            if (error.isNotEmpty) Text(error),
          ],
        ),
      ),
    );
  }
}
