import 'package:material_ui/material_ui.dart';

import '../../core/localization/system_labels.dart';

import '../workspace/workspace_models.dart';
import 'operations_workflows.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key, required this.c});
  final PmsController c;
  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  String filter = 'all';
  PmsController get c => widget.c;
  Future<void> create() async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => MaintenanceEditor(c: c),
    );
    if (changed == true && mounted) await c.load();
  }

  @override
  Widget build(BuildContext context) {
    final items = c
        .rows('maintenance')
        .where((m) => filter == 'all' || m['status'] == filter)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsEyebrow(ui('MAINTENANCE')),
        PmsPageTitle(ui('Issues become owned work.')),
        Text(
          ui(
            'No WhatsApp archaeology. Every issue has a property, urgency, owner and resolution trail.',
          ),
        ),
        const SizedBox(height: 16),
        if (c.user.isOperator || c.user.role == 'cleaner')
          Align(
            alignment: Alignment.centerRight,
            child: PmsButton(
              ui('+ Report issue'),
              primary: true,
              onPressed: c.saving ? null : create,
            ),
          ),
        const SizedBox(height: 20),
        PmsSelect(
          ui('Status'),
          value: filter,
          items: {
            'all': ui('All cases'),
            'reported': ui('Reported'),
            'assigned': ui('Assigned'),
            'in_progress': ui('In progress'),
            'resolved': ui('Resolved'),
            'verified': ui('Verified'),
          },
          onChanged: c.saving ? null : (v) => setState(() => filter = v),
        ),
        PmsColumns([for (final m in items) caseCard(m)], columns: 2),
        if (items.isEmpty) PmsEmpty(ui('No maintenance cases in this view.')),
      ],
    );
  }

  Widget caseCard(Json m) {
    final status = text(m, 'status');
    final next = ['reported', 'assigned', 'open'].contains(status)
        ? 'in_progress'
        : status == 'in_progress'
        ? 'resolved'
        : status == 'resolved' && c.user.isOperator
        ? 'verified'
        : null;
    final permitted =
        c.user.isOperator ||
        (c.user.role == 'maintenance' &&
            (m['assigned_to'] == null || m['assigned_to'] == c.user.id));
    const stages = [
      'reported',
      'assigned',
      'in_progress',
      'resolved',
      'verified',
    ];
    final index = stages.indexOf(status == 'open' ? 'reported' : status);
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 8,
            children: [
              PmsEyebrow(text(m, 'property_name')),
              PmsBadge(text(m, 'severity'), tone: text(m, 'severity')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            text(m, 'title'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(text(m, 'detail')),
          const SizedBox(height: 20),
          PmsLifecycleRail(stages: stages, index: index),
          const SizedBox(height: 20),
          Text(ui('Owner: ${text(m, 'assigned_name', 'Unassigned')}')),
          Text(ui('Reported ${text(m, 'created_at')}')),
          if (m['due_at'] != null) Text(ui('Due ${text(m, 'due_at')}')),
          if (m['resolved_at'] != null)
            Text(ui('Resolved ${text(m, 'resolved_at')}')),
          if (m['verified_at'] != null)
            Text(ui('Verified ${text(m, 'verified_at')}')),
          const SizedBox(height: 16),
          if (permitted && next != null)
            Align(
              alignment: Alignment.centerRight,
              child: PmsButton(
                next == 'in_progress'
                    ? ui('Start work')
                    : next == 'resolved'
                    ? ui('Mark resolved')
                    : ui('Verify'),
                primary: next != 'in_progress',
                onPressed: c.saving
                    ? null
                    : () => c.act(
                        () => OperationsWorkflows(c).maintenanceStatus(m, next),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class MaintenanceEditor extends StatefulWidget {
  const MaintenanceEditor({super.key, required this.c});
  final PmsController c;
  @override
  State<MaintenanceEditor> createState() => _MaintenanceEditorState();
}

class _MaintenanceEditorState extends State<MaintenanceEditor>
    with PmsActions<MaintenanceEditor> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(), detail = TextEditingController();
  late String property = widget.c.rows('properties').isEmpty
      ? ''
      : text(widget.c.rows('properties').first, 'id');
  String severity = 'medium';
  bool saved = false;
  @override
  void dispose() {
    title.dispose();
    detail.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saved || property.isEmpty || !form.currentState!.validate()) return;
    final ok = await perform(() async {
      await OperationsWorkflows(widget.c).maintenance({
        'property_id': property,
        'title': title.text,
        'detail': detail.text,
        'severity': severity,
      });
      saved = true;
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Delvane will route it.'),
    eyebrow: ui('REPORT ISSUE'),
    width: 650,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Cancel'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        ui('Create case'),
        primary: true,
        onPressed: busy || saved || property.isEmpty ? null : save,
      ),
    ],
    child: Form(
      key: form,
      child: Column(
        children: [
          errors(),
          if (widget.c.rows('properties').isEmpty)
            PmsEmpty(ui('No properties available. Reload the workspace.')),
          PmsSelect(
            ui('Property'),
            value: property,
            items: {
              for (final p in widget.c.rows('properties'))
                text(p, 'id'): text(p, 'name'),
            },
            onChanged: busy ? null : (v) => setState(() => property = v),
          ),
          PmsField(
            ui('Issue'),
            controller: title,
            required: true,
            hint: ui('e.g. Bathroom tap leaking'),
          ),
          PmsSelect(
            ui('Severity'),
            value: severity,
            items: {
              'low': ui('low'),
              'medium': ui('medium'),
              'high': ui('high'),
            },
            onChanged: busy ? null : (v) => setState(() => severity = v),
          ),
          PmsField(
            ui('Details'),
            controller: detail,
            lines: 4,
            hint: ui('What did you notice?'),
          ),
        ],
      ),
    ),
  );
}

class SuppliesPage extends StatelessWidget {
  const SuppliesPage({super.key, required this.c});
  final PmsController c;
  Future<void> adjust(BuildContext context, Json item) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => StockEditor(c: c, item: item),
    );
    if (changed == true && c.auth.user != null) await c.load();
  }

  @override
  Widget build(BuildContext context) {
    final d = c.object('inventory'), items = optionalRows(d['items']);
    if (!c.user.isOperator) return PmsEmpty(ui('No access'));
    final low = items.where((x) => x['low'] == true).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsEyebrow(ui('SUPPLIES')),
        PmsPageTitle(ui('Delvane watches consumption.')),
        Text(
          ui(
            '${d['upcoming_stays'] ?? 0} upcoming stays are included in the current estimate.',
          ),
        ),
        const SizedBox(height: 24),
        PmsColumns([
          for (final item in items)
            PmsCard(
              color: item['low'] == true
                  ? const Color(0xFFFFF5CC)
                  : PmsStyle.soft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PmsEyebrow(
                    item['low'] == true
                        ? ui('RESTOCK SUGGESTED')
                        : ui('STOCK HEALTHY'),
                  ),
                  Text(
                    inventoryName(item),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${uiDecimal('${item['quantity']}')} ${inventoryUnit(item)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ui(
                      'Target ${item['par_level']} · estimated upcoming use ${item['estimated_need']}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: stockFraction(item)),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PmsButton(
                      ui('Adjust stock'),
                      small: true,
                      onPressed: c.saving ? null : () => adjust(context, item),
                    ),
                  ),
                ],
              ),
            ),
        ], columns: 3),
        if (items.isEmpty) PmsEmpty(ui('No inventory items.')),
        const SizedBox(height: 24),
        PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PmsEyebrow(ui('SHOPPING LIST')),
              Text(
                ui('${low.length} items need attention'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final item in low)
                Text(
                  '${inventoryName(item)} · ${uiDecimal('${shoppingQuantity(item)}')} ${inventoryUnit(item)}',
                ),
              if (low.isEmpty) Text(ui('Nothing to buy.')),
            ],
          ),
        ),
      ],
    );
  }
}

double stockFraction(Json item) {
  final par = (item['par_level'] as num? ?? 0).toDouble();
  return ((item['quantity'] as num? ?? 0) / (par < 1 ? 1 : par))
      .clamp(0, 1)
      .toDouble();
}

int shoppingQuantity(Json item) =>
    ((item['par_level'] as num? ?? 0) - (item['quantity'] as num? ?? 0))
        .ceil()
        .clamp(0, 1 << 53);

class StockEditor extends StatefulWidget {
  const StockEditor({super.key, required this.c, required this.item});
  final PmsController c;
  final Json item;
  @override
  State<StockEditor> createState() => _StockEditorState();
}

class _StockEditorState extends State<StockEditor>
    with PmsActions<StockEditor> {
  late final quantity = TextEditingController(
    text: '${widget.item['quantity']}',
  );
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final ok = await perform(
      () =>
          OperationsWorkflows(widget.c)
              .stock(text(widget.item, 'id'), num.parse(quantity.text)),
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Adjust stock'),
    eyebrow: inventoryName(widget.item),
    width: 480,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Cancel'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(ui('Save'), primary: true, onPressed: busy ? null : save),
    ],
    child: Form(
      key: form,
      child: Column(
        children: [
          errors(),
          PmsField(
            ui('Current quantity'),
            controller: quantity,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => num.tryParse(v ?? '')?.isFinite != true
                ? 'Enter a finite quantity'
                : null,
          ),
        ],
      ),
    ),
  );
}
