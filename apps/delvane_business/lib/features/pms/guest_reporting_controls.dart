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
