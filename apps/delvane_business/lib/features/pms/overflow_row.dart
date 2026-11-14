import '../../core/localization/web_strings.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Hints are driven by measured overflow, never by an assumed device width.
class PmsOverflowRow extends StatefulWidget {
  const PmsOverflowRow({super.key, required this.child});
  final Widget child;
  @override
  State<PmsOverflowRow> createState() => _PmsOverflowRowState();
}

class _PmsOverflowRowState extends State<PmsOverflowRow> {
  final scroll = ScrollController();
  bool before = false, after = false;
  @override
  void initState() {
    super.initState();
    scroll.addListener(update);
  }

  void update() {
    if (!mounted || !scroll.hasClients) return;
    final a = scroll.offset > 1,
        b = scroll.position.maxScrollExtent - scroll.offset > 1;
    if (a != before || b != after) {
      setState(() {
        before = a;
        after = b;
      });
    }
  }

  void move(double amount) {
    if (scroll.hasClients) {
      final target = (scroll.offset + amount)
          .clamp(0, scroll.position.maxScrollExtent)
          .toDouble();
      if (MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(target);
        return;
      }
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => update());
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => update());
        return false;
      },
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              ((event.logicalKey == LogicalKeyboardKey.arrowLeft && before) ||
                  (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                      after))) {
            move(event.logicalKey == LogicalKeyboardKey.arrowLeft ? -180 : 180);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && (before || after)) {
              final delta = event.scrollDelta.dy + event.scrollDelta.dx;
              if (!((delta > 0 && after) || (delta < 0 && before))) {
                return;
              }
              GestureBinding.instance.pointerSignalResolver.register(
                event,
                (_) => move(delta),
              );
            }
          },
          child: Row(
            children: [
              if (before)
                IconButton(
                  tooltip: ui('Scroll backward'),
                  onPressed: () => move(-180),
                  icon: const Icon(Icons.chevron_left, size: 18),
                ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  child: widget.child,
                ),
              ),
              if (after)
                IconButton(
                  tooltip: ui('Scroll forward'),
                  onPressed: () => move(180),
                  icon: const Icon(Icons.chevron_right, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
