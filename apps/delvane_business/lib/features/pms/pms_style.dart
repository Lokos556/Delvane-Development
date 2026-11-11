import 'package:flutter/material.dart';

// Source: final computed static/styles.css cascade, not the older theme layers.
abstract final class PmsStyle {
  static const yellow = Color(0xFFFFD500);
  static const ink = Color(0xFF171717);
  static const muted = Color(0xFF686868);
  static const canvas = Colors.white;
  static const soft = Color(0xFFFAF7F0);
  static const line = Color(0x85FFFFFF);
  static const logo = 'assets/delvane-icon.png';
  static const shadow = BoxShadow(color: Color(0x0C302714), blurRadius: 32, offset: Offset(0, 12));
}

ThemeData pmsTheme() => ThemeData(
  useMaterial3: true, fontFamily: 'Segoe UI', scaffoldBackgroundColor: PmsStyle.canvas,
  colorScheme: ColorScheme.fromSeed(seedColor: PmsStyle.yellow, primary: PmsStyle.ink,
    secondary: PmsStyle.yellow, surface: Colors.white),
  textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 14, color: PmsStyle.ink, height: 1.4)),
  inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0x99FFFFFF),
    isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE8E6E1))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE8E6E1))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: PmsStyle.yellow))),
  dividerColor: const Color(0xFFE8E6E1), splashFactory: NoSplash.splashFactory,
);

class PmsButton extends StatelessWidget {
  const PmsButton(this.label, {super.key, required this.onPressed, this.primary = false,
    this.danger = false, this.small = false, this.leading});
  final String label;
  final VoidCallback? onPressed;
  final bool primary, danger, small;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Semantics(button: true, enabled: onPressed != null,
    child: Opacity(opacity: onPressed == null ? .48 : 1,
      child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: primary ? const [Color(0xFFFFE76A), Color(0xFFFFD000)] : const [Color(0xDDFFFFFF), Color(0x88FFFFFF)]),
        borderRadius: BorderRadius.circular(small ? 12 : 18),
        border: Border.all(color: const Color(0xBBFFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x0B302714), blurRadius: 14, offset: Offset(0, 5))]),
        child: Material(type: MaterialType.transparency, child: InkWell(onTap: onPressed,
          borderRadius: BorderRadius.circular(small ? 12 : 18),
          child: Padding(padding: EdgeInsets.symmetric(horizontal: small ? 12 : 17, vertical: small ? 8 : 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading!, const SizedBox(width: 7)],
              Flexible(child: Text(label, style: TextStyle(fontSize: small ? 12 : 13,
                fontWeight: FontWeight.w700, color: danger ? const Color(0xFFA12E36) : PmsStyle.ink))),
            ]))),
      ),
    ));
}

class PmsCard extends StatelessWidget {
  const PmsCard({super.key, required this.child, this.padding = const EdgeInsets.all(20),
    this.radius = 18, this.color = const Color(0x6BFFFFFF), this.shadow = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final bool shadow;
  @override
  Widget build(BuildContext context) => Container(padding: padding, decoration: BoxDecoration(
    color: color, borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: PmsStyle.line), boxShadow: shadow ? const [PmsStyle.shadow] : null), child: child);
}

class PmsEyebrow extends StatelessWidget {
  const PmsEyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontSize: 11.52, height: 1.3, letterSpacing: 1.38, fontWeight: FontWeight.w700, color: Colors.black));
}

class PmsBadge extends StatelessWidget {
  const PmsBadge(this.label, {super.key, this.tone = 'neutral'});
  final String label, tone;
  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      'ready' || 'complete' || 'verified' || 'paid' => (const Color(0xFFE5F4EB), const Color(0xFF26734D)),
      'high' || 'rejected' => (const Color(0xFFFDE9E8), const Color(0xFFAA3139)),
      'attention' || 'pending' || 'needs_review' || 'cleaning' => (const Color(0xFFFFF3BD), const Color(0xFF6C5200)),
      _ => (const Color(0xFFF0ECE4), const Color(0xFF5F5A51)),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(16)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colors.$2)));
  }
}

class PmsColumns extends StatelessWidget {
  const PmsColumns(this.children, {super.key, this.columns = 3, this.gap = 14, this.mobileBreakpoint = 720});
  final List<Widget> children;
  final int columns;
  final double gap, mobileBreakpoint;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final window = MediaQuery.sizeOf(context).width;
    final count = window <= mobileBreakpoint ? 1 : window <= 1050 && columns > 2 ? 2 : columns;
    final width = (constraints.maxWidth - gap * (count - 1)) / count;
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (var i=0; i<children.length; i++) SizedBox(
        width: count == 2 && children.length == 3 && i == 2 ? constraints.maxWidth : width,
        child: children[i]),
    ]);
  });
}

class PmsEmpty extends StatelessWidget {
  const PmsEmpty([this.label = '—', this.tall = false]);
  final String label;
  final bool tall;
  @override
  Widget build(BuildContext context) => Padding(padding: EdgeInsets.symmetric(vertical: tall ? 64 : 24, horizontal: 12),
      child: Center(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: PmsStyle.muted))));
}

class PmsTabs extends StatelessWidget {
  const PmsTabs({super.key, required this.labels, required this.selected, required this.onChanged});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(scrollDirection: Axis.horizontal,
    child: Row(children: [for (var i=0;i<labels.length;i++) Padding(padding: const EdgeInsets.only(right: 8),
      child: PmsButton(labels[i], primary: i == selected, small: true, onPressed: () => onChanged(i)))]));
}

class PmsField extends StatelessWidget {
  const PmsField(this.label, {super.key, required this.controller, this.required = false,
    this.lines = 1, this.keyboard, this.hint, this.onChanged, this.validator});
  final String label;
  final TextEditingController controller;
  final bool required;
  final int lines;
  final TextInputType? keyboard;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 5),
      TextFormField(controller: controller, maxLines: lines, keyboardType: keyboard,
        onChanged: onChanged, decoration: InputDecoration(hintText: hint),
        validator: validator ?? (required ? (value) => value == null || value.trim().isEmpty ? 'Required' : null : null)),
    ]));
}

class PmsSelect extends StatelessWidget {
  const PmsSelect(this.label, {super.key, required this.value, required this.items, required this.onChanged});
  final String label, value;
  final Map<String, String> items;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 5),
      DropdownButtonFormField<String>(value: items.containsKey(value) ? value : null, isExpanded: true,
        items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged == null ? null : (value) { if (value != null) onChanged!(value); }),
    ]));
}

class PmsModal extends StatelessWidget {
  const PmsModal({super.key, required this.title, required this.child, this.eyebrow,
    this.width = 920, this.actions = const []});
  final String title;
  final String? eyebrow;
  final Widget child;
  final double width;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog(backgroundColor: Colors.transparent,
    insetPadding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 720 ? 7 : 24),
    child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(context).height * .94),
      child: PmsCard(radius: 24, color: const Color(0xFAFFFEFA), padding: EdgeInsets.zero, shadow: true,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 20, 14, 18), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (eyebrow != null) PmsEyebrow(eyebrow!), Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -.8)),
            ])),
            PmsButton('×', small: true, onPressed: () => Navigator.of(context).pop()),
          ])),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), child: child)),
          if (actions.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions)),
        ]))));
}
