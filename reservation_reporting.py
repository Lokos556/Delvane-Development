"""Normal booking facts; missing facts block reporting, not booking operations."""
import json
import re
from fastapi import HTTPException
from ntak_contracts import contracts,XSD
import physical_units
from ntak_countries import COUNTRIES


def migrate(backend,con):
    backend.add_column_if_missing(con,'reservations','ntak_booking_id','TEXT')
    backend.add_column_if_missing(con,'reservations','booking_created_at','TEXT')
    # Existing stable IDs/timestamps are factual; never replace them with guessed dates.
    con.execute('UPDATE reservations SET ntak_booking_id=id WHERE ntak_booking_id IS NULL')
    con.execute("UPDATE reservations SET booking_created_at=created_at WHERE booking_created_at IS NULL AND source='Direct'")
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (?,?,?)',(3076,'normal_reservation_reporting_facts',backend.now_iso()))


def save(con,org,rid,values,now):
    allowed={'garantaltFoglalas','vendegKuldoOrszaga','ertekesitesiCsatorna','piaciSzegmens','expected_guest_count'}
    if set(values)-allowed:raise HTTPException(422,'Unknown reservation reporting field')
    schema=contracts()['reservation'][1]
    for key,typ in [('ertekesitesiCsatorna','ErtekesitesiCsatornaType'),('piaciSzegmens','PiaciSzegmensType')]:
        if values.get(key) is not None and values[key] not in schema.xpath('./xs:simpleType[@name="'+typ+'"]//xs:enumeration/@value',namespaces={'xs':XSD}):
            raise HTTPException(422,'Invalid official booking classification')
    if values.get('garantaltFoglalas') is not None and type(values['garantaltFoglalas']) is not bool:raise HTTPException(422,'Guarantee must be boolean or unknown')
    country=values.get('vendegKuldoOrszaga')
    if country is not None and not (country in COUNTRIES or country=='EGYEBKULFOLDI'):raise HTTPException(422,'Invalid sending country')
    expected=values.get('expected_guest_count')
    if expected is not None and (type(expected) is not int or not 1<=expected<100):raise HTTPException(422,'Expected guest count must be between 1 and 99')
    r=con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,org)).fetchone()
    previous=con.execute('SELECT facts_json FROM ntak_reservation_facts WHERE reservation_id=?',(rid,)).fetchone()
    merged=json.loads(previous['facts_json']) if previous else {}
    merged.update(values)
    import business_days
    business_days.dirty_range(con,org,r['property_id'],r['arrival_date'],'system','Reservation reporting facts changed')
    con.execute('''INSERT INTO ntak_reservation_facts(reservation_id,organization_id,property_id,facts_json,updated_at) VALUES (?,?,?,?,?)
      ON CONFLICT(reservation_id) DO UPDATE SET property_id=excluded.property_id,facts_json=excluded.facts_json,updated_at=excluded.updated_at''',(rid,org,r['property_id'],json.dumps(merged,ensure_ascii=False,sort_keys=True),now))


def facts(con,row,legacy):
    import reservation_allocations
    result=dict(legacy)
    allocations=reservation_allocations.active(con,row['id'])
    if not allocations and row['status']=='cancelled':
        # Last factual revision retains the allocation description after release.
        job=con.execute("SELECT j.payload_json FROM ntak_jobs j JOIN government_outbox o ON o.id=j.id JOIN ntak_reservation_versions v ON v.reservation_id=o.reservation_id WHERE o.reservation_id=? AND j.logical_key=('reservation:' || v.reservation_id || ':' || v.revision)",(row['id'],)).fetchone()
        if job:
            old=json.loads(job['payload_json']).get('foglalasEsemeny',{})
            if old.get('foglaltLakoegysegek'):result['foglaltLakoegysegek']=old['foglaltLakoegysegek']
    if allocations:
        units={}
        for a in allocations:
            versions=physical_units.units_on(con,row['organization_id'],row['property_id'],a['date_from'])
            unit=next(v for v in versions if v['id']==a['unit_id'])
            units[a['unit_id']]={'tipus':unit['classification'],'ferohelyKapacitas':unit['single_beds']+2*unit['double_beds']}
        result['foglaltLakoegysegek']={'foglaltLakoegyseg':list(units.values())}
    return result


def snapshot(backend,con,rid,org):
    row=con.execute('SELECT * FROM reservations WHERE id=? AND organization_id=?',(rid,org)).fetchone()
    old=con.execute('SELECT facts_json FROM ntak_reservation_facts WHERE reservation_id=?',(rid,)).fetchone()
    data=json.loads(old['facts_json']) if old else {}
    required=['garantaltFoglalas','vendegKuldoOrszaga','ertekesitesiCsatorna','piaciSzegmens','expected_guest_count']
    missing=[k for k in required if data.get(k) is None]
    derived=facts(con,row,data)
    if not derived.get('foglaltLakoegysegek'):missing.append('foglaltLakoegysegek')
    if row['total_huf'] is None:missing.append('total_huf')
    if not row['booking_created_at']:missing.append('booking_created_at')
    return {'values':{k:data.get(k) for k in required},'missing_fields':missing,'ntak_booking_id':row['ntak_booking_id'] or row['id'],'booking_created_at':row['booking_created_at']}
