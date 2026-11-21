"""In-process response fixtures and evidence assertions for Task 20 tests."""

from datetime import timedelta, timezone
from hashlib import sha256
from uuid import uuid4

from lxml import etree

import app
import ntak_reporting
from ntak_contracts import NAMESPACE, OPERATIONS, validate
from test_ntak_evidence import package
from test_ntak_reporting import get


def add(parent, name, value=None):
    node = etree.SubElement(parent, f'{{{NAMESPACE}}}{name}')
    node.text = value
    return node


class Rehearsal:
    def __init__(self, client):
        self.client = client
        self.now = ntak_reporting.datetime.now(timezone.utc)
        self.outcomes = {}
        self.receipts = {}
        self.requests = {}

    def exchange(self, operation, xml, **scope):
        assert scope == {'property_id': 'prop_flora', 'environment': 'test'}
        request = validate(operation, xml)
        response = etree.Element(f'{{{NAMESPACE}}}{OPERATIONS[operation]}Response')
        if operation == 'verification':
            receipt = request.findtext(f'.//{{{NAMESPACE}}}feldolgozasAzonosito')
            message = self.receipts[receipt]
            responses = self.outcomes.get(message)
            status, diagnostics = responses.pop(0) if responses else ('TELJESEN_SIKERES', ())
            result = add(response, 'uzenetValaszok')
            add(result, 'feldolgozasAzonosito', receipt)
            add(result, 'statusz', status)
            warnings = add(result, 'figyelmeztetesLista')
            errors = add(result, 'hibaLista')
            for severity, field, code, value in diagnostics:
                item = add(warnings if severity == 'warning' else errors, 'hiba')
                add(item, 'mezoNeve', field)
                add(item, 'kuldottErtek', value)
                add(item, 'hibaKulcs', code)
                add(item, 'hibaUzenet', 'Synthetic rehearsal diagnostic')
        else:
            message = request.findtext(f'.//{{{NAMESPACE}}}uzenetId')
            receipt = str(uuid4())
            self.receipts[receipt] = message
            add(response, 'feldolgozasAzonosito', receipt)
        self.requests.setdefault(message, []).append((operation, xml))
        wire = etree.tostring(response)
        validate(operation, wire, response=True)
        return wire

    def finish(self, job, expected='succeeded', *, pending=False, diagnostics=()):
        initial = get(job)
        assert initial['state'] == 'ready', initial['error_code']
        message = initial['message_id']
        status = {'succeeded': 'TELJESEN_SIKERES', 'rejected': 'TELJESEN_HIBAS',
                  'review_required': 'VIZSGALANDO'}[expected]
        self.outcomes[message] = ([('BEFOGADVA', ())] if pending else []) + [(status, diagnostics)]
        for state in ['accepted'] * (2 if pending else 1) + [expected]:
            self.now = max(self.now, ntak_reporting.datetime.now(timezone.utc)) + timedelta(minutes=6)
            ntak_reporting.worker_once(app.db, transport=self, now=self.now)
            assert get(job)['state'] == state
        final = get(job)
        receipt = final['processing_id']
        assert self.receipts[receipt] == message
        assert final['payload_json'] == initial['payload_json']

        exported = package(self.client, job)
        assert exported.status_code == 200, exported.text
        evidence = exported.json()
        assert evidence['root_job_id'] == job
        assert evidence['official_acceptance_confirmed'] is False
        assert evidence['transmission_enabled'] is False
        attempts = [a for a in evidence['attempts'] if a['job_id'] == job]
        assert len(attempts) == (3 if pending else 2)
        for attempt, (operation, wire) in zip(attempts, self.requests[message], strict=True):
            assert attempt['request_hash'] == sha256(wire).hexdigest()
            phases = {e['phase']: e for e in evidence['events'] if e['attempt_id'] == attempt['id']}
            assert set(phases) == {'request', 'response', 'outcome'}
            assert phases['request']['operation'] == operation
            assert phases['outcome']['processing_id'] == receipt
        assert 'wire_base64' not in exported.text
        assert 'Synthetic rehearsal diagnostic' not in exported.text
        return evidence
