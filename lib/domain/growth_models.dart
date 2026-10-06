class Tribulation {
  Tribulation(
    this.origin,
    this.rounds,
    this.shield, {
    this.turn = 0,
    this.guard,
  });
  final String origin;
  final int rounds;
  int turn, shield;
  final String? guard;
  Map<String, Object?> toJson() => {
    'origin': origin,
    'rounds': rounds,
    'shield': shield,
    'turn': turn,
    'guard': guard,
  };
  factory Tribulation.fromJson(Map<String, dynamic> j) => Tribulation(
    j['origin'],
    j['rounds'],
    j['shield'],
    turn: j['turn'],
    guard: j['guard'],
  );
}

class SecretRun {
  SecretRun(this.place, this.origin, {this.stage = 0});
  final String place, origin;
  int stage;
  Map<String, Object?> toJson() => {
    'place': place,
    'origin': origin,
    'stage': stage,
  };
  factory SecretRun.fromJson(Map<String, dynamic> j) =>
      SecretRun(j['place'], j['origin'], stage: j['stage']);
}

class GrowthView {
  const GrowthView({
    this.stage = 0,
    this.foundation = 30,
    this.insight = 0,
    this.threshold = 80,
    this.rootRequired = 20,
    this.insightRequired = 0,
    this.material = '',
    this.trialRounds = 0,
    this.shield = 0,
    this.injured = false,
    this.highTrial = false,
    this.terminal = false,
    this.missing = const [],
    this.guards = const [],
    this.sourceCount = 0,
  });
  final int stage,
      foundation,
      insight,
      threshold,
      rootRequired,
      insightRequired,
      trialRounds,
      shield,
      sourceCount;
  final String material;
  final bool injured, highTrial, terminal;
  final List<String> missing, guards;
}
