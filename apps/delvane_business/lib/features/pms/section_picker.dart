import 'package:material_ui/material_ui.dart';

/// Fits destinations at their natural text size, or exposes them in one picker.
/// Selection belongs to the caller, so resizing/dismissing never resets a page.
class PmsSectionPicker extends StatelessWidget {
  const PmsSectionPicker({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.pickerLabel,
    this.allowSegments = true,
  });
  final String? pickerLabel;
  final bool allowSegments;
  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onChanged;

  Future<void> open(BuildContext context) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 180),
              reverseDuration: Duration(milliseconds: 140),
            ),
      backgroundColor: const Color(0xFFFFFDF8),
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
            maxWidth: 640,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: labels.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                selected: i == selected,
                child: ListTile(
                  minVerticalPadding: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: i == selected ? const Color(0x66FFD500) : null,
                  title: Text(labels[i]),
                  trailing: i == selected ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, i),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (context.mounted && choice != null && choice != selected) {
      onChanged?.call(choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final index = selected.clamp(0, labels.length - 1);
    const style = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
    return LayoutBuilder(
      builder: (context, constraints) {
        var widest = 0.0;
        for (final label in labels) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          if (painter.width > widest) widest = painter.width;
          painter.dispose();
        }
        final fits =
            labels.length <= 5 &&
            (widest + 36) * labels.length <= constraints.maxWidth;
        return Material(
          color: const Color(0xEFFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x1A000000)),
          ),
          clipBehavior: Clip.antiAlias,
          child: fits
              ? Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: Semantics(
                            selected: i == index,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black,
                                minimumSize: const Size(48, 48),
                                backgroundColor: i == index
                                    ? const Color(0xFFFFD500)
                                    : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: style,
                              ),
                              onPressed: onChanged == null
                                  ? null
                                  : () => onChanged!(i),
                              child: Text(labels[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : Semantics(
                  button: true,
                  selected: selected >= 0,
                  child: InkWell(
                    onTap: onChanged == null ? null : () => open(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 22,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD500),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              pickerLabel ?? labels[index],
                              style: style,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.expand_more, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
