import 'package:intl/date_symbol_data_local.dart';

import 'guest_link_picker.dart';
import 'cancellation_dialog.dart';

import 'package:intl/intl.dart';

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';
import 'guest_history_dialog.dart';

List<String> reservationRequests(Object? value) {
  final decoded = value is String
      ? jsonDecode(value.isEmpty ? '[]' : value)
      : value;
  return decoded is List ? decoded.map((v) => v.toString()).toList() : [];
}

class ReservationEditor extends StatefulWidget {
  const ReservationEditor({
    super.key,
    required this.api,
    this.reservation,
    this.initialDate,
  });
  final PmsWorkflows api;
  final Json? reservation;
  final String? initialDate;
  @override
  State<ReservationEditor> createState() => _ReservationEditorState();
}

class _ReservationEditorState extends State<ReservationEditor>
    with PmsActions<ReservationEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  List<Json> properties = [], rooms = [];
  String property = '', room = '', source = 'Direct';
  String? selectedGuestId;
  bool loading = true, roomLoading = false;
  int request = 0;
  bool get editing => widget.reservation != null;
  String t(String s) => widget.api.controller.t(s);
  @override
  void initState() {
    super.initState();
    final r = widget.reservation ?? {};
    final start =
        DateTime.tryParse(widget.initialDate ?? '') ??
        DateTime.now().add(const Duration(days: 1));
    for (final key in [
      'guest_name',
      'arrival_date',
      'departure_date',
      'guest_count',
      'arrival_time',
      'total_huf',
      'external_ref',
      'special_requests',
    ]) {
      fields[key] = TextEditingController(
        text: key == 'special_requests'
            ? reservationRequests(r[key]).join(', ')
            : text(r, key),
      );
    }
    if (!editing) {
      fields['arrival_date']!.text = isoDate(start);
      fields['departure_date']!.text = isoDate(
        start.add(const Duration(days: 3)),
      );
      fields['guest_count']!.text = '2';
    }
    source = text(r, 'source', 'Direct');
    property = text(r, 'property_id');
    room = text(r, 'room_type_id');
    load();
  }

  Future<void> load() async {
    final ok = await perform(() async {
      properties = await widget.api.rows('/api/properties');
      if (property.isEmpty && properties.isNotEmpty) {
        property = text(properties.first, 'id');
      }
      if (property.isNotEmpty) rooms = await widget.api.rooms(property);
      if (!rooms.any((r) => r['id'] == room)) {
        room = rooms.isEmpty ? '' : text(rooms.first, 'id');
      }
      loading = false;
    });
    if (!ok && mounted) setState(() => loading = true);
  }

  Future<void> changeProperty(String value) async {
    final generation = ++request;
    setState(() {
      property = value;
      roomLoading = true;
      failure = null;
      rooms = [];
      room = '';
    });
    try {
      final list = await widget.api.rooms(value);
      if (!mounted || generation != request) return;
      setState(() {
        rooms = list;
        room = list.isEmpty ? '' : text(list.first, 'id');
        roomLoading = false;
      });
    } catch (e) {
      if (mounted && generation == request) {
        setState(() {
          failure = workflowError(e);
          roomLoading = true;
        });
      }
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final body = <String, dynamic>{
      if (selectedGuestId != null) 'guest_id': selectedGuestId,
      'property_id': property,
      'room_type_id': room.isEmpty ? null : room,
      'source': source,
      'guest_name': fields['guest_name']!.text.trim(),
      'arrival_date': fields['arrival_date']!.text,
      'departure_date': fields['departure_date']!.text,
      'guest_count': int.parse(fields['guest_count']!.text),
      'arrival_time': fields['arrival_time']!.text.isEmpty
          ? null
          : fields['arrival_time']!.text,
      'total_huf': fields['total_huf']!.text.isEmpty
          ? null
          : int.parse(fields['total_huf']!.text),
      'external_ref': fields['external_ref']!.text.isEmpty
          ? null
          : fields['external_ref']!.text,
      'special_requests': fields['special_requests']!.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    };
    final ok = await perform(() async {
      await widget.api.save(
        body,
        id: editing ? text(widget.reservation!, 'id') : null,
      );
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => CancellationDialog(
        api: widget.api,
        id: text(widget.reservation!, 'id'),
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    ++request;
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(fields['arrival_date']!.text),
        end = DateTime.tryParse(fields['departure_date']!.text);
    final nights = start == null || end == null
        ? 0
        : end.difference(start).inDays;
    final selected = rooms.where((r) => r['id'] == room).firstOrNull;
    return PopScope(
      canPop: !busy,
      child: PmsModal(
        title: editing
            ? text(widget.reservation!, 'guest_name')
            : t('Add a stay'),
        eyebrow: editing ? ui('RESERVATION') : ui('NEW RESERVATION'),
        width: 760,
        canClose: !busy,
        actions: [
          if (editing && widget.reservation!['status'] == 'inquiry')
            PmsButton(
              t('Confirm booking'),
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await perform(() async {
                        await widget.api.confirm(
                          text(widget.reservation!, 'id'),
                        );
                      });
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
            ),
          if (editing)
            PmsButton(
              t('Cancel reservation'),
              danger: true,
              onPressed: busy ? null : cancel,
            ),
          PmsButton(
            t('Close'),
            onPressed: busy ? null : () => Navigator.pop(context),
          ),
          PmsButton(
            t(editing ? 'Save changes' : 'Create reservation'),
            primary: true,
            onPressed: busy || loading || roomLoading || property.isEmpty
                ? null
                : save,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            errors(),
            PmsButton(
              ui('Link returning guest'),
              onPressed: busy
                  ? null
                  : () async {
                      final guest = await showDialog<Json>(
                        context: context,
                        useRootNavigator: false,
                        builder: (_) => GuestLinkPicker(api: widget.api),
                      );
                      if (guest != null && mounted) {
                        setState(() {
                          selectedGuestId = text(guest, 'id');
                          fields['guest_name']!.text = text(guest, 'full_name');
                        });
                      }
                    },
            ),
            if (loading) ...[
              if (!busy) PmsButton(ui('Retry'), onPressed: load),
            ] else
              AbsorbPointer(
                absorbing: busy,
                child: PmsForm(
                  formKey: form,
                  child: Column(
                    children: [
                      PmsColumns([
                        PmsSelect(
                          t('Property'),
                          required: true,
                          value: property,
                          items: {
                            for (final p in properties)
                              text(p, 'id'): text(p, 'name'),
                          },
                          onChanged: changeProperty,
                        ),
                        PmsSelect(
                          t('Room type'),
                          value: room,
                          items: {
                            for (final r in rooms)
                              text(
                                r,
                                'id',
                              ): '${text(r, 'name')} · inventory ${r['inventory_count']} units',
                          },
                          onChanged: roomLoading
                              ? null
                              : (v) => setState(() => room = v),
                        ),
                      ], columns: 2),
                      if (roomLoading)
                        PmsButton(
                          ui('Retry room types'),
                          onPressed: () => changeProperty(property),
                        ),
                      PmsSelect(
                        t('Source'),
                        value: source,
                        items: {
                          for (final v in {
                            'Direct',
                            'Booking.com',
                            'Szallas.hu',
                            source,
                          })
                            v: v,
                        },
                        onChanged: (v) => setState(() => source = v),
                      ),
                      PmsField(
                        t('Guest name'),
                        controller: fields['guest_name']!,
                        status: failureField == 'guest_name' ? failure : null,
                        required: true,
                      ),
                      PmsColumns([
                        PmsDateField(
                          t('Arrival'),
                          controller: fields['arrival_date']!,
                          onChanged: (_) => setState(() {}),
                        ),
                        PmsDateField(
                          t('Departure / checkout'),
                          controller: fields['departure_date']!,
                          onChanged: (_) => setState(() {}),
                        ),
                      ], columns: 2),
                      PmsCard(
                        child: Text(
                          nights > 0
                              ? ui(
                                  '$nights nights. Occupied nights: ${fields['arrival_date']!.text} through ${isoDate(end!.subtract(const Duration(days: 1)))}. Checkout: ${fields['departure_date']!.text}; that night remains available.',
                                )
                              : ui(
                                  'Choose a valid stay. Departure must be after arrival.',
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      PmsColumns([
                        PmsField(
                          t('Guests'),
                          controller: fields['guest_count']!,
                          required: true,
                          status: failureField == 'guest_count'
                              ? failure
                              : null,
                          keyboard: TextInputType.number,
                          validator: (v) =>
                              int.tryParse(v ?? '') != null &&
                                  int.parse(v!) >= 1
                              ? null
                              : 'Enter a positive whole guest count.',
                        ),
                        PmsField(
                          t('Guest arrival time'),
                          controller: fields['arrival_time']!,
                          hint: ui('HH:MM'),
                          validator: optionalTime,
                        ),
                        PmsField(
                          t('Total reservation value (HUF)'),
                          controller: fields['total_huf']!,
                          hint: ui('Optional — not the nightly rate'),
                          keyboard: TextInputType.number,
                          validator: (v) =>
                              v == null ||
                                  v.isEmpty ||
                                  (int.tryParse(v) != null && int.parse(v) >= 0)
                              ? null
                              : 'Enter a non-negative whole HUF amount.',
                        ),
                        PmsField(
                          t('Reference'),
                          controller: fields['external_ref']!,
                          hint: ui('Optional'),
                        ),
                      ], columns: 2),
                      PmsField(
                        t('Special preparation'),
                        controller: fields['special_requests']!,
                        hint: ui('High chair, baby cot, extra towels'),
                      ),
                      if (selected != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            ui(
                              'Room capacity: ${selected['max_guests']}. Rate plans are informational; reservation value is entered above.',
                            ),
                          ),
                        ),
                      if (selected != null)
                        for (final plan in optionalRows(selected['rate_plans']))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(text(plan, 'name')),
                            subtitle: Text(
                              ui(
                                'Base rate: ${text(plan, 'base_rate_huf', 'Not configured')} HUF · ${text(plan, 'cancellation_policy')}',
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReservationWorkspace extends StatefulWidget {
  const ReservationWorkspace({
    super.key,
    required this.api,
    required this.id,
    required this.openReception,
    this.openTask,
  });
  final PmsWorkflows api;
  final String id;
  final VoidCallback openReception;
  final ValueChanged<String>? openTask;
  @override
  State<ReservationWorkspace> createState() => _ReservationWorkspaceState();
}

class _ReservationWorkspaceState extends State<ReservationWorkspace>
    with PmsActions<ReservationWorkspace> {
  Json? data, delivery;
  String? deliveryError;
  int tab = 0;
  bool changed = false;
  final arrival = TextEditingController(), note = TextEditingController();
  String payment = 'unknown', registration = 'incomplete';
  String get path => '/api/reservations/${idPath(widget.id)}';
  String t(String s) => widget.api.controller.t(s);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await perform(() async {
      await initializeDateFormatting('hu');
      final result = await widget.api.detail(widget.id);
      final r = jsonObject(result['reservation']);
      if (!mounted) return;
      setState(() {
        data = result;
        arrival.text = text(r, 'arrival_time');
        payment = text(r, 'payment_status', 'unknown');
        registration = text(r, 'registration_status', 'incomplete');
      });
    });
    await loadDelivery();
  }

  Future<void> loadDelivery() async {
    try {
      final result = await widget.api.object(
        '$path/channex-availability-delivery',
      );
      if (mounted) {
        setState(() {
          delivery = result;
          deliveryError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => deliveryError = workflowError(e));
    }
  }

  Future<void> mutate(Future<void> Function() action) async {
    if (await perform(action)) {
      changed = true;
      await load();
    }
  }

  Future<void> saveOperations() async {
    final invalid = optionalTime(arrival.text);
    if (invalid != null) {
      setState(() => failure = invalid);
      return;
    }
    await mutate(() async {
      await widget.api.operations(widget.id, {
        'arrival_time': arrival.text,
        'payment_status': payment,
      });
    });
  }

  @override
  void dispose() {
    arrival.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = data == null
        ? <String, dynamic>{}
        : jsonObject(data!['reservation']);
    final reg = optionalRows(data?['registration']);
    return PopScope(
      canPop: !busy,
      child: PmsModal(
        title: text(r, 'guest_name', 'Reservation'),
        titleSize: MediaQuery.sizeOf(context).width <= 760 ? 18 : 22,
        mobileSheet: true,
        eyebrow: text(r, 'source'),
        canClose: !busy,
        width: 1040,
        headerActions: [
          if (data != null)
            PmsButton(
              t('Edit booking'),
              onPressed: busy
                  ? null
                  : () async {
                      final result = await showDialog<bool>(
                        useRootNavigator: false,
                        context: context,
                        barrierDismissible: false,
                        builder: (_) =>
                            ReservationEditor(api: widget.api, reservation: r),
                      );
                      if (result == true) {
                        changed = true;
                        await load();
                      }
                    },
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            errors(),
            if (data == null && !busy) PmsButton(ui('Retry'), onPressed: load),
            if (data != null) ...[
              PmsCard(
                padding: const EdgeInsets.all(14),
                color: const Color(0xB3FFFFFF),
                shadow: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        for (final item in [
                          ('Check-in', 'arrival_date'),
                          ('Checkout', 'departure_date'),
                        ])
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t(item.$1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  DateFormat.yMMMd(
                                    WebStrings.current.language == 'hu'
                                        ? 'hu'
                                        : 'en',
                                  ).format(DateTime.parse(text(r, item.$2))),
                                  style: TextStyle(
                                    fontSize:
                                        MediaQuery.sizeOf(context).width <= 760
                                        ? 22
                                        : 32,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(text(r, 'property_name')),
                    PmsBadge(text(r, 'status')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PmsTabs(
                labels: [
                  t('Stay overview'),
                  t('Preparation'),
                  t('Communication'),
                  t('Activity'),
                ],
                selected: tab,
                onChanged: busy ? (_) {} : (v) => setState(() => tab = v),
              ),
              const SizedBox(height: 12),
              PmsColumns(
                [
                  stat(
                    'Payment',
                    payment,
                    '${uiDecimal(text(r, 'total_huf', '—'))} Ft',
                  ),
                  stat(
                    'Registration',
                    registration,
                    '${reg.isEmpty && registration == 'complete' ? r['guest_count'] : reg.where((g) => g['completeness'] == 'complete').length}/${reg.length > (r['guest_count'] as int? ?? 0) ? reg.length : r['guest_count']}',
                  ),
                  stat(
                    'Arrival time',
                    text(r, 'arrival_time', text(r, 'checkin_time')),
                    text(r, 'property_name'),
                  ),
                  stat('Guest', text(r, 'guest_count'), ''),
                ],
                columns: 4,
                mobileColumns: 2,
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 18),
              if (tab == 0) overview(r),
              if (tab == 1) preparation(r, reg),
              if (tab == 2) communications(),
              if (tab == 3) activity(),
            ],
          ],
        ),
      ),
    );
  }

  Widget stat(String title, String value, String small) => PmsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(title),
          style: const TextStyle(fontSize: 11, color: PmsStyle.muted),
        ),
        Text(
          uiFieldValue(title, value),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(small, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
  Widget overview(Json r) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PmsColumns([
        PmsCard(
          child: PmsKeyValues({
            'Property': text(r, 'property_name'),
            'Address': text(r, 'address'),
            'Check-in': text(r, 'checkin_time'),
            'Checkout': text(r, 'checkout_time'),
            'Special requests': reservationRequests(r['special_requests'])
                .join(' · '),
          }),
        ),
        guestContext(),
        PmsCard(
          child: Column(
            children: [
              PmsEyebrow(t('Preparation')),
              PmsField(
                t('Arrival time'),
                controller: arrival,
                hint: ui('HH:MM'),
              ),
              PmsSelect(
                t('Payment'),
                value: payment,
                items: {
                  for (final v in [
                    'unknown',
                    'unpaid',
                    'partial',
                    'paid',
                    'refunded',
                  ])
                    v: t(v),
                },
                onChanged: busy ? null : (v) => setState(() => payment = v),
              ),
              Text('${t('Registration')}: ${t(registration)}'),
              Text(ui('Registration follows guest data and identity review.')),
              PmsButton(
                t('Save'),
                primary: true,
                onPressed: busy ? null : saveOperations,
              ),
            ],
          ),
        ),
      ]),
      const SizedBox(height: 18),
      distribution(),
    ],
  );
  Widget guestContext() {
    final gp = data?['guest_profile'];
    if (gp is! Json) {
      return PmsCard(
        child: Column(
          children: [PmsEyebrow(ui('GUEST CONTEXT')), PmsEmpty('\u2014')],
        ),
      );
    }
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PmsEyebrow(ui('GUEST CONTEXT')),
          Text(
            text(gp, 'full_name'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(ui('${ui('Language')}: ${text(gp, 'preferred_language', '—')}')),
          GuestHistorySummary(summary: optionalObject(gp['history_summary'])),
          for (final pref in optionalRows(gp['preferences']).take(4))
            Text(
              '${text(pref, 'preference_key')} · ${text(pref, 'preference_value')}',
            ),
          PmsButton(
            t('View guest history'),
            onPressed: () => guestHistory(text(gp, 'id')),
          ),
        ],
      ),
    );
  }

  Future<void> guestHistory(String id) async {
    await showDialog<void>(
      useRootNavigator: false,
      context: context,
      builder: (_) => GuestHistoryDialog(api: widget.api, id: id),
    );
  }

  Widget distribution() {
    final delivered = optionalRows(delivery?['delivered']);
    final ids = delivered
        .expand(
          (d) => (d['task_ids'] as List? ?? []).map((id) => id.toString()),
        )
        .toList();
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PmsEyebrow(ui('CHANNEL DISTRIBUTION')),
          Text(ui('Availability update')),
          if (deliveryError != null) ...[
            Text(ui(deliveryError!)),
            PmsButton(
              ui('Retry status'),
              onPressed: busy ? null : loadDelivery,
            ),
          ] else if (delivery == null)
            Text(ui('Checking Channex delivery…'))
          else if (ids.isNotEmpty) ...[
            Text(ui('Delivered to Channex')),
            Text(ui('Task IDs: ${ids.join(', ')}')),
            Text(
              ui('Submission evidence does not prove final OTA acceptance.'),
            ),
          ] else
            Text(
              optionalRows(delivery?['pending']).isNotEmpty
                  ? ui('Queued for Channex')
                  : ui('No delivery recorded for this reservation'),
            ),
          if (delivery != null && ids.isEmpty)
            PmsButton(
              optionalRows(delivery?['pending']).isEmpty
                  ? ui('Send current availability to Channex')
                  : ui('Send to Channex now'),
              onPressed: busy
                  ? null
                  : () async {
                      await perform(() async {
                        final response = jsonObject(
                          await widget.api.change(
                            'POST',
                            '$path/channex-availability-delivery/retry',
                          ),
                        );
                        if (optionalRows(response['failed']).isNotEmpty) {
                          throw const FormatException('Dispatch failed');
                        }
                      });
                      await loadDelivery();
                    },
            ),
        ],
      ),
    );
  }

  Widget preparation(Json r, List<Json> reg) => PmsColumns([
    PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PmsEyebrow(ui('GUEST REGISTRATION')),
          PmsBadge(
            registration == 'complete'
                ? ui('Registration ready')
                : ui('Registration waiting'),
            tone: registration == 'complete' ? 'ready' : 'attention',
          ),
          for (final g in reg)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(g, 'full_name')),
              subtitle: Text(
                '${text(g, 'nationality', '—')} · ${t(text(g, 'completeness'))} · ${t(text(g, 'verification_status', 'not_submitted'))}',
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (registration != 'complete' && r['status'] == 'confirmed') ...[
                PmsButton(
                  ui('Send guest check-in link'),
                  onPressed: busy ? null : links,
                ),
                PmsButton(
                  t('Prepare reminder'),
                  onPressed: busy
                      ? null
                      : () => mutate(() async {
                          await widget.api.change(
                            'POST',
                            '$path/registration-reminder',
                          );
                        }),
                ),
                PmsButton(
                  t('Open reception'),
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.pop(context, changed);
                          widget.openReception();
                        },
                ),
              ],
              PmsButton(
                ui('Review identity verification'),
                onPressed: busy || r['status'] != 'confirmed' ? null : verify,
              ),
            ],
          ),
        ],
      ),
    ),
    PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PmsEyebrow(t('Cleaning checklist')),
          for (final task in optionalRows(data?['cleaning']))
            ListTile(
              onTap: widget.openTask == null
                  ? null
                  : () => widget.openTask!(text(task, 'id')),
              contentPadding: EdgeInsets.zero,
              title: Text(text(task, 'title', 'Cleaning')),
              subtitle: Text(
                '${text(task, 'scheduled_date')} · ${text(task, 'assigned_name', 'Unassigned')}',
              ),
              trailing: PmsBadge(
                text(task, 'status'),
                tone: text(task, 'status'),
              ),
            ),
          if (optionalRows(data?['cleaning']).isEmpty) const PmsEmpty('\u2014'),
          if (optionalRows(data?['maintenance']).isNotEmpty) ...[
            Text(t('Open maintenance')),
            for (final m in optionalRows(data?['maintenance']))
              Text(text(m, 'title')),
          ],
        ],
      ),
    ),
  ], columns: 2);
  Future<void> links() async {
    Json? response;
    if (!await perform(() async {
      response = await widget.api.object('$path/guest-checkin-links');
    })) {
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      useRootNavigator: false,
      context: context,
      builder: (_) => PmsModal(
        title: ui('Secure guest links'),
        eyebrow: ui('GUEST PRE-CHECK-IN'),
        width: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ui(
                'Send each guest their own link. Generating/copying a link does not send a message.',
              ),
            ),
            for (final link in optionalRows(response?['links']))
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text(link, 'guest_name')),
                    Text(text(link, 'completeness')),
                    SelectableText(text(link, 'url')),
                    PmsButton(
                      ui('Copy link'),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: text(link, 'url')),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> verify() async {
    await showDialog<void>(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (_) => IdentityReview(api: widget.api, id: widget.id),
    );
    if (mounted) {
      changed = true;
      await load();
    }
  }

  Widget communications() => PmsColumns([
    PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PmsEyebrow(t('Messages')),
          for (final m in optionalRows(data?['messages']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(m, 'sender_name', text(m, 'subject'))),
              subtitle: Text(
                '${text(m, 'source')} · ${text(m, 'received_at')}\n${text(m, 'body')}',
              ),
            ),
          if (optionalRows(data?['messages']).isEmpty)
            PmsEmpty(t('No messages linked to this stay.')),
        ],
      ),
    ),
    PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PmsRequiredNote(),
          PmsField(
            t('Add note'),
            required: true,
            controller: note,
            lines: 4,
            hint: t('Add an internal note…'),
          ),
          PmsButton(
            t('Add note'),
            primary: true,
            onPressed: busy
                ? null
                : () => mutate(() async {
                    if (note.text.trim().isEmpty) return;
                    await widget.api.note(widget.id, note.text.trim());
                    note.clear();
                  }),
          ),
          for (final n in optionalRows(data?['notes']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(n, 'author_name', 'Delvane')),
              subtitle: Text(
                '${uiDateTime(text(n, 'created_at'))}\n${text(n, 'body')}',
              ),
            ),
          if (optionalRows(data?['notes']).isEmpty)
            PmsEmpty(t('No internal notes yet.')),
        ],
      ),
    ),
  ], columns: 2);
  Widget activity() => PmsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsEyebrow(t('Activity')),
        for (final event in optionalRows(data?['events']))
          ListTile(
            title: Text(text(event, 'summary')),
            subtitle: Text(
              '${uiDateTime(text(event, 'created_at'))} · ${text(event, 'event_type')}',
            ),
          ),
        if (optionalRows(data?['events']).isEmpty)
          PmsEmpty(t('No reservation activity yet.')),
      ],
    ),
  );
}

class IdentityReview extends StatefulWidget {
  const IdentityReview({super.key, required this.api, required this.id});
  final PmsWorkflows api;
  final String id;
  @override
  State<IdentityReview> createState() => _IdentityReviewState();
}

class _IdentityReviewState extends State<IdentityReview>
    with PmsActions<IdentityReview> {
  List<Json>? guests;
  bool confirmed = false;
  final notes = <String, TextEditingController>{};
  final methods = <String, String>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await perform(() async {
      final data = await widget.api.object(
        '/api/reservations/${idPath(widget.id)}/guest-checkin-status',
      );
      guests = optionalRows(data['guests']);
      confirmed = data['reservation_status'] == 'confirmed';
    });
  }

  Future<void> decide(Json guest, String decision) async {
    final id = text(guest, 'id');
    final ok = await perform(() async {
      await widget.api.change(
        'POST',
        '/api/reservations/${idPath(widget.id)}/guests/${idPath(id)}/verify',
        {
          'decision': decision,
          'verification_method': methods[id] ?? 'in_person',
          'review_note': notes[id]?.text ?? '',
        },
      );
    });
    if (ok) await load();
  }

  @override
  void dispose() {
    for (final note in notes.values) {
      note.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: PmsModal(
      title: ui('Identity verification'),
      eyebrow: ui('GUEST PRE-CHECK-IN'),
      width: 650,
      canClose: !busy,
      actions: [
        PmsButton(
          ui('Done'),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ui(
              "Guest-submitted details are not verified automatically. Check the guest's identity and data before approving registration for VIZA. Delvane does not store document images.",
            ),
          ),
          if (confirmed &&
              (guests ?? <Json>[]).any(
                (g) =>
                    g['completeness'] == 'complete' &&
                    g['verification_status'] != 'verified',
              ))
            const PmsRequiredNote(),
          errors(),
          if (guests == null && !busy) PmsButton(ui('Retry'), onPressed: load),
          if (guests == null && busy) const LinearProgressIndicator(),
          if (guests != null && guests!.isEmpty)
            PmsEmpty(ui('No guest registration records.')),
          for (final guest in guests ?? <Json>[])
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(text(guest, 'full_name')),
                  PmsBadge(
                    text(guest, 'verification_status', 'not_submitted'),
                    tone: text(guest, 'verification_status'),
                  ),
                  Text(
                    ui('Registration data: ${ui(text(guest, 'completeness'))}'),
                  ),
                  if (guest['verified_at'] != null)
                    Text(
                      ui('Verified ${uiDateTime(text(guest, 'verified_at'))}'),
                    ),
                  if (text(guest, 'review_note').isNotEmpty)
                    Text(text(guest, 'review_note')),
                  if (confirmed &&
                      guest['completeness'] == 'complete' &&
                      guest['verification_status'] != 'verified') ...[
                    PmsSelect(
                      ui('Verification method'),
                      required: true,
                      value: methods[text(guest, 'id')] ?? 'in_person',
                      items: {
                        'in_person': ui('Checked in person'),
                        'video_call': ui('Verified by video call'),
                        'identity_image': ui('Reviewed identity image'),
                        'manual_review': ui('Manual review'),
                      },
                      onChanged: busy
                          ? null
                          : (v) =>
                                setState(() => methods[text(guest, 'id')] = v),
                    ),
                    PmsField(
                      ui('Review note'),
                      maxLength: 1000,
                      controller: notes.putIfAbsent(
                        text(guest, 'id'),
                        () => TextEditingController(),
                      ),
                      hint: ui('Optional note'),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        PmsButton(
                          ui('Verify identity'),
                          primary: true,
                          onPressed: busy
                              ? null
                              : () => decide(guest, 'verify'),
                        ),
                        PmsButton(
                          ui('Needs correction'),
                          onPressed: busy
                              ? null
                              : () => decide(guest, 'reject'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
