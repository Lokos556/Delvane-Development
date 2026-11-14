import 'section_picker.dart';

import 'package:delvane_business/core/localization/web_strings.dart';

import 'dart:ui' as canvas_ui;

import 'package:flutter/foundation.dart';

import 'package:material_ui/material_ui.dart';

import 'pms_icons.dart';

// Source: final computed static/styles.css cascade, not the older theme layers.
abstract final class PmsStyle {
  static const yellow = Color(0xFFFFD500);
  static const ink = Color(0xFF171717);
  static const muted = Color(0xFF686868);
  static const canvas = Colors.white;
  static const soft = Color(0xFFFAF7F0);
  static const line = Color(0x85FFFFFF);
  static const font = 'Segoe UI';
  static const sidebarWidth = 235.0;
  static const mobileBreakpoint = 760.0;
  static const logo = 'assets/delvane-icon.png';
  // CSS backdrop-filter: blur(...) saturate(...). Applied only to actual glass
  // layers, not every nested card (which would repeatedly filter the backdrop).
  static canvas_ui.ImageFilter glassFilter(double blur, double saturation) {
    final r = .2126 * (1 - saturation),
        g = .7152 * (1 - saturation),
        b = .0722 * (1 - saturation);
    return canvas_ui.ImageFilter.compose(
      outer: ColorFilter.matrix([
        r + saturation,
        g,
        b,
        0,
        0,
        r,
        g + saturation,
        b,
        0,
        0,
        r,
        g,
        b + saturation,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      inner: canvas_ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
    );
  }

  static const shadow = BoxShadow(
    color: Color(0x172D2719),
    blurRadius: 36,
    offset: Offset(0, 12),
  );
}

ThemeData pmsTheme() => ThemeData(
  scrollbarTheme: ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(
      defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS
          ? 2.5
          : 9,
    ),
  ),
  useMaterial3: true,
  fontFamily: PmsStyle.font,
  fontFamilyFallback: const ['Segoe UI Symbol', 'Arial', 'sans-serif'],
  scaffoldBackgroundColor: PmsStyle.canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: PmsStyle.yellow,
    primary: PmsStyle.ink,
    secondary: PmsStyle.yellow,
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 16, color: Colors.black, height: 1.4),
  ),
  listTileTheme: const ListTileThemeData(
    dense: true,
    minVerticalPadding: 8,
    contentPadding: EdgeInsets.symmetric(horizontal: 16),
    horizontalTitleGap: 12,
    titleTextStyle: TextStyle(
      fontFamily: PmsStyle.font,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: PmsStyle.ink,
    ),
    subtitleTextStyle: TextStyle(
      fontFamily: PmsStyle.font,
      fontSize: 12,
      color: PmsStyle.muted,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0x99FFFFFF),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE8E6E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE8E6E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: PmsStyle.yellow),
    ),
  ),
  dividerColor: const Color(0xFFE8E6E1),
  splashFactory: NoSplash.splashFactory,
);

class PmsButton extends StatelessWidget {
  const PmsButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.small = false,
    this.leading,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary, danger, small;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    child: Opacity(
      opacity: onPressed == null ? .48 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: primary ? null : const Color(0x6BFFFFFF),
          gradient: primary
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE76A), Color(0xFFFFD000)],
                )
              : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xBBFFFFFF)),
          boxShadow: primary
              ? const [
                  BoxShadow(
                    color: Color(0x33BF9B00),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            hoverColor: const Color(0x14FFD500),
            focusColor: const Color(0x33FFD500),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: small ? 12 : 18,
                vertical: small ? 8 : 13,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 7)],
                  Flexible(
                    child: Text(
                      ui(label),
                      style: TextStyle(
                        fontSize: small ? 12 : 16,
                        fontWeight: FontWeight.w700,
                        color: danger ? const Color(0xFFA12E36) : PmsStyle.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PmsNavItem extends StatelessWidget {
  const PmsNavItem(
    this.label, {
    super.key,
    required this.selected,
    required this.onPressed,
    this.mobile = false,
  });
  final String label;
  final bool selected, mobile;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Container(
      height: mobile ? 60 : 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xE0FFFFFF)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0xFAFFE64B), Color(0xEBFFD500)]
              : const [Color(0x80FFFFFF), Color(0x40FFFCF3)],
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x26C29700),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(19),
          hoverColor: const Color(0x33FFD500),
          focusColor: const Color(0x33FFD500),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                ui(label),
                style: TextStyle(
                  fontSize: mobile ? 18 : 16,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: PmsStyle.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PmsIconButton extends StatelessWidget {
  const PmsIconButton(
    this.glyph, {
    super.key,
    required this.label,
    required this.onPressed,
    this.size = 42,
    this.surface = false,
  });
  final String glyph, label;
  final double size;
  final bool surface;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: ui(label),
    child: Semantics(
      label: ui(label),
      button: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: surface ? const Color(0xA6FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(size / 2),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(size / 2),
            hoverColor: const Color(0x22FFD500),
            child: Center(
              child: PmsVectorIcon(
                glyph,
                color: onPressed == null ? PmsStyle.muted : Colors.black,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PmsPageHeader extends StatelessWidget {
  const PmsPageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description = '',
    this.actions = const [],
    this.titleSize,
    this.descriptionSize = 16,
    this.titleLineHeight = 1.04,
  });
  final String eyebrow, title, description;
  final List<Widget> actions;
  final double? titleSize;
  final double descriptionSize;
  final double titleLineHeight;
  @override
  Widget build(BuildContext context) {
    final mobile =
        MediaQuery.sizeOf(context).width <= PmsStyle.mobileBreakpoint;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PmsEyebrow(eyebrow),
        Text(
          title,
          style: TextStyle(
            fontSize: titleSize ?? (mobile ? 38.4 : 57.6),
            height: titleLineHeight,
            letterSpacing: -2,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        if (description.isNotEmpty)
          Text(
            description,
            style: TextStyle(fontSize: descriptionSize, height: 1.4),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: copy),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 20),
                  Wrap(spacing: 8, children: actions),
                ],
              ],
            ),
    );
  }
}

class PmsPageTitle extends StatelessWidget {
  const PmsPageTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      fontSize: MediaQuery.sizeOf(context).width <= 760 ? 38.4 : 57.6,
      height: 1.04,
      letterSpacing: -2,
      fontWeight: FontWeight.w700,
      color: Colors.black,
    ),
  );
}

class PmsSideSheet extends StatelessWidget {
  const PmsSideSheet({
    super.key,
    required this.child,
    required this.title,
    this.eyebrow = 'WORKSPACE',
  });
  final Widget child;
  final String title, eyebrow;
  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width <= 760;
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.all(mobile ? 8 : 12),
          child: SizedBox(
            width: mobile ? MediaQuery.sizeOf(context).width - 16 : 490,
            height: MediaQuery.sizeOf(context).height - (mobile ? 16 : 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(mobile ? 30 : 32),
              child: BackdropFilter(
                enabled:
                    !MediaQuery.disableAnimationsOf(context) &&
                    !MediaQuery.accessibleNavigationOf(context),
                filter: PmsStyle.glassFilter(42, 1.9),
                child: Material(
                  color: const Color(0xA8FFFCF3),
                  child: Container(
                    padding: mobile
                        ? const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 22,
                          )
                        : const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xADFFFFFF)),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PmsEyebrow(eyebrow),
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PmsIconButton(
                              '×',
                              label: ui('Close settings'),
                              surface: true,
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Expanded(child: PmsScrollPane(child: child)),
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
}

class PmsCount extends StatelessWidget {
  const PmsCount(this.value, {super.key, this.symbol = false});
  final String value;
  final bool symbol;
  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: symbol ? const Color(0xFFF0ECE6) : PmsStyle.yellow,
    ),
    child: Text(
      value,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: symbol ? const Color(0xFF554F43) : Colors.black,
      ),
    ),
  );
}

class PmsCard extends StatelessWidget {
  const PmsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.color = const Color(0x6BFFFFFF),
    this.shadow = true,
    this.gradient,
    this.backdropBlur = 0,
    this.saturation = 1,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final bool shadow;
  final Gradient? gradient;
  final double backdropBlur, saturation;
  @override
  Widget build(BuildContext context) {
    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: PmsStyle.line),
        boxShadow: shadow ? const [PmsStyle.shadow] : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    if (backdropBlur == 0) return surface;
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      return ColoredBox(color: Colors.white, child: surface);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: PmsStyle.glassFilter(backdropBlur, saturation),
        child: surface,
      ),
    );
  }
}

class PmsEyebrow extends StatelessWidget {
  const PmsEyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11.52,
      height: 1.3,
      letterSpacing: 1.38,
      fontWeight: FontWeight.w700,
      color: Colors.black,
    ),
  );
}

class PmsBadge extends StatelessWidget {
  const PmsBadge(
    this.label, {
    super.key,
    this.tone = 'neutral',
    this.large = false,
    this.compact = false,
    this.localizeLabel = true,
  });
  final String label, tone;
  final bool large;
  final bool compact;
  final bool localizeLabel;
  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      'ready' ||
      'complete' ||
      'verified' ||
      'paid' => (const Color(0xFFE5F4EB), const Color(0xFF26734D)),
      'high' ||
      'rejected' => (const Color(0xFFFDE9E8), const Color(0xFFAA3139)),
      'attention' ||
      'pending' ||
      'needs_review' ||
      'cleaning' => (const Color(0xFFFFF3BD), const Color(0xFF6C5200)),
      _ => (const Color(0xFFF0ECE4), const Color(0xFF5F5A51)),
    };
    return Container(
      constraints: large ? const BoxConstraints(minHeight: 54) : null,
      padding: EdgeInsets.symmetric(
        horizontal: large
            ? 20
            : compact
            ? 8
            : 11,
        vertical: large
            ? 18
            : compact
            ? 5
            : 7,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        localizeLabel ? ui(label) : label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w800,
          color: colors.$2,
        ),
      ),
    );
  }
}

class PmsToggle extends StatelessWidget {
  const PmsToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    enabled: onChanged != null,
    label: ui('Enabled'),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Container(
            width: 38,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? PmsStyle.yellow : const Color(0xFFDAD7D0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Align(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PmsColumns extends StatelessWidget {
  const PmsColumns(
    this.children, {
    super.key,
    this.columns = 3,
    this.gap = 14,
    this.mobileBreakpoint = 720,
    this.mobileColumns = 1,
  });
  final List<Widget> children;
  final int columns;
  final int mobileColumns;
  final double gap, mobileBreakpoint;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final window = MediaQuery.sizeOf(context).width;
      final count = window <= mobileBreakpoint
          ? mobileColumns
          : window <= 1100 && columns > 2
          ? 2
          : columns;
      final width = (constraints.maxWidth - gap * (count - 1)) / count;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(
              width: count == 2 && children.length == 3 && i == 2
                  ? constraints.maxWidth
                  : width,
              child: children[i],
            ),
        ],
      );
    },
  );
}

class PmsEmpty extends StatelessWidget {
  const PmsEmpty(this.label, {super.key, this.tall = false});
  final String label;
  final bool tall;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: tall ? 64 : 24, horizontal: 12),
    child: Center(
      child: Text(
        ui(label),
        textAlign: TextAlign.center,
        style: const TextStyle(color: PmsStyle.muted),
      ),
    ),
  );
}

class PmsTabs extends StatelessWidget {
  const PmsTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.plain = false,
    this.localizeLabels = true,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool plain;
  final bool localizeLabels;
  @override
  Widget build(BuildContext context) => PmsSectionPicker(
    labels: [for (final label in labels) localizeLabels ? ui(label) : label],
    selected: selected,
    onChanged: onChanged,
  );
}

class PmsLifecycleRail extends StatelessWidget {
  const PmsLifecycleRail({
    super.key,
    required this.stages,
    required this.index,
  });
  final List<String> stages;
  final int index;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < stages.length; i++)
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == 0
                          ? Colors.transparent
                          : const Color(0xFFE8E3D9),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= index
                          ? PmsStyle.yellow
                          : const Color(0xFFF0ECE4),
                    ),
                    child: Text(
                      i < index ? '✓' : '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == stages.length - 1
                          ? Colors.transparent
                          : const Color(0xFFE8E3D9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ui(stages[i].replaceAll('_', ' ')),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: PmsStyle.muted),
              ),
            ],
          ),
        ),
    ],
  );
}

class PmsRequiredNote extends StatelessWidget {
  const PmsRequiredNote({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      ui('Fields marked with * are required.'),
      style: const TextStyle(fontSize: 12, color: PmsStyle.muted),
    ),
  );
}

class PmsForm extends StatelessWidget {
  const PmsForm({
    super.key,
    required this.formKey,
    required this.child,
    this.showRequiredNote = true,
  });
  final GlobalKey<FormState> formKey;
  final Widget child;
  final bool showRequiredNote;
  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [if (showRequiredNote) const PmsRequiredNote(), child],
    ),
  );
}

class PmsField extends StatelessWidget {
  const PmsField(
    this.label, {
    super.key,
    required this.controller,
    this.required = false,
    this.lines = 1,
    this.keyboard,
    this.hint,
    this.onChanged,
    this.validator,
    this.suffix,
    this.maxLength,
    this.status,
    this.localizeLabel = true,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  final int lines;
  final TextInputType? keyboard;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final int? maxLength;
  final String? status;
  final bool localizeLabel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${localizeLabel ? ui(label) : label}${required ? ' *' : ''}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (status != null)
          Text(
            ui(status!),
            style: const TextStyle(fontSize: 11, color: PmsStyle.muted),
          ),
        const SizedBox(height: 5),
        Semantics(
          label:
              '${localizeLabel ? ui(label) : label}${required ? ' · ${ui('Required')}' : ''}',
          child: TextFormField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: controller,
            maxLines: lines,
            maxLength: maxLength,
            keyboardType: keyboard,
            onChanged: onChanged,
            decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
            validator: (value) {
              final error = validator != null
                  ? validator!(value)
                  : required && (value == null || value.trim().isEmpty)
                  ? 'Required'
                  : null;
              return error == null ? null : ui(error);
            },
          ),
        ),
      ],
    ),
  );
}

class PmsSelect extends StatelessWidget {
  const PmsSelect(
    this.label, {
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.required = false,
  });
  final bool required;
  final String label, value;
  final Map<String, String> items;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${ui(label)}${required ? ' *' : ''}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Semantics(
          label: '${ui(label)}${required ? ' · ${ui('Required')}' : ''}',
          child: DropdownButtonFormField<String>(
            borderRadius: BorderRadius.circular(18),
            dropdownColor: const Color(0xFFFFFDF8),
            icon: const PmsVectorIcon('chevron_down', size: 18),
            initialValue: items.containsKey(value) ? value : null,
            isExpanded: true,
            items: items.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: onChanged == null
                ? null
                : (value) {
                    if (value != null) onChanged!(value);
                  },
          ),
        ),
      ],
    ),
  );
}

class PmsModal extends StatelessWidget {
  const PmsModal({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.width = 920,
    this.actions = const [],
    this.canClose = true,
    this.headerActions = const [],
    this.mobileSheet = false,
    this.titleSize = 32,
  });
  final String title;
  final String? eyebrow;
  final Widget child;
  final double width;
  final List<Widget> actions;
  final bool canClose;
  final List<Widget> headerActions;
  final bool mobileSheet;
  final double titleSize;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: canClose,
    child: Dialog(
      alignment: mobileSheet && MediaQuery.sizeOf(context).width <= 760
          ? Alignment.bottomCenter
          : Alignment.center,
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(
        mobileSheet && MediaQuery.sizeOf(context).width <= 760
            ? 0
            : MediaQuery.sizeOf(context).width < 720
            ? 7
            : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        child: PmsCard(
          radius: 24,
          color: const Color(0xE0FFFFFF),
          backdropBlur: 26,
          saturation: 1.55,
          padding: EdgeInsets.zero,
          shadow: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (eyebrow != null) PmsEyebrow(eyebrow!),
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (MediaQuery.sizeOf(context).width > 760)
                          ...headerActions,
                        PmsIconButton(
                          '×',
                          label: ui('Close dialog'),
                          size: 36,
                          surface: true,
                          onPressed: canClose
                              ? () => Navigator.of(context).pop()
                              : null,
                        ),
                      ],
                    ),
                    if (MediaQuery.sizeOf(context).width <= 760 &&
                        headerActions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: headerActions,
                        ),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: PmsScrollPane(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                  child: child,
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PmsScrollPane extends StatefulWidget {
  const PmsScrollPane({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  State<PmsScrollPane> createState() => _PmsScrollPaneState();
}

class _PmsScrollPaneState extends State<PmsScrollPane> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: controller,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}
