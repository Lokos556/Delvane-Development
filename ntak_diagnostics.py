"""Safe NTAK field diagnostics. Official v9.07 section9.5 pp89-100.

Never retain remote values/prose or infer guest identity from an array index.
This is not SOAP evidence storage (Tasks16-17).
"""
from functools import lru_cache
import json
import re
from ntak_contracts import contracts, XSD

# Exact documented keys, grouped only for local recovery guidance, not retry policy.
GROUPS = {
    'required': 'NemUres KotelezoMezo KotelezoSzallasdij IfaTerhelesHianya HianyzoIfaMertek',
    'format': 'UresMezo NemKuldendoElem Formatum HibasErtek Negativ NegativTerhelesHiba HibasKitoltes HibasKategoria HibasOrszagKod FoglalasOrszagKod IrszHiba',
    'range': 'ElsodlegesMax ElsodlegesMin MasodlagosMax MasodlagosMin MagasEletkor HibasSzuletesiEv',
    'tax': 'ifaTipusHiba ErvenytelenIfa TargynaponErvenyesIfa FoglalasSzintuIfa NemHatalyosIfaMentesseg',
    'capacity': 'NappaliHasznalatHiba nemUzemeloSzobak OsszesSzobaszamEllentmondas KiadottDarabszamElteres TobbKiadott FerohelyekEllentmondasa HibasFerohelyOsszeg UzemenKivuliSzobakSzama HibasKiadhatoHelySzam HibasKiadottHelySzam HibasOosOsszeg HibasOooOsszeg ElteresRegisztraltAdatokban',
    'history': 'JovobeliDatum JovobeniErkezes MultbeliTavozas lemondasFrissites MultbeliDatum JavithatosagIdokorlat AdatszolgaltatasIdokorlat IsmetlodoAzonosito NemTalalhato MarLetezoUjZaras ErvenytelenModositoZaras EgyedisegKorlatozas',
    'connection': 'SzerverHiba AdatszolgaltatasTiltva FeldolgozasHiba HianyzoSzolgaltatoAdatokAdoszam NemTalalhatoPms ElteroKuldorendszer NemTalalhatoSzolgaltatasiHely HianyzoAlairas HibasAlgoritmus UresTanusitvany TanusitvanyTipusHiba ElteresCNadatok ElteresOUadatok ElteresOIDadatok NemMegbizhatoTanus\u00edtvany',
}
CATALOG = {key: group for group, keys in GROUPS.items() for key in keys.split()}
# The field tables pp108-109 use these spellings, unlike the summary p99.
# Recognize both verbatim; do not rewrite any official response.
CATALOG.update({'ElteresCnAdatok':'connection','ElteresOidAdatok':'connection'})
# Local preflight failures, deliberately separate from the66 official catalog keys.
LOCAL_SECURITY = {key:'connection' for key in (
    'ntak_canonicalization_invalid','ntak_signed_info_invalid','rsa_4096_required',
    'ntak_security_clock_invalid','ntak_timestamp_invalid','certificate_not_yet_valid',
    'certificate_expired_or_expiring','certificate_key_mismatch','missing_certificate_or_key',
    'unreadable_certificate_or_key','invalid_credential_reference','ntak_signature_invalid',
    'ntak_verification_trust_missing','ntak_endpoint_binding_invalid',
    'ntak_credential_binding_missing','ntak_credential_binding_mismatch')}



def migrate(con, now):
    con.executescript("""
    CREATE TABLE IF NOT EXISTS ntak_diagnostic_results (
      attempt_id TEXT PRIMARY KEY REFERENCES government_delivery_attempts(id) ON DELETE CASCADE,
      job_id TEXT NOT NULL REFERENCES ntak_jobs(id) ON DELETE CASCADE,
      organization_id TEXT NOT NULL, property_id TEXT NOT NULL,
      phase TEXT NOT NULL, diagnostics_json TEXT NOT NULL, created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_ntak_diagnostic_job ON ntak_diagnostic_results(job_id,created_at);
    """)
    con.execute('INSERT OR IGNORE INTO schema_migrations(version,name,applied_at) VALUES (3088,?,?)',
                ('ntak_field_diagnostics', now))


@lru_cache(maxsize=5)
def field_names(operation):
    return {n.get('name') for n in contracts()[operation][1].iter('{'+XSD+'}element')}


def safe_field(operation, value):
    if value == 'GLOBAL':
        return value
    if not isinstance(value, str) or len(value) > 512:
        return 'GLOBAL'
    # Only schema vocabulary and bounded numeric indices; never preserve arbitrary text.
    parts = value.split('.')
    if not parts or any(not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*(?:\[[0-9]{1,6}\])?', p)
                        or p.split('[')[0] not in field_names(operation) for p in parts):
        return 'GLOBAL'
    return value


def sanitize(operation, items):
    return [{'severity': 'warning' if item.get('severity') == 'warning' else 'error',
             'code': item.get('code') if item.get('code') in CATALOG or item.get('code') in LOCAL_SECURITY else 'unknown_remote_diagnostic',
             'field': safe_field(operation, item.get('field')),
             'guidance': CATALOG.get(item.get('code'), LOCAL_SECURITY.get(item.get('code'), 'review'))}
            for item in items]


def record(con, job, attempt, phase, items, now):
    con.execute("""INSERT INTO ntak_diagnostic_results
      (attempt_id,job_id,organization_id,property_id,phase,diagnostics_json,created_at)
      VALUES (?,?,?,?,?,?,?)""", (attempt, job['id'], job['organization_id'], job['property_id'],
      phase, json.dumps(sanitize(job['operation'], items), ensure_ascii=False), now))


def history(con, org, prop, job):
    return [{**dict(row), 'diagnostics': json.loads(row['diagnostics_json'])}
            for row in con.execute("""SELECT attempt_id,phase,created_at,diagnostics_json
            FROM ntak_diagnostic_results WHERE organization_id=? AND property_id=? AND job_id=?
            ORDER BY created_at,attempt_id""", (org, prop, job))]
