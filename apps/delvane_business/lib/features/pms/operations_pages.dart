import 'package:flutter/material.dart';
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
        const PmsEyebrow('MAINTENANCE'),
        const Text(
          'Issues become owned work.',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
        ),
        const Text(
          'No WhatsApp archaeology. Every issue has a property, urgency, owner and resolution trail.',
        ),
        const SizedBox(height: 16),
        if (c.user.isOperator || c.user.role == 'cleaner')
          Align(
            alignment: Alignment.centerRight,
            child: PmsButton(
              '+ Report issue',
              primary: true,
              onPressed: c.saving ? null : create,
            ),
          ),
        const SizedBox(height: 20),
        PmsSelect(
          'Status',
          value: filter,
          items: const {
            'all': 'All cases',
            'reported': 'Reported',
            'assigned': 'Assigned',
            'in_progress': 'In progress',
            'resolved': 'Resolved',
            'verified': 'Verified',
          },
          onChanged: c.saving ? null : (v) => setState(() => filter = v),
        ),
        PmsColumns([for (final m in items) caseCard(m)], columns: 2),
        if (items.isEmpty) const PmsEmpty('No maintenance cases in this view.'),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < stages.length; i++)
                PmsBadge(
                  '${i < index ? '✓' : i + 1} ${stages[i].replaceAll('_', ' ')}',
                  tone: i == index ? 'attention' : 'neutral',
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Owner: ${text(m, 'assigned_name', 'Unassigned')}'),
          Text('Reported ${text(m, 'created_at')}'),
          if (m['due_at'] != null) Text('Due ${text(m, 'due_at')}'),
          if (m['resolved_at'] != null)
            Text('Resolved ${text(m, 'resolved_at')}'),
          if (m['verified_at'] != null)
            Text('Verified ${text(m, 'verified_at')}'),
          const SizedBox(height: 16),
          if (permitted && next != null)
            Align(
              alignment: Alignment.centerRight,
              child: PmsButton(
                next == 'in_progress'
                    ? 'Start work'
                    : next == 'resolved'
                    ? 'Mark resolved'
                    : 'Verify',
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
    title: 'Delvane will route it.',
    eyebrow: 'REPORT ISSUE',
    width: 650,
    canClose: !busy,
    actions: [
      PmsButton(
        'Cancel',
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        'Create case',
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
            const PmsEmpty('No properties available. Reload the workspace.'),
          PmsSelect(
            'Property',
            value: property,
            items: {
              for (final p in widget.c.rows('properties'))
                text(p, 'id'): text(p, 'name'),
            },
            onChanged: busy ? null : (v) => setState(() => property = v),
          ),
          PmsField(
            'Issue',
            controller: title,
            required: true,
            hint: 'e.g. Bathroom tap leaking',
          ),
          PmsSelect(
            'Severity',
            value: severity,
            items: const {'low': 'low', 'medium': 'medium', 'high': 'high'},
            onChanged: busy ? null : (v) => setState(() => severity = v),
          ),
          PmsField(
            'Details',
            controller: detail,
            lines: 4,
            hint: 'What did you notice?',
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
    if (!c.user.isOperator) return const PmsEmpty('No access');
    final low = items.where((x) => x['low'] == true).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PmsEyebrow('SUPPLIES'),
        const Text(
          'Delvane watches consumption.',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
        ),
        Text(
          '${d['upcoming_stays'] ?? 0} upcoming stays are included in the current estimate.',
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
                    item['low'] == true ? 'RESTOCK SUGGESTED' : 'STOCK HEALTHY',
                  ),
                  Text(
                    text(item, 'name'),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${item['quantity']} ${text(item, 'unit')}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Target ${item['par_level']} · estimated upcoming use ${item['estimated_need']}',
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: stockFraction(item)),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PmsButton(
                      'Adjust stock',
                      small: true,
                      onPressed: c.saving ? null : () => adjust(context, item),
                    ),
                  ),
                ],
              ),
            ),
        ], columns: 3),
        if (items.isEmpty) const PmsEmpty('No inventory items.'),
        const SizedBox(height: 24),
        PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PmsEyebrow('SHOPPING LIST'),
              Text(
                '${low.length} items need attention',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final item in low)
                Text(
                  '${text(item, 'name')} · ${shoppingQuantity(item)} ${text(item, 'unit')}',
                ),
              if (low.isEmpty) const Text('Nothing to buy.'),
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
      () => OperationsWorkflows(
        widget.c,
      ).stock(text(widget.item, 'id'), num.parse(quantity.text)),
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: 'Adjust stock',
    eyebrow: text(widget.item, 'name'),
    width: 480,
    canClose: !busy,
    actions: [
      PmsButton(
        'Cancel',
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton('Save', primary: true, onPressed: busy ? null : save),
    ],
    child: Form(
      key: form,
      child: Column(
        children: [
          errors(),
          PmsField(
            'Current quantity',
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
