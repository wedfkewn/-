import 'dart:convert';
import 'adventure_models.dart';
import 'map_models.dart';
import 'growth_models.dart';
export 'adventure_models.dart';
export 'map_models.dart';
export 'growth_models.dart';

enum KarmaNodeType {
  player,
  npc,
  sect,
  family,
  location,
  worldEvent,
  historicalEvent,
}

enum KarmaRelationType {
  gratitude,
  hatred,
  friendship,
  kinship,
  masterDisciple,
  daoCompanion,
  sectAffiliation,
  debt,
  rivalry,
  promise,
  karmicEntanglement,
  eventParticipation,
}

enum RelationStatus { active, settled, historical, inherited }

enum InformationChannel {
  witness,
  investigation,
  rumor,
  divination,
  sectIntelligence,
  told,
}

enum CausalKind { direct, influence }

const relationLabels = [
  '救命之恩',
  '仇怨',
  '友谊',
  '血缘',
  '师徒',
  '道侣',
  '宗门',
  '债务',
  '竞争',
  '承诺',
  '因果纠缠',
  '事件参与',
];
const statusLabels = ['未了结', '已了结', '历史', '已传承'];
String relationLabel(KarmaRelationType type) => relationLabels[type.index];
String statusLabel(RelationStatus status) => statusLabels[status.index];

class Entity {
  Entity({
    required this.id,
    required this.type,
    required this.name,
    this.importance = 1,
    this.created = 0,
    this.updated = 0,
    this.alive = true,
    this.realm = 0,
    this.ageDays = 18 * 360,
    this.location = '',
    this.sect,
    this.family,
    this.personality = '谨慎',
    this.spirit = 0,
    this.coins = 30,
    this.hp = 100,
    this.lastActed = 0,
  });
  final String id;
  final KarmaNodeType type;
  final String name;
  final int importance;
  final int created;
  int updated, realm, ageDays, spirit, coins, hp, lastActed;
  bool alive;
  String location, personality;
  String? sect, family;
  int stage = 0,
      foundation = 30,
      insight = 0,
      injuryDay = -1,
      stabilizedDay = -1;
  final Map<String, String> growthSources = {};
  final Map<String, int> supplies = {};
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'importance': importance,
    'created': created,
    'updated': updated,
    'alive': alive,
    'realm': realm,
    'ageDays': ageDays,
    'location': location,
    'sect': sect,
    'family': family,
    'personality': personality,
    'spirit': spirit,
    'coins': coins,
    'hp': hp,
    'lastActed': lastActed,
    'stage': stage,
    'foundation': foundation,
    'insight': insight,
    'injuryDay': injuryDay,
    'stabilizedDay': stabilizedDay,
    'growthSources': growthSources,
    'supplies': supplies,
  };
  factory Entity.fromJson(Map<String, dynamic> j) =>
      Entity(
          id: j['id'],
          type: KarmaNodeType.values.byName(j['type']),
          name: j['name'],
          importance: j['importance'],
          created: j['created'],
          updated: j['updated'],
          alive: j['alive'],
          realm: j['realm'],
          ageDays: j['ageDays'],
          location: j['location'],
          sect: j['sect'],
          family: j['family'],
          personality: j['personality'],
          spirit: j['spirit'],
          coins: j['coins'],
          hp: j['hp'],
          lastActed: j['lastActed'] ?? 0,
        )
        ..stage = j['stage'] ?? 0
        ..foundation = j['foundation'] ?? 30
        ..insight = j['insight'] ?? 0
        ..injuryDay = j['injuryDay'] ?? -1
        ..stabilizedDay = j['stabilizedDay'] ?? -1
        ..growthSources.addAll(
          Map<String, String>.from(j['growthSources'] ?? {}),
        )
        ..supplies.addAll(Map<String, int>.from(j['supplies'] ?? {}));
}

class Relation {
  Relation({
    required this.id,
    required this.source,
    required this.target,
    required this.type,
    this.strength = 20,
    RelationStatus status = RelationStatus.active,
    bool? resolved,
    this.bidirectional = false,
    this.created = 0,
    this.updated = 0,
    List<String>? events,
    this.inheritedFrom,
  }) : events = events ?? [],
       _status = status,
       resolved = resolved ?? status == RelationStatus.settled;
  final String id, source, target;
  final KarmaRelationType type;
  final bool bidirectional;
  final int created;
  final String? inheritedFrom;
  int strength, updated;
  RelationStatus _status;
  bool resolved;
  RelationStatus get status => _status;
  set status(RelationStatus value) {
    _status = value;
    if (value == RelationStatus.settled) {
      resolved = true;
    }
    if (value == RelationStatus.active) {
      resolved = false;
    }
  }

  final List<String> events;
  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'target': target,
    'type': type.name,
    'strength': strength,
    'status': status.name,
    'resolved': resolved,
    'bidirectional': bidirectional,
    'created': created,
    'updated': updated,
    'events': events,
    'inheritedFrom': inheritedFrom,
  };
  factory Relation.fromJson(Map<String, dynamic> j) => Relation(
    id: j['id'],
    source: j['source'],
    target: j['target'],
    type: KarmaRelationType.values.byName(j['type']),
    strength: j['strength'],
    status: RelationStatus.values.byName(j['status']),
    resolved: j['resolved'],
    bidirectional: j['bidirectional'],
    created: j['created'],
    updated: j['updated'],
    events: List<String>.from(j['events']),
    inheritedFrom: j['inheritedFrom'],
  );
}

class Cause {
  const Cause(this.eventId, this.kind);
  final String eventId;
  final CausalKind kind;
  Map<String, Object?> toJson() => {'eventId': eventId, 'kind': kind.name};
  factory Cause.fromJson(Map<String, dynamic> j) =>
      Cause(j['eventId'], CausalKind.values.byName(j['kind']));
}

class GameEvent {
  GameEvent({
    required this.id,
    required this.time,
    required this.kind,
    required this.title,
    required this.description,
    required this.location,
    required this.participants,
    this.importance = 1,
    this.causes = const [],
  });
  final String id, kind, title, description, location;
  final int time, importance;
  final List<String> participants;
  final List<Cause> causes;
  Map<String, Object?> toJson() => {
    'id': id,
    'time': time,
    'kind': kind,
    'title': title,
    'description': description,
    'location': location,
    'participants': participants,
    'importance': importance,
    'causes': causes.map((c) => c.toJson()).toList(),
  };
  factory GameEvent.fromJson(Map<String, dynamic> j) => GameEvent(
    id: j['id'],
    time: j['time'],
    kind: j['kind'],
    title: j['title'],
    description: j['description'],
    location: j['location'],
    participants: List<String>.from(j['participants']),
    importance: j['importance'],
    causes: (j['causes'] as List)
        .map((c) => Cause.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
  );
}

class Knowledge {
  const Knowledge(
    this.observer,
    this.subject,
    this.channel,
    this.time, {
    this.confirmed = true,
    this.depth = 0,
    this.source,
    this.snapshot = const {},
  });
  final String observer, subject;
  final InformationChannel channel;
  final int time, depth;
  final bool confirmed;
  final String? source;
  final Map<String, Object?> snapshot;
  String get key => '$observer|$subject';
  Map<String, Object?> toJson() => {
    'observer': observer,
    'subject': subject,
    'channel': channel.name,
    'time': time,
    'confirmed': confirmed,
    'depth': depth,
    'source': source,
    'snapshot': snapshot,
  };
  factory Knowledge.fromJson(Map<String, dynamic> j) => Knowledge(
    j['observer'],
    j['subject'],
    InformationChannel.values.byName(j['channel']),
    j['time'],
    confirmed: j['confirmed'],
    depth: j['depth'],
    source: j['source'],
    snapshot: Map<String, Object?>.from(j['snapshot'] ?? {}),
  );
}

/// Persisted PRNG: no dependence on platform Random or wall-clock.
class SeedRandom {
  SeedRandom(int state) : state = state == 0 ? 1 : state & 0x7fffffff;
  int state;
  int next(int bound) {
    state = (state * 48271) % 2147483647;
    return state % bound;
  }

  static int hash(String text) {
    var result = 17;
    for (final code in text.codeUnits) {
      result = (result * 31 + code) % 2147483647;
    }
    return result == 0 ? 1 : result;
  }
}

class World {
  World({
    required this.id,
    required this.seed,
    required this.playerId,
    required this.random,
    this.generationVersion = 1,
    this.npcCount = 120,
  });
  final String id, seed, playerId;
  final int generationVersion, npcCount;
  final SeedRandom random;
  int day = 0, sequence = 0, revision = 0, simulationCursor = 0;
  bool frozen = false;
  final Map<String, Entity> entities = {};
  final Map<String, Relation> relations = {};
  final Map<String, GameEvent> events = {};
  final Map<String, Knowledge> knowledge = {};
  final Map<String, int> inventory = {'灵草': 6, '回春丹': 2};
  final Set<String> techniques = {'长春诀'};
  final Map<String, int> quests = {};
  int mapVersion = 0, regionCount = 12, placesPerRegion = 24;
  final Map<String, MapPlace> mapPlaces = {};
  final Map<String, MapRoad> mapRoads = {};
  Journey? journey;
  Tribulation? tribulation;
  SecretRun? secretRun;
  final Set<String> processedDeaths = {};
  String? weapon, armor, battleTarget, battleOrigin;
  int battleHp = 0;
  int rulesVersion = 3, battleQi = 10, battleRound = 0, aiWorldDay = 0;
  String style = '长春诀';
  String? weaponId, armorId, battleReward;
  Encounter? encounter;
  Map<String, dynamic>? pendingAi;
  final Map<String, Equipment> equipment = {};
  final List<DialogueTurn> dialogue = [];
  final List<Map<String, dynamic>> generations = [];
  final Set<String> completedActions = {};
  SeedRandom? _adventureRandom;
  SeedRandom get adventureRandom =>
      _adventureRandom ??= SeedRandom(SeedRandom.hash('$seed:adventure'));

  Map<String, Object?>? assessment;
  Entity get player => entities[playerId]!;
  String nextId(String kind) => '$id:$kind:${sequence++}';
  bool knows(String observer, String subject) =>
      knowledge['$observer|$subject']?.confirmed == true;
  void discover(
    String observer,
    String subject,
    InformationChannel channel, {
    bool confirmed = true,
    int depth = 0,
    String? source,
    bool geography = false,
  }) {
    final previous = knowledge['$observer|$subject'];
    final entity = entities[subject];
    final relation = relations[subject];
    final entry = Knowledge(
      observer,
      subject,
      channel,
      day,
      confirmed: confirmed,
      depth: depth > (previous?.depth ?? 0) ? depth : (previous?.depth ?? 0),
      source: source,
      snapshot: entity != null
          ? {
              'alive': entity.alive,
              'realm': entity.realm,
              'stage': entity.stage,
              'updated': entity.updated,
              'location': entity.location,
              if (mapPlaces.containsKey(subject)) ...{
                'geographySource': geography
                    ? source
                    : previous?.snapshot['geographySource'] ??
                          (previous == null ? source : null),
                'geographyTime': geography
                    ? day
                    : previous?.snapshot['geographyTime'] ??
                          previous?.time ??
                          day,
                'geographyChannel': geography
                    ? channel.name
                    : previous?.snapshot['geographyChannel'] ??
                          previous?.channel.name ??
                          channel.name,
              },
            }
          : relation != null
          ? {
              'strength': relation.strength,
              'status': relation.status.name,
              'resolved': relation.resolved,
              'updated': relation.updated,
            }
          : const {},
    );
    if (previous == null ||
        (!previous.confirmed && confirmed) ||
        confirmed && day >= previous.time) {
      knowledge[entry.key] = entry;
    }
  }

  Map<String, Object?> metadata() => {
    'id': id,
    'seed': seed,
    'playerId': playerId,
    'random': random.state,
    'generationVersion': generationVersion,
    'npcCount': npcCount,
    'day': day,
    'sequence': sequence,
    'revision': revision,
    'simulationCursor': simulationCursor,
    'frozen': frozen,
    'inventory': inventory,
    'techniques': techniques.toList(),
    'quests': quests,
    'mapVersion': mapVersion,
    'regionCount': regionCount,
    'placesPerRegion': placesPerRegion,
    'mapPlaces': mapPlaces.values.map((p) => p.toJson()).toList(),
    'mapRoads': mapRoads.values.map((p) => p.toJson()).toList(),
    'journey': journey?.toJson(),
    'tribulation': tribulation?.toJson(),
    'secretRun': secretRun?.toJson(),
    'processedDeaths': processedDeaths.toList(),
    'weapon': weapon,
    'armor': armor,
    'battleTarget': battleTarget,
    'battleOrigin': battleOrigin,
    'battleHp': battleHp,
    'assessment': assessment,
    'rulesVersion': rulesVersion,
    'battleQi': battleQi,
    'battleRound': battleRound,
    'aiWorldDay': aiWorldDay,
    'style': style,
    'weaponId': weaponId,
    'armorId': armorId,
    'battleReward': battleReward,
    'encounter': encounter?.toJson(),
    'equipment': equipment.values.map((e) => e.toJson()).toList(),
    'dialogue': dialogue.map((e) => e.toJson()).toList(),
    'generations': generations,
    'completedActions': completedActions.toList(),
    'adventureRandom': adventureRandom.state,
    'pendingAi': pendingAi,
  };
  Map<String, Object?> toJson() => {
    ...metadata(),
    'entities': entities.values.map((e) => e.toJson()).toList(),
    'relations': relations.values.map((e) => e.toJson()).toList(),
    'events': events.values.map((e) => e.toJson()).toList(),
    'knowledge': knowledge.values.map((e) => e.toJson()).toList(),
  };
  factory World.fromJson(Map<String, dynamic> j) {
    final w = World(
      id: j['id'],
      seed: j['seed'],
      playerId: j['playerId'],
      random: SeedRandom(j['random']),
      generationVersion: j['generationVersion'],
      npcCount: j['npcCount'],
    );
    w.day = j['day'];
    w.sequence = j['sequence'];
    w.revision = j['revision'];
    w.simulationCursor = j['simulationCursor'] ?? 0;
    w.frozen = j['frozen'];
    w.inventory
      ..clear()
      ..addAll(Map<String, int>.from(j['inventory']));
    w.techniques
      ..clear()
      ..addAll(List<String>.from(j['techniques']));
    w.quests.addAll(Map<String, int>.from(j['quests']));
    w.mapVersion = j['mapVersion'] ?? 0;
    if (j['tribulation'] != null) {
      w.tribulation = Tribulation.fromJson(
        Map<String, dynamic>.from(j['tribulation']),
      );
    }
    if (j['secretRun'] != null) {
      w.secretRun = SecretRun.fromJson(
        Map<String, dynamic>.from(j['secretRun']),
      );
    }
    w.regionCount = j['regionCount'] ?? 12;
    w.placesPerRegion = j['placesPerRegion'] ?? 24;
    for (final value in j['mapPlaces'] ?? []) {
      final p = MapPlace.fromJson(Map<String, dynamic>.from(value));
      w.mapPlaces[p.id] = p;
    }
    for (final value in j['mapRoads'] ?? []) {
      final p = MapRoad.fromJson(Map<String, dynamic>.from(value));
      w.mapRoads[p.id] = p;
    }
    if (j['journey'] != null) {
      w.journey = Journey.fromJson(Map<String, dynamic>.from(j['journey']));
    }
    w.processedDeaths.addAll(List<String>.from(j['processedDeaths'] ?? []));
    w.weapon = j['weapon'];
    w.armor = j['armor'];
    w.battleTarget = j['battleTarget'];
    w.battleOrigin = j['battleOrigin'];
    w.battleHp = j['battleHp'];
    w.rulesVersion = j['rulesVersion'] ?? 1;
    w.battleQi = j['battleQi'] ?? 10;
    w.battleRound = j['battleRound'] ?? 0;
    w.aiWorldDay = j['aiWorldDay'] ?? w.day;
    w.style = j['style'] ?? '长春诀';
    w.pendingAi = j['pendingAi'] == null
        ? null
        : Map<String, dynamic>.from(j['pendingAi']);
    w.weaponId = j['weaponId'];
    w.armorId = j['armorId'];
    w.battleReward = j['battleReward'];
    w._adventureRandom = SeedRandom(
      j['adventureRandom'] ?? SeedRandom.hash('${w.seed}:adventure'),
    );
    if (j['encounter'] != null) {
      w.encounter = Encounter.fromJson(
        Map<String, dynamic>.from(j['encounter']),
      );
    }
    for (final value in j['equipment'] ?? []) {
      final e = Equipment.fromJson(Map<String, dynamic>.from(value));
      w.equipment[e.id] = e;
    }
    for (final value in j['dialogue'] ?? []) {
      w.dialogue.add(DialogueTurn.fromJson(Map<String, dynamic>.from(value)));
    }
    for (final value in j['generations'] ?? []) {
      w.generations.add(Map<String, dynamic>.from(value));
    }
    w.completedActions.addAll(List<String>.from(j['completedActions'] ?? []));
    w.assessment = j['assessment'] == null
        ? null
        : Map<String, Object?>.from(j['assessment']);
    for (final value in j['entities'] ?? []) {
      final e = Entity.fromJson(Map<String, dynamic>.from(value));
      w.entities[e.id] = e;
    }
    for (final value in j['relations'] ?? []) {
      final e = Relation.fromJson(Map<String, dynamic>.from(value));
      w.relations[e.id] = e;
    }
    for (final value in j['events'] ?? []) {
      final e = GameEvent.fromJson(Map<String, dynamic>.from(value));
      w.events[e.id] = e;
    }
    for (final value in j['knowledge'] ?? []) {
      final e = Knowledge.fromJson(Map<String, dynamic>.from(value));
      w.knowledge[e.key] = e;
    }
    if (j['equipment'] == null) {
      for (final name in ['青锋剑', '玄铁甲']) {
        for (var i = 0; i < (w.inventory[name] ?? 0); i++) {
          final id = '${w.id}:legacy:$name:$i';
          w.equipment[id] = Equipment(
            id,
            name,
            name == '青锋剑' ? 'weapon' : 'armor',
          );
          if (i == 0 && w.weapon == name) w.weaponId = id;
          if (i == 0 && w.armor == name) w.armorId = id;
        }
        w.inventory.remove(name);
      }
    }
    return w;
  }
  World copy() => World.fromJson(jsonDecode(jsonEncode(toJson())));
}
