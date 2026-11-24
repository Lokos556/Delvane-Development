import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../workspace/workspace_models.dart';
import 'guest_country_names.dart';
import 'pms_controller.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

const _identityLabels = {
  'csaladnev': 'Family name',
  'utonev': 'Given names',
  'szuletesiCsaladnev': 'Birth family name',
  'szuletesiUtonev': 'Birth given names',
  'anyjaCsaladnev': 'Mother family name',
  'anyjaUtonev': 'Mother given names',
  'szuletesiDatum': 'Date of birth',
  'szuletesiHely': 'Place of birth',
  'allampolgarsagKod': 'Nationality',
  'nem': 'Sex',
  'okmanyTipus': 'Document type',
  'okmanyAzonositoSzam': 'Document number',
  'vizumEngedelySzam': 'Visa or residence permit number',
  'beutazasDatuma': 'Entry date',
  'beutazasHelye': 'Entry location',
};
const _reportLabels = {
  'full_name': 'Full legal name',
  'birth_name': 'Birth name',
  'country_of_residence': 'Country of residence',
  'postal_code': 'Residence postal code',
  'ifa_status': 'Tourism tax obligation or exemption',
  'effective_from': 'Effective date',
  'nationality_country': 'Nationality for NTAK',
};
const _shared = {
  'szuletesiDatum': 'date_of_birth',
  'szuletesiHely': 'birth_place',
  'nem': 'sex',
  'allampolgarsagKod': 'nationality_country',
};
const _submittedLabels = {
  'full_name': 'Full name',
  'birth_name': 'Birth name',
  'birth_place': 'Place of birth',
  'date_of_birth': 'Date of birth',
  'date_of_expiry': 'Document expiry date',
  'sex': 'Sex',
  'nationality': 'Nationality',
  'mother_birth_name': "Mother's birth name",
  'document_type': 'Document type',
  'document_number': 'Document number',
  'address': 'Address',
};
const _sex = {
  'NO': 'Female',
  'FERFI': 'Male',
  'EGYEB_VAGY_NEM_ISMERT': 'Other or unknown',
};
const _documents = {
  'SZEM_IG': 'Identity card',
  'UTLEVEL': 'Passport',
  'VEZ_ENG': 'Driving licence',
  'EGYEB': 'Other',
};
const _methods = {
  'in_person': 'Checked in person',
  'video_call': 'Verified by video call',
  'identity_image': 'Reviewed identity image',
  'manual_review': 'Manual review',
};

String _stage(Json guest) => text(
  guest,
  'registration_stage',
  switch (guest['verification_status']) {
    'verified' => 'verified',
    'rejected' => 'needs_correction',
    _ =>
      guest['completeness'] == 'complete' ? 'submitted' : 'awaiting_invitation',
  },
);

bool guestDetailsReceived(Json guest) =>
    const {'submitted', 'needs_correction', 'verified'}.contains(_stage(guest));

class GuestRegistrationBadge extends StatelessWidget {
  const GuestRegistrationBadge(this.guest, {super.key});
  final Json guest;

  @override
  Widget build(BuildContext context) {
    final stage = _stage(guest);
    return PmsBadge(
      ui(switch (stage) {
        'verified' => 'Identity verified',
        'submitted' => 'Registration submitted',
        'needs_correction' => 'Correction required',
        'awaiting_registration' => 'Awaiting registration',
        _ => 'Awaiting invitation',
      }),
      tone: switch (stage) {
        'verified' => 'ready',
        'submitted' || 'needs_correction' => 'attention',
        _ => 'neutral',
      },
    );
  }
}

Future<void> openGuestRegistration(
  BuildContext context,
  PmsWorkflows api, {
  String? reservationId,
  String? guestId,
}) => showDialog<void>(
  context: context,
  useRootNavigator: false,
  barrierDismissible: false,
  builder: (_) => GuestRegistrationWorkspace(
    api: api,
    reservationId: reservationId,
    guestId: guestId,
  ),
);

class GuestRegistrationWorkspace extends StatefulWidget {
  const GuestRegistrationWorkspace({
    super.key,
    required this.api,
    this.reservationId,
    this.guestId,
  }) : assert(reservationId != null || guestId != null);
  final PmsWorkflows api;
  final String? reservationId, guestId;

  @override
  State<GuestRegistrationWorkspace> createState() =>
      _GuestRegistrationWorkspaceState();
}

class _GuestRegistrationWorkspaceState
    extends State<GuestRegistrationWorkspace> {
  final _fields = {
    for (final key in [
      ..._identityLabels.keys,
      ..._reportLabels.keys,
      'reason',
      'note',
    ])
      key: TextEditingController(),
  };
  final _initial = <String, String>{};
  Json? _profile;
  List<Json> _guests = [];
  String? _reservationId, _guestId, _error, _errorField;
  String _applicability = '', _method = 'in_person';
  bool _busy = false,
      _reviewSuggestions = false,
      _confirmScanner = false,
      _align = false;

  @override
  void initState() {
    super.initState();
    _reservationId = widget.reservationId;
    _guestId = widget.guestId;
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String _path(String id) =>
      '/api/registration/records/${idPath(id)}/workspace';
  List<String> _strings(Object? value) =>
      (value as List? ?? []).whereType<String>().toList();
  String _value(String key) => _fields[key]!.text.trim();
  bool _edited(String key) => _value(key) != (_initial[key] ?? '');
  bool get _reportingChanged => _align || _reportLabels.keys.any(_edited);
  bool get _identityChanged =>
      _identityLabels.keys.any(_edited) ||
      _applicability != (_initial['applicability'] ?? '') ||
      _confirmScanner ||
      _reviewSuggestions;
  bool get _dirty => _identityChanged || _reportingChanged;
  bool get _separateNationality =>
      !_strings(_profile?['ntak_countries'])
          .contains(_value('allampolgarsagKod'));
  bool get _showAlignment =>
      optionalObject(_profile?['reporting_profile']).isNotEmpty &&
      (_shared.keys.any(_edited) ||
          _strings(_profile?['reporting_conflicts']).isNotEmpty);

  Future<void> _load() => _run(() async {
    Json? profile;
    if (_reservationId == null) {
      profile = await widget.api.object(_path(_guestId!));
      _reservationId = text(profile, 'reservation_id');
    }
    await _loadGuests();
    if (_guests.isEmpty) return;
    final id = _guests.any((guest) => guest['id'] == _guestId)
        ? _guestId!
        : text(_guests.first, 'id');
    _apply(
      profile?['id'] == id ? profile! : await widget.api.object(_path(id)),
    );
  });

  Future<void> _loadGuests() async {
    final data = await widget.api.object(
      '/api/reservations/${idPath(_reservationId!)}/guest-checkin-status',
    );
    if (mounted) _guests = optionalRows(data['guests']);
  }

  void _apply(Json profile) {
    if (!mounted) return;
    _guestId = text(profile, 'id');
    _profile = profile;
    final identity = optionalObject(profile['identity']);
    final reporting = optionalObject(profile['reporting_profile']);
    final defaults = optionalObject(profile['reporting_defaults']);
    _initial
      ..clear()
      ..addAll({
        for (final key in _identityLabels.keys) key: '${identity[key] ?? ''}',
        for (final key in _reportLabels.keys)
          key:
              '${key == 'effective_from' ? profile['business_date'] ?? '' : reporting[key] ?? defaults[key] ?? ''}',
      });
    _applicability = switch (profile['third_country_applicable']) {
      true => 'yes',
      false => 'no',
      _ => '',
    };
    _initial['applicability'] = _applicability;
    for (final entry in _fields.entries) {
      entry.value.text = _initial[entry.key] ?? '';
    }
    final method = text(
      optionalObject(profile['verification']),
      'verification_method',
    );
    _method = _methods.containsKey(method) ? method : 'in_person';
    _reviewSuggestions = _confirmScanner = _align = false;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = _errorField = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      _error = switch (error) {
        ApiException(code: 'guest_workspace_changed') =>
          'This guest profile changed. Reload it before saving.',
        ApiException(code: 'reporting_alignment_required') => 'Review the differences and confirm which personal details to use for reporting.',
        ApiException(statusCode: 400 || 422) =>
          'Check the highlighted fields and their formats before saving.',
        ApiException(statusCode: 403 || 404) =>
          'This guest profile is unavailable or you do not have access.',
        ApiException(statusCode: 409) => 'The reservation or guest changed. Reload the profile and review it again.',
        _ => 'The guest profile could not be updated. Try again.',
      };
      if (error is ApiException) {
        final key = error.field;
        _errorField = _fields.containsKey(key)
            ? key
            : _shared.entries
                  .where((entry) => entry.value == key)
                  .firstOrNull
                  ?.key;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _invalid(String key, String message) {
    setState(() {
      _error = message;
      _errorField = key;
    });
    return false;
  }

  DateTime? _date(String value) {
    final date = DateTime.tryParse(value);
    return date != null && date.toIso8601String().startsWith('${value}T')
        ? date
        : null;
  }

  bool _validate() {
    if (_value('reason').length < 3) {
      return _invalid('reason', 'Enter a short reason for the changes.');
    }
    for (final key in ['szuletesiDatum', 'beutazasDatuma', 'effective_from']) {
      if (_value(key).isNotEmpty && _date(_value(key)) == null) {
        return _invalid(key, 'Enter the date in YYYY-MM-DD format.');
      }
    }
    if (!_reportingChanged) return true;
    for (final key in [
      'full_name',
      'country_of_residence',
      'postal_code',
      'ifa_status',
      'effective_from',
    ]) {
      if (_value(key).isEmpty) {
        return _invalid(key, 'Complete the required residence and tax fields.');
      }
    }
    final defaults = optionalObject(_profile?['reporting_defaults']);
    for (final key in ['szuletesiDatum', 'szuletesiHely', 'nem']) {
      if (_value(key).isEmpty && text(defaults, _shared[key]!).isEmpty) {
        return _invalid(
          key,
          'Complete the personal information required for reporting.',
        );
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (!_dirty || !_validate()) return;
    final suggestions = _strings(_profile?['suggested_fields']);
    final request = {
      'revision': _profile!['revision'],
      'reason': _value('reason'),
      if (_identityChanged)
        'identity': {
          'manual': {
            for (final key in _identityLabels.keys)
              if (_edited(key) ||
                  (_reviewSuggestions && suggestions.contains(key)))
                key: _value(key).isEmpty ? null : _value(key),
          },
          'third_country_applicable': _applicability.isEmpty
              ? null
              : _applicability == 'yes',
          'confirm_ambiguities': _confirmScanner,
        },
      if (_reportingChanged)
        'reporting': {
          for (final key in _reportLabels.keys)
            if (key != 'nationality_country' || _separateNationality)
              key: _value(key),
          'confirm_alignment': _align,
        },
    };
    await _run(() async {
      _apply(
        jsonObject(await widget.api.change('PUT', _path(_guestId!), request)),
      );
      await _loadGuests();
    });
  }

  Future<void> _decide(String decision) => _run(() async {
    await widget.api.change(
      'POST',
      '/api/reservations/${idPath(_reservationId!)}/guests/${idPath(_guestId!)}/verify',
      {
        'decision': decision,
        'verification_method': _method,
        'review_note': _value('note'),
      },
    );
    _apply(await widget.api.object(_path(_guestId!)));
    await _loadGuests();
  });

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Guest registration'),
    titleSize: 28,
    width: 1120,
    canClose: !_busy,
    actions: [
      if (_dirty && !_busy)
        PmsButton(
          ui('Discard changes'),
          onPressed: () => setState(() {
            _apply(_profile!);
            _error = _errorField = null;
          }),
        ),
      PmsButton(
        ui('Close'),
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        ui('Save guest profile'),
        primary: true,
        onPressed: _busy || !_dirty ? null : _save,
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                ui(_error!),
                style: const TextStyle(color: Color(0xffa4323c)),
              ),
            ),
          ),
          if (!_busy)
            Align(
              alignment: Alignment.centerLeft,
              child: PmsButton(ui('Reload profile'), onPressed: _load),
            ),
        ],
        if (!_busy && _guests.isEmpty && _error == null)
          PmsEmpty(ui('No guest registration records.')),
        if (_guests.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 820) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 218, child: _guestList()),
                    const SizedBox(width: 16),
                    Expanded(child: _editor()),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_guestList(), const SizedBox(height: 12), _editor()],
              );
            },
          ),
      ],
    ),
  );

  Widget _guestList() {
    final received = _guests
        .where(
          (guest) => const {
            'submitted',
            'verified',
            'needs_correction',
          }.contains(_stage(guest)),
        )
        .length;
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ui('Guests'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: received / _guests.length),
          const SizedBox(height: 6),
          Text('$received / ${_guests.length} · ${ui('Details received')}'),
          for (final guest in _guests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              selected: text(guest, 'id') == _guestId,
              enabled: !_busy && !_dirty,
              title: Text(text(guest, 'full_name')),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: GuestRegistrationBadge(guest),
              ),
              onTap: text(guest, 'id') == _guestId
                  ? null
                  : () => _run(() async {
                      _apply(await widget.api.object(_path(text(guest, 'id'))));
                    }),
            ),
        ],
      ),
    );
  }

  Widget _editor() {
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    final submitted = optionalObject(profile['submitted']);
    final originals = optionalObject(profile['original']);
    final ambiguous = _strings(profile['ambiguities']);
    final readiness = optionalObject(profile['readiness']);
    final dob = _date(_value('szuletesiDatum'));
    final reference = _date(text(profile, 'reference_date'));
    final lastDay = reference == null
        ? null
        : DateTime(reference.year - 14, reference.month + 1, 0).day;
    final needsDocument = dob == null || reference == null || lastDay == null
        ? profile['document_required'] == true
        : !dob.isAfter(
            DateTime(
              reference.year - 14,
              reference.month,
              reference.day.clamp(1, lastDay),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text(profile, 'full_name'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GuestRegistrationBadge(profile),
          ],
        ),
        if (submitted.isNotEmpty || originals.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(ui('Submitted and scanned information')),
            children: [
              if (submitted.isNotEmpty)
                _readOnlyFacts(
                  profile['submitted_snapshot'] == true
                      ? 'Guest submission'
                      : 'Available values from earlier registration',
                  submitted,
                  _submittedLabels,
                ),
              if (originals.isNotEmpty)
                _readOnlyFacts(
                  'Original scanner values (read only)',
                  originals,
                  _identityLabels,
                ),
            ],
          ),
        if (_strings(profile['suggested_fields']).isNotEmpty)
          _check(
            'Confirm suggested values from the existing records',
            _reviewSuggestions,
            (value) => _reviewSuggestions = value,
          ),
        const SizedBox(height: 12),
        PmsColumns([
          _section('Personal information', [
            if ((_value('csaladnev').isEmpty || _value('utonev').isEmpty) &&
                text(submitted, 'full_name').isNotEmpty)
              _notice(
                'Check the family and given names against the document. The submitted full name was kept as entered.',
              ),
            _field('csaladnev', required: true),
            _field('utonev', required: true),
            _field('szuletesiDatum', required: true, date: true),
            _field('szuletesiHely', required: _reportingChanged),
            _choice('nem', _sex, required: true),
            _country('allampolgarsagKod', 'viza_countries', required: true),
            if (text(profile, 'raw_nationality').isNotEmpty ||
                (_value('allampolgarsagKod').isEmpty &&
                    text(submitted, 'nationality').isNotEmpty))
              _notice(
                'Confirm the nationality from the document. The submitted value is kept above.',
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(ui('Birth and parent names')),
              children: [
                _field(
                  'szuletesiCsaladnev',
                  required: _value('szuletesiUtonev').isNotEmpty,
                ),
                _field(
                  'szuletesiUtonev',
                  required: _value('szuletesiCsaladnev').isNotEmpty,
                ),
                _field(
                  'anyjaCsaladnev',
                  required: _value('anyjaUtonev').isNotEmpty,
                ),
                _field(
                  'anyjaUtonev',
                  required: _value('anyjaCsaladnev').isNotEmpty,
                ),
              ],
            ),
          ]),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('Identity document', [
                _choice('okmanyTipus', _documents, required: needsDocument),
                _field('okmanyAzonositoSzam', required: needsDocument),
                _notice(
                  'Document requirements are checked at actual arrival. Under 14, document fields are optional.',
                ),
                if (ambiguous.isNotEmpty) ...[
                  for (final code in ambiguous) Text(_blocker(code)),
                  _check(
                    'Confirm ambiguous scanner values after review',
                    _confirmScanner,
                    (v) => _confirmScanner = v,
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              _section('Additional information', [
                _choice('applicability', const {
                  'yes': 'Applicable',
                  'no': 'Not applicable',
                }, required: true),
                if (_applicability.isEmpty)
                  _notice(
                    'Review whether third-country entry details are required.',
                  ),
                if (_applicability == 'yes') ...[
                  _field('vizumEngedelySzam', required: true),
                  _field('beutazasDatuma', required: true, date: true),
                  _field('beutazasHelye', required: true),
                ],
              ]),
            ],
          ),
        ], columns: 2),
        const SizedBox(height: 12),
        PmsColumns([
          _section('Residence information', [
            if (text(submitted, 'address').isNotEmpty)
              Text(
                '${ui('Submitted address')} · ${text(submitted, 'address')}',
              ),
            _country('country_of_residence', 'ntak_countries', required: true),
            _field('postal_code', required: true),
          ]),
          _section('Tourism tax', [
            _choice('ifa_status', {
              for (final entry in optionalObject(
                profile['ifa_reasons'],
              ).entries)
                entry.key: '${entry.value}',
            }, required: true),
            _field('effective_from', required: true, date: true),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(ui('Name used for reporting')),
              children: [
                _field('full_name', required: true),
                _field('birth_name'),
              ],
            ),
            if (_separateNationality)
              _country('nationality_country', 'ntak_countries'),
            if (_showAlignment) ...[
              for (final entry in _shared.entries)
                if (_strings(profile['reporting_conflicts'])
                    .contains(entry.value))
                  Text(
                    '${ui('Saved reporting value')} · ${ui(_label(entry.key))}: ${_savedReportingValue(profile, entry.key, entry.value)}',
                  ),
              _check(
                'Use the reviewed personal details in the reporting profile',
                _align,
                (v) => _align = v,
              ),
            ],
          ]),
        ], columns: 2),
        if (_dirty) ...[
          const SizedBox(height: 12),
          _section('Save changes', [
            _notice(
              'Changes are saved with their reason and may require a new identity review.',
            ),
            _field('reason', required: true, maxLength: 500),
          ]),
        ],
        const SizedBox(height: 12),
        PmsColumns([_verification(profile), _readiness(readiness)], columns: 2),
      ],
    );
  }

  Widget _verification(Json profile) {
    final verification = optionalObject(profile['verification']);
    final verified = verification['status'] == 'verified';
    return _section('Identity verification', [
      if (verified) ...[
        Text(ui('Identity verified')),
        Text(uiDateTime(text(verification, 'verified_at'))),
        if (_methods.containsKey(verification['verification_method']))
          Text(ui(_methods[verification['verification_method']]!)),
      ] else
        _notice('Guest submission requires a separate identity review.'),
      if (text(verification, 'review_note').isNotEmpty)
        Text(text(verification, 'review_note')),
      if (!verified && profile['can_verify'] == true) ...[
        PmsSelect(
          'Verification method',
          key: ValueKey('$_guestId-method-$_method'),
          value: _method,
          items: _methods.map((key, value) => MapEntry(key, ui(value))),
          onChanged: _busy ? null : (value) => setState(() => _method = value),
        ),
        _field('note', maxLength: 1000),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PmsButton(
              ui('Verify identity'),
              primary: true,
              onPressed: _busy || _dirty ? null : () => _decide('verify'),
            ),
            PmsButton(
              ui('Needs correction'),
              onPressed: _busy || _dirty ? null : () => _decide('reject'),
            ),
          ],
        ),
      ],
    ]);
  }

  Widget _readiness(Json readiness) {
    final viza = _strings(readiness['viza_blockers']);
    final ntak = _strings(readiness['ntak_blockers']);
    return _section('Government reporting readiness', [
      Text(ui('Official transmission is disabled.')),
      const SizedBox(height: 8),
      Text(
        ui('VIZA identity data'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      if (viza.isEmpty)
        Text(ui('The identity data passed the local VIZA checks.')),
      for (final message in viza.map(_blocker).toSet()) Text('• $message'),
      const SizedBox(height: 8),
      Text(
        ui('NTAK and tourism tax'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      if (ntak.isEmpty)
        Text(ui('The profile passed the local NTAK data checks.')),
      for (final message in ntak.map(_blocker).toSet()) Text('• $message'),
      if (readiness['actual_arrival_recorded'] != true)
        _notice(
          'Record actual arrival separately. Registration does not create an arrival.',
        ),
    ]);
  }

  String _blocker(String code) {
    final parts = code.split(':');
    final label = _identityLabels[parts.last];
    if (label != null) {
      switch (parts.first) {
        case 'missing':
          return '${ui('Required field')} · ${ui(label)}';
        case 'conflicting_scan':
          return '${ui('Check conflicting document values')} · ${ui(label)}';
        case 'length':
          return '${ui('Check the field length')} · ${ui(label)}';
      }
    }
    return ui(switch (parts.first) {
      'birth_date' => 'Check the date of birth.',
      'sex' => 'Select the sex shown on the document.',
      'document_type' => 'Select a valid document type.',
      'country_mapping_requires_review' ||
      'nationality_country_mapping_required' =>
        'Confirm the guest’s nationality.',
      'mrz_birth_century_confirmation' =>
        'Confirm the complete birth year from the document.',
      'third_country_applicability_review' =>
        'Review whether third-country entry details are required.',
      'entry_date' || 'entry_date_future' => 'Check the entry date.',
      'owner_verification_required' =>
        'Owner identity verification is required',
      'missing_guest_reporting_profile' =>
        'Save the residence and tourism tax details.',
      'identity_normalization_unresolved' =>
        'The NTAK guest identifier is pending.',
      'name_pair' ||
      'manual_name_pair' => 'Review both parts of the recorded name.',
      _ => 'Review the identity fields before reporting.',
    });
  }

  Widget _readOnlyFacts(
    String title,
    Json facts,
    Map<String, String> labels,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ui(title), style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final item in labels.entries)
          if (text(facts, item.key).isNotEmpty)
            Text(
              '${ui(item.value)} · ${_submittedValue(item.key, text(facts, item.key))}',
            ),
      ],
    ),
  );

  String _submittedValue(String key, String value) => switch (key) {
    'sex' => ui(
      const {'F': 'Female', 'M': 'Male', 'X': 'Other or unknown'}[value] ??
          value,
    ),
    'nem' => ui(_sex[value] ?? value),
    'document_type' => ui(
      const {
            'id_card': 'Identity card',
            'passport': 'Passport',
            'driver_license': 'Driving licence',
            'other': 'Other',
          }[value] ??
          value,
    ),
    'okmanyTipus' => ui(_documents[value] ?? value),
    _ => value,
  };

  String _savedReportingValue(
    Json profile,
    String identityKey,
    String reportingKey,
  ) {
    final value = text(
      optionalObject(profile['reporting_profile']),
      reportingKey,
    );
    final country = reportingKey == 'nationality_country'
        ? guestCountryNames[value]
        : null;
    if (country == null) return _submittedValue(identityKey, value);
    return widget.api.controller.strings.language == 'hu'
        ? country.$2
        : country.$1;
  }

  Widget _section(String title, List<Widget> children) => PmsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ui(title),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget _notice(String message) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      ui(message),
      style: const TextStyle(fontSize: 12, color: PmsStyle.muted),
    ),
  );

  String _label(String key) =>
      _identityLabels[key] ??
      _reportLabels[key] ??
      switch (key) {
        'note' => 'Review note',
        'reason' => 'Reason',
        _ => 'Third-country facts applicable',
      };

  String? _fieldStatus(String key, bool required) => _errorField == key
      ? 'Check this field'
      : required && _value(key).isEmpty
      ? 'Required'
      : null;

  Widget _field(
    String key, {
    bool required = false,
    bool date = false,
    int? maxLength,
  }) => PmsField(
    _label(key),
    key: ValueKey('guest-field-$key'),
    controller: _fields[key]!,
    required: required,
    hint: date ? 'YYYY-MM-DD' : null,
    maxLength: maxLength,
    status: _fieldStatus(key, required),
    onChanged: (_) => setState(() {}),
  );

  Widget _choice(
    String key,
    Map<String, String> options, {
    bool required = false,
  }) {
    final isApplicability = key == 'applicability';
    final current = isApplicability ? _applicability : _value(key);
    final hint = isApplicability ? null : _fieldStatus(key, required);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hint != null) _notice(hint),
        PmsSelect(
          _label(key),
          key: ValueKey('$_guestId-$key-$current'),
          value: current,
          required: required,
          items: {
            if (!isApplicability || current.isEmpty)
              '': ui(isApplicability ? 'Needs review' : 'Select'),
            ...options.map((key, value) => MapEntry(key, ui(value))),
          },
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  if (isApplicability) {
                    _applicability = value;
                  } else {
                    _fields[key]!.text = value;
                  }
                }),
        ),
      ],
    );
  }

  Widget _country(String key, String choices, {bool required = false}) {
    final current = _value(key);
    final hint = _fieldStatus(key, required);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hint != null) _notice(hint),
        _CountryPicker(
          key: ValueKey('$_guestId-$key-$current'),
          label: _label(key),
          selected: current,
          choices: _strings(_profile?[choices]),
          hungarian: widget.api.controller.strings.language == 'hu',
          required: required,
          onChanged: _busy
              ? null
              : (value) => setState(() => _fields[key]!.text = value),
        ),
      ],
    );
  }

  Widget _check(String label, bool checked, ValueChanged<bool> onChange) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(ui(label)),
        value: checked,
        onChanged: _busy
            ? null
            : (value) => setState(() => onChange(value == true)),
      );
}

class _CountryPicker extends StatefulWidget {
  const _CountryPicker({
    super.key,
    required this.label,
    required this.choices,
    required this.selected,
    required this.hungarian,
    required this.required,
    this.onChanged,
  });
  final String label, selected;
  final List<String> choices;
  final bool hungarian, required;
  final ValueChanged<String>? onChanged;

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  bool _expanded = false;
  String _query = '';

  String _label(String key) {
    final names = guestCountryNames[key];
    return names == null
        ? '${ui('Special country entry')} ($key)'
        : widget.hungarian
        ? names.$2
        : names.$1;
  }

  String _searchKey(String input) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ö': 'o',
      'ő': 'o',
      'ú': 'u',
      'ü': 'u',
      'ű': 'u',
    };
    return input.toLowerCase().replaceAllMapped(
      RegExp('[áéíóöőúüű]'),
      (m) => accents[m[0]]!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchKey(_query.trim());
    final matches = [
      for (final code in widget.choices)
        if (query.isEmpty ||
            [
              code,
              _label(code),
              guestCountryNames[code]?.$1 ?? '',
              guestCountryNames[code]?.$2 ?? '',
            ].any((name) => _searchKey(name).contains(query)))
          code,
    ]..sort((a, b) => _label(a).compareTo(_label(b)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${ui(widget.label)}${widget.required ? ' *' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          PmsButton(
            widget.selected.isEmpty
                ? ui('Select country')
                : _label(widget.selected),
            onPressed: widget.onChanged == null
                ? null
                : () => setState(() {
                    _expanded = !_expanded;
                    _query = '';
                  }),
          ),
          if (_expanded) ...[
            TextField(
              autofocus: true,
              decoration: InputDecoration(labelText: ui('Search countries')),
              onChanged: (value) => setState(() => _query = value),
            ),
            if (widget.selected.isNotEmpty && !widget.required)
              ListTile(
                title: Text(ui('Clear selection')),
                onTap: () => widget.onChanged?.call(''),
              ),
            if (matches.isEmpty)
              Text(ui('No matching countries'))
            else
              SizedBox(
                height: (matches.length.clamp(1, 5) * 44).toDouble(),
                child: ListView.builder(
                  primary: false,
                  itemExtent: 44,
                  itemCount: matches.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    title: Text(_label(matches[i])),
                    onTap: () => widget.onChanged?.call(matches[i]),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
