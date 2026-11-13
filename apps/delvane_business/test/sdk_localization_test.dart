import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/localization/web_strings.dart';

import 'support/fake_pms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SDK migration retains Hungarian as the production default', () async {
    final strings = WebStrings();
    await strings.load();
    expect(strings.language, 'hu');
    expect(strings.t('Today'), isNot('Today'));
    strings.language = 'en';
    expect(strings.t('Today'), 'Today');
  });
  test('SDK migration retains selected-language persistence', () async {
    final store = MemorySessionStore();
    final first = WebStrings();
    await first.initialize(store);
    await first.select('en');
    final restored = WebStrings();
    await restored.initialize(store);
    expect(restored.language, 'en');
    expect(restored.t('Reservations'), 'Reservations');
    await restored.select('hu');
    expect(store.values[WebStrings.preferenceKey], 'hu');
  });
}
