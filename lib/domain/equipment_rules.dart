part of 'engine.dart';

abstract final class BirthRules {
  static List<CharacterAttributes> candidates(String seed) {
    final rng = SeedRandom(SeedRandom.hash('$seed:birth:v1'));
    final result = <CharacterAttributes>[];
    final seen = <String>{};
    while (result.length < 3) {
      final v = [2 + rng.next(7), 2 + rng.next(7), 2 + rng.next(7)];
      final last = 20 - v.fold<int>(0, (a, b) => a + b);
      if (last < 2 || last > 8 || !seen.add('${v.join(',')},$last')) continue;
      result.add(CharacterAttributes(v[0], v[1], v[2], last));
    }
    return result;
  }

  static CharacterAttributes allocate(
    CreationDraft draft,
    int index,
    List<int> points,
  ) {
    if (index < 0 ||
        index >= 3 ||
        points.length != 4 ||
        points.any((p) => p < 0) ||
        points.fold<int>(0, (a, b) => a + b) != draft.entitlement.points) {
      throw const RuleViolation('属性点分配无效');
    }
    final v = List.generate(
      4,
      (i) => draft.candidates[index].values[i] + points[i],
    );
    if (v.any((p) => p > 12)) throw const RuleViolation('单项资质不能超过12');
    return CharacterAttributes(v[0], v[1], v[2], v[3]);
  }
}

class EquipmentStats {
  const EquipmentStats(this.attack, this.defense, this.qi);
  final int attack, defense, qi;
}

abstract final class EquipmentRules {
  static EquipmentStats stats(World w, {Equipment? replacement}) {
    final slots = [w.equipment[w.weaponId], w.equipment[w.armorId]];
    if (replacement != null) {
      slots[replacement.slot == 'weapon' ? 0 : 1] = replacement;
    }
    var attack = 0, defense = 0, qi = 0;
    for (final e in slots.whereType<Equipment>()) {
      if (e.slot == 'weapon') {
        attack += e.baseValue;
      } else {
        defense += e.baseValue;
      }
      attack += e.effects['锋锐'] ?? 0;
      defense += e.effects['坚韧'] ?? 0;
      qi += e.effects['养气'] ?? 0;
    }
    return EquipmentStats(attack, defense, qi);
  }

  static int maxQi(World w) =>
      (10 +
              w.player.realm * 2 +
              w.player.attributes.awareness -
              5 +
              stats(w).qi)
          .clamp(1, 1000);
  static int price(String name, int realm) =>
      Content.prices[name]! * (realm + 1) * (realm + 1);
  static int sale(Equipment e) =>
      price(e.name, e.realm) * Equipment.multipliers[e.quality] ~/ 100 ~/ 2;
  static Equipment generate(World w, String name, bool reward) {
    final rng = w.equipmentRandom;
    var quality = 0;
    if (reward) {
      final roll = rng.next(100);
      quality = roll < 70
          ? 1
          : roll < 95
          ? 2
          : 3;
    }
    final realm = w.player.realm;
    final weapon = name == '青锋剑';
    var base =
        ((weapon ? 12 + realm * 8 : 9 + realm * 4) *
        Equipment.multipliers[quality] ~/
        100);
    if (reward) base = base * (90 + rng.next(21)) ~/ 100;
    final pool = ['锋锐', '坚韧', '养气'];
    final bonuses = <String, int>{};
    for (var i = 0; i < quality; i++) {
      final key = pool.removeAt(rng.next(pool.length));
      bonuses[key] = 2 + realm + rng.next(3 + realm);
    }
    return Equipment(
      w.nextId('equipment'),
      name,
      weapon ? 'weapon' : 'armor',
      realm: realm,
      quality: quality,
      base: base.clamp(1, 10000),
      bonuses: bonuses,
      version: 1,
    );
  }
}
