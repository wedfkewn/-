/// Versioned rules. Costs are game days, never wall-clock time.
abstract final class Content {
  static const version = 1;
  static int awareness(int realm, int spirit, bool hasTianji) =>
      10 + realm * 20 + (spirit ~/ 10).clamp(0, 40) + (hasTianji ? 20 : 0);
  static const questDescriptions = {
    '古碑': ['调查碑文，寻找遗失线索', '花费10灵石拓印，或放下此缘', '解读拓片，获得天机诀'],
    '宗门委托': ['交付2株灵草', '交付1枚回春丹', '领取70灵石与30修为'],
  };
  static const realms = ['炼气', '筑基', '金丹', '元婴', '化神', '炼虚', '合体', '大乘', '渡劫'];
  static const lifespans = [
    120,
    240,
    500,
    1000,
    2000,
    4000,
    8000,
    12000,
    20000,
  ];
  static const places = ['青溪镇', '黑风谷', '苍玄山', '丹霞坊', '北荒'];
  static const sects = ['苍玄宗', '天剑宗', '血河宗'];
  static const families = ['沈家', '顾家', '林家', '韩家'];
  static const techniques = {'长春诀': 3, '天机诀': 5, '御剑诀': 7};
  static const recipes = {'回春丹': 2, '聚灵丹': 3};
  static const prices = {
    '灵草': 4,
    '回春丹': 12,
    '聚灵丹': 18,
    '青锋剑': 40,
    '玄铁甲': 35,
    '天机诀': 55,
    '御剑诀': 65,
  };
  static const durations = {
    'cultivate': 30,
    'breakthrough': 7,
    'explore': 3,
    'travel': 5,
    'rescue': 2,
    'befriend': 1,
    'apprentice': 7,
    'joinSect': 7,
    'trade': 1,
    'craft': 3,
    'learn': 7,
    'equip': 1,
    'useItem': 1,
    'quest': 5,
    'divine': 7,
    'investigate': 7,
    'startBattle': 1,
    'attack': 1,
    'skill': 1,
    'flee': 1,
    'promise': 1,
    'borrow': 1,
    'repay': 1,
    'companion': 7,
    'wait': 30,
  };
  static String date(int day) =>
      '玄元历 ${day ~/ 360 + 1} 年 ${day % 360 ~/ 30 + 1} 月 ${day % 30 + 1} 日';
}
