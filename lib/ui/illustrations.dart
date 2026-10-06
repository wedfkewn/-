import 'package:flutter/material.dart';
import '../domain/karma_repository.dart';
import '../domain/models.dart';
import '../domain/map_repository.dart';

abstract final class IllustrationCatalog {
  static const keys = [
    'town_a',
    'town_b',
    'market_a',
    'market_b',
    'sect_a',
    'sect_b',
    'wild_a',
    'wild_b',
    'vein_a',
    'vein_b',
    'ruin_a',
    'ruin_b',
    'secret_a',
    'secret_b',
    'tribulation_a',
    'tribulation_b',
    'encounter_herbs',
    'encounter_treasure',
    'encounter_rescue',
    'encounter_tablet',
    'encounter_escort',
    'encounter_weapon',
    'encounter_ambush',
    'encounter_spring',
    'portrait_a',
    'portrait_b',
    'portrait_c',
    'portrait_d',
    'feature_birth',
    'feature_equipment',
    'feature_alchemy',
    'feature_archive',
  ];
  static String path(String key) =>
      'assets/illustrations/${keys.contains(key) ? key : 'wild_a'}.webp';
}

/// Only filtered presentation contracts enter this resolver. Never reads World.
abstract final class IllustrationResolver {
  static int variant(String id, int count) {
    var value = 17;
    for (final rune in id.runes) {
      value = (value * 31 + rune) % 2147483647;
    }
    return value % count;
  }

  static String place(KnownPlace? place) {
    if (place == null || !place.confirmed) return 'wild_a';
    return '${place.place.kind.name}_${variant(place.place.id, 2) == 0 ? 'a' : 'b'}';
  }

  static String current(MapView map) => place(
    map.places
        .where((p) => p.place.id == map.current && p.confirmed)
        .firstOrNull,
  );
  static String encounter(Encounter encounter, MapView map) {
    if (encounter.source != 'local') return current(map);
    final kind = encounter.options.where((o) => !o.leaves).firstOrNull?.id;
    final key = 'encounter_$kind';
    return IllustrationCatalog.keys.contains(key) ? key : current(map);
  }

  static String portrait(String knownId) =>
      'portrait_${['a', 'b', 'c', 'd'][variant(knownId, 4)]}';
  static String node(KarmaNode node) => switch (node.type) {
    KarmaNodeType.npc => portrait(node.entityId),
    KarmaNodeType.player => 'feature_birth',
    KarmaNodeType.sect => 'sect_${variant(node.entityId, 2) == 0 ? 'a' : 'b'}',
    KarmaNodeType.family =>
      'town_${variant(node.entityId, 2) == 0 ? 'a' : 'b'}',
    _ => 'wild_a',
  };
}

class InkIllustration extends StatelessWidget {
  const InkIllustration({
    super.key,
    required this.art,
    this.height,
    this.compact = false,
    this.opacity = 1,
  });
  final String art;
  final double? height;
  final bool compact;
  final double opacity;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final h =
            height ?? (width / 2).clamp(140.0, width >= 600 ? 220.0 : 180.0);
        final decode = compact
            ? 160
            : ((width * MediaQuery.devicePixelRatioOf(context) / 256).ceil() *
                      256)
                  .clamp(256, 1024);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final picture = Image.asset(
          IllustrationCatalog.path(art),
          height: h,
          width: width,
          fit: BoxFit.cover,
          cacheWidth: decode,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) =>
              SizedBox(height: h, width: width),
        );
        return SizedBox(
          height: h,
          child: Opacity(
            opacity: opacity,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const RadialGradient(
                radius: .82,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, .55, 1],
              ).createShader(bounds),
              child: dark
                  ? ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        -.55,
                        0,
                        0,
                        0,
                        176,
                        0,
                        -.55,
                        0,
                        0,
                        172,
                        0,
                        0,
                        -.55,
                        0,
                        159,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: picture,
                    )
                  : picture,
            ),
          ),
        );
      },
    ),
  );
}

class ExpandableNarrative extends StatefulWidget {
  const ExpandableNarrative(
    this.text, {
    super.key,
    this.lines = 4,
    this.label = '展开经过',
    this.style,
  });
  final String text, label;
  final int lines;
  final TextStyle? style;
  @override
  State<ExpandableNarrative> createState() => _ExpandableNarrativeState();
}

class _ExpandableNarrativeState extends State<ExpandableNarrative> {
  bool expanded = false;
  @override
  void didUpdateWidget(covariant ExpandableNarrative old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) expanded = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: widget.lines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final over = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            style: widget.style,
            maxLines: expanded ? null : widget.lines,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
          if (over)
            TextButton(
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? '收起经过' : widget.label),
            ),
        ],
      );
    },
  );
}
