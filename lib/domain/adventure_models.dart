class Equipment {
  const Equipment(this.id, this.name, this.slot, {this.affix, this.value = 0});
  final String id, name, slot;
  final String? affix;
  final int value;
  String get description =>
      '${slot == 'weapon' ? '武器 · 攻击＋12' : '护甲 · 减伤＋9'}${affix == null ? '' : ' · $affix＋$value'}';
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'slot': slot,
    'affix': affix,
    'value': value,
  };
  factory Equipment.fromJson(Map<String, dynamic> j) => Equipment(
    j['id'],
    j['name'],
    j['slot'],
    affix: j['affix'],
    value: j['value'] ?? 0,
  );
}

class EncounterOption {
  const EncounterOption(
    this.id,
    this.label,
    this.effects, {
    this.target,
    this.cost = 0,
    this.pill = false,
  });
  final String id, label;
  final List<String> effects;
  final String? target;
  final int cost;
  final bool pill;
  bool get leaves => effects.isEmpty;
  String get risk => effects.contains('battle') ? '危险 · 可能永久死亡' : '安全';
  String get requirements =>
      '${leaves ? 0 : 1}日${cost > 0 ? ' · $cost灵石' : ''}${pill ? ' · 回春丹×1' : ''} · $risk';
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'effects': effects,
    'target': target,
    'cost': cost,
    'pill': pill,
  };
  factory EncounterOption.fromJson(Map<String, dynamic> j) => EncounterOption(
    j['id'],
    j['label'],
    List<String>.from(j['effects']),
    target: j['target'],
    cost: j['cost'] ?? 0,
    pill: j['pill'] ?? false,
  );
}

class Encounter {
  const Encounter(
    this.id,
    this.title,
    this.text,
    this.options,
    this.origin, {
    this.source = 'local',
  });
  final String id, title, text, origin, source;
  final List<EncounterOption> options;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'origin': origin,
    'source': source,
    'options': options.map((o) => o.toJson()).toList(),
  };
  factory Encounter.fromJson(Map<String, dynamic> j) => Encounter(
    j['id'],
    j['title'],
    j['text'],
    (j['options'] as List)
        .map((o) => EncounterOption.fromJson(Map<String, dynamic>.from(o)))
        .toList(),
    j['origin'],
    source: j['source'] ?? 'local',
  );
}

class DialogueTurn {
  const DialogueTurn(this.npc, this.input, this.reply, this.day);
  final String npc, input, reply;
  final int day;
  Map<String, Object?> toJson() => {
    'npc': npc,
    'input': input,
    'reply': reply,
    'day': day,
  };
  factory DialogueTurn.fromJson(Map<String, dynamic> j) =>
      DialogueTurn(j['npc'], j['input'], j['reply'], j['day']);
}
