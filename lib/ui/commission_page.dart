import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/game_controller.dart';
import '../domain/engine.dart';
import 'details.dart';
import 'illustrations.dart';
import 'ink_overlays.dart';
import 'ink_theme.dart';
import 'map_page.dart';

class CommissionPage extends ConsumerStatefulWidget {
  const CommissionPage({super.key});
  @override
  ConsumerState<CommissionPage> createState() => _CommissionPageState();
}

class _CommissionPageState extends ConsumerState<CommissionPage> {
  bool busy = false;
  String message = '';
  Future<void> act(String kind, {String? item}) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await ref
          .read(gameProvider.notifier)
          .command(GameCommand(kind, item: item));
      if (!mounted) return;
      message = kind == 'claimCommission'
          ? '报酬已结算，委托经过已记入因果长河。'
          : kind == 'abandonCommission'
          ? '此约已放下，历史仍保留。'
          : '已接取委托。从这一刻起，真实行动将计入进度。';
    } catch (error) {
      if (mounted) {
        message = error is RuleViolation ? error.message : '委托未能保存，请重试。';
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> abandon() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => InkDialog(
        title: const Text('放下此约'),
        content: const Text('本境界内无法重新接取这份委托。已有经过仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续履约'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认放弃'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await act('abandonCommission');
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gameProvider).asData?.value;
    if (view == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final board = view.commission, active = board.active;
    final blocked =
        busy ||
        view.readOnly ||
        view.battleName != null ||
        view.encounter != null ||
        view.secretStage != null;
    return Scaffold(
      appBar: AppBar(title: const Text('山河委托')),
      body: PaperSurface(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const InkIllustration(art: 'encounter_escort', height: 150),
            Text('一诺落山河', style: Theme.of(context).textTheme.headlineSmall),
            const Text('接约 → 历练 → 交付 · 突破保留进度'),
            if (view.readOnly) const Text('历史只读：此世委托已随人生封存。'),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message),
              ),
            if (busy) const LinearProgressIndicator(),
            if (board.notice.isNotEmpty) Text(board.notice),
            if (active != null) ...[
              const Divider(height: 28),
              Text(active.title, style: Theme.of(context).textTheme.titleLarge),
              ExpandableNarrative(active.description, lines: 2, label: '委托缘由'),
              Text(
                '报酬 ${active.coins}灵石 · 根基+${active.foundation}${active.deliveryItem == null ? '' : ' · 交付${active.deliveryItem}×1'}',
              ),
              const SizedBox(height: 14),
              ...active.objectives.map(
                (step) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    step.current >= step.required
                        ? Icons.task_alt
                        : Icons.radio_button_unchecked,
                    color: step.current >= step.required
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(step.label),
                  trailing: Text('${step.current}/${step.required}'),
                  subtitle: step.sourceEventIds.isEmpty
                      ? const Text('只计算接取后的真实行动')
                      : const Text('已留痕 · 点击追溯'),
                  onTap: step.sourceEventIds.isEmpty
                      ? null
                      : () {
                          final repo = ref
                              .read(gameProvider.notifier)
                              .repository!;
                          final event = repo.event(step.sourceEventIds.last);
                          if (event != null) {
                            showEventDetails(context, repo, event);
                          }
                        },
                ),
              ),
              if (active.notice.isNotEmpty) Text(active.notice),
              FilledButton(
                onPressed: blocked || !board.canClaim
                    ? null
                    : () => act('claimCommission'),
                child: const Text('交付并领取报酬'),
              ),
              TextButton(
                onPressed: blocked ? null : abandon,
                child: const Text('放弃本次委托'),
              ),
              const Divider(height: 28),
            ],
            ExpansionTile(
              key: ValueKey(active?.id ?? 'commission-offers'),
              initiallyExpanded: active == null,
              tilePadding: EdgeInsets.zero,
              title: Text(active == null ? '可接告示' : '后续告示'),
              children: board.offers
                  .map(
                    (offer) => Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkIllustration(
                                art: offer.id == 'alchemy'
                                    ? 'feature_alchemy'
                                    : offer.id == 'foundation'
                                    ? 'vein_b'
                                    : 'wild_b',
                                height: 84,
                              ),
                              Text(
                                offer.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              ...offer.goals.map((goal) => Text('· $goal')),
                              Text('${offer.coins}灵石 · 根基+${offer.foundation}'),
                              if (offer.notice.isNotEmpty) Text(offer.notice),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text('委托缘由'),
                                children: [Text(offer.description)],
                              ),
                              OutlinedButton(
                                key: Key('accept-commission-${offer.id}'),
                                onPressed:
                                    blocked ||
                                        !board.canAccept ||
                                        !offer.available
                                    ? null
                                    : () => act(
                                        'acceptCommission',
                                        item: offer.id,
                                      ),
                                child: const Text('接下此约'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('查看山河，安排历练'),
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const MapPage()),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
