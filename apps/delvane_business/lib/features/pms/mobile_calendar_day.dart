import 'package:material_ui/material_ui.dart';

import 'pms_controller.dart';
import 'pms_style.dart';
import '../workspace/workspace_models.dart';

/// Phone calendar presentation only. The caller supplies the existing stay
/// filter and property palette; no availability or reservation rules live here.
class MobileCalendarDay extends StatelessWidget {
  const MobileCalendarDay({
    super.key,
    required this.date,
    required this.inMonth,
    required this.width,
    required this.stays,
    required this.colorFor,
    required this.onCreate,
    required this.onReservation,
    required this.arrivals,
    required this.departures,
  });
  final DateTime date;
  final bool inMonth;
  final double width;
  final List<Json> stays;
  final Color Function(Json) colorFor;
  final VoidCallback onCreate;
  final ValueChanged<String> onReservation;
  final int arrivals, departures;

  void _open(BuildContext context) {
    if (stays.length == 1) {
      onReservation(text(stays.single, 'id'));
      return;
    }
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => PmsModal(
        title: uiDate(isoDate(date)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ui('${stays.length} stays')),
            Text(ui('$arrivals in · $departures out')),
            for (final stay in stays)
              ListTile(
                minTileHeight: 52,
                leading: Container(
                  width: 12,
                  height: 30,
                  decoration: BoxDecoration(
                    color: colorFor(stay),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(text(stay, 'guest_name')),
                subtitle: Text(
                  '${text(stay, 'property_name')}\n'
                  '${uiDate(text(stay, 'arrival_date'))} → ${uiDate(text(stay, 'departure_date'))}',
                ),
                isThreeLine: true,
                onTap: () {
                  Navigator.pop(dialogContext);
                  onReservation(text(stay, 'id'));
                },
              ),
            PmsButton(
              ui('New reservation'),
              onPressed: () {
                Navigator.pop(dialogContext);
                onCreate();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iso = isoDate(date);
    return SizedBox(
      width: width,
      height: 112,
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: inMonth ? Colors.white : const Color(0xFFF6F5F2),
          border: Border.all(color: const Color(0xFFECEAE5)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tooltip(
              message: '${ui('New reservation')} · ${uiDate(iso)}',
              child: InkWell(
                key: ValueKey('calendar-day-$iso'),
                onTap: onCreate,
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: inMonth ? Colors.black : PmsStyle.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                button: true,
                label:
                    '${uiDate(iso)}, ${ui('${stays.length} stays')}, '
                    '${ui('$arrivals in · $departures out')}',
                child: InkWell(
                  key: ValueKey('mobile-stays-$iso'),
                  onTap: () => _open(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final stay in stays.take(3))
                        Container(
                          key: ValueKey('mobile-stay-${text(stay, 'id')}-$iso'),
                          margin: const EdgeInsets.only(bottom: 3),
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorFor(stay),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      if (stays.length > 3)
                        Text(
                          '+${stays.length - 3}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
