import 'package:material_ui/material_ui.dart';

import 'pms_controller.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

/// Dialog actions stay disabled until a request ends. Failures remain inline.
mixin PmsActions<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? failure;
  Future<bool> perform(Future<void> Function() action) async {
    if (busy) return false;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) setState(() => failure = workflowError(e));
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget errors() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy) const LinearProgressIndicator(),
      if (failure != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              ui(failure!),
              style: const TextStyle(color: Color(0xFFAA3139)),
            ),
          ),
        ),
    ],
  );
}

Future<bool> pmsConfirm(
  BuildContext context,
  String title,
  String detail,
) async =>
    await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => PmsModal(
        title: title,
        width: 520,
        actions: [
          PmsButton(
            ui('Close'),
            onPressed: () => Navigator.pop(context, false),
          ),
          PmsButton(
            ui('Confirm'),
            primary: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
        child: Text(detail),
      ),
    ) ??
    false;

class PmsTextDialog extends StatefulWidget {
  const PmsTextDialog({
    super.key,
    required this.title,
    required this.label,
    required this.submitLabel,
    required this.save,
    this.initial = '',
    this.hint,
    this.lines = 5,
    this.required = true,
  });
  final String title, label, submitLabel, initial;
  final String? hint;
  final int lines;
  final bool required;
  final Future<void> Function(String) save;
  @override
  State<PmsTextDialog> createState() => _PmsTextDialogState();
}

class _PmsTextDialogState extends State<PmsTextDialog>
    with PmsActions<PmsTextDialog> {
  late final input = TextEditingController(text: widget.initial);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: PmsModal(
      title: widget.title,
      width: 600,
      canClose: !busy,
      actions: [
        PmsButton(
          widget.submitLabel,
          primary: true,
          onPressed: busy
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  final ok = await perform(
                    () => widget.save(input.text.trim()),
                  );
                  if (ok && context.mounted) Navigator.pop(context, true);
                },
        ),
      ],
      child: Form(
        key: form,
        child: Column(
          children: [
            PmsField(
              widget.label,
              controller: input,
              required: widget.required,
              lines: widget.lines,
              hint: widget.hint,
            ),
            errors(),
          ],
        ),
      ),
    ),
  );
}

/// Date format and stay-length presentation; capacity/conflicts remain server-side.
class PmsDateField extends StatelessWidget {
  const PmsDateField(
    this.label, {
    super.key,
    required this.controller,
    this.onChanged,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => PmsField(
    label,
    controller: controller,
    required: true,
    hint: ui('YYYY-MM-DD'),
    suffix: IconButton(
      tooltip: ui('Choose $label'),
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      onPressed: () async {
        final selected = await showDialog<DateTime>(
          context: context,
          useRootNavigator: false,
          builder: (_) => PmsDatePicker(
            initial: DateTime.tryParse(controller.text) ?? DateTime.now(),
          ),
        );
        if (selected != null) {
          controller.text = isoDate(selected);
          onChanged?.call(controller.text);
        }
      },
    ),
    onChanged: onChanged,
    validator: (value) =>
        validDate(value) ? null : 'Use a valid YYYY-MM-DD date.',
  );
}

bool validDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final date = DateTime.tryParse(value);
  return date != null &&
      date.year >= 1 &&
      date.year <= 9999 &&
      isoDate(date) == value;
}

class PmsDatePicker extends StatefulWidget {
  const PmsDatePicker({super.key, required this.initial});
  final DateTime initial;
  @override
  State<PmsDatePicker> createState() => _PmsDatePickerState();
}

class _PmsDatePickerState extends State<PmsDatePicker> {
  late DateTime month = DateTime(widget.initial.year, widget.initial.month);
  @override
  Widget build(BuildContext context) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final start = month.subtract(Duration(days: month.weekday - 1));
    return PmsModal(
      title: WebStrings.current.language == 'hu'
          ? '${month.year}. ${ui(names[month.month - 1])}'
          : '${names[month.month - 1]} ${month.year}',
      width: 390,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              PmsButton(
                '‹',
                small: true,
                onPressed: month.year == 1 && month.month == 1
                    ? null
                    : () => setState(
                        () => month = DateTime(month.year, month.month - 1),
                      ),
              ),
              PmsButton(
                ui('Today'),
                small: true,
                onPressed: () => setState(
                  () => month = DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                  ),
                ),
              ),
              PmsButton(
                '›',
                small: true,
                onPressed: month.year == 9999 && month.month == 12
                    ? null
                    : () => setState(
                        () => month = DateTime(month.year, month.month + 1),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final label in [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ])
                Expanded(
                  child: Center(
                    child: Text(
                      ui(label),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var index = 0; index < 42; index++)
                Builder(
                  builder: (context) {
                    final day = start.add(Duration(days: index));
                    return Semantics(
                      button: true,
                      label: isoDate(day),
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: day.year < 1 || day.year > 9999
                              ? null
                              : () => Navigator.pop(context, day),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            alignment: Alignment.center,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isoDate(day) == isoDate(widget.initial)
                                  ? PmsStyle.yellow
                                  : null,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                color: day.month == month.month
                                    ? PmsStyle.ink
                                    : PmsStyle.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String? optionalTime(String? value) =>
    value == null ||
        value.isEmpty ||
        RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)
    ? null
    : 'Use a valid 24-hour HH:MM time.';

class PmsKeyValues extends StatelessWidget {
  const PmsKeyValues(this.values, {super.key});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in values.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ui(entry.key),
                style: const TextStyle(fontSize: 11, color: PmsStyle.muted),
              ),
              SelectableText(
                entry.value.isEmpty
                    ? '—'
                    : uiFieldValue(entry.key, entry.value),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
    ],
  );
}
