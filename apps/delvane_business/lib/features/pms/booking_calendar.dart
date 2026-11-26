import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_style.dart';

enum BookingPhase { arrival, occupied, departure, dayUse }

class CalendarSelection {
  CalendarSelection(DateTime date) : day = DateUtils.dateOnly(date);

  DateTime day;
  bool yearView = false;
  int yearOffset = 0;
  String? property;
}

typedef _DayBooking = (Json, BookingPhase);

class BookingCalendar extends StatefulWidget {
  const BookingCalendar({
    super.key,
    required this.selection,
    required this.properties,
    required this.reservations,
    required this.propertyLabel,
    required this.onOpen,
    required this.onCreate,
    this.onZoom,
    this.viewportHeight,
    this.loading = false,
  });

  final CalendarSelection selection;
  final List<Json> properties, reservations;
  final String Function(String) propertyLabel;
  final ValueChanged<String> onOpen, onCreate;
  final VoidCallback? onZoom;
  final double? viewportHeight;
  final bool loading;

  @override
  State<BookingCalendar> createState() => _BookingCalendarState();
}

class _BookingCalendarState extends State<BookingCalendar> {
  CalendarSelection get selection => widget.selection;
  DateTime get today {
    final property =
        widget.properties
            .where((row) => row['id'] == selection.property)
            .firstOrNull ??
        widget.properties.firstOrNull;
    return DateUtils.dateOnly(
      DateTime.tryParse(text(property ?? {}, 'business_date')) ??
          DateTime.now(),
    );
  }

  DateTime get month => DateTime(selection.day.year, selection.day.month);
  DateTime get yearStart =>
      DateTime(today.year + selection.yearOffset, today.month);

  DateTime shiftDay(DateTime day, int offset) =>
      DateTime(day.year, day.month, day.day + offset);

  void selectMonth(int year, int month) {
    final last = DateUtils.getDaysInMonth(year, month);
    selection.day = DateTime(year, month, math.min(selection.day.day, last));
  }

  void step(int amount) => setState(() {
    if (selection.yearView) {
      selection.yearOffset += amount;
    } else {
      final target = DateTime(month.year, month.month + amount);
      selectMonth(target.year, target.month);
    }
  });

  void zoom(bool year) {
    if (selection.yearView == year) return;
    setState(() {
      selection.yearView = year;
      if (year) selection.yearOffset = 0;
    });
    widget.onZoom?.call();
  }

  Future<void> jumpToDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selection.day,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date != null && mounted) {
      setState(() => selection.day = date);
    }
  }

  List<DateTime> monthDays(DateTime first) {
    final offset = first.weekday - DateTime.monday;
    final length = DateUtils.getDaysInMonth(first.year, first.month);
    final count = ((offset + length + 6) ~/ 7) * 7;
    return List.generate(count, (i) => shiftDay(first, i - offset));
  }

  Map<DateTime, List<_DayBooking>> bookingsFor(
    List<Json> records,
    DateTime from,
    DateTime to,
  ) {
    final result = <DateTime, List<_DayBooking>>{};
    for (final booking in records) {
      final arrival = DateTime.tryParse(text(booking, 'arrival_date'));
      final departure = DateTime.tryParse(text(booking, 'departure_date'));
      if (booking['status'] != 'confirmed' ||
          arrival == null ||
          departure == null ||
          departure.isBefore(arrival) ||
          departure.isBefore(from) ||
          arrival.isAfter(to)) {
        continue;
      }
      final first = arrival.isBefore(from) ? from : arrival;
      final last = departure.isAfter(to) ? to : departure;
      for (var day = first; !day.isAfter(last); day = shiftDay(day, 1)) {
        final phase = arrival == departure
            ? BookingPhase.dayUse
            : day == departure
            ? BookingPhase.departure
            : day == arrival
            ? BookingPhase.arrival
            : BookingPhase.occupied;
        result.putIfAbsent(day, () => []).add((booking, phase));
      }
    }
    return result;
  }

  String phaseLabel(BookingPhase phase) => ui(switch (phase) {
    BookingPhase.arrival => 'Arrival',
    BookingPhase.occupied => 'Occupied night',
    BookingPhase.departure => 'Departure',
    BookingPhase.dayUse => 'Day use',
  });

  IconData phaseIcon(BookingPhase phase) => switch (phase) {
    BookingPhase.arrival => Icons.login,
    BookingPhase.occupied => Icons.bed_outlined,
    BookingPhase.departure => Icons.logout,
    BookingPhase.dayUse => Icons.wb_sunny_outlined,
  };

  Color phaseColor(BookingPhase phase) => switch (phase) {
    BookingPhase.arrival => const Color(0xFF006658),
    BookingPhase.occupied => const Color(0xFF43558C),
    BookingPhase.departure => const Color(0xFF824D17),
    BookingPhase.dayUse => const Color(0xFF775514),
  };

  String propertyName(Json row) =>
      widget.propertyLabel(text(row, 'property_name'));

  @override
  Widget build(BuildContext context) {
    final labels = MaterialLocalizations.of(context);
    final propertyNames = {
      '': ui('All properties'),
      for (final property in widget.properties)
        text(property, 'id'): widget.propertyLabel(text(property, 'name')),
    };
    final property = propertyNames.containsKey(selection.property)
        ? selection.property!
        : '';
    final records = widget.reservations
        .where((r) => property.isEmpty || r['property_id'] == property)
        .toList();
    final days = monthDays(month);
    final data = selection.yearView
        ? bookingsFor(
            records,
            yearStart,
            DateTime(yearStart.year, yearStart.month + 12, 0),
          )
        : bookingsFor(records, days.first, days.last);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            moveSelection(-1, -1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            moveSelection(1, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            moveSelection(-7, -3),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            moveSelection(7, 3),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => step(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => step(1),
        const SingleActivator(LogicalKeyboardKey.equal): () => zoom(false),
        const SingleActivator(LogicalKeyboardKey.minus): () => zoom(true),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  ui('Calendar'),
                  style: PmsStyle.pageTitle(context, size: 30),
                ),
                PmsButton(
                  ui('+ New reservation'),
                  primary: true,
                  onPressed: () => widget.onCreate(isoDate(selection.day)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: ui(
                        selection.yearView ? 'Previous year' : 'Previous month',
                      ),
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => step(-1),
                    ),
                    Tooltip(
                      message: ui('Go to date'),
                      child: TextButton(
                        onPressed: jumpToDate,
                        child: Text(
                          selection.yearView
                              ? '${labels.formatMonthYear(yearStart)} – ${labels.formatMonthYear(DateTime(yearStart.year, yearStart.month + 11))}'
                              : labels.formatMonthYear(month),
                          key: const ValueKey('calendar-period'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: ui(
                        selection.yearView ? 'Next year' : 'Next month',
                      ),
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => step(1),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => setState(() {
                        selection.day = today;
                        selection.yearOffset = 0;
                      }),
                      child: Text(ui('Today')),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(ui('Month')),
                          tooltip: ui('Zoom in to month'),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(ui('Year')),
                          tooltip: ui('Zoom out to year'),
                        ),
                      ],
                      showSelectedIcon: false,
                      selected: {selection.yearView},
                      onSelectionChanged: (value) => zoom(value.single),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: DropdownButton<String>(
                        key: const ValueKey('calendar-property'),
                        value: property,
                        isExpanded: true,
                        onChanged: (value) =>
                            setState(() => selection.property = value),
                        items: [
                          for (final option in propertyNames.entries)
                            DropdownMenuItem(
                              value: option.key,
                              child: Text(
                                option.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (selection.yearView)
              yearGrid(context, data)
            else
              LayoutBuilder(
                builder: (context, box) {
                  final dock = box.maxWidth >= 980;
                  final selected = data[selection.day] ?? const [];
                  final panel = dayPanel(context, selected);
                  final gridWidth = box.maxWidth - (dock ? 272 : 0);
                  final grid = monthGrid(
                    context,
                    days,
                    data,
                    dock: dock,
                    narrow:
                        gridWidth < 590 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.2,
                  );
                  return dock
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: grid),
                            const SizedBox(width: 16),
                            SizedBox(width: 256, child: panel),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [grid, const SizedBox(height: 12), panel],
                        );
                },
              ),
            finalInquiries(records),
          ],
        ),
      ),
    );
  }

  void moveSelection(int days, int months) {
    if (selection.yearView) {
      setState(() {
        final target = DateTime(month.year, month.month + months);
        selectMonth(target.year, target.month);
      });
    } else {
      setState(() => selection.day = shiftDay(selection.day, days));
    }
  }

  List<Widget> weekdayLabels({bool small = false}) {
    final days = WebStrings.current.language == 'hu'
        ? const ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return [
      for (final day in days)
        Expanded(
          child: Center(
            child: Text(
              day,
              style: TextStyle(
                fontSize: small ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: PmsStyle.muted,
              ),
            ),
          ),
        ),
    ];
  }

  Widget monthGrid(
    BuildContext context,
    List<DateTime> days,
    Map<DateTime, List<_DayBooking>> data, {
    required bool dock,
    required bool narrow,
  }) {
    final rows = days.length ~/ 7;
    final height = narrow
        ? 44.0
        : (((widget.viewportHeight ?? 800) - 220) / rows).clamp(56.0, 72.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 25, child: Row(children: weekdayLabels())),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (final date in days.skip(row * 7).take(7))
                Expanded(
                  child: dayCell(
                    date,
                    data[date] ?? const [],
                    height,
                    narrow,
                    dock,
                  ),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final phase in BookingPhase.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(phaseIcon(phase), size: 14, color: phaseColor(phase)),
                    const SizedBox(width: 4),
                    Text(
                      phaseLabel(phase),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget dayCell(
    DateTime date,
    List<_DayBooking> entries,
    double height,
    bool narrow,
    bool dock,
  ) {
    final inMonth = date.month == month.month;
    final selected = date == selection.day;
    void openDay() {
      setState(() => selection.day = date);
      if (!dock) showDay(date, entries);
    }

    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: selected
            ? const Color(0xFFFFF5C6)
            : inMonth
            ? Colors.white
            : const Color(0xFFF7F7F5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: selected ? const Color(0xFFD4A900) : const Color(0xFFEAEAE6),
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Semantics(
          label: MaterialLocalizations.of(context).formatFullDate(date),
          selected: selected,
          child: InkWell(
            key: ValueKey('calendar-day-${isoDate(date)}'),
            onTap: openDay,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: date == today
                          ? BoxDecoration(
                              color: PmsStyle.yellow,
                              borderRadius: BorderRadius.circular(5),
                            )
                          : null,
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: inMonth ? PmsStyle.ink : PmsStyle.muted,
                        ),
                      ),
                    ),
                    if (narrow)
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final phase
                                  in entries
                                      .map((entry) => entry.$2)
                                      .toSet()
                                      .take(3))
                                Icon(
                                  phaseIcon(phase),
                                  size: 10,
                                  color: phaseColor(phase),
                                ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      for (final entry in entries.take(
                        entries.length > 2 ? 1 : 2,
                      ))
                        bookingChip(date, entry),
                      if (entries.length > 2)
                        InkWell(
                          onTap: () => showDay(date, entries),
                          child: Text(
                            ui('+${entries.length - 1} more'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget bookingChip(DateTime date, _DayBooking entry) {
    final (booking, phase) = entry;
    final id = text(booking, 'id'), name = text(booking, 'guest_name');
    final color = phaseColor(phase);
    return Tooltip(
      message: '${phaseLabel(phase)} · $name · ${propertyName(booking)}',
      child: InkWell(
        key: ValueKey('calendar-booking-$id-${isoDate(date)}'),
        onTap: () => widget.onOpen(id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(phaseIcon(phase), size: 11, color: color),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.32,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showDay(DateTime day, List<_DayBooking> entries) {
    final date = isoDate(day);
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => PmsModal(
        title: dayLabel(context, day),
        actions: [
          if (entries.isEmpty)
            PmsButton(
              ui('Add a stay'),
              primary: true,
              onPressed: () {
                Navigator.pop(dialogContext);
                widget.onCreate(date);
              },
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (entries.isEmpty)
              Text(
                ui(
                  widget.loading
                      ? 'Loading bookings…'
                      : 'No bookings for this day.',
                ),
              ),
            for (final entry in entries)
              dayEntry(entry, () {
                Navigator.pop(dialogContext);
                widget.onOpen(text(entry.$1, 'id'));
              }),
          ],
        ),
      ),
    );
  }

  String dayLabel(BuildContext context, DateTime day) =>
      WebStrings.current.language == 'hu'
      ? MaterialLocalizations.of(context).formatFullDate(day)
      : isoDate(day);

  Widget dayEntry(_DayBooking entry, VoidCallback onOpen) {
    final (booking, phase) = entry;
    return ListTile(
      dense: true,
      minTileHeight: 49,
      contentPadding: EdgeInsets.zero,
      leading: Icon(phaseIcon(phase), size: 17, color: phaseColor(phase)),
      title: Text(
        text(booking, 'guest_name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${phaseLabel(phase)} · ${propertyName(booking)}'),
      onTap: onOpen,
    );
  }

  Widget dayPanel(BuildContext context, List<_DayBooking> entries) => Container(
    key: const ValueKey('calendar-selected-day'),
    padding: const EdgeInsets.fromLTRB(15, 12, 0, 12),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: PmsStyle.yellow, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          dayLabel(context, selection.day),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            ui(
              widget.loading
                  ? 'Loading bookings…'
                  : 'No bookings for this day.',
            ),
            style: const TextStyle(color: PmsStyle.muted),
          ),
        for (final entry in entries.take(5))
          dayEntry(entry, () => widget.onOpen(text(entry.$1, 'id'))),
        if (entries.length > 5)
          TextButton(
            onPressed: () => showDay(selection.day, entries),
            child: Text(ui('View all bookings')),
          ),
        if (entries.isEmpty) const SizedBox(height: 12),
        if (entries.isEmpty)
          PmsButton(
            ui('Add a stay'),
            onPressed: () => widget.onCreate(isoDate(selection.day)),
          ),
      ],
    ),
  );

  Widget yearGrid(
    BuildContext context,
    Map<DateTime, List<_DayBooking>> data,
  ) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 700
          ? 3
          : box.maxWidth >= 440
          ? 2
          : 1;
      final width = (box.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var offset = 0; offset < 12; offset++)
            SizedBox(
              width: width,
              child: miniMonth(
                context,
                DateTime(yearStart.year, yearStart.month + offset),
                data,
              ),
            ),
        ],
      );
    },
  );

  Widget miniMonth(
    BuildContext context,
    DateTime date,
    Map<DateTime, List<_DayBooking>> data,
  ) {
    final days = monthDays(date);
    final active = date.month == selection.day.month;
    return Material(
      color: active ? const Color(0xFFFFF9DE) : const Color(0xFFF9F9F7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('calendar-month-${date.year}-${date.month}'),
        onTap: () {
          selectMonth(date.year, date.month);
          zoom(false);
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                MaterialLocalizations.of(context).formatMonthYear(date),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Row(children: weekdayLabels(small: true)),
              for (var week = 0; week < 6; week++)
                Row(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(
                        child: miniDay(
                          context,
                          week * 7 + weekday < days.length
                              ? days[week * 7 + weekday]
                              : null,
                          date.month,
                          data,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget miniDay(
    BuildContext context,
    DateTime? date,
    int month,
    Map<DateTime, List<_DayBooking>> data,
  ) {
    final height = math.max(
      18.0,
      MediaQuery.textScalerOf(context).scale(11) * 1.2 + 4,
    );
    if (date == null || date.month != month) return SizedBox(height: height);
    final phases =
        data[date]?.map((entry) => entry.$2).toSet() ?? const <BookingPhase>{};
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: date == today || date == selection.day
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          if (phases.isNotEmpty)
            Tooltip(
              message: phases.map(phaseLabel).join(' · '),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 1,
                children: [
                  for (final phase in phases)
                    Container(width: 4, height: 3, color: phaseColor(phase)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget finalInquiries(List<Json> records) {
    final inquiries = records
        .where((record) => record['status'] == 'inquiry')
        .take(8)
        .toList();
    if (inquiries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ui('Inquiries'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          for (final inquiry in inquiries)
            ListTile(
              dense: true,
              title: Text(text(inquiry, 'guest_name')),
              subtitle: Text(
                '${propertyName(inquiry)} · ${text(inquiry, 'arrival_date')} → ${text(inquiry, 'departure_date')}',
              ),
              onTap: () => widget.onOpen(text(inquiry, 'id')),
            ),
        ],
      ),
    );
  }
}
