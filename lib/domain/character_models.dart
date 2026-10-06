class CharacterAttributes {
  const CharacterAttributes([
    this.physique = 5,
    this.root = 5,
    this.insight = 5,
    this.awareness = 5,
  ]);
  final int physique, root, insight, awareness;
  List<int> get values => [physique, root, insight, awareness];
  static const labels = ['体魄', '根骨', '悟性', '神识'];
  static const descriptions = [
    '影响气血与基础攻击',
    '影响闭关修为收益',
    '降低大突破感悟要求',
    '影响战斗灵力与天机能力',
  ];
  int scale(int value, int attribute, int percent) =>
      value * (100 + (attribute - 5) * percent) ~/ 100;
  int insightRequired(int realm) =>
      ((10 + realm * 10) * (100 - (insight - 5) * 2) / 100).ceil();
  Map<String, Object?> toJson() => {'values': values};
  factory CharacterAttributes.fromJson(Map<String, dynamic>? j) {
    final v = List<int>.from(j?['values'] ?? [5, 5, 5, 5]);
    return CharacterAttributes(v[0], v[1], v[2], v[3]);
  }
}

class RebirthEntitlement {
  const RebirthEntitlement({this.source, this.score = 0, this.points = 0});
  final String? source;
  final int score, points;
  static int reward(int score) => score < 100
      ? 0
      : score < 300
      ? 2
      : score < 600
      ? 4
      : score < 1000
      ? 6
      : score < 1500
      ? 8
      : score < 2000
      ? 10
      : 12;
}

class CreationDraft {
  const CreationDraft(this.id, this.seed, this.candidates, this.entitlement);
  final String id, seed;
  final List<CharacterAttributes> candidates;
  final RebirthEntitlement entitlement;
  Map<String, Object?> toJson() => {
    'id': id,
    'seed': seed,
    'candidates': candidates.map((c) => c.toJson()).toList(),
    'source': entitlement.source,
    'score': entitlement.score,
    'points': entitlement.points,
    'version': 1,
  };
  factory CreationDraft.fromJson(Map<String, dynamic> j) => CreationDraft(
    j['id'],
    j['seed'],
    (j['candidates'] as List)
        .map((c) => CharacterAttributes.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
    RebirthEntitlement(
      source: j['source'],
      score: j['score'],
      points: j['points'],
    ),
  );
}

class CombatFeedback {
  const CombatFeedback({
    required this.actionId,
    required this.kind,
    required this.damage,
    required this.received,
    required this.healing,
    required this.absorbed,
  });
  final String actionId, kind;
  final int damage, received, healing, absorbed;
}
