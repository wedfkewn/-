import 'illustrations.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../application/game_controller.dart';
import 'ink_theme.dart';

class BattleStage extends StatefulWidget {
  const BattleStage({
    super.key,
    required this.view,
    required this.busy,
    required this.onCommand,
  });
  final GameView view;
  final bool busy;
  final ValueChanged<String> onCommand;
  @override
  State<BattleStage> createState() => _BattleStageState();
}

class _BattleStageState extends State<BattleStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  String? last;
  @override
  void initState() {
    super.initState();
    last = widget.view.combatFeedback?.actionId;
    animation.addStatusListener((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant BattleStage old) {
    super.didUpdateWidget(old);
    final f = widget.view.combatFeedback;
    if (widget.view.readOnly) {
      animation.stop();
      return;
    }
    if (f != null && f.actionId != last) {
      last = f.actionId;
      if (!MediaQuery.disableAnimationsOf(context)) animation.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && animation.isAnimating) {
      animation.stop();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.view, f = v.combatFeedback;
    if (v.battleName == null && f == null) return const SizedBox.shrink();
    final disabled = widget.busy || v.readOnly || animation.isAnimating;
    final color = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          v.battleName ?? '交锋已定',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = animation.value;
            final shake = animation.isAnimating
                ? math.sin(t * math.pi * 10) * (1 - t) * 4
                : 0.0;
            Widget seal(String text, int hp, bool enemy) => Transform.translate(
              offset: Offset(
                (enemy ? (f?.damage ?? 0) > 0 : (f?.received ?? 0) > 0)
                    ? (enemy ? shake : -shake)
                    : 0,
                0,
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: enemy ? color : InkTheme.cinnabar,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontFamily: 'MaShan',
                        fontSize: 26,
                      ),
                    ),
                  ),
                  Text(enemy && v.inTribulation ? '雷劫' : '气血 $hp'),
                  SizedBox(
                    width: 72,
                    child: LinearProgressIndicator(
                      value: (hp / (enemy ? v.battleMaxHp : v.maxHp)).clamp(
                        0.0,
                        1.0,
                      ),
                      color: enemy ? color : InkTheme.cinnabar,
                    ),
                  ),
                ],
              ),
            );
            return SizedBox(
              height: 150,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InkIllustration(
                      art: IllustrationResolver.current(v.map),
                      height: 150,
                      opacity: .22,
                    ),
                  ),
                  Row(
                    children: [
                      seal('你', v.hp, false),
                      Expanded(
                        child: SizedBox(
                          height: 70,
                          child: CustomPaint(
                            painter: _CombatInk(
                              t,
                              animation.isAnimating,
                              (f?.kind ?? '').replaceFirst('雷劫:', ''),
                              color,
                              v.inTribulation ||
                                  (f?.kind.startsWith('雷劫:') ?? false),
                            ),
                          ),
                        ),
                      ),
                      seal(
                        v.inTribulation ? '劫' : '敌',
                        v.battleHp.clamp(0, 999999),
                        true,
                      ),
                    ],
                  ),
                  if (f != null && animation.isAnimating)
                    Positioned(
                      top: 30,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: 1 - t,
                        child: Transform.translate(
                          offset: Offset(0, -30 * t),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                f.healing > 0
                                    ? '+${f.healing}'
                                    : '-${f.received}',
                                style: TextStyle(
                                  color: f.healing > 0
                                      ? Colors.green
                                      : InkTheme.cinnabar,
                                ),
                              ),
                              Text(
                                '-${f.damage}',
                                style: const TextStyle(
                                  color: InkTheme.cinnabar,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (f != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Text(
                        '造成 ${f.damage} · 受伤 ${f.received} · 恢复 ${f.healing}${f.absorbed > 0 ? ' · 护盾 ${f.absorbed}' : ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: f.healing > 0
                              ? Colors.green
                              : InkTheme.cinnabar,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Text('战斗灵力 ${v.battleQi}/${v.maxQi}\n${v.omen}'),
        if (v.battleName != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InkAction(
                label: '出手攻击',
                onPressed: disabled ? null : () => widget.onCommand('attack'),
              ),
              TextButton(
                onPressed: disabled ? null : () => widget.onCommand('skill'),
                child: Text('${v.style} · ${v.style == '御剑诀' ? 4 : 3}灵力'),
              ),
              TextButton(
                onPressed: disabled ? null : () => widget.onCommand('defend'),
                child: const Text('守御调息'),
              ),
              TextButton(
                onPressed: disabled ? null : () => widget.onCommand('useItem'),
                child: const Text('服回春丹'),
              ),
              TextButton(
                onPressed: disabled || v.inTribulation
                    ? null
                    : () => widget.onCommand('flee'),
                child: Text(v.inTribulation ? '雷劫不可逃离' : '尝试脱身'),
              ),
            ],
          ),
      ],
    );
  }
}

class _CombatInk extends CustomPainter {
  _CombatInk(this.t, this.active, this.kind, this.color, this.lightning);
  final double t;
  final bool active, lightning;
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final p = Paint()
      ..color =
          (kind == '长春诀' || kind == 'useItem'
                  ? Colors.green
                  : kind == '天机诀'
                  ? InkTheme.cinnabar
                  : color)
              .withValues(alpha: 1 - t)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    if (lightning) {
      final path = Path()
        ..moveTo(size.width * .7, 0)
        ..lineTo(size.width * .45, size.height * .4)
        ..lineTo(size.width * .6, size.height * .45)
        ..lineTo(size.width * .3, size.height);
      canvas.drawPath(
        path,
        p..color = InkTheme.cinnabar.withValues(alpha: 1 - t),
      );
    }
    if (['defend', '长春诀', 'useItem', '天机诀'].contains(kind)) {
      canvas.drawCircle(center, 10 + 24 * t, p);
      canvas.drawCircle(center, 5 + 16 * t, p..strokeWidth = 1);
    } else {
      for (var i = 0; i < (kind == '御剑诀' ? 3 : 1); i++) {
        final y = size.height / 2 + (i - 1) * 10;
        canvas.drawLine(
          Offset(size.width * .1, y + 18),
          Offset(size.width * (.1 + .8 * t), y - 18),
          p..strokeWidth = 3 - i * .7,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CombatInk old) =>
      old.t != t ||
      old.active != active ||
      old.kind != kind ||
      old.color != color ||
      old.lightning != lightning;
}
