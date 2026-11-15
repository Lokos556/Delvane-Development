"""Read-only owner query plans. SQL and factual prose never come from a model."""
import re
import unicodedata
from datetime import date, timedelta

INTENTS = ('count', 'arrivals', 'departures', 'cancelled', 'upcoming', 'availability',
           'attention', 'readiness', 'maintenance', 'unknown', 'write')
SCOPES = ('all', 'today', 'tomorrow', 'week', 'month', 'next_weekend', 'upcoming')
PLAN_SCHEMA = {'type': 'object', 'additionalProperties': False,
    'properties': {'intent': {'type': 'string', 'enum': list(INTENTS)},
                   'scope': {'type': 'string', 'enum': list(SCOPES)},
                   'property': {'type': 'string'}},
    'required': ['intent', 'scope', 'property']}


def fold(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', value.lower())
                   if not unicodedata.combining(c))


def local_plan(message, context):
    q = fold(message)
    if re.search(r'\b(cancel|delete|create|book|send|change|update|move|reassign|assign|set|remove)\b', q) or re.search(r'\b(torold|mondd le|hozz letre|kuldd|modosits|allits|helyezd|oszd|add at)', q):
        # Past-tense cancelled/cancellation questions do not match cancel.
        return {'intent': 'write', 'scope': 'all', 'property': ''}
    scope = ('next_weekend' if 'next weekend' in q or 'kovetkezo hetveg' in q else
             'tomorrow' if 'tomorrow' in q or 'holnap' in q else
             'month' if 'this month' in q or 'ebben a honap' in q else
             'week' if 'this week' in q or 'ezen a het' in q else
             'today' if 'today' in q or re.search(r'\bma\b', q) else 'all')
    intent = ('cancelled' if 'cancelled' in q or 'canceled' in q or 'lemond' in q else
              'availability' if re.search(r'available|availability|free|szabad|elerheto|ures', q) else
              'arrivals' if re.search(r'arriv|\bcheck[ -]?in\b|\bchecking in\b|erkez', q) else
              'departures' if re.search(r'depart|checking out|check.?out|leav|tavoz|kijelentkez', q) else
              'count' if re.search(r'how many.*reservations|reservation count|hany.*foglal', q) else
              'upcoming' if re.search(r'upcoming.*reservations|summari[sz]e.*reservations|kovetkezo.*foglal|kozelgo.*foglal', q) else
              'readiness' if re.search(r'\bready\b|keszen', q) else
              'maintenance' if re.search(r'maintenance|karbant', q) else
              'attention' if re.search(r'attention|tasks|teendo|feladat|figyelm|aggaszto|concerning|not ready|aren.t ready', q) else
              'unknown')
    if intent == 'unknown' and re.search(r'\b(and|what about|es|akkor)\b', q):
        intent = context.get('intent', 'unknown')
        if scope == 'all': scope = context.get('scope','all')
    if intent in {'upcoming', 'attention'} and scope == 'all': scope = 'upcoming'
    if intent == 'availability' and scope == 'all' and re.search(r'\b(currently|now|most|jelenleg)\b', q): scope = 'today'
    return {'intent': intent, 'scope': scope, 'property': ''}


def date_range(scope, today):
    if scope == 'today': return today, today + timedelta(days=1)
    if scope == 'tomorrow': return today + timedelta(days=1), today + timedelta(days=2)
    if scope == 'week':
        start = today - timedelta(days=today.weekday())
        return start, start + timedelta(days=7)
    if scope == 'month':
        start = today.replace(day=1)
        return start, (start.replace(year=start.year+1, month=1) if start.month == 12
                       else start.replace(month=start.month+1))
    if scope == 'next_weekend':
        start = today + timedelta(days=(5-today.weekday()) % 7 or 7)
        return start, start + timedelta(days=2)
    if scope == 'upcoming': return today, None
    return None, None


def property_scope(properties, message, context, requested=''):
    q = fold(message)
    matches = [p for p in properties if re.search(r'(?<!\w)'+re.escape(fold(p['name']))+r'(?!\w)', q)]
    if requested:
        matches = [p for p in properties if fold(requested) in {fold(p['name']), fold(p['id'])}]
        if not matches: return None, True
    if len(matches) > 1: return None, True
    if matches: return matches[0], False
    named_question = re.search(r'^(?:is|does|can)\s+(.+?)\s+(?:ready|available|free|have\b)', q)
    if not named_question:
        named_question = re.search(r'^(?:a|az)\s+(.+?)\s+(?:keszen|szabad|elerheto)', q)
    if named_question and named_question[1].strip() not in {'it','everything','all properties','anything'}:
        return None, True
    if re.search(r'\b(there|that property|it|ott|annal|abban|and|es|akkor)\b', q) and context.get('property_id'):
        return next((p for p in properties if p['id'] == context['property_id']), None), False
    # Unknown named scope must not silently become an all-properties answer.
    named = re.search(r'\b(?:at|in|for)\s+(.+?)(?:\?|$)', message, re.I)
    if named and not re.fullmatch(r'(?:next weekend|this week|this month|today|tomorrow|\d{4}-\d{2}-\d{2}(?: to \d{4}-\d{2}-\d{2})?)', fold(named[1]).strip(' .?')) and fold(named[1]).strip(' .?') not in {'my properties', 'all properties', 'the business', 'my business', 'this month', 'this week', 'tomorrow', 'today'}:
        return None, True
    if re.search(r'\b(?:prop_[a-z0-9_-]+)\b', q): return None, True
    return None, False


def answer(con, user, message, language, context, today, plan=None):
    hu = language == 'hu'
    choose = lambda en, hu_text: hu_text if hu else en
    plan = plan or local_plan(message, context)
    if (not isinstance(plan, dict) or set(plan) != {'intent','scope','property'} or
        plan['intent'] not in INTENTS or plan['scope'] not in SCOPES or
        not isinstance(plan['property'], str) or len(plan['property']) > 200):
        plan = {'intent':'unknown','scope':'all','property':''}
    properties = [dict(p) for p in con.execute('SELECT id,name FROM properties WHERE organization_id=? ORDER BY name', (user['organization_id'],))]
    prop, invalid = property_scope(properties, message, context, plan['property'])
    intent, scope = plan['intent'], plan['scope']
    facts = {'timezone':'Europe/Budapest', 'as_of':str(today), 'intent':intent,
             'scope':scope, 'property_id':prop['id'] if prop else None}
    updated = {'intent':intent, 'scope':scope, **({'property_id':prop['id'], 'last_property_name':prop['name']} if prop else {})}
    def result(text, route='database'):
        return {'answer':text, 'facts':facts, 'context':updated, 'intent':intent,
                'route':route, 'provider':'local', 'proposals':[], 'read_only':True}
    if invalid:
        facts["scope_unavailable"]=True
        return result(choose('I cannot identify that property within your accessible records. Please select an accessible property by its exact name.',
            'Ezt a szálláshelyet nem tudom azonosítani a hozzáférhető adatok között. Adja meg egy hozzáférhető szálláshely pontos nevét.'), 'unknown')
    if intent == 'write':
        return result(choose('This assistant is read-only. I can look up PMS information, but cannot change records or send messages.',
            'Ez az asszisztens csak lekérdezésre használható. Megnézhetem a PMS adatait, de nem módosíthatok adatokat és nem küldhetek üzenetet.'), 'read_only')
    if intent in {'count','arrivals','departures','cancelled','upcoming','availability'} and re.search(r'\b(before|after|since|until|elott|utan|paid|unpaid|pending|fizetett|fizetetlen|fuggoben)\b', fold(message)):
        return result(choose('That filter is not supported by this lookup. Please use exact stay dates or the PMS filters; I will not return an unfiltered total.', 'Ezt a szűrőt ez a lekérdezés nem támogatja. Adjon meg pontos dátumokat, vagy használja a PMS szűrőit; nem adok szűretlen összesítést.'), 'clarification')
    if intent != 'unknown' and re.search(r'\b(last month|next month|last week|next week(?!end)|last year|this year|yesterday|tegnap|elozo honap|jovo honap)\b', fold(message)):
        return result(choose('Please specify this period with ISO dates (YYYY-MM-DD). I will not substitute a different period.', 'Ezt az időszakot ÉÉÉÉ-HH-NN dátumokkal adja meg. Nem helyettesítem másik időszakkal.'), 'clarification')
    start, end = date_range(scope, today)
    dates = re.findall(r'\b\d{4}-\d{2}-\d{2}\b', message)
    if dates:
        try:
            start = date.fromisoformat(dates[0])
            end = date.fromisoformat(dates[1]) if len(dates)>1 else start+timedelta(days=1)
            if len(dates)>2 or end<=start or (end-start).days>366: raise ValueError()
        except ValueError:
            return result(choose('Use valid ISO dates, with checkout after arrival and a range of at most 366 days.', 'Érvényes ÉÉÉÉ-HH-NN dátumokat adjon meg; a távozás legyen az érkezés után, legfeljebb 366 napos időszakkal.'), 'clarification')
    if re.search(r'\b(then|same dates|akkor|ugyanakkor)\b', fold(message)) and not dates and context.get('date_from'):
        try:
            start=date.fromisoformat(context['date_from'])
            end=date.fromisoformat(context['date_to_exclusive']) if context.get('date_to_exclusive') else None
        except (ValueError, TypeError): pass
    facts.update(date_from=str(start) if start else None, date_to_exclusive=str(end) if end else None)
    updated.update(date_from=facts['date_from'], date_to_exclusive=facts['date_to_exclusive'])
    base = 'r.organization_id=? AND p.organization_id=?'
    args = [user['organization_id'], user['organization_id']]
    if prop: base += ' AND r.property_id=?'; args.append(prop['id'])
    if intent in {'count','arrivals','departures','cancelled','upcoming'}:
        status = 'cancelled' if intent == 'cancelled' else ('confirmed' if re.search(r'confirmed|visszaigazolt', fold(message)) else None) if intent == 'count' else 'confirmed'
        if status: base += ' AND r.status=?'; args.append(status)
        column = 'departure_date' if intent == 'departures' else 'arrival_date'
        if start: base += f' AND r.{column}>=?'; args.append(str(start))
        if end: base += f' AND r.{column}<?'; args.append(str(end))
        query = ' FROM reservations r JOIN properties p ON p.id=r.property_id WHERE '+base
        total = con.execute('SELECT COUNT(*) c'+query, tuple(args)).fetchone()['c']
        records = [dict(x) for x in con.execute('SELECT r.id,r.guest_name,r.arrival_date,r.departure_date,r.status,p.name property_name'+query+' ORDER BY r.'+column+',r.id LIMIT 50', tuple(args))]
        facts.update(count=total, records=records, truncated=total > 50,
                     date_basis=column, status=status or 'all')
        labels = {'count':choose('Confirmed reservations' if status else 'Reservations (all statuses)', 'Visszaigazolt foglalások' if status else 'Foglalások (minden állapot)'),
                  'arrivals':choose('Confirmed arrivals', 'Visszaigazolt érkezések'),
                  'departures':choose('Confirmed departures', 'Visszaigazolt távozások'),
                  'cancelled':choose('Cancelled reservations', 'Lemondott foglalások'),
                  'upcoming':choose('Upcoming confirmed reservations', 'Közelgő visszaigazolt foglalások')}
        period = (f" · {start} – {end-timedelta(days=1)}" if end else
                  choose(f" · from {start}", f" · {start} napjától")) if start else ''
        text = f"{labels[intent]}{(' · '+prop['name']) if prop else ''}{period}: {total}."
        if intent != 'count':
            text += ''.join(f"\n• {r['guest_name']} · {r['property_name']} · {r['arrival_date']} → {r['departure_date']}" for r in records)
        if total > 50: text += choose('\nShowing the first 50 records.', '\nAz első 50 találat látható.')
        if intent == 'cancelled' and start:
            text += choose('\nFiltered by planned arrival date; cancellation occurrence dates may be missing.', '\nA szűrés a tervezett érkezés dátuma alapján történt; a lemondás időpontja hiányozhat.')
        return result(text, 'database' if intent in {'count','cancelled'} else 'operations')
    if intent == 'availability':
        if not start or not end:
            return result(choose('Which stay dates should I check? You can ask about next weekend (Saturday arrival, Monday checkout).',
                'Melyik időszakot nézzem meg? Kérdezhet a következő hétvégéről (szombati érkezés, hétfői távozás).'), 'clarification')
        available=[]
        for p in properties:
            if prop and p['id'] != prop['id']: continue
            rooms = [dict(x) for x in con.execute('SELECT id,inventory_count FROM room_types WHERE organization_id=? AND property_id=? AND active=1', (user['organization_id'], p['id']))]
            # Same occupancy convention as reservation creation: checkout frees that night.
            possible=False
            for room in rooms:
                bookings=list(con.execute("SELECT arrival_date,departure_date FROM reservations WHERE organization_id=? AND property_id=? AND status='confirmed' AND (room_type_id=? OR room_type_id IS NULL) AND arrival_date<? AND departure_date>?", (user['organization_id'],p['id'],room['id'],str(end),str(start))))
                if all(sum(r['arrival_date']<=str(day)<r['departure_date'] for r in bookings) < room['inventory_count'] for day in (start+timedelta(days=i) for i in range((end-start).days))):
                    possible=True
            if possible: available.append(p)
        facts['properties']=available
        return result(choose(f'PMS inventory available for {start} → {end}: ', f'A PMS nyilvántartása szerint elérhető {start} → {end}: ')+
            (', '.join(p['name'] for p in available) or choose('none.', 'nincs.'))+
            choose('\nBased on confirmed PMS reservations and active room inventory; external channel restrictions are not checked.', '\nA visszaigazolt PMS-foglalások és az aktív szobakészlet alapján; a külső csatornák korlátozásait nem ellenőriztem.'))
    if intent == 'attention':
        due=(end-timedelta(days=1)) if end else today+timedelta(days=7)
        sql="SELECT t.id,t.title,t.scheduled_date,t.status,p.name property_name FROM work_tasks t JOIN properties p ON p.id=t.property_id WHERE t.organization_id=? AND p.organization_id=? AND t.status!='complete' AND t.scheduled_date<=?"
        params=[user['organization_id'],user['organization_id'],str(due)]
        if scope not in {'all','upcoming'} and start:
            sql+=' AND t.scheduled_date>=?';params.append(str(start))
        else:
            facts['date_from']=None
        facts['date_to_exclusive']=str(due+timedelta(days=1))
        if prop: sql+=' AND t.property_id=?';params.append(prop['id'])
        records=[dict(r) for r in con.execute(sql+' ORDER BY t.scheduled_date,t.id LIMIT 50',tuple(params))]
        facts['tasks']=records
        return result(choose('Open work due by '+str(due)+':', 'Nyitott feladatok '+str(due)+' napjáig:')+
            (''.join(f"\n• {r['title']} · {r['property_name']} · {r['scheduled_date']}" for r in records) or choose(' none recorded.', ' nincs rögzítve.'))+
            choose('\nUp to 50 tasks; this is a task list, not a complete business risk assessment.', '\nLegfeljebb 50 feladat; ez feladatlista, nem teljes üzleti kockázatértékelés.'))
    return result(choose('I do not have a supported lookup for that information. Ask about reservation counts, arrivals, departures, cancellations, upcoming stays, availability or open tasks.',
        'Ehhez az információhoz nincs támogatott lekérdezésem. Kérdezhet a foglalások számáról, érkezésekről, távozásokról, lemondásokról, közelgő foglalásokról, elérhetőségről vagy nyitott feladatokról.'), 'unknown')
