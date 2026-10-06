import 'package:flutter/material.dart';
import '../domain/content.dart';
import '../domain/karma_repository.dart';
import 'details.dart';

class CausalTimeline extends StatefulWidget {
  const CausalTimeline({
    super.key,
    required this.repository,
    this.entity,
    this.relation,
  });
  final KarmaRepository repository;
  final String? entity, relation;
  @override
  State<CausalTimeline> createState() => _CausalTimelineState();
}

class _CausalTimelineState extends State<CausalTimeline> {
  List<VisibleEvent> events = [];
  bool more = true;
  String? chain;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final page = widget.repository.timeline(
      offset: events.length,
      limit: 30,
      entity: widget.entity,
      relation: widget.relation,
    );
    events.addAll(page);
    more = page.length == 30;
  }

  @override
  Widget build(BuildContext context) {
    final visible = chain == null
        ? events
        : widget.repository.causalChain(chain!);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: visible.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chain == null ? '因果长河' : '明确因果链',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('按时间排列；仅明确原因与影响建立链接。'),
              if (chain != null)
                TextButton(
                  onPressed: () => setState(() => chain = null),
                  child: const Text('返回全部已知历史'),
                ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('暂无符合条件的已知事件'),
                ),
            ],
          );
        }
        if (index == visible.length + 1) {
          return chain == null && more
              ? TextButton(
                  onPressed: () => setState(load),
                  child: const Text('加载更多'),
                )
              : const SizedBox(height: 24);
        }
        final event = visible[index - 1];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: Icon(
                    event.importance >= 3
                        ? Icons.auto_awesome
                        : Icons.circle_outlined,
                  ),
                  title: Text(event.title),
                  subtitle: Text(
                    '${Content.date(event.time)} · ${event.locationName}',
                  ),
                  onTap: () =>
                      showEventDetails(context, widget.repository, event),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    event.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => chain = event.id),
                      child: const Text('追溯明确因果链'),
                    ),
                    if (event.causes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('${event.causes.length} 条已知来源'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
