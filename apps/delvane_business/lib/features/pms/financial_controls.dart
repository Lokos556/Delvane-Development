import 'package:material_ui/material_ui.dart';

import 'actual_stay_controls.dart';
import 'ntak_reporting_dialog.dart';
import '../workspace/workspace_models.dart';
import 'pms_style.dart';
import 'pms_dialogs.dart';
import 'pms_workflows.dart';
import 'pms_controller.dart';

String financialLabel(String code) => ui(financialLabels[code] ?? code);
const financialLabels = <String, String>{
  'SZALLASDIJ': 'Accommodation charge',
  'IFA': 'Tourism tax',
  'ETEL': 'Food',
  'ALKOHOLOSITAL': 'Alcoholic beverages',
  'ALKMENTESITAL_HELYBEN': 'Locally prepared soft drinks',
  'ALKMENTESITAL_NEM_HELYBEN': 'Packaged soft drinks',
  'KOZFURDO': 'Public bath',
  'TERMESZETES_FURDO': 'Natural bathing site',
  'MUZEUM_VAR_KASTELY': 'Museum, castle or palace',
  'TURISZTIKAI_KOZLEKEDES': 'Tourist transport',
  'KALANDPARK': 'Adventure park',
  'ALLATKERT': 'Zoo',
  'VIDAMPARK': 'Amusement park',
  'VEDETT_TERMESZETI_TERULET': 'Protected natural area',
  'ZENES_TANCOS_RENDEZVENY': 'Music and dance event',
  'EGYEB': 'Other',
  'BANKKARTYA': 'Bank card',
  'KESZPENZ': 'Cash',
  'SZEP_KARTYA': 'SZ\u00c9P card',
  'ATUTALAS': 'Bank transfer',
  'UTALVANY': 'Voucher',
  'UTOLAGOS': 'Deferred payment',
  'KOKTEL': 'Cocktail',
  'LIKOR': 'Liqueur',
  'PARLAT': 'Spirits',
  'SOR': 'Beer',
  'BOR': 'Wine',
  'PEZSGO': 'Champagne',
  'ITALCSOMAG': 'Beverage package',
  'REGGELI': 'Breakfast',
  'SZENDVICS': 'Sandwich',
  'ELOETEL': 'Starter',
  'LEVES': 'Soup',
  'FOETEL': 'Main course',
  'KORET': 'Side dish',
  'SAVANYUSAG_SALATA': 'Pickles or salad',
  'KOSTOLO': 'Tasting dish',
  'PEKSUTEMENY': 'Bakery products',
  'DESSZERT': 'Dessert',
  'SNACK': 'Snack',
  'FOETEL_KORETTEL': 'Main course with side dish',
  'ETELCSOMAG': 'Food package',
  'VIZ': 'Water',
  'LIMONADE_SZORP_FACSART': 'Lemonade, syrup or fresh juice',
  'ALKOHOLMENTES_KOKTEL': 'Alcohol-free cocktail',
  'TEA_FORROCSOKOLADE': 'Tea or hot chocolate',
  'KAVE': 'Coffee',
  'ROSTOS_UDITO': 'Fruit juice',
  'SZENSAVAS_UDITO': 'Carbonated soft drink',
  'SZENSAVMENTES_UDITO': 'Still soft drink',
  'FURDO_PROGRAM': 'Spa programme',
  'STRAND_PROGRAM': 'Beach programme',
  'USZODAI_PROGRAM': 'Swimming programme',
  'WELLNESS_PROGRAM': 'Wellness programme',
  'EGESZSEGUGYI_SZOLGALTATAS': 'Health service',
  'SZABADVIZI_STRAND_PROGRAM': 'Outdoor beach programme',
  'KIALLITAS': 'Exhibition',
  'MUZEUMPEDAGOGIA': 'Museum education',
  'TARLATVEZETES': 'Guided tour',
  'EGYHAZI_LETESITMENY_LATOGATASA': 'Religious facility visit',
  'KASTELYLATOGATAS': 'Palace visit',
  'VARLATOGATAS': 'Castle visit',
  'EGYEB_MUEMLEK_LATOGATASA': 'Other monument visit',
  'OKTATASI_PROGRAM': 'Educational programme',
  'TAVI_HAJOZAS': 'Lake cruise',
  'FOLYAMI_HAJOZAS': 'River cruise',
  'HOP_ON_HOP_OFF': 'Hop-on hop-off programme',
  'KALANDPARKI_PROGRAM': 'Adventure park programme',
  'ELMENYKOZPONTI_PROGRAM': 'Experience centre programme',
  'ALLATKERTI_PROGRAM': 'Zoo programme',
  'VADASPARKI_PROGRAM': 'Wildlife park programme',
  'VIDAMPARKI_PROGRAM': 'Amusement park programme',
  'NEMZETI_PARK_LATOGATAS': 'National park visit',
  'BARLANGLATOGATAS': 'Cave visit',
  'PARKLATOGATAS': 'Park visit',
  'TEMATIKUS_BEMUTATOHELY_LATOGATAS': 'Thematic park visit',
  'TURAK_KIRANDULASOK': 'Tours and trips',
  'KULTURALIS_RENDEZVENY': 'Cultural event',
  'KONCERT': 'Concert',
  'FESZTIVAL': 'Festival',
  'SZERVIZDIJ': 'Service fee',
  'BORRAVALO': 'Tip',
  'EGYEB_VENDEGLATAS': 'Other hospitality services',
};

class FolioDialog extends StatefulWidget {
  const FolioDialog({
    super.key,
    required this.api,
    required this.reservationId,
  });
  final PmsWorkflows api;
  final String reservationId;
  @override
  State<FolioDialog> createState() => _FolioDialogState();
}

class _FolioDialogState extends State<FolioDialog>
    with PmsActions<FolioDialog> {
  Json? data;
  String get path => '/api/reservations/${widget.reservationId}/folio';
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() => perform(() async {
    final d = await widget.api.object(path);
    if (mounted) setState(() => data = d);
  });
  Future<void> edit(String kind, [Json? entry]) async {
    await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => FinancialEntryDialog(
        api: widget.api,
        path: path,
        kind: kind,
        catalog: data!,
        entry: entry,
      ),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Reservation folio'),
    width: 900,
    mobileSheet: true,
    actions: [
      PmsButton(
        ui('Close'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        Text(
          ui(
            'Records only: no payment is collected and no legal invoice is issued.',
          ),
        ),
        if (data != null) ...[
          if (data!['managed'] != true)
            Text(
              ui(
                'The quoted booking amount is retained separately. The first posting activates the itemized ledger; enter all applicable charges.',
              ),
            ),
          for (final k in ['charges', 'payments', 'refunds', 'balance'])
            Text('${ui(k)}: ${data!['totals'][k]} HUF'),
          Wrap(
            spacing: 8,
            children: [
              PmsButton(
                ui('Add charge'),
                onPressed: busy ? null : () => edit('charge'),
              ),
              PmsButton(
                ui('Record payment'),
                onPressed: busy ? null : () => edit('payment'),
              ),
            ],
          ),
          for (final e in optionalRows(data!['entries']))
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e['description']} \u00b7 ${e['total_huf']} HUF'),
                  Text('${ui('Business date')}: ${e['business_date']}'),
                  Text(
                    e['kind'] == 'charge'
                        ? '${financialLabel('${e['category']}')} \u00b7 ${e['vat']}% \u00b7 ${ui(e['in_package'] == 1 ? 'Included in package' : 'Outside package')}'
                        : financialLabel('${e['payment_method']}'),
                  ),
                  PmsButton(
                    ui('Correct entry'),
                    onPressed: busy ? null : () => edit('${e['kind']}', e),
                  ),
                ],
              ),
            ),
          ExpansionTile(
            title: Text(ui('Financial history')),
            children: [
              for (final e in optionalRows(data!['history']))
                ListTile(
                  title: Text(
                    '${e['description']} \u00b7 ${e['total_huf']} HUF',
                  ),
                  subtitle: Text(
                    '${e['business_date']} \u00b7 ${e['posted_at']}\n${e['reason']}',
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class FinancialEntryDialog extends StatefulWidget {
  const FinancialEntryDialog({
    super.key,
    required this.api,
    required this.path,
    required this.kind,
    required this.catalog,
    this.entry,
  });
  final PmsWorkflows api;
  final String path, kind;
  final Json catalog;
  final Json? entry;
  @override
  State<FinancialEntryDialog> createState() => _FinancialEntryDialogState();
}

class _FinancialEntryDialogState extends State<FinancialEntryDialog>
    with PmsActions<FinancialEntryDialog> {
  final form = GlobalKey<FormState>();
  final requestId = stayRequestId();
  final fields = <String, TextEditingController>{};
  String category = 'SZALLASDIJ',
      subcategory = '',
      vat = '5',
      method = 'KESZPENZ',
      direction = 'payment',
      unit = '',
      guest = '',
      refundOf = '';
  bool package = true, voided = false;
  List<Json> units = [], guests = [];
  bool get charge => widget.kind == 'charge';
  @override
  void initState() {
    super.initState();
    final e = widget.entry ?? {};
    for (final k in [
      'description',
      'quantity',
      'unit_price',
      'business_date',
      'currency',
      'exchange_rate',
      'exchange_evidence',
      'document_date',
      'reason',
    ]) {
      fields[k] = TextEditingController(
        text:
            '${e[k] ?? switch (k) {
                  'quantity' || 'exchange_rate' => '1',
                  'currency' => 'HUF',
                  'business_date' => '${widget.catalog['business_date'] ?? DateTime.now().toIso8601String().substring(0, 10)}',
                  _ => '',
                }}',
      );
    }
    category = '${e['category'] ?? category}';
    subcategory = '${e['subcategory'] ?? ''}';
    vat = '${e['vat'] ?? vat}';
    method = '${e['payment_method'] ?? method}';
    direction = '${e['direction'] ?? direction}';
    package = e.isEmpty ? true : e['in_package'] == 1;
    unit = '${e['unit_id'] ?? ''}';
    guest = '${e['guest_id'] ?? ''}';
    refundOf = '${e['refund_of'] ?? ''}';
    if (widget.path.endsWith('/folio')) {
      perform(() async {
        final d = await widget.api.object(
          widget.path.replaceFirst('/folio', '/actual-stay'),
        );
        if (mounted) {
          setState(() {
            units = optionalRows(d['planned_allocations']);
            guests = optionalRows(d['guests']);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> options(Iterable<String> values) => {
    for (final v in values) v: financialLabel(v),
  };
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (widget.entry != null &&
        !await pmsConfirm(
          context,
          ui('Correct financial history'),
          ui(
            'The original entry remains in history. A closed business day will require a new reporting revision.',
          ),
        )) {
      return;
    }
    final ok = await perform(() async {
      await widget.api.change('POST', widget.path, {
        'request_id': requestId,
        'kind': widget.kind,
        for (final k in fields.keys)
          if (k != 'document_date' || fields[k]!.text.isNotEmpty)
            k: fields[k]!.text,
        'unit_id': unit.isEmpty ? null : unit,
        'guest_id': guest.isEmpty ? null : guest,
        'supersedes': widget.entry?['id'],
        'voided': voided,
        if (charge) ...{
          'category': category,
          'subcategory': subcategory.isEmpty ? null : subcategory,
          'vat': vat,
          'in_package': package,
        } else ...{
          'payment_method': method,
          'payment_subtype': method == 'SZEP_KARTYA' ? 'SZALLASHELY' : null,
          'direction': direction,
          'refund_of': direction == 'refund' && refundOf.isNotEmpty
              ? refundOf
              : null,
        },
      });
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cats = jsonObject(widget.catalog['categories']);
    return PmsModal(
      title: ui(
        widget.entry != null
            ? 'Correct entry'
            : charge
            ? 'Add charge'
            : 'Record payment',
      ),
      width: 650,
      mobileSheet: true,
      actions: [
        PmsButton(
          ui('Close'),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        PmsButton(
          ui('Save entry'),
          primary: true,
          onPressed: busy ? null : save,
        ),
      ],
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            errors(),
            Text(
              ui(
                'Records only: no payment is collected and no legal invoice is issued.',
              ),
            ),
            for (final pair in {
              'description': 'Description',
              'business_date': 'Business date',
              'unit_price': charge ? 'Unit price' : 'Amount',
              'quantity': 'Quantity',
              'currency': 'Currency',
              'exchange_rate': 'HUF exchange rate',
              'exchange_evidence': 'Exchange rate evidence',
              'document_date': 'Invoice issue date (post-stay payments)',
              'reason': 'Reason',
            }.entries)
              if (charge || pair.key != 'quantity')
                PmsField(
                  pair.value,
                  controller: fields[pair.key]!,
                  required: [
                    'description',
                    'business_date',
                    'unit_price',
                    'reason',
                  ].contains(pair.key),
                ),
            if (charge) ...[
              PmsSelect(
                'Charge category',
                value: category,
                items: options(cats.keys),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        category = v;
                        subcategory = (cats[v] as List).isEmpty
                            ? ''
                            : '${(cats[v] as List).first}';
                        package = v == 'SZALLASDIJ';
                        if (v == 'IFA') vat = '0';
                      }),
              ),
              if ((cats[category] as List? ?? []).isNotEmpty)
                PmsSelect(
                  'Charge subcategory',
                  value: subcategory,
                  items: options((cats[category] as List).map((v) => '$v')),
                  onChanged: (v) => setState(() => subcategory = v),
                ),
              PmsSelect(
                'VAT rate',
                value: vat,
                items: {
                  for (final v in widget.catalog['vat_rates'] as List)
                    '$v': '$v%',
                },
                onChanged: (v) => setState(() => vat = v),
              ),
              SwitchListTile(
                title: Text(ui('Included in package')),
                value: package,
                onChanged: (v) => setState(() => package = v),
              ),
            ] else ...[
              PmsSelect(
                'Payment method',
                value: method,
                items: options(
                  (widget.catalog['payment_methods'] as List).map((v) => '$v'),
                ),
                onChanged: (v) => setState(() => method = v),
              ),
              PmsSelect(
                'Payment or refund',
                value: direction,
                items: {'payment': ui('Payment'), 'refund': ui('Refund')},
                onChanged: (v) => setState(() => direction = v),
              ),
              if (direction == 'refund')
                PmsSelect(
                  'Original payment',
                  value: refundOf,
                  items: {
                    '': ui('Choose original payment'),
                    for (final e in optionalRows(widget.catalog['entries']))
                      if (e['kind'] == 'payment' && e['direction'] == 'payment')
                        '${e['root_id'] ?? e['id']}':
                            '${e['description']} - ${e['total_huf']} HUF',
                  },
                  onChanged: (v) => setState(() => refundOf = v),
                ),
            ],
            PmsSelect(
              'Physical unit',
              value: unit,
              items: {
                '': ui('Unassigned'),
                for (final u in units)
                  '${u['unit_id']}': '${u['unit_number'] ?? u['unit_id']}',
              },
              onChanged: (v) => setState(() => unit = v),
            ),
            PmsSelect(
              'Guest',
              value: guest,
              items: {
                '': ui('All guests'),
                for (final g in guests)
                  '${g['id']}': '${g['full_name'] ?? g['id']}',
              },
              onChanged: (v) => setState(() => guest = v),
            ),
            if (widget.entry != null)
              SwitchListTile(
                title: Text(ui('Reverse this entry')),
                value: voided,
                onChanged: (v) => setState(() => voided = v),
              ),
          ],
        ),
      ),
    );
  }
}

class PropertyFinanceDialog extends StatefulWidget {
  const PropertyFinanceDialog({
    super.key,
    required this.api,
    required this.propertyId,
    required this.businessDate,
  });
  final PmsWorkflows api;
  final String propertyId, businessDate;
  @override
  State<PropertyFinanceDialog> createState() => _PropertyFinanceDialogState();
}

class _PropertyFinanceDialogState extends State<PropertyFinanceDialog>
    with PmsActions<PropertyFinanceDialog> {
  Json? data;
  String get path => '/api/properties/${widget.propertyId}/financial-entries';
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() => perform(() async {
    final d = await widget.api.object(
      '$path?business_date=${widget.businessDate}',
    );
    if (mounted) {
      setState(() => data = d);
    }
  });
  Future<void> edit(Json e) async {
    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) => FinancialEntryDialog(
        api: widget.api,
        path: path,
        kind: '${e['kind']}',
        catalog: data!,
        entry: e,
      ),
    );
    if (mounted) {
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Other financial entries'),
    width: 800,
    mobileSheet: true,
    actions: [
      PmsButton(
        ui('Close'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        Text('${ui('Business date')}: ${widget.businessDate}'),
        if (data != null) ...[
          for (final e in optionalRows(data!['entries']))
            ListTile(
              title: Text('${e['description']} - ${e['total_huf']} HUF'),
              subtitle: Text('${e['business_date']}'),
              trailing: PmsButton(
                ui('Correct entry'),
                onPressed: busy ? null : () => edit(e),
              ),
            ),
          ExpansionTile(
            title: Text(ui('Financial history')),
            children: [
              for (final e in optionalRows(data!['history']))
                ListTile(
                  title: Text('${e['description']} - ${e['total_huf']} HUF'),
                  subtitle: Text('${e['posted_at']} - ${e['reason']}'),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class BusinessClosingPanel extends StatefulWidget {
  const BusinessClosingPanel({super.key, required this.c});
  final PmsController c;
  @override
  State<BusinessClosingPanel> createState() => _BusinessClosingPanelState();
}

class _BusinessClosingPanelState extends State<BusinessClosingPanel>
    with PmsActions<BusinessClosingPanel> {
  List<Json> properties = [];
  Future<void> refresh() => perform(() async {
    final result = await PmsWorkflows(widget.c).rows('/api/properties');
    if (mounted) {
      setState(() => properties = result);
    }
  });
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(ui('Daily closing and finances')),
    onExpansionChanged: (open) {
      if (open) {
        refresh();
      }
    },
    children: [
      errors(),
      for (final p in properties)
        ListTile(
          title: Text('${p['name']}'),
          trailing: PmsButton(
            ui('Open daily closing'),
            onPressed: busy
                ? null
                : () => showDialog(
                    context: context,
                    useRootNavigator: false,
                    builder: (_) => BusinessDayDialog(
                      api: PmsWorkflows(widget.c),
                      propertyId: '${p['id']}',
                    ),
                  ),
          ),
        ),
    ],
  );
}

class BusinessDayDialog extends StatefulWidget {
  const BusinessDayDialog({
    super.key,
    required this.api,
    required this.propertyId,
  });
  final PmsWorkflows api;
  final String propertyId;
  @override
  State<BusinessDayDialog> createState() => _BusinessDayDialogState();
}

class _BusinessDayDialogState extends State<BusinessDayDialog>
    with PmsActions<BusinessDayDialog> {
  final day = TextEditingController(
    text: DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10),
  );
  final start = TextEditingController();
  final zone = TextEditingController(text: 'Europe/Budapest');
  final hour = TextEditingController(text: '10');
  final reason = TextEditingController();
  final tax = TextEditingController(text: '400');
  Json? data;
  bool operating = true, automatic = false;
  String correction = 'TERHELES_VAGY_KOLTES_JAV', taxType = 'TETELES';
  String get base => '/api/properties/${widget.propertyId}';
  String get path => '$base/business-days/${day.text}';
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    for (final c in [day, start, zone, hour, reason, tax]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> other(String kind) async {
    Json? catalog;
    final ok = await perform(() async {
      catalog = await widget.api.object(
        '$base/financial-entries?business_date=${day.text}',
      );
    });
    if (!ok || !mounted) {
      return;
    }
    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) => FinancialEntryDialog(
        api: widget.api,
        path: '$base/financial-entries',
        kind: kind,
        catalog: catalog!,
      ),
    );
    if (mounted) {
      refresh();
    }
  }

  Future<void> refresh() => perform(() async {
    final d = await widget.api.object(path);
    if (mounted) {
      setState(() {
        data = d;
        operating = jsonObject(d['day'])['operating'] != 0;
        final cfg = jsonObject(d['settings']);
        if (cfg.isNotEmpty) {
          start.text = '${cfg['start_date']}';
          zone.text = '${cfg['timezone']}';
          hour.text = '${cfg['closing_hour']}';
          automatic = cfg['automatic'] == 1;
        }
      });
    }
  });
  Future<void> change(String method, String target, Json body) async {
    final ok = await perform(() async {
      await widget.api.change(method, target, body);
    });
    if (ok && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Business day closing'),
    width: 780,
    mobileSheet: true,
    actions: [
      PmsButton(
        ui('Close'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        PmsField('Business date', controller: day, required: true),
        PmsButton(ui('Load business day'), onPressed: busy ? null : refresh),
        PmsField('Reason', controller: reason, required: true),
        ExpansionTile(
          title: Text(ui('Operating calendar settings')),
          children: [
            PmsField('First business date', controller: start, required: true),
            PmsField('Property timezone', controller: zone, required: true),
            PmsField('Automatic closing hour', controller: hour),
            SwitchListTile(
              title: Text(ui('Enable automatic closing')),
              subtitle: Text(
                ui(
                  'Only confirmed, consistent past days close automatically. Historical corrections require review.',
                ),
              ),
              value: automatic,
              onChanged: (v) => setState(() => automatic = v),
            ),
            PmsButton(
              ui('Save calendar'),
              onPressed: busy
                  ? null
                  : () => change('PUT', '$base/business-calendar', {
                      'start_date': start.text,
                      'timezone': zone.text,
                      'automatic': automatic,
                      'closing_hour': int.tryParse(hour.text),
                      'reason': reason.text,
                    }),
            ),
          ],
        ),
        SwitchListTile(
          title: Text(ui('Property operating on this date')),
          value: operating,
          onChanged: (v) => setState(() => operating = v),
        ),
        PmsButton(
          ui('Confirm operating state'),
          onPressed: busy
              ? null
              : () => change('PUT', path, {
                  'operating': operating,
                  'reason': reason.text,
                }),
        ),
        ExpansionTile(
          title: Text(ui('Effective tourism tax')),
          children: [
            PmsSelect(
              'Tourism tax type',
              value: taxType,
              items: {
                'TETELES': ui('Fixed amount'),
                'SZAZALEKOS': ui('Percentage'),
                'NINCS': ui('No tourism tax'),
              },
              onChanged: (v) => setState(() => taxType = v),
            ),
            PmsField('Tax rate', controller: tax),
            PmsButton(
              ui('Save effective tax rate'),
              onPressed: busy
                  ? null
                  : () => change('PUT', '$base/ifa-rates', {
                      'effective_from': day.text,
                      'tax_type': taxType,
                      'rate': tax.text,
                      'reason': reason.text,
                    }),
            ),
          ],
        ),
        if (data != null) ...[
          Wrap(
            spacing: 8,
            children: [
              PmsButton(
                ui('Add other charge'),
                onPressed: busy ? null : () => other('charge'),
              ),
              PmsButton(
                ui('Record other payment'),
                onPressed: busy ? null : () => other('payment'),
              ),
            ],
          ),
          if (jsonObject(data!['day'])['dirty'] == 1)
            Text(
              ui(
                'Historical sources changed; review and save a new full revision.',
              ),
            ),
          PmsButton(
            ui('Review other financial entries'),
            onPressed: busy
                ? null
                : () async {
                    await showDialog(
                      context: context,
                      useRootNavigator: false,
                      builder: (_) => PropertyFinanceDialog(
                        api: widget.api,
                        propertyId: widget.propertyId,
                        businessDate: day.text,
                      ),
                    );
                    if (mounted) {
                      refresh();
                    }
                  },
          ),
          Text(
            '${ui('Guest nights')}: ${data!['guest_nights']} \u00b7 ${ui('Sold units')}: ${data!['sold_units']}',
          ),
          for (final k in ['charges', 'payments', 'refunds', 'balance'])
            Text('${ui(k)}: ${data!['totals'][k]} HUF'),
          for (final b in data!['blockers'] as List? ?? [])
            Text(
              ui(
                closingMessages['$b'] ??
                    'Review the missing operational facts before closing.',
              ),
            ),
          PmsSelect(
            'Correction reason',
            value: correction,
            items: {
              for (final r in data!['correction_reasons'] as List? ?? [])
                '$r': ui(correctionLabels['$r'] ?? 'Other'),
            },
            onChanged: (v) => setState(() => correction = v),
          ),
          PmsButton(
            ui('Close or revise business day'),
            primary: true,
            onPressed: busy
                ? null
                : () async {
                    if (await pmsConfirm(
                      context,
                      ui('Confirm daily closing'),
                      ui(
                        'Save a complete historical snapshot for the selected business date. Reporting may remain blocked.',
                      ),
                    )) {
                      change('POST', '$path/close', {
                        'reason': reason.text,
                        'correction_reason': correction,
                      });
                    }
                  },
          ),
          PmsButton(
            ui('Recheck saved reporting prerequisites'),
            onPressed: busy
                ? null
                : () => change('POST', '$path/reporting-recovery', {}),
          ),
          for (final s in optionalRows(data!['snapshots']))
            ListTile(
              title: Text(
                '${ui('Revision')} ${s['revision']} \u00b7 ${s['business_date']}',
              ),
              subtitle: Text(
                '${ui('Reporting status')}: ${ntakState(s['reporting_state'] as String?)}\n${ui(correctionLabels['${s['correction_reason']}'] ?? 'Initial daily report')}\n${s['blocker'] == null ? (s['error_code'] == null ? '' : ntakProblem(s['error_code'] as String?)) : closingReportingProblem(s['blocker'] as String?)}',
              ),
            ),
        ],
      ],
    ),
  );
}

const correctionLabels = {
  'VENDEG_VAGY_IFA_JAVITAS': 'Guest or tourism tax correction',
  'SZOBA_VAGY_FEROHELY_MOD': 'Unit or capacity correction',
  'TERHELES_VAGY_KOLTES_JAV': 'Charge or payment correction',
  'SZAMLAMODOSITAS': 'Invoice correction',
  'TECH_HIBA_ADATJAVITAS': 'Technical data correction',
  'ELLENORZES_ELTERES_JAV': 'Inspection discrepancy correction',
  'ELOZO_BEKULDES_NEM_TELJES': 'Incomplete previous submission',
  'EGYEB': 'Other',
};
const closingMessages = {
  'operating_calendar_not_configured':
      'Configure the operating calendar first.',
  'operating_day_not_confirmed':
      'Confirm whether the property operated on this date.',
  'physical_inventory_missing': 'Configure the physical accommodation units.',
  'physical_inventory_reconciliation_required':
      'Reconcile physical units with room-type inventory.',
  'planned_stay_requires_actual_review':
      'Review expected stays and record actual arrivals or cancellations.',
  'reservation_folio_not_itemized':
      'Complete the itemized folios for actual stays.',
  'effective_ifa_rate_missing': 'Confirm the effective tourism tax rate.',
  'closed_property_has_activity':
      'A closed property day contains actual stays or financial activity.',
  'missing_guest_reporting_profile': 'Complete the effective guest residence and tax profile. The actual event is saved.',
};

String closingReportingProblem(String? code) => ui(switch (code) {
  'identity_normalization_unresolved' => 'Guest identity normalization needs official clarification. The closed day is saved.',
  'prior_closing_outcome_pending' =>
    'Wait for the original report processing outcome. The correction is saved.',
  'financial_unit_assignment_required' => 'Assign financial entries to the correct physical unit, then revise the day.',
  'refund_requires_original_day_correction' ||
  'refund_original_day_revision_required' => 'Link the refund to its original payment and revise the original business day.',
  'reporting_not_enabled' =>
    'Local reporting is not enabled. The closed day is saved.',
  _ => 'Reporting is blocked. Review the source facts and reporting prerequisites.',
});
