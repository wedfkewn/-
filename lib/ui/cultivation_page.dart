import 'package:flutter/material.dart';
import '../application/game_controller.dart';
import '../domain/karma_repository.dart';
import '../domain/models.dart';
import 'details.dart';
import 'battle_stage.dart';
import 'ink_theme.dart';

class CultivationPage extends StatelessWidget {
  const CultivationPage({
    super.key,
    required this.view,
    required this.repository,
    required this.busy,
    required this.onCommand,
    required this.onWorld,
    required this.onWorkshop,
    required this.onTheme,
  });
  final GameView view;
  final KarmaRepository repository;
  final bool busy;
  final ValueChanged<String> onCommand;
  final VoidCallback onWorld, onTheme;
  final ValueChanged<int> onWorkshop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frozen = view.readOnly || busy;
    final graph = repository.query(
      const GraphQuery(
        hops: 1,
        limit: 20,
        types: {
          KarmaRelationType.gratitude,
          KarmaRelationType.hatred,
          KarmaRelationType.debt,
          KarmaRelationType.promise,
        },
      ),
    );
    final bonds = graph.edges
        .where(
          (e) =>
              e.sourceNodeId == view.playerId ||
              e.targetNodeId == view.playerId,
        )
        .toList();
    final bond =
        bonds.where((e) => !e.resolved).firstOrNull ?? bonds.firstOrNull;
    final other = bond == null
        ? null
        : repository.node(
            bond.sourceNodeId == view.playerId
                ? bond.targetNodeId
                : bond.sourceNodeId,
          );
    final latest = repository.recent(limit: 1).firstOrNull;
    final narrative = view.readOnly
        ? '此世已入长河。山河与因果，皆留于碑上。'
        : view.battleName != null
        ? '你与${view.battleName}狭路相逢。气息交错，胜负未分。'
        : '${view.location}云雾渐散。你盘坐于石台，运转周天。';
    return ListView(
      key: const PageStorageKey('cultivation-home'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SizedBox(
          height: 279,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 160,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0, .14, .88, 1],
                  ).createShader(bounds),
                  child: Image.asset(
                    'assets/images/cultivation-landscape.png',
                    fit: BoxFit.cover,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xff62594a)
                        : null,
                    colorBlendMode: BlendMode.modulate,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 58,
                top: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '游戏第 ${view.day} 日',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 13),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '修行录',
                              style: TextStyle(
                                fontFamily: 'MaShan',
                                fontSize: 57,
                                height: 1.15,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _Seal('修\n行'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${view.name} · ${view.realm}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 19),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                top: 14,
                child: Tooltip(
                  message: '切换深浅主题',
                  child: InkWell(
                    onTap: onTheme,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        children: [
                          Text(
                            '一\n世\n仙\n途',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'MaShan',
                              fontSize: 14,
                              height: 1.35,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const _Seal('因\n缘'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 15, 22, 18),
          child: Text(
            narrative,
            style: const TextStyle(fontSize: 17, height: 1.6),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      _Stat(
                        '修为',
                        '${view.spirit}',
                        Icons.local_fire_department_outlined,
                      ),
                      _separator(context),
                      _Stat(
                        '气血',
                        '${view.hp}',
                        Icons.favorite_outline,
                        tooltip: '气血 ${view.hp}/${view.maxHp}',
                      ),
                      _separator(context),
                      _Stat('灵石', '${view.coins}', Icons.diamond_outlined),
                      _separator(context),
                      _Stat(
                        '寿元',
                        '${view.age}/${view.lifespan}岁',
                        Icons.hourglass_empty,
                        small: true,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 7, bottom: 6),
                child: Row(
                  children: [
                    Text(
                      view.battleName == null ? '此刻' : '交锋',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(fontSize: 28),
                    ),
                    const Spacer(),
                    Text(
                      view.readOnly ? '这一世，已成往事。' : '于一念之间，行己之道。',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (view.battleName == null) ...[
                _ActionRow(
                  title: '闭关修炼',
                  subtitle: '静心凝神，运转周天，稳固修为。',
                  active: true,
                  icon: Icons.self_improvement,
                  trailing: InkAction(
                    key: const Key('cultivate-action'),
                    label: busy ? '运转中…' : '执行 · 30日',
                    onPressed: frozen ? null : () => onCommand('cultivate'),
                  ),
                ),
                _ActionRow(
                  title: view.growth.stage < 3 ? '境界成长' : '突破准备',
                  subtitle:
                      '根基 ${view.growth.foundation} · 感悟 ${view.growth.insight} · 查看条件与历练',
                  icon: Icons.arrow_upward,
                  onTap: frozen ? null : () => onCommand('breakthrough'),
                ),
                _ActionRow(
                  title: '前往世界',
                  subtitle: '游历四方，结识故人，探寻机缘。',
                  icon: Icons.temple_buddhist_outlined,
                  onTap: onWorld,
                ),
              ],
              BattleStage(
                key: const ValueKey('battle-stage'),
                view: view,
                busy: busy,
                onCommand: onCommand,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  List.generate(
                    4,
                    (i) =>
                        '${CharacterAttributes.labels[i]} ${view.attributes.values[i]}',
                  ).join(' · '),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 11, bottom: 8),
                child: InkWell(
                  onTap: bond == null
                      ? (latest == null
                            ? null
                            : () =>
                                  showEventDetails(context, repository, latest))
                      : () => showEdgeDetails(context, repository, bond),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '近日因缘',
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(fontSize: 23),
                          ),
                          const Spacer(),
                          const _Seal('缘\n起'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bond != null && other != null
                            ? '${relationLabel(bond.relationType)} · ${other.displayName} · ${bond.resolved ? '已了结' : '尚未了结'}。'
                            : latest?.title ?? '一世初启，缘随行生。',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => onWorkshop(0),
                      child: const Text('行囊 · 功法'),
                    ),
                    TextButton(
                      onPressed: () => onWorkshop(1),
                      child: const Text('炼丹 · 坊市'),
                    ),
                    TextButton(
                      onPressed: () => onWorkshop(2),
                      child: const Text('奇遇 · 委托'),
                    ),
                  ],
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: frozen ? null : () => onCommand('wait'),
                    child: const Text('静观30日'),
                  ),
                  TextButton(
                    onPressed: frozen ? null : () => onCommand('divine'),
                    child: const Text('推演天机'),
                  ),
                ],
              ),
              Text(
                '神识 ${view.awareness} · ${view.weapon ?? '未佩兵刃'} · ${view.armor ?? '未着护甲'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _separator(BuildContext context) => VerticalDivider(
    width: 1,
    thickness: .5,
    color: Theme.of(context).dividerColor,
  );
}

class _Stat extends StatelessWidget {
  const _Stat(
    this.label,
    this.value,
    this.icon, {
    this.small = false,
    this.tooltip,
  });
  final String label, value;
  final IconData icon;
  final bool small;
  final String? tooltip;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Tooltip(
      message: tooltip ?? '$label $value',
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!small) ...[
                Icon(
                  icon,
                  size: 17,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(fontSize: small ? 13 : 17),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.active = false,
    this.trailing,
    this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final bool active;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final heading = Text(
      title,
      style: const TextStyle(fontFamily: 'MaShan', fontSize: 25, height: 1.25),
    );
    final caption = Text(
      subtitle,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    final leading = SizedBox(
      width: 26,
      child: active
          ? Image.asset(
              'assets/images/crimson-mark.png',
              width: 7,
              height: 34,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            )
          : icon == Icons.temple_buddhist_outlined
          ? const InkIcon(index: 1, size: 29)
          : icon == Icons.arrow_upward
          ? Image.asset(
              'assets/images/breakthrough-ink.png',
              width: 29,
              height: 32,
              fit: BoxFit.contain,
              color: Theme.of(context).colorScheme.onSurface,
              colorBlendMode: BlendMode.srcIn,
              excludeFromSemantics: true,
            )
          : Icon(
              icon,
              size: 29,
              color: Theme.of(context).colorScheme.onSurface,
            ),
    );
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: active ? 6 : 10),
            child: active
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          leading,
                          const SizedBox(width: 10),
                          Expanded(child: heading),
                          ?trailing,
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 36, top: 2),
                        child: caption,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      leading,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading,
                            const SizedBox(height: 5),
                            caption,
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 29),
                    ],
                  ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}

class _Seal extends StatelessWidget {
  const _Seal(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(
        color: Theme.of(context).colorScheme.primary,
        width: .8,
      ),
      borderRadius: BorderRadius.circular(1),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'MaShan',
        fontSize: 11,
        height: 1.05,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
