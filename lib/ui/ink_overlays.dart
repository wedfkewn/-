import 'package:flutter/material.dart';
import 'ink_theme.dart';

/// All surfaces scroll within the actual space left by the keyboard.
Future<T?> showInkSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (ctx) {
    final size = MediaQuery.sizeOf(ctx);
    final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
    final available = ((size.height - keyboard) * .9).clamp(0.0, size.height);
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        key: const Key('ink-sheet-surface'),
        width: double.infinity,
        constraints: BoxConstraints(
          minHeight: (size.height * .42).clamp(0, available),
          maxHeight: available,
        ),
        child: PaperSurface(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '一世仙途',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭弹窗',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  builder(ctx),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  },
);

class InkDialog extends StatelessWidget {
  const InkDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
    this.canClose = true,
  });
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  final bool canClose;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: SizedBox(
      width: 560,
      child: PaperSurface(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DefaultTextStyle(
                        style: Theme.of(context).textTheme.titleLarge!,
                        child: title,
                      ),
                    ),
                    if (canClose)
                      IconButton(
                        tooltip: '关闭弹窗',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 16),
                ?content,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
