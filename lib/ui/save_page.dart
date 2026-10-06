import 'package:flutter/material.dart';
import '../application/game_controller.dart';
import '../domain/content.dart';
import 'ink_theme.dart';

class SavePage extends StatelessWidget {
  const SavePage({
    super.key,
    required this.view,
    required this.busy,
    required this.onContinue,
    required this.onCreate,
    required this.onArchive,
    required this.onTheme,
  });
  final GameView view;
  final bool busy;
  final VoidCallback onContinue, onCreate, onTheme;
  final ValueChanged<String> onArchive;
  @override
  Widget build(BuildContext context) {
    final alive = view.exists && !view.readOnly;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '切换深浅主题',
            onPressed: onTheme,
            icon: const Icon(Icons.brightness_6_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: PaperSurface(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '仙途存档',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall!.copyWith(fontSize: 42),
                    ),
                  ),
                  Container(
                    width: 30,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: InkTheme.cinnabar),
                    ),
                    child: const Text(
                      '修',
                      style: TextStyle(
                        fontFamily: 'MaShan',
                        fontSize: 24,
                        color: InkTheme.cinnabar,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                alive
                    ? '一卷一生，落笔无悔。'
                    : view.archives.isEmpty
                    ? '落笔入山河，修行始于此。'
                    : '此世已终，因果长存。',
              ),
              const SizedBox(height: 8),
              Image.asset(
                'assets/images/cultivation-landscape.png',
                height: 146,
                width: double.infinity,
                fit: BoxFit.cover,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xff62594a)
                    : null,
                colorBlendMode: BlendMode.modulate,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 24),
              if (alive) ...[
                Text(
                  view.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('${view.realm} · ${view.age}岁'),
                Text('${view.location} · ${view.date}'),
                const SizedBox(height: 18),
                Center(
                  child: InkAction(
                    label: '继续这一世',
                    width: 240,
                    height: 58,
                    onPressed: busy ? null : onContinue,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('这一世仍在修行，行动后自动存档。'),
              ] else ...[
                Center(
                  child: Text(
                    '再启仙途',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall!.copyWith(fontSize: 40),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(child: Text('当前没有在世角色。')),
                const SizedBox(height: 18),
                Center(
                  child: InkAction(
                    label: '开启新一世',
                    width: 240,
                    height: 58,
                    onPressed: busy ? null : onCreate,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              const Divider(),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text('万世碑', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(width: 16),
                  Text('已封存 ${view.archives.length} 世'),
                ],
              ),
              const SizedBox(height: 12),
              if (view.archives.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Text('碑上尚无刻痕。'),
                ),
              ...view.archives.map(
                (a) => Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        a.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: Text(
                        '${a.realm} · ${a.age}岁\n${Content.date(a.day)} · 已封存',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy ? null : () => onArchive(a.id),
                    ),
                    const Divider(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                alive ? '本地自动存档 · 关闭后世界暂停' : '逝去之世只可回望，无法继续。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
