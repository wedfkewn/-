import 'dart:async';
import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/game_database.dart';
import '../domain/content.dart';
import '../domain/engine.dart';
import '../domain/karma_repository.dart';
import '../domain/models.dart';

final databaseProvider = Provider<GameDatabase>(
  (ref) => throw UnimplementedError('数据库未初始化'),
);
final gameProvider = AsyncNotifierProvider<GameController, GameView>(
  GameController.new,
);

class GameView {
  const GameView({
    this.exists = false,
    this.readOnly = false,
    this.name = '',
    this.date = '',
    this.seed = '',
    this.realm = '',
    this.location = '',
    this.age = 0,
    this.day = 0,
    this.lifespan = 0,
    this.hp = 0,
    this.maxHp = 100,
    this.spirit = 0,
    this.awareness = 10,
    this.coins = 0,
    this.realmIndex = 0,
    this.revision = 0,
    this.inventory = const {},
    this.techniques = const [],
    this.quests = const {},
    this.nearby = const [],
    this.places = const [],
    this.sects = const [],
    this.assessment,
    this.playerId = '',
    this.weapon,
    this.armor,
    this.battleName,
    this.battleHp = 0,
    this.archives = const [],
  });
  final bool exists, readOnly;
  final String name, date, seed, realm, location, playerId;
  final int age,
      day,
      lifespan,
      hp,
      maxHp,
      spirit,
      awareness,
      coins,
      realmIndex,
      revision,
      battleHp;
  final String? weapon, armor, battleName;
  final Map<String, int> inventory, quests;
  final List<String> techniques;
  final List<KarmaNode> nearby, places, sects;
  final Map<String, Object?>? assessment;
  final List<LifeArchive> archives;
}

class LifeArchive {
  const LifeArchive(this.id, this.name, this.day, this.score);
  final String id, name;
  final int day, score;
}

class GameController extends AsyncNotifier<GameView> {
  World? _world;
  KarmaRepository? _repository;
  bool _busy = false;
  bool _viewingArchive = false;
  List<LifeArchive> _archives = [];
  KarmaRepository? get repository => _repository;
  @override
  Future<GameView> build() async {
    _world = await ref.read(databaseProvider).load();
    await _refreshArchives();
    return _project();
  }

  Future<void> _refreshArchives() async {
    final records = await ref.read(databaseProvider).archives();
    _archives = records
        .map(
          (j) => LifeArchive(
            j['id'],
            '第 ${records.length - records.indexOf(j)} 世',
            j['day'],
            (j['assessment']?['score'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  GameView _project() {
    final w = _world;
    if (w == null) {
      return GameView(archives: _archives);
    }
    _repository = KarmaRepository(w);
    final p = w.player;
    final nearby = w.entities.values
        .where(
          (n) =>
              n.type == KarmaNodeType.npc &&
              n.alive &&
              n.location == p.location,
        )
        .map((n) => _repository!.node(n.id))
        .whereType<KarmaNode>()
        .toList();
    return GameView(
      exists: true,
      readOnly: w.frozen || _viewingArchive,
      name: p.name,
      date: Content.date(w.day),
      seed: w.seed,
      realm: Content.realms[p.realm],
      location: w.entities[p.location]!.name,
      age: p.ageDays ~/ 360,
      day: w.day,
      lifespan: Content.lifespans[p.realm],
      hp: p.hp,
      maxHp: GameCommandService.maxHp(p),
      spirit: p.spirit,
      awareness: Content.awareness(
        p.realm,
        p.spirit,
        w.techniques.contains('天机诀'),
      ),
      coins: p.coins,
      realmIndex: p.realm,
      revision: w.revision,
      inventory: Map.unmodifiable(w.inventory),
      techniques: List.unmodifiable(w.techniques),
      quests: Map.unmodifiable(w.quests),
      nearby: List.unmodifiable(nearby),
      places: _repository!.search('', type: KarmaNodeType.location),
      sects: _repository!.search('', type: KarmaNodeType.sect),
      assessment: w.assessment == null ? null : Map.unmodifiable(w.assessment!),
      playerId: p.id,
      weapon: w.weapon,
      armor: w.armor,
      battleName: w.battleTarget == null
          ? null
          : _repository!.node(w.battleTarget!)?.displayName,
      battleHp: w.battleHp,
      archives: List.unmodifiable(_archives),
    );
  }

  Future<void> create(String name, String seed) async {
    if (_busy) {
      throw const RuleViolation('正在保存，请稍候');
    }
    if (_world != null && !_world!.frozen && !_viewingArchive) {
      throw const RuleViolation('当前人生尚未结束');
    }
    if (name.trim().length > 20 || seed.length > 100) {
      throw const RuleViolation('名字最多20字，种子最多100字');
    }
    _busy = true;
    try {
      final current = await ref.read(databaseProvider).load();
      if (current != null && !current.frozen) {
        throw const RuleViolation('当前人生尚未结束，请返回继续修行');
      }
      final next = WorldGenerator.generate(
        seed: seed.trim().isEmpty
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : seed.trim(),
        name: name,
        worldId: 'life-${DateTime.now().microsecondsSinceEpoch}',
      );
      await ref.read(databaseProvider).save(next, makeActive: true);
      _world = next;
      _viewingArchive = false;
      state = AsyncData(_project());
    } finally {
      _busy = false;
    }
  }

  Future<void> command(GameCommand command) async {
    if (_busy) {
      throw const RuleViolation('正在保存，请稍候');
    }
    if (_world == null || _viewingArchive || _world!.frozen) {
      throw const RuleViolation('历史档案只读');
    }
    _busy = true;
    try {
      final current = _world!;
      final next = await Isolate.run(
        () => GameCommandService().execute(current, command),
      );
      await ref.read(databaseProvider).save(next, previous: _world);
      _world = next;
      if (next.frozen) {
        await _refreshArchives();
      }
      state = AsyncData(_project());
    } finally {
      _busy = false;
    }
  }

  Future<void> openArchive(String id) async {
    if (_busy) {
      throw const RuleViolation('正在保存，请稍候');
    }
    _busy = true;
    try {
      final archived = await ref.read(databaseProvider).load(id: id);
      if (archived == null || !archived.frozen) {
        throw const RuleViolation('档案不存在');
      }
      _world = archived;
      _viewingArchive = true;
      state = AsyncData(_project());
    } finally {
      _busy = false;
    }
  }

  Future<void> returnToCurrent() async {
    if (_busy) {
      throw const RuleViolation('正在保存，请稍候');
    }
    _busy = true;
    try {
      _world = await ref.read(databaseProvider).load();
      _viewingArchive = false;
      state = AsyncData(_project());
    } finally {
      _busy = false;
    }
  }
}
