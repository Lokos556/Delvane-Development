from datetime import date
import pytest
import app
import guest_reporting as g
from ntak_protocol import ReportingBlocked,guest_hash
from test_flutter_reservation_reception import client,login,body

PROFILE={'country_of_residence':'IT','postal_code':'47921','full_name':'Sergey Cherkasov','date_of_birth':'1986-01-01',
 'birth_place':'Москва','sex':'FERFI','ifa_status':'KOTELES','effective_from':'2026-01-01','reason':'Fictional reviewed identity','source':'manual'}


def record(client):
    login(client);rid=client.post('/api/reservations',json=body()).json()['id']
    with app.db() as con:gid=con.execute('SELECT id FROM guest_records WHERE reservation_id=?',(rid,)).fetchone()['id']
    return gid,'/api/registration/records/'+gid+'/reporting-profile'


def test_profile_correction_frozen_identity_and_history(client):
    gid,url=record(client)
    assert client.put(url,json=PROFILE).status_code==200
    with app.db() as con:
        with pytest.raises(ReportingBlocked):g.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid)
        first=g.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid,canonical_identity='Sergey Cherkasov Москва 1986.01.01.')
    corrected={**PROFILE,'date_of_birth':'1987-02-11','ifa_status':'im5','source':'correction','reason':'NZ_04B fictional correction'}
    assert client.put(url,json=corrected).status_code==200
    assert client.put(url,json=corrected).json()['duplicate']
    with app.db() as con:
        assert g.identity_for_submission(app,con,'org_casa_rosa','prop_flora',gid,canonical_identity='corrected identity')==first
        stored=con.execute('SELECT encrypted_payload FROM guest_reporting_profiles WHERE guest_record_id=?',(gid,)).fetchall()
        assert all('Cherkasov' not in r['encrypted_payload'] for r in stored)
        salt=con.execute('SELECT encrypted_salt FROM ntak_property_salts').fetchone()['encrypted_salt']
        assert '$2a$' not in salt
        with pytest.raises(ReportingBlocked):g.identity_for_submission(app,con,'org_casa_rosa','prop_terra',gid,canonical_identity='no')
        g.migrate(con,app.now_iso());g.migrate(con,app.now_iso())
    result=client.get(url,params={'business_date':'2026-01-01'}).json()
    assert result['profile']['date_of_birth']=='1987-02-11'
    assert result['profile']['country_of_residence']=='IT' and result['defaults']['nationality'] is None
    assert len(result['history'])==2 and result['identity_state']=='frozen'
    assert 'salt' not in result
    assert client.put(url,json={**PROFILE,'source':'scanner'}).status_code==422
    login(client,'cleaner');assert client.get(url,params={'business_date':'2026-01-01'}).status_code==403


@pytest.mark.parametrize('status',list(g.IFA_REASONS))
def test_official_ifa_codes(client,status):
    gid,url=record(client)
    assert client.put(url,json={**PROFILE,'ifa_status':status}).status_code==200


def test_official_hash_and_unicode():
    salt=b'$2a$10$zDaBMMumxc/1rLNjHHg55O'
    assert guest_hash('dr. Teszt Edit Budapest 1979.07.12.',salt)=='473/rnEtql5aigjoPG33qz1uARVImcW'
    assert guest_hash('Őrült Ágnes Łódź 1990.01.01.',salt)==guest_hash('Őrült Ágnes Łódź 1990.01.01.',salt)
    assert guest_hash('Őrült Ágnes Łódź 1990.01.01.',salt)!=guest_hash('Orult Agnes Lodz 1990.01.01.',salt)
