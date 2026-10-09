/// Immutable, observer-safe commission projections. Geography IDs stay in state.
class CommissionOffer {
  const CommissionOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.goals,
    required this.coins,
    required this.foundation,
    this.deliveryItem,
    this.available = false,
    this.notice = '',
  });
  final String id, title, description, notice;
  final List<String> goals;
  final int coins, foundation;
  final String? deliveryItem;
  final bool available;
}

class CommissionObjectiveView {
  const CommissionObjectiveView({
    required this.id,
    required this.label,
    required this.current,
    required this.required,
    this.sourceEventIds = const [],
  });
  final String id, label;
  final int current, required;
  final List<String> sourceEventIds;
}

class CommissionView {
  const CommissionView({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.acceptedRealm,
    required this.coins,
    required this.foundation,
    required this.objectives,
    this.deliveryItem,
    this.canClaim = false,
    this.notice = '',
  });
  final String id, kind, title, description, notice;
  final int acceptedRealm, coins, foundation;
  final String? deliveryItem;
  final List<CommissionObjectiveView> objectives;
  final bool canClaim;
}

class CommissionBoardView {
  const CommissionBoardView({
    this.active,
    this.offers = const [],
    this.canAccept = false,
    this.canClaim = false,
    this.notice = '',
  });
  final CommissionView? active;
  final List<CommissionOffer> offers;
  final bool canAccept, canClaim;
  final String notice;
}

/// Durable facts, including completed and abandoned commissions.
class CommissionState {
  CommissionState({
    required this.id,
    required this.kind,
    required this.realm,
    required this.origin,
    required this.coins,
    required this.foundation,
    this.deliveryItem,
    this.status = 'active',
    this.result,
  });
  final String id, kind, origin;
  final int realm;
  final int coins, foundation;
  final String? deliveryItem;
  String status;
  String? result;
  final Map<String, Map<String, String>> evidence = {};
  final List<String> progressEvents = [];
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'realm': realm,
    'origin': origin,
    'coins': coins,
    'foundation': foundation,
    'deliveryItem': deliveryItem,
    'status': status,
    'result': result,
    'evidence': evidence,
    'progressEvents': progressEvents,
  };
  factory CommissionState.fromJson(Map<String, dynamic> json) {
    final state = CommissionState(
      id: json['id'],
      kind: json['kind'],
      realm: json['realm'],
      origin: json['origin'],
      coins: json['coins'],
      foundation: json['foundation'],
      deliveryItem: json['deliveryItem'],
      status: json['status'] ?? 'active',
      result: json['result'],
    );
    for (final entry in (json['evidence'] as Map? ?? {}).entries) {
      state.evidence[entry.key as String] = Map<String, String>.from(
        entry.value,
      );
    }
    state.progressEvents.addAll(
      List<String>.from(json['progressEvents'] ?? []),
    );
    return state;
  }
}

class CommissionDefinition {
  const CommissionDefinition({
    required this.title,
    required this.description,
    required this.objectives,
    required this.requirements,
    required this.coins,
    required this.foundation,
    this.deliveryItem,
  });
  final String title, description;
  final Map<String, String> objectives;
  final Map<String, int> requirements;
  final int coins, foundation;
  final String? deliveryItem;
}
