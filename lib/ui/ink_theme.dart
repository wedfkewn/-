import 'package:flutter/material.dart';

abstract final class InkTheme {
  static const paper = Color(0xfff7f3ea);
  static const ink = Color(0xff24231f);
  static const cinnabar = Color(0xffad2922);
  static const muted = Color(0xff817869);

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xff201f1c) : paper;
    final foreground = dark ? const Color(0xffeee5d5) : ink;
    final scheme = ColorScheme.fromSeed(
      seedColor: cinnabar,
      brightness: brightness,
      surface: surface,
      primary: dark ? const Color(0xffdf7767) : cinnabar,
      onSurface: foreground,
      outline: dark ? const Color(0xff756b5c) : const Color(0xffaaa293),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'WenKai',
      scaffoldBackgroundColor: surface,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyLarge: TextStyle(
          fontFamily: 'WenKai',
          fontSize: 16,
          height: 1.55,
          color: foreground,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'WenKai',
          fontSize: 15,
          height: 1.5,
          color: foreground,
        ),
        bodySmall: TextStyle(
          fontFamily: 'WenKai',
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        titleLarge: TextStyle(
          fontFamily: 'MaShan',
          fontSize: 28,
          color: foreground,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'MaShan',
          fontSize: 32,
          color: foreground,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'MaShan',
          fontSize: 27,
          color: foreground,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: .7),
        thickness: .6,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: foreground,
          foregroundColor: surface,
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(fontFamily: 'WenKai', fontSize: 15),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          foregroundColor: foreground,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontFamily: 'WenKai', fontSize: 15),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary.withValues(alpha: .08)
                : Colors.transparent,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(
          fontFamily: 'WenKai',
          fontSize: 15,
          color: foreground,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outline, width: .6),
        ),
        elevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: scheme.outline, width: .6),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    );
  }
}

class PaperSurface extends StatelessWidget {
  const PaperSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: Opacity(
            opacity: Theme.of(context).brightness == Brightness.dark
                ? .06
                : .18,
            child: Image.asset(
              'assets/images/rice-paper.png',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

class InkNavigation extends StatelessWidget {
  const InkNavigation({
    super.key,
    required this.index,
    required this.onChanged,
  });
  final int index;
  final ValueChanged<int> onChanged;
  static const labels = ['修行', '世界', '因果', '万世碑'];
  static const icons = [
    Icons.self_improvement,
    Icons.temple_buddhist_outlined,
    Icons.hub_outlined,
    Icons.account_balance_outlined,
  ];
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(color: Theme.of(context).dividerColor, width: .6),
      ),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 72,
        child: Row(
          children: List.generate(
            4,
            (i) => Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                label: labels[i],
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkIcon(
                        index: i,
                        size: 32,
                        color: i == index
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.1,
                          color: i == index
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 18,
                        height: 2,
                        color: i == index
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class InkAction extends StatelessWidget {
  const InkAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.width = 139,
    this.height = 49,
  });
  final String label;
  final VoidCallback? onPressed;
  final double width, height;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .4 : 1,
    child: SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/ink-action.png'),
            fit: BoxFit.fill,
          ),
        ),
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: InkTheme.paper,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: const RoundedRectangleBorder(),
          ),
          onPressed: onPressed,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontFamily: 'WenKai', fontSize: 18),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The source is actual ink artwork. Crop only the chosen sprite at display time.
class InkIcon extends StatelessWidget {
  const InkIcon({super.key, required this.index, this.size = 32, this.color});
  final int index;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * 440 / 410,
    child: ClipRect(
      child: Stack(
        children: [
          Positioned(
            left: -(index * 543 + 65) * size / 410,
            top: -145 * size / 410,
            width: 2172 * size / 410,
            height: 724 * size / 410,
            child: Image.asset(
              'assets/images/navigation-ink.png',
              fit: BoxFit.fill,
              color: color ?? Theme.of(context).colorScheme.onSurface,
              colorBlendMode: BlendMode.srcIn,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    ),
  );
}
