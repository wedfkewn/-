part of 'engine.dart';

abstract final class CommissionRules {
  static CommissionState? active(World w) =>
      w.commissions.where((c) => c.status == 'active').firstOrNull;

  static String _blocked(World w) {
    if (w.frozen || !w.player.alive) return '这一世已结束，委托记录只读';
    if (w.encounter != null) return '请先处理奇遇';
    if (w.battleTarget != null || w.tribulation != null) return '请先完成交锋';
    if (w.secretRun != null) return '请先离开秘境';
    return '';
  }

  static bool _atBoard(World w) =>
      w.knows(w.playerId, w.player.location) &&
      [
        PlaceKind.town,
        PlaceKind.market,
        PlaceKind.sect,
      ].contains(w.mapPlaces[w.player.location]?.kind);

  static bool _complete(World w, CommissionState state) {
    final config = Content.commissions[state.kind]!;
    return config.requirements.entries.every(
      (e) =>
          (state.evidence[e.key]?.values
                  .where(
                    (id) => w.events.containsKey(id) && w.knows(w.playerId, id),
                  )
                  .length ??
              0) >=
          e.value,
    );
  }

  static String _claimNotice(World w, CommissionState state) {
    final blocked = _blocked(w);
    if (blocked.isNotEmpty) return blocked;
    if (!_complete(w, state)) return '接取后完成全部目标，再返回交付';
    if (!_atBoard(w)) return '请返回已确认的城镇、坊市或宗门驻地交付';
    if (state.deliveryItem != null &&
        (w.inventory[state.deliveryItem] ?? 0) < 1) {
      return '需交付${state.deliveryItem} ×1';
    }
    return '';
  }

  static CommissionBoardView view(World w) {
    final state = active(w);
    if (w.frozen && state == null) {
      return const CommissionBoardView(notice: '这一世已结束，委托记录只读');
    }
    final blocked = _blocked(w);
    final boardNotice = blocked.isNotEmpty
        ? blocked
        : !_atBoard(w)
        ? '请前往已确认的城镇、坊市或宗门驻地接取和交付'
        : state != null
        ? '当前一约待履行'
        : '每类每大境界一次；放弃也占用次数';
    CommissionView? projected;
    if (state != null) {
      final config = Content.commissions[state.kind]!;
      final notice = _claimNotice(w, state);
      projected = CommissionView(
        id: state.id,
        kind: state.kind,
        title: config.title,
        description: config.description,
        acceptedRealm: state.realm,
        coins: state.coins,
        foundation: state.foundation,
        deliveryItem: state.deliveryItem,
        canClaim: notice.isEmpty,
        notice: notice,
        objectives: List.unmodifiable(
          config.requirements.entries.map((e) {
            final sources = (state.evidence[e.key]?.values ?? const <String>[])
                .where(
                  (id) => w.events.containsKey(id) && w.knows(w.playerId, id),
                )
                .toList();
            return CommissionObjectiveView(
              id: e.key,
              label: config.objectives[e.key]!,
              current: sources.length.clamp(0, e.value),
              required: e.value,
              sourceEventIds: List.unmodifiable(sources),
            );
          }),
        ),
      );
    }
    final offers = w.frozen
        ? const <CommissionOffer>[]
        : Content.commissions.entries.map((entry) {
            final used = w.commissions.any(
              (c) => c.kind == entry.key && c.realm == w.player.realm,
            );
            final config = entry.value;
            final notice = used
                ? '本境界已接取过此委托'
                : state != null
                ? '请先完成或放弃当前委托'
                : blocked.isNotEmpty
                ? blocked
                : !_atBoard(w)
                ? '须在已确认的城镇、坊市或宗门驻地接取'
                : '';
            return CommissionOffer(
              id: entry.key,
              title: config.title,
              description: config.description,
              goals: List.unmodifiable(
                config.requirements.entries.map(
                  (e) => '${config.objectives[e.key]} ×${e.value}',
                ),
              ),
              coins: config.coins,
              foundation: config.foundation,
              deliveryItem: config.deliveryItem,
              available: notice.isEmpty,
              notice: notice,
            );
          }).toList();
    return CommissionBoardView(
      active: projected,
      offers: List.unmodifiable(offers),
      canAccept: offers.any((offer) => offer.available),
      canClaim: projected?.canClaim ?? false,
      notice: boardNotice,
    );
  }

  static void accept(World w, FactWriter f, String? kind) {
    final offer = view(w).offers.where((offer) => offer.id == kind).firstOrNull;
    if (offer == null) throw const RuleViolation('无此山河委托');
    if (!offer.available) throw RuleViolation(offer.notice);
    final event = f.event(
      'commissionAccepted',
      '接取${offer.title}',
      '仅接取后的真实行动计入进度；报酬${offer.coins}灵石、${offer.foundation}根基。',
      [w.playerId],
    );
    w.commissions.add(
      CommissionState(
        id: w.nextId('commission'),
        kind: kind!,
        realm: w.player.realm,
        origin: event.id,
        coins: offer.coins,
        foundation: offer.foundation,
        deliveryItem: offer.deliveryItem,
      ),
    );
  }

  static void record(
    World w,
    FactWriter f,
    GameCommand command,
    World previous,
  ) {
    if (w.frozen || !w.player.alive) return;
    final state = active(w);
    if (state == null || !previous.events.containsKey(state.origin)) return;
    final config = Content.commissions[state.kind]!;
    final (objective, eventKind) = switch ((
      state.kind,
      command.kind,
      command.item,
    )) {
      ('travel', 'moveStep', _) => ('visit', 'travel'),
      ('alchemy', 'gather', '灵草') => ('gather', 'gather'),
      ('alchemy', 'craft', '回春丹') => ('craft', 'craft'),
      ('foundation', 'stabilize', _) => ('stabilize', 'stabilize'),
      ('foundation', 'practice', _) => ('practice', 'practice'),
      _ => ('', ''),
    };
    if (objective.isEmpty) return;
    final result = w.events.values
        .where(
          (e) =>
              !previous.events.containsKey(e.id) &&
              e.kind == eventKind &&
              e.participants.contains(w.playerId) &&
              w.knows(w.playerId, e.id),
        )
        .firstOrNull;
    if (result == null) return;
    final evidence = state.evidence.putIfAbsent(objective, () => {});
    final token = objective == 'visit' ? result.location : objective;
    if (evidence.containsKey(token) ||
        evidence.length >= config.requirements[objective]!) {
      return;
    }
    evidence[token] = result.id;
    final progress = f.event(
      'commissionProgress',
      '${config.title} · ${config.objectives[objective]}',
      '真实行动达成目标，进度${evidence.length}/${config.requirements[objective]}。',
      [w.playerId],
      causes: [
        Cause(state.origin, CausalKind.direct),
        Cause(result.id, CausalKind.direct),
      ],
    );
    state.progressEvents.add(progress.id);
  }

  static void claim(World w, FactWriter f) {
    final state = active(w);
    if (state == null) throw const RuleViolation('没有待交付的山河委托');
    final notice = _claimNotice(w, state);
    if (notice.isNotEmpty) throw RuleViolation(notice);
    if (state.deliveryItem != null) {
      w.inventory[state.deliveryItem!] = w.inventory[state.deliveryItem]! - 1;
    }
    w.player.coins += state.coins;
    w.player.foundation = (w.player.foundation + state.foundation).clamp(
      0,
      100,
    );
    final event = f.event(
      'commissionClaimed',
      '交付${Content.commissions[state.kind]!.title}',
      '${state.deliveryItem == null ? '' : '交付${state.deliveryItem} ×1，'}获得${state.coins}灵石与${state.foundation}根基。',
      [w.playerId],
      causes: [
        Cause(state.origin, CausalKind.direct),
        ...state.progressEvents.map((id) => Cause(id, CausalKind.direct)),
      ],
    );
    state.status = 'claimed';
    state.result = event.id;
  }

  static void abandon(World w, FactWriter f) {
    final blocked = _blocked(w);
    if (blocked.isNotEmpty) throw RuleViolation(blocked);
    final state = active(w);
    if (state == null) throw const RuleViolation('没有可放弃的山河委托');
    final event = f.event(
      'commissionAbandoned',
      '放弃${Content.commissions[state.kind]!.title}',
      '保留已发生的历练记录，本境界不能再次接取同类委托。',
      [w.playerId],
      causes: [Cause(state.origin, CausalKind.direct)],
    );
    state.status = 'abandoned';
    state.result = event.id;
  }
}
