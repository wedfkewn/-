import 'illustrations.dart';
import 'ink_overlays.dart';
import 'package:flutter/material.dart';
import '../domain/content.dart';
import '../domain/karma_repository.dart';
import '../domain/models.dart';

void showNodeDetails(BuildContext context, KarmaNode node) =>
    showInkSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                InkIllustration(
                  art: IllustrationResolver.node(node),
                  height: node.type == KarmaNodeType.npc ? 120 : null,
                ),
                Text(node.description),
                const SizedBox(height: 8),
                Text('${node.visibility} · ${node.alive ? '存续' : '已入历史'}'),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );

void showEventDetails(
  BuildContext context,
  KarmaRepository repository,
  VisibleEvent event,
) => showInkSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(event.title, style: Theme.of(context).textTheme.headlineSmall),
          Text('${Content.date(event.time)} · ${event.locationName}'),
          const SizedBox(height: 16),
          const InkIllustration(art: 'wild_a'),
          ExpandableNarrative(event.description),
          const Divider(),
          const Text('已知参与者'),
          Wrap(
            spacing: 8,
            children: event.participants
                .map(
                  (n) => ActionChip(
                    label: Text(n.displayName),
                    onPressed: () => showNodeDetails(context, n),
                  ),
                )
                .toList(),
          ),
          const Divider(),
          const Text('明确起因'),
          if (event.causes.isEmpty) const Text('尚无已知、明确记录的因果来源。'),
          ...event.causes.map((c) {
            final source = repository.event(c.eventId)!;
            return ListTile(
              leading: Icon(
                c.kind == CausalKind.direct
                    ? Icons.arrow_downward
                    : Icons.waves,
              ),
              title: Text(source.title),
              subtitle: Text(c.kind == CausalKind.direct ? '直接原因' : '间接影响'),
              onTap: () => showEventDetails(context, repository, source),
            );
          }),
          const Divider(),
          const Text('已知后果'),
          ...event.consequences.map((c) {
            final target = repository.event(c.eventId)!;
            return ListTile(
              title: Text(target.title),
              subtitle: Text(c.kind == CausalKind.direct ? '直接后果' : '间接影响'),
              onTap: () => showEventDetails(context, repository, target),
            );
          }),
          const Divider(),
          const Text('相关关系'),
          ...event.relations.map(
            (r) => ListTile(
              title: Text(relationLabel(r.relationType)),
              subtitle: Text(statusLabel(r.status)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('时间相邻仅表示先后，不代表因果。'),
          ),
        ],
      ),
    ),
  ),
);

void showEdgeDetails(
  BuildContext context,
  KarmaRepository repository,
  KarmaEdge edge, {
  VoidCallback? onTimeline,
}) => showInkSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            relationLabel(edge.relationType),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            '${repository.node(edge.sourceNodeId)!.displayName} ${edge.bidirectional ? '↔' : '→'} ${repository.node(edge.targetNodeId)!.displayName}',
          ),
          Text(
            '强度 ${edge.strength} · ${statusLabel(edge.status)} · ${edge.resolved ? '因果已了结' : '因果未偿'} · ${edge.visibilityLevel}',
          ),
          Text('建立于 ${Content.date(edge.createdGameTime)}'),
          if (edge.inheritedFrom != null) const Text('该义务由历史关系继承'),
          const Divider(),
          const Text('已知事实记录'),
          if (edge.relatedEventIds.isEmpty) const Text('初始世界关系，尚无已知的后续事件。'),
          ...edge.relatedEventIds.map((id) {
            final e = repository.event(id)!;
            return ListTile(
              title: Text(e.title),
              subtitle: Text(Content.date(e.time)),
              onTap: () => showEventDetails(context, repository, e),
            );
          }),
          if (onTimeline != null)
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(context);
                onTimeline();
              },
              child: const Text('查看因果演化'),
            ),
        ],
      ),
    ),
  ),
);
