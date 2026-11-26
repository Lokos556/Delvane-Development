"""Operator workspace over the existing registration, identity and IFA records."""

from datetime import date

from fastapi import APIRouter, Cookie, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, ValidationError

import guest_reporting
import viza_identity


contract = viza_identity.contract
DOCUMENT_TYPES = {'id_card': 'SZEM_IG', 'passport': 'UTLEVEL', 'driver_license': 'VEZ_ENG', 'other': 'EGYEB'}
SEX = {'F': 'NO', 'M': 'FERFI', 'X': 'EGYEB_VAGY_NEM_ISMERT'}
SHARED_FIELDS = {'date_of_birth': 'szuletesiDatum', 'birth_place': 'szuletesiHely', 'sex': 'nem',
                 'nationality_country': 'allampolgarsagKod'}
SUBMISSION_FIELDS = ('full_name', 'birth_name', 'birth_place', 'date_of_birth', 'date_of_expiry', 'sex',
                     'nationality', 'mother_birth_name', 'document_type', 'document_number', 'address')


def country(value):
    try:
        return contract.country(value)
    except contract.ContractError:
        return None


def unstructured_identity(submitted):
    """Only map exact document/sex enumerations and unambiguous official codes."""
    doc = submitted.get('document_type')
    sex = submitted.get('sex')
    return {k: v for k, v in {
        'szuletesiDatum': submitted.get('date_of_birth'), 'szuletesiHely': submitted.get('birth_place'),
        'okmanyAzonositoSzam': submitted.get('document_number'),
        'okmanyTipus': DOCUMENT_TYPES.get(doc, doc) if doc in (*DOCUMENT_TYPES, *DOCUMENT_TYPES.values()) else None,
        'nem': SEX.get(sex, sex) if sex in (*SEX, *SEX.values()) else None,
        'allampolgarsagKod': country(submitted.get('nationality')),
    }.items() if v}


def progress(con, record, now):
    """Derive per-guest progress without consulting the email provider state."""
    status = record['verification_status']
    if status == 'verified':
        return 'verified'
    if status == 'rejected':
        return 'needs_correction'
    guest_id, org, reservation = (record[key] for key in ('id', 'organization_id', 'reservation_id'))
    if record['completeness'] == 'complete' or con.execute('''SELECT 1 FROM guest_checkin_events
        WHERE guest_record_id=? AND organization_id=? AND reservation_id=? AND event_type='guest_confirmed' LIMIT 1''',
        (guest_id, org, reservation)).fetchone():
        return 'submitted'
    if con.execute('''SELECT 1 FROM guest_checkin_tokens WHERE guest_record_id=? AND organization_id=?
        AND reservation_id=? AND status='active' AND expires_at>? LIMIT 1''', (guest_id, org, reservation, now)).fetchone():
        return 'awaiting_registration'
    return 'awaiting_invitation'


class ReportingEdit(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    full_name: str = Field(min_length=2, max_length=255)
    birth_name: str = Field(default='', max_length=255)
    country_of_residence: str
    postal_code: str
    ifa_status: str
    effective_from: date
    nationality_country: str | None = None
    confirm_alignment: bool = False


class IdentityChanges(contract.DTO):
    manual: dict[str, str | None] = Field(default_factory=dict)
    third_country_applicable: bool | None = None
    confirm_ambiguities: bool = False


class Edit(contract.DTO):
    revision: list[int] = Field(min_length=2, max_length=2)
    reason: str = Field(default='', max_length=500)
    identity: IdentityChanges | None = None
    reporting: ReportingEdit | None = None


def latest_revision(con, guest_id, projected):
    reporting = con.execute('SELECT COALESCE(MAX(revision),0) n FROM guest_reporting_profiles WHERE guest_record_id=?',
                            (guest_id,)).fetchone()['n']
    return [projected['history'][-1]['revision'] if projected['history'] else 0, reporting]


def reporting_person(identity, saved):
    result = {}
    for key, viza_key in SHARED_FIELDS.items():
        value = identity.get(viza_key)
        if key == 'nationality_country':
            value = country(value)
            if value not in guest_reporting.COUNTRIES:
                value = None
        result[key] = value or saved.get(key)
    return result


def shared_conflicts(identity, saved):
    review = reporting_person(identity, saved)
    return [key for key in SHARED_FIELDS if saved.get(key) and review[key] != saved[key]]


def identity_defaults(effective, submitted, profile):
    values = unstructured_identity(submitted)
    for key, target in SHARED_FIELDS.items():
        value = profile.get(key)
        if key == 'nationality_country':
            value = country(value)
        if value:
            values.setdefault(target, value)
    return {key: value for key, value in values.items() if key not in effective}


def workspace(backend, con, row, business_day):
    gid, org, rid = (row[key] for key in ('id', 'organization_id', 'reservation_id'))
    projected = viza_identity.project(backend, con, gid)
    effective = projected['effective']
    protected = viza_identity.vault_data(backend, con, gid, org)
    submission = projected['guest_submission']
    if submission is None and con.execute('''SELECT 1 FROM guest_checkin_events WHERE guest_record_id=?
        AND organization_id=? AND reservation_id=? AND event_type='guest_confirmed' LIMIT 1''', (gid, org, rid)).fetchone():
        # Old submissions did not archive the original display name and nationality separately.
        submission = {key: protected.get(key, row.get(key)) for key in SUBMISSION_FIELDS}
    fallback = submission or {**row, **protected}
    profile, _ = guest_reporting.profile_on(backend, con, gid, business_day)
    saved = profile or {}
    defaults = identity_defaults(effective, fallback, saved)
    display = {**defaults, **effective}
    accepted = country(display.get('allampolgarsagKod'))
    display['allampolgarsagKod'] = accepted
    verification = con.execute('''SELECT status,verification_method,verified_at,review_note
        FROM guest_identity_verifications WHERE guest_record_id=? AND organization_id=? AND reservation_id=?''',
        (gid, org, rid)).fetchone()
    status = verification['status'] if verification else 'not_submitted'
    actual = con.execute('''SELECT e.business_date FROM guest_occupancy o JOIN stay_events e ON e.id=o.arrival_event_id
        WHERE o.guest_id=? AND o.reservation_id=? AND o.voided=0 ORDER BY o.started_at DESC LIMIT 1''', (gid, rid)).fetchone()
    reference = date.fromisoformat(actual['business_date'] if actual else row['arrival_date'])
    assessment = viza_identity.readiness(backend, con, gid, reference)
    frozen = con.execute('''SELECT 1 FROM ntak_guest_ids WHERE guest_record_id=? AND organization_id=? AND property_id=?''',
                         (gid, org, row['property_id'])).fetchone()
    mapping_required = (row['nationality'] not in guest_reporting.COUNTRIES
                        and saved.get('nationality_country') not in guest_reporting.COUNTRIES)
    ntak_blockers = (["missing_guest_reporting_profile"] if not saved else []) + (
        ['nationality_country_mapping_required'] if mapping_required else []) + (
        ['identity_normalization_unresolved'] if not frozen else [])
    try:
        document_required = date.fromisoformat(display.get('szuletesiDatum') or '') <= contract.years_before(reference, 14)
    except ValueError:
        document_required = None
    return {
        'id': gid, 'reservation_id': rid, 'full_name': row['full_name'], 'business_date': str(business_day),
        'reference_date': str(reference), 'document_required': document_required,
        'registration_stage': progress(con, {**row, 'verification_status': status}, backend.now_iso()),
        'can_verify': row['reservation_status'] == 'confirmed' and row['completeness'] == 'complete',
        'verification': dict(verification) if verification else {'status': status},
        'revision': latest_revision(con, gid, projected), 'identity': display,
        'suggested_fields': list(defaults), 'original': projected['original'],
        'submitted': submission, 'submitted_snapshot': projected['guest_submission'] is not None,
        'raw_nationality': effective.get('allampolgarsagKod') if not accepted else None,
        'third_country_applicable': projected['third_country_applicable'], 'ambiguities': projected['ambiguities'],
        'reporting_profile': saved, 'reporting_conflicts': shared_conflicts(display, saved),
        'reporting_defaults': {**reporting_person(display, saved), 'full_name': saved.get('full_name') or row['full_name'],
                               'birth_name': saved.get('birth_name', fallback.get('birth_name', ''))},
        'ifa_reasons': guest_reporting.IFA_REASONS,
        'viza_countries': sorted(contract.COUNTRIES), 'ntak_countries': sorted(guest_reporting.COUNTRIES),
        'readiness': {'viza_blockers': assessment['blockers'], 'ntak_blockers': ntak_blockers,
                      'actual_arrival_recorded': bool(actual), 'transmission_enabled': False},
    }


def save_reporting(backend, con, user, row, body, reason, request):
    current, _ = guest_reporting.profile_on(backend, con, row['id'], body.effective_from)
    saved = current or {}
    projected = viza_identity.project(backend, con, row['id'])
    effective = projected['effective']
    fallback = projected['guest_submission'] or {**row, **viza_identity.vault_data(backend, con, row['id'], row['organization_id'])}
    effective = {**identity_defaults(effective, fallback, saved), **effective}
    if shared_conflicts(effective, saved) and not body.confirm_alignment:
        raise backend.pms_error('reporting_alignment_required', None, 409)
    person = reporting_person(effective, saved)
    if body.nationality_country is not None:
        person['nationality_country'] = body.nationality_country or None
    try:
        profile = guest_reporting.Profile.model_validate({**person, **body.model_dump(exclude={'confirm_alignment', 'nationality_country'}),
            'reason': reason, 'source': 'correction' if current else 'manual'})
    except ValidationError as error:
        raise backend.pms_error('invalid_guest_reporting_fields', str(error.errors()[0]['loc'][0])) from None
    guest_reporting.apply_profile(backend, con, user, row, profile, request)


def install(backend):
    router = APIRouter(prefix='/api/registration/records/{guest_id}/workspace')

    def access(con, guest_id, session):
        user = backend.require_user(session)
        backend.require_roles(user, 'owner', 'manager')
        row = viza_identity.scope(con, user['organization_id'], guest_id)
        backend._lock_reservation(con, row['reservation_id'], user['organization_id'])
        row = viza_identity.scope(con, user['organization_id'], guest_id)
        reservation = con.execute('SELECT status FROM reservations WHERE id=? AND organization_id=?',
                                  (row['reservation_id'], user['organization_id'])).fetchone()
        return user, {**row, 'reservation_status': reservation['status']}

    @router.get('')
    def get(guest_id: str, business_date: date | None = None, rosa_session: str | None = Cookie(default=None)):
        with backend.db() as con:
            _, row = access(con, guest_id, rosa_session)
            return workspace(backend, con, row, business_date or date.fromisoformat(row['arrival_date']))

    @router.put('')
    def put(guest_id: str, body: Edit, request: Request, rosa_session: str | None = Cookie(default=None)):
        reason = body.reason.strip()
        with backend.db() as con:
            user, row = access(con, guest_id, rosa_session)
            projected = viza_identity.project(backend, con, guest_id)
            if latest_revision(con, guest_id, projected) != body.revision:
                raise backend.pms_error('guest_workspace_changed', None, 409)
            if not reason and body.identity is not None and body.reporting is None:
                current = workspace(backend, con, row, date.fromisoformat(row['arrival_date']))
                if current['registration_stage'] in {'awaiting_invitation', 'awaiting_registration'}:
                    reason = 'Initial guest identity draft'
            if len(reason) < 3:
                raise backend.pms_error('invalid_fields', 'reason')
            if body.identity is not None:
                edit = viza_identity.IdentityEdit(**body.identity.model_dump(), reason=reason)
                viza_identity.apply_edit(backend, con, user, row, edit)
            if body.reporting is not None:
                save_reporting(backend, con, user, row, body.reporting, reason, request)
            row = {**viza_identity.scope(con, user['organization_id'], guest_id), 'reservation_status': row['reservation_status']}
            return workspace(backend, con, row, body.reporting.effective_from if body.reporting else date.fromisoformat(row['arrival_date']))

    backend.app.include_router(router)
