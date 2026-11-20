import 'package:material_ui/material_ui.dart';

import 'inventory_controls.dart';
import 'pms_controller.dart';
import 'pms_workflows.dart';

Future<void> editGuestReporting(
  BuildContext context,
  PmsWorkflows api,
  String guestId,
) async {
  final day = DateTime.now().toIso8601String().substring(0, 10);
  final path = '/api/registration/records/$guestId/reporting-profile';
  final data = await api.object('$path?business_date=$day');
  final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? {});
  final defaults = Map<String, dynamic>.from(data['defaults'] as Map? ?? {});
  if (!context.mounted) return;
  await showDialog(
    context: context,
    useRootNavigator: false,
    builder: (_) => InventoryForm(
      title: 'Guest residence and tourism tax',
      labels: const {
        'full_name': 'Full legal name',
        'date_of_birth': 'Date of birth',
        'birth_name': 'Birth name',
        'birth_place': 'Place of birth',
        'sex': 'Sex',
        'country_of_residence': 'Residence country (two-letter code)',
        'nationality_country': 'Nationality country (two-letter code)',
        'postal_code': 'Residence postal code',
        'ifa_status': 'Tourism tax obligation or exemption',
        'effective_from': 'Effective date',
        'source': 'Data source',
        'reason': 'Reason',
      },
      optional: const {'birth_name', 'nationality_country'},
      initial: {
        ...defaults,
        ...profile,
        'effective_from': day,
        'reason': '',
        'source': profile.isEmpty ? 'manual' : 'correction',
      },
      selects: {
        'sex': {
          'NO': ui('Female'),
          'FERFI': ui('Male'),
          'EGYEB_VAGY_NEM_ISMERT': ui('Other or unknown'),
        },
        'source': {
          'manual': ui('Manually entered'),
          'correction': ui('Correction'),
        },
        'ifa_status': {
          for (final e in (data['ifa_reasons'] as Map? ?? {}).entries)
            '${e.key}': ui('${e.value}'),
        },
      },
      save: (values) async {
        if (values['nationality_country'] == '') {
          values['nationality_country'] = null;
        }
        await api.change('PUT', path, values);
      },
    ),
  );
}

/// Normal reception review: original fields remain read-only and corrections require a reason.
Future<void> editVizaIdentity(
  BuildContext context,
  PmsWorkflows api,
  String guestId,
) async {
  final path = '/api/registration/records/$guestId/viza-identity';
  final data = await api.object(path);
  final effective = Map<String, dynamic>.from(data['effective'] as Map? ?? {});
  final original = Map<String, dynamic>.from(data['original'] as Map? ?? {});
  const labels = {
    'csaladnev': 'Family name',
    'utonev': 'Given names',
    'szuletesiCsaladnev': 'Birth family name',
    'szuletesiUtonev': 'Birth given names',
    'anyjaCsaladnev': 'Mother family name',
    'anyjaUtonev': 'Mother given names',
    'szuletesiDatum': 'Date of birth',
    'szuletesiHely': 'Place of birth',
    'allampolgarsagKod': 'VIZA nationality code',
    'nem': 'Sex',
    'okmanyTipus': 'Document type',
    'okmanyAzonositoSzam': 'Document number',
    'third_country': 'Third-country facts applicable',
    'vizumEngedelySzam': 'Visa or residence permit number',
    'beutazasDatuma': 'Entry date',
    'beutazasHelye': 'Entry location',
    'ambiguities': 'Confirm ambiguous scanner values after review',
    'reason': 'Reason',
  };
  if (!context.mounted) return;
  await showDialog(
    context: context,
    useRootNavigator: false,
    builder: (_) => InventoryForm(
      title: 'VIZA identity review',
      labels: labels,
      optional: labels.keys
          .where(
            (k) => k != 'reason' && k != 'third_country' && k != 'ambiguities',
          )
          .toSet(),
      intro: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ui('Original scanner values (read only)')),
          for (final entry in original.entries)
            Text(
              '${ui(labels[entry.key] ?? entry.key)}: ${entry.value ?? "-"}',
            ),
          if (original.isEmpty)
            Text(
              ui(
                'Original scanner values unavailable; combined names are not split automatically.',
              ),
            ),
          Text(
            ui(
              'Document requirements are checked at actual arrival. Under 14, document fields are optional.',
            ),
          ),
          Text(
            ui(
              'Saving requires owner verification again. Scanning and registration do not record an arrival.',
            ),
          ),
          for (final b
              in ((data['readiness'] as Map?)?['blockers'] as List? ?? []))
            Text(ui('$b')),
        ],
      ),
      initial: {
        ...effective,
        'third_country': data['third_country_applicable'] == null
            ? 'unknown'
            : data['third_country_applicable'] == true
            ? 'yes'
            : 'no',
        'ambiguities': 'no',
        'reason': '',
      },
      selects: {
        'nem': {
          '': '',
          'NO': ui('Female'),
          'FERFI': ui('Male'),
          'EGYEB_VAGY_NEM_ISMERT': ui('Other or unknown'),
        },
        'okmanyTipus': {
          '': '',
          'SZEM_IG': ui('Identity card'),
          'UTLEVEL': ui('Passport'),
          'VEZ_ENG': ui('Driving licence'),
          'EGYEB': ui('Other'),
        },
        'third_country': {
          'unknown': ui('Needs review'),
          'yes': ui('Applicable'),
          'no': ui('Not applicable'),
        },
        'ambiguities': {
          'no': ui('Needs review'),
          'yes': ui('Reviewed and confirmed'),
        },
      },
      save: (values) async {
        final manual = <String, dynamic>{};
        for (final key in effective.keys.followedBy(labels.keys).toSet()) {
          if (!{'reason', 'third_country', 'ambiguities'}.contains(key) &&
              values.containsKey(key) &&
              '${values[key] ?? ""}' != '${effective[key] ?? ""}') {
            manual[key] = values[key] == '' ? null : values[key];
          }
        }
        await api.change('PUT', path, {
          'manual': manual,
          'reason': values['reason'],
          'third_country_applicable': values['third_country'] == 'unknown'
              ? null
              : values['third_country'] == 'yes',
          'confirm_ambiguities': values['ambiguities'] == 'yes',
        });
      },
    ),
  );
}
