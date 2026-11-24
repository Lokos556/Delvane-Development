"""Room-level housekeeping for allocated overnight stays."""

from datetime import datetime
from zoneinfo import ZoneInfo

import physical_units

PREFIX = 'unit-cleaning:'


def task_unit(task):
    key = task['source_key'] or ''
    return key.split(':')[2] if key.startswith(PREFIX) else None


def waits_for_checkout(con, task):
    return not checkout_observed(task) or occupied(con, task_unit(task))


def checkout_observed(task):
    return task_unit(task) is not None and task['source_key'].count(':') == 3


def occupied(con, unit_id):
    return con.execute("""SELECT 1 FROM guest_occupancy
        WHERE unit_id=? AND ended_at IS NULL AND voided=0 LIMIT 1""", (unit_id,)).fetchone() is not None


def decorate_tasks(con, tasks, day):
    for task in tasks:
        unit_id = task_unit(task)
        if not unit_id:
            continue
        task['checkout_observed'] = checkout_observed(task)
        unit = con.execute("""SELECT v.unit_number,v.building FROM physical_units u
            JOIN physical_unit_versions v ON v.unit_id=u.id
            WHERE u.id=? AND u.organization_id=? AND u.property_id=? AND v.effective_from<=?
            ORDER BY v.effective_from DESC LIMIT 1""",
            (unit_id, task['organization_id'], task['property_id'], str(day))).fetchone()
        if unit:
            task['unit_label'] = label(unit)


def label(unit):
    return ' · '.join(part for part in (unit['building'], unit['unit_number']) if part)


def refresh(backend, con, prop, reservation, assigned, lower, upper):
    """Return current work keys, or None for a booking without physical evidence."""
    rid = reservation['id']
    org, property_id = prop['organization_id'], prop['id']
    plans = {row['unit_id']: row['planned_day'] for row in con.execute("""
        SELECT unit_id,MAX(date_to) planned_day FROM reservation_unit_allocations
        WHERE reservation_id=? AND organization_id=? AND property_id=? AND state='active'
        GROUP BY unit_id""", (rid, org, property_id))}
    visits = con.execute("""SELECT o.unit_id,o.ended_at,o.departure_event_id,e.timezone,e.kind
        FROM guest_occupancy o LEFT JOIN stay_events e ON e.id=o.departure_event_id
        WHERE o.reservation_id=? AND o.voided=0 ORDER BY o.ended_at,o.departure_event_id""",
        (rid,)).fetchall()
    if not plans and not visits:
        return None
    present = {visit['unit_id'] for visit in visits if not visit['ended_at']}
    releases = {visit['unit_id']: visit for visit in visits
                if visit['unit_id'] not in present and visit['kind'] in ('depart', 'transfer')}
    units = sorted(set(plans) | {visit['unit_id'] for visit in visits})
    existing = con.execute("""SELECT * FROM work_tasks
        WHERE organization_id=? AND property_id=? AND previous_reservation_id=? AND source_key LIKE 'unit-cleaning:%'
        ORDER BY created_at,id""", (org, property_id, rid)).fetchall()
    valid = set()
    for unit_id in units:
        base = f'{PREFIX}{rid}:{unit_id}'
        tasks = [row for row in existing if task_unit(row) == unit_id]
        release = releases.get(unit_id)
        planned = plans.get(unit_id, reservation['departure_date'])
        if release:
            actual = datetime.fromisoformat(release['ended_at']).astimezone(ZoneInfo(release['timezone']))
            day, earliest = str(actual.date()), actual.strftime('%H:%M')
            key = f"{base}:{release['departure_event_id']}"
            if not lower <= day <= upper and not any(
                row['source_key'] == key and row['status'] in ('open', 'in_progress') for row in tasks
            ):
                continue
        else:
            if (reservation['status'] != 'confirmed' or unit_id not in plans
                    or (not lower <= planned <= upper and not tasks and unit_id not in present)):
                continue
            day, earliest, key = planned, prop['checkout_time'], base
        nxt = con.execute("""SELECT r.id,a.date_from,r.arrival_time FROM reservation_unit_allocations a
            JOIN reservations r ON r.id=a.reservation_id
            WHERE a.unit_id=? AND a.organization_id=? AND a.property_id=? AND a.state='active'
                AND r.status='confirmed' AND r.id!=? AND a.date_from>=?
            ORDER BY a.date_from,r.id LIMIT 1""", (unit_id, org, property_id, rid, min(day, planned))).fetchone()
        deadline = (nxt['arrival_time'] or prop['checkin_time']) if nxt and nxt['date_from'] <= day else None
        next_id = nxt['id'] if nxt else None
        priority = 'high' if deadline else 'normal'
        detail = 'Actual room checkout recorded.' if release else 'Waiting for actual room checkout.'
        valid.add(key)
        task = next((row for row in tasks if row['source_key'] == key), None)
        if task is None and release:
            task = next((row for row in tasks if row['source_key'] == base and row['status'] == 'open'), None)
        if task is None and not tasks and len(units) == 1:
            task = con.execute("""SELECT w.* FROM work_tasks w WHERE w.previous_reservation_id=?
                AND w.organization_id=? AND w.property_id=? AND w.source_key LIKE 'cleaning:%'
                AND w.status='open' AND NOT EXISTS (
                    SELECT 1 FROM reservations r WHERE r.id!=? AND r.organization_id=w.organization_id
                    AND r.property_id=w.property_id AND r.status='confirmed' AND r.stay_type='overnight'
                    AND 'cleaning:' || r.property_id || ':' || r.departure_date=w.source_key
                    AND NOT EXISTS (SELECT 1 FROM reservation_unit_allocations a WHERE a.reservation_id=r.id AND a.state='active')
                ) ORDER BY w.created_at,w.id LIMIT 1""", (rid, org, property_id, rid)).fetchone()
        if task and task['status'] == 'complete':
            continue
        if task:
            task_id = task['id']
            con.execute("""UPDATE work_tasks SET source_key=?,detail=?,scheduled_date=?,earliest_time=?,
                deadline_time=?,priority=?,next_reservation_id=?,status=CASE WHEN status='cancelled' THEN 'open' ELSE status END
                WHERE id=?""", (key, detail, day, earliest, deadline, priority, next_id, task_id))
        else:
            task_id = backend.new_id('task')
            assignee = tasks[-1]['assigned_to'] if tasks else assigned
            con.execute("""INSERT INTO work_tasks
                (id,organization_id,property_id,assigned_to,task_type,title,detail,scheduled_date,earliest_time,
                 deadline_time,priority,status,source_key,previous_reservation_id,next_reservation_id,created_at)
                VALUES (?,?,?,?,'cleaning',?,?,?,?,?,?,'open',?,?,?,?)""",
                (task_id, org, property_id, assignee, f"Clean {prop['name']}", detail, day, earliest,
                 deadline, priority, key, rid, next_id, backend.now_iso()))
        backend.ensure_task_checklist(con, org, task_id)
    return valid


def readiness(con, org, property_id, day):
    result = []
    for unit in physical_units.units_on(con, org, property_id, day):
        if not unit['active']:
            continue
        unit_id = unit['id']
        period = con.execute("""SELECT state FROM physical_unit_periods
            WHERE unit_id=? AND date_from<=? AND date_to>=?
            AND (cancelled_from IS NULL OR cancelled_from>?) LIMIT 1""",
            (unit_id, str(day), str(day), str(day))).fetchone()
        task = con.execute("""SELECT id,source_key,status FROM work_tasks WHERE organization_id=? AND property_id=?
            AND (source_key LIKE ? OR ((source_key LIKE ? OR source_key LIKE ?) AND scheduled_date<=?))
            AND status IN ('open','in_progress')
            ORDER BY scheduled_date,id LIMIT 1""",
            (org, property_id, f'{PREFIX}%:{unit_id}:%', f'{PREFIX}%:{unit_id}',
             f'day-use-cleaning:%:{unit_id}', str(day))).fetchone()
        state = ('unavailable' if period else 'occupied' if occupied(con, unit_id)
                 else 'waiting_for_checkout' if task and task_unit(task) and waits_for_checkout(con, task)
                 else 'cleaning' if task else 'ready')
        result.append({'unit_id': unit_id, 'label': label(unit), 'state': state})
    return result
