import 'package:flutter/material.dart';
import '../application/game_controller.dart';
import '../domain/models.dart';
import 'illustrations.dart';

/// Activity cards use only already-filtered geography and player presentation.
class LocationActivities extends StatelessWidget {
  const LocationActivities({
    super.key,
    required this.view,
    required this.busy,
    required this.onAction,
  });
  final GameView view;
  final bool busy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final here = view.map.places
        .where((p) => p.confirmed && p.place.id == view.map.current)
        .firstOrNull;
    final blocked =
        busy ||
        view.readOnly ||
        view.encounter != null ||
        view.battleName != null ||
        view.secretStage != null;
    final cards =
        <
          ({
            String title,
            String subtitle,
            String art,
            String action,
            bool blocked,
          })
        >[
          (
            title: '探索 · 3日',
            subtitle: '发现奇遇，选择去留',
            art: IllustrationResolver.current(view.map),
            action: 'explore',
            blocked: blocked,
          ),
          (
            title: '山河委托',
            subtitle: view.commission.active == null
                ? '接约 · 历练 · 交付'
                : '正在进行：${view.commission.active!.title}',
            art: 'encounter_escort',
            action: 'commission',
            blocked: busy,
          ),
          (
            title: '山河行旅',
            subtitle: view.map.destination == null ? '已知道路，逐段前进' : '继续尚未结束的行旅',
            art: 'wild_b',
            action: 'map',
            blocked: busy,
          ),
          if (here != null &&
              [
                PlaceKind.town,
                PlaceKind.market,
                PlaceKind.sect,
              ].contains(here.place.kind))
            (
              title: '坊市补给',
              subtitle: '丹药 · 装备 · 材料',
              art: 'market_a',
              action: 'market',
              blocked: blocked,
            ),
          if (here != null &&
              [PlaceKind.wild, PlaceKind.ruin].contains(here.place.kind) &&
              here.place.resources.contains('灵草'))
            (
              title: '采集灵草',
              subtitle: '10日 · 为炼丹积攒材料',
              art: 'encounter_herbs',
              action: 'gather',
              blocked: blocked,
            ),
          (
            title: here?.place.kind == PlaceKind.vein ? '灵脉修行' : '修行准备',
            subtitle: '根基 · 感悟 · 渡劫',
            art: 'vein_a',
            action: 'growth',
            blocked: blocked,
          ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 21;
        final columns = width >= 650 && !largeText
            ? 3
            : width >= 320 && !largeText
            ? 2
            : 1;
        final tileWidth = (width - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: tileWidth,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: .35),
                    ),
                    child: InkWell(
                      onTap: card.blocked ? null : () => onAction(card.action),
                      child: Semantics(
                        button: true,
                        enabled: !card.blocked,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkIllustration(
                                art: card.art,
                                height: 76,
                                opacity: card.blocked ? .45 : 1,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                card.title,
                                style: TextStyle(
                                  fontFamily: 'MaShan',
                                  fontFamilyFallback: ['WenKai'],
                                  fontSize: 23,
                                  color: card.blocked
                                      ? Theme.of(context).disabledColor
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                card.subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
