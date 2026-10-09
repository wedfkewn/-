import 'dart:async';
import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/game_database.dart';
import '../domain/content.dart';
import '../domain/engine.dart';
import '../domain/karma_repository.dart';
import '../domain/models.dart';
import '../domain/map_repository.dart';
import 'ai_service.dart';

final databaseProvider = Provider<GameDatabase>(
  (ref) => throw UnimplementedError('数据库未初始化'),
);
final aiServiceProvider = Provider<AiContentService>(
  (ref) => AiContentService(
    ref.read(databaseProvider),
    ref.read(aiClientProvider),
    ref.read(secretStoreProvider),
  ),
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
    this.battleMaxHp = 100,
    this.encounter,
    this.equipment = const [],
    this.dialogue = const [],
    this.battleQi = 0,
    this.omen = '',
    this.style = '长春诀',
    this.weaponId,
    this.armorId,
    this.aiNotice = '',
    this.archives = const [],
    this.map = const MapView(),
    this.growth = const GrowthView(),
    this.inTribulation = false,
    this.secretStage,
    this.attributes = const CharacterAttributes(),
    this.rebirth = const RebirthEntitlement(),
    this.equipmentAttack = 0,
    this.equipmentDefense = 0,
    this.maxQi = 10,
    this.combatFeedback,
    this.commission = const CommissionBoardView(),
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
      battleHp,
      battleMaxHp;
  final String? weapon, armor, battleName;
  final Map<String, int> inventory, quests;
  final List<String> techniques;
  final List<KarmaNode> nearby, places, sects;
  final Map<String, Object?>? assessment;
  final Encounter? encounter;
  final List<Equipment> equipment;
  final List<DialogueTurn> dialogue;
  final int battleQi;
  final String omen, style, aiNotice;
  final String? weaponId, armorId;
  final List<LifeArchive> archives;
  final MapView map;
  final GrowthView growth;
  final bool inTribulation;
  final int? secretStage;
  final CharacterAttributes attributes;
  final RebirthEntitlement rebirth;
  final int equipmentAttack, equipmentDefense, maxQi;
  final CombatFeedback? combatFeedback;
  final CommissionBoardView commission;
}

class LifeArchive {
  const LifeArchive(
    this.id,
    this.name,
    this.day,
    this.score, {
    this.realm = '',
    this.age = 0,
  });
  final String id, name;
  final int day, score;
  final String realm;
  final int age;
}

class GameController extends AsyncNotifier<GameView> {
  World? _world;
  KarmaRepository? _repository;
  bool _busy = false;
  String _aiNotice = '';
  void cancelAi() => ref.read(aiServiceProvider).cancel();
  bool _viewingArchive = false;
  bool _currentLifeEnded = true;
  List<LifeArchive> _archives = [];
  RebirthEntitlement _rebirth = const RebirthEntitlement();
  KarmaRepository? get repository => _repository;
  bool get canCreateLife => _currentLifeEnded;
  List<String> conversationTopics(String npc) {
    if (_world == null) return const [];
    try {
      return ref.read(aiServiceProvider).suggestedTopics(_world!, npc);
    } on RuleViolation {
      return const [];
    }
  }

  List<MapRoad>? previewRoute(String target) =>
      _world == null ? null : MapRepository(_world!).route(target);
  GrowthView previewGrowth({String? guard, bool pill = false}) => _world == null
      ? const GrowthView()
      : GrowthRules.view(_world!, guard: guard, pill: pill);
  @override
  Future<GameView> build() async {
    final service = ref.read(aiServiceProvider);
    ref.onDispose(service.cancel);
    _world = await ref.read(databaseProvider).load();
    _currentLifeEnded = _world?.frozen != false;
    if (_world != null && !_world!.frozen && _world!.mapVersion == 0) {
      final next = _world!.copy();
      MapRules.generate(next);
      for (final n
          in next.entities.values
              .where((e) => e.type == KarmaNodeType.npc)
              .toList()) {
        MapRules.revealNearby(next, n.id, InformationChannel.witness);
      }
      next.rulesVersion = Content.version;
      next.revision++;
      await ref.read(databaseProvider).save(next, previous: _world);
      _world = next;
    }
    if (_world?.pendingAi != null && !_world!.frozen) {
      final pending = _world!.pendingAi!;
      final next = GameCommandService().execute(
        _world!,
        GameCommand(
          pending['kind'],
          target: pending['target'],
          item: pending['item'],
          amount: pending['amount'] ?? 1,
          secret: pending['secret'] ?? false,
          actionId: pending['id'],
        ),
      );
      next.pendingAi = null;
      _aiNotice = '上次生成已中断，使用本地内容恢复行动。';
      await ref.read(databaseProvider).save(next, previous: _world);
      _world = next;
    }
    await _refreshArchives();
    _currentLifeEnded = _world?.frozen != false;
    return _project();
  }

  Future<void> _refreshArchives() async {
    final records = await ref.read(databaseProvider).archives();
    _rebirth = await ref.read(databaseProvider).rebirth();
    _archives = records
        .map(
          (j) => LifeArchive(
            j['id'],
            j['player']?['name'] as String? ??
                '第 ${records.length - records.indexOf(j)} 世',
            j['day'],
            (j['assessment']?['score'] as int?) ?? 0,
            realm:
                '${Content.realms[(j['player']?['realm'] as int?) ?? 0]}${j['mapVersion'] == 0 ? '' : Content.stages[(j['player']?['stage'] as int?) ?? 0]}',
            age: ((j['player']?['ageDays'] as int?) ?? 0) ~/ 360,
          ),
        )
        .toList();
  }

  GameView _project() {
    final w = _world;
    if (w == null) {
      return GameView(archives: _archives, rebirth: _rebirth);
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
      realm: w.frozen && w.mapVersion == 0
          ? Content.realms[p.realm]
          : '${Content.realms[p.realm]}${Content.stages[p.stage]}',
      location: w.entities[p.location]!.name,
      attributes: p.attributes,
      rebirth: _rebirth,
      equipmentAttack: EquipmentRules.stats(w).attack,
      equipmentDefense: EquipmentRules.stats(w).defense,
      maxQi: EquipmentRules.maxQi(w),
      combatFeedback: w.feedback,
      commission: CommissionRules.view(w),
      age: p.ageDays ~/ 360,
      day: w.day,
      lifespan: Content.lifespans[p.realm],
      hp: p.hp,
      maxHp: GameCommandService.maxHp(p),
      spirit: p.spirit,
      awareness: p.attributes.scale(
        Content.awareness(p.realm, p.spirit, w.techniques.contains('天机诀')),
        p.attributes.awareness,
        4,
      ),
      coins: p.coins,
      realmIndex: p.realm,
      map: MapRepository(w).query(),
      growth: GrowthRules.view(w),
      inTribulation: w.tribulation != null,
      secretStage: w.secretRun?.stage,
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
      battleName: w.tribulation != null
          ? '天劫 · 第${w.tribulation!.turn + 1}道'
          : w.battleTarget == null
          ? null
          : _repository!.node(w.battleTarget!)?.displayName,
      battleHp: w.battleHp,
      battleMaxHp: w.battleTarget == null
          ? 100
          : GameCommandService.maxHp(w.entities[w.battleTarget]!),
      encounter: w.encounter,
      equipment: List.unmodifiable(w.equipment.values),
      dialogue: List.unmodifiable(w.dialogue),
      battleQi: w.battleQi,
      omen: w.tribulation == null
          ? AdventureRules.omen(w)
          : GrowthRules.omen(w),
      style: w.style,
      weaponId: w.weaponId,
      armorId: w.armorId,
      aiNotice: _aiNotice,
      archives: List.unmodifiable(_archives),
    );
  }

  Future<void> create(
    String name,
    String seed, {
    int regionCount = 12,
    int placesPerRegion = 24,
    int npcCount = 1200,
    CreationDraft? draft,
    int candidate = 0,
    List<int> allocation = const [0, 0, 0, 0],
  }) async {
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
      final chosenDraft =
          draft ?? await ref.read(databaseProvider).creationDraft(seed: seed);
      BirthRules.allocate(chosenDraft, candidate, allocation);
      final next = WorldGenerator.generate(
        seed: chosenDraft.seed,
        name: name,
        regionCount: regionCount,
        placesPerRegion: placesPerRegion,
        npcCount: npcCount,
        worldId: 'life-${DateTime.now().microsecondsSinceEpoch}',
      );
      await ref
          .read(databaseProvider)
          .createLife(next, chosenDraft, candidate, allocation);
      await _refreshArchives();
      _world = next;
      _viewingArchive = false;
      _currentLifeEnded = false;
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
      if (_world!.pendingAi != null) {
        final pending = _world!.pendingAi!;
        final recovered = GameCommandService().execute(
          _world!,
          GameCommand(
            pending['kind'],
            target: pending['target'],
            item: pending['item'],
            amount: pending['amount'] ?? 1,
            secret: pending['secret'] ?? false,
            actionId: pending['id'],
          ),
        );
        recovered.pendingAi = null;
        await ref.read(databaseProvider).save(recovered, previous: _world);
        _world = recovered;
        _currentLifeEnded = recovered.frozen;
        if (recovered.frozen) await _refreshArchives();
        state = AsyncData(_project());
        throw const RuleViolation('上次行动已用本地内容恢复，请检查结果后继续');
      }
      final original = _world!;
      final fallback = await Isolate.run(
        () => GameCommandService().execute(original, command),
      );
      // Validate before any charged request, including invalid command/target/input.
      if (command.kind == 'talk') {
        if (command.item == null ||
            command.item!.trim().isEmpty ||
            command.item!.runes.length > 300) {
          throw const RuleViolation('请输入1至300字');
        }
        ref
            .read(aiServiceProvider)
            .context(
              original,
              'talk',
              target: command.target,
              input: command.item,
            );
      }
      if (original.encounter != null && command.kind != 'chooseEncounter') {
        throw const RuleViolation('请先处理待定奇遇');
      }
      if (original.battleTarget != null &&
          ![
            'attack',
            'skill',
            'defend',
            'useItem',
            'flee',
          ].contains(command.kind)) {
        throw const RuleViolation('请先完成战斗');
      }
      final service = ref.read(aiServiceProvider);
      service.beginAction();
      final settings = await service.settings();
      final enabled = settings.enabled && settings.consent;
      final kind = command.kind;
      var current = original;
      final actionId = '${current.id}:command:${current.revision}';
      _aiNotice = '';
      if (enabled && (kind == 'explore' || kind == 'talk' || settings.world)) {
        current = original.copy();
        current.pendingAi = {
          'id': actionId,
          'kind': kind,
          'target': command.target,
          'item': command.item,
          'amount': command.amount,
          'secret': command.secret,
        };
        await ref.read(databaseProvider).save(current, previous: original);
        _world = current;
      }
      Map<String, dynamic>? generated;
      if (enabled && (kind == 'explore' || kind == 'talk')) {
        ref
            .read(aiRequestProvider.notifier)
            .update(kind == 'explore' ? '推演奇遇…' : '倾听人物…');
        try {
          generated = await service.generate(
            current,
            kind,
            settings,
            target: command.target,
            input: command.item,
          );
        } on AiFailure catch (e) {
          _aiNotice = '${e.message}，使用本地内容。';
        }
      }
      if (_world?.id != current.id ||
          _world?.revision != current.revision ||
          _viewingArchive) {
        throw const RuleViolation('生成对应的世界已失效');
      }
      final submitted = GameCommand(
        kind,
        target: command.target,
        item: command.item,
        amount: command.amount,
        secret: command.secret,
        proposal: generated?['proposal'],
        generation: generated == null
            ? null
            : {
                ...generated,
                'worldId': current.id,
                'revision': current.revision,
                'actionId': actionId,
              },
        actionId: actionId,
      );
      final next = generated == null
          ? fallback
          : await Isolate.run(
              () => GameCommandService().execute(current, submitted),
            );
      next.completedActions.add(actionId);
      next.pendingAi = null;
      if (enabled &&
          settings.world &&
          service.foreground &&
          !service.cancelled &&
          !next.frozen &&
          next.encounter == null &&
          next.battleTarget == null &&
          next.tribulation == null &&
          next.secretRun == null &&
          next.day ~/ 30 > original.day ~/ 30 &&
          next.day ~/ 30 > next.aiWorldDay ~/ 30) {
        next.aiWorldDay = next.day;
        if (AdventureRules.worldCatalog(next).isNotEmpty) {
          ref.read(aiRequestProvider.notifier).update('推演世事…');
          try {
            final worldResult = await service.generate(next, 'world', settings);
            AiProposalValidator.validate(
              next,
              'world',
              worldResult['proposal'],
            );
            AdventureRules.worldProposal(next, worldResult['proposal']);
            next.generations.add({
              ...worldResult,
              'worldId': next.id,
              'revision': next.revision,
              'actionId': '$actionId:world',
            });
          } on AiFailure catch (e) {
            _aiNotice = '${e.message}，世事依本地规则运行。';
          }
        }
      }
      await ref.read(databaseProvider).save(next, previous: current);
      _world = next;
      _currentLifeEnded = next.frozen;
      if (next.frozen) {
        await _refreshArchives();
      }
      state = AsyncData(_project());
    } finally {
      ref.read(aiRequestProvider.notifier).update(null);
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
      _currentLifeEnded = _world?.frozen != false;
      state = AsyncData(_project());
    } finally {
      _busy = false;
    }
  }
}
