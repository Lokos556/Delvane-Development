import 'package:material_ui/material_ui.dart';

import '../../core/localization/web_strings.dart';

class ScopedSearch extends StatefulWidget {
  const ScopedSearch({
    super.key,
    required this.query,
    required this.label,
    required this.onChanged,
  });
  final TextEditingController query;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  State<ScopedSearch> createState() => _ScopedSearchState();
}

class _ScopedSearchState extends State<ScopedSearch> {
  late bool expanded = widget.query.text.isNotEmpty;
  final focus = FocusNode();

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: AnimatedSize(
      alignment: Alignment.centerRight,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: expanded
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: TextField(
                controller: widget.query,
                focusNode: focus,
                onChanged: widget.onChanged,
                textInputAction: TextInputAction.search,
                onTapOutside: (_) => focus.unfocus(),
                decoration: InputDecoration(
                  labelText: ui(widget.label),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: ui('Close search'),
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      widget.query.clear();
                      widget.onChanged('');
                      setState(() => expanded = false);
                    },
                  ),
                ),
              ),
            )
          : IconButton(
              tooltip: ui(widget.label),
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() => expanded = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) focus.requestFocus();
                });
              },
            ),
    ),
  );
}
