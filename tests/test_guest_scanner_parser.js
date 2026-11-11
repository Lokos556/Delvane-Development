const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
let source = fs.readFileSync(__dirname + '/../static/guest-checkin.js', 'utf8').replace(/\nboot\(\);?\s*$/, '');
source += '\nglobalThis.__test = {parseMRZ, parseVisibleText, dateFromYYMMDD, applyParsed, renderFields, getState:()=>state, setState:(s)=>state=s, setReservation:(r)=>state={reservation:r}};';
const mockElements = {};
const context = {
  document: { getElementById: (id) => (mockElements[id] ||= { innerHTML: '', value: '', tagName: 'INPUT', dispatchEvent(){} }), querySelector: () => null, createElement: () => ({}) },
  location: { pathname: '/guest/checkin/test-token' },
  window: {},
  Intl, Date, Math, String, Object, Array, RegExp, Number, JSON, Promise,
  console,
};
vm.createContext(context);
vm.runInContext(source, context);
const { parseMRZ, parseVisibleText, dateFromYYMMDD, applyParsed, renderFields, getState } = context.__test;
const passport = parseMRZ('P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO7408122F1204159ZE184226B<<<<<10');
assert(passport, 'TD3 passport sample should parse');
assert.equal(passport.document_type, 'passport');
assert.equal(passport.full_name, 'ANNA MARIA ERIKSSON');
assert.equal(passport.date_of_birth, '1974-08-12');
assert.equal(passport.document_number, 'L898902C3');
assert.equal(passport.confidence, 'verified');
// A non-numeric character in the MRZ date must remain unverified rather than
// being silently corrected. The guest can review and correct the visible field.
const passportOcrTypo = parseMRZ('P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nL898902C36UTO74O8122F1204159ZE184226B<<<<<10');
assert(passportOcrTypo, 'an MRZ with OCR errors should still yield reviewable suggestions');
assert.equal(passportOcrTypo.document_number, 'L898902C3');
assert.equal(passportOcrTypo.date_of_birth, '');
assert.equal(passportOcrTypo.confidence, 'manual_review');
const id = parseMRZ('I<UTOD231458907<<<<<<<<<<<<<<<\n7408122F1204159UTO<<<<<<<<<<<6\nERIKSSON<<ANNA<MARIA<<<<<<<<<<');
assert(id, 'TD1 identity card sample should parse');
assert.equal(id.document_type, 'id_card');
assert.equal(id.full_name, 'ANNA MARIA ERIKSSON');
assert.equal(id.date_of_birth, '1974-08-12');
assert.equal(id.document_number, 'D23145890');
assert.equal(id.confidence, 'verified');
assert.equal(dateFromYYMMDD('740812'), '1974-08-12');
assert.equal(dateFromYYMMDD('741332'), '');
const visible = parseVisibleText('Teljes név: TESZT ANNA\nSzületési idő: 2001. 02. 03.\nOkmány szám: AB123456');
assert(visible, 'Hungarian labelled visible text should yield suggestions');
assert.equal(visible.full_name, 'TESZT ANNA');
assert.equal(visible.date_of_birth, '2001-02-03');
assert.equal(visible.document_number, 'AB123456');
const splitLineVisible = parseVisibleText('SZEMÉLYAZONOSÍTÓ IGAZOLVÁNY\nCSALÁDI ÉS UTÓNÉV / FAMILY NAME AND GIVEN NAME\nTESZT ANNA\nÁLLAMPOLGÁRSÁG / NATIONALITY\nHUN\nSZÜLETÉSI IDŐ / DATE OF BIRTH\n2001. 02. 03.\nÉRVÉNYESSÉGI IDŐ / DATE OF EXPIRY\n2031. 05. 20.\nOKMÁNYAZONOSÍTÓ / DOCUMENT NO\nAB123456\nNEM / SEX\nNŐ');
assert.equal(splitLineVisible.full_name, 'TESZT ANNA');
assert.equal(splitLineVisible.nationality, 'Hungarian');
assert.equal(splitLineVisible.date_of_birth, '2001-02-03');
const bilingualSameLineDate = parseVisibleText('SZÜLETÉSI IDŐ / DATE OF BIRTH 2007. 11. 03.\nÉRVÉNYESSÉGI IDŐ / DATE OF EXPIRY 2030. 04. 05.');
assert.equal(bilingualSameLineDate.date_of_birth, '2007-11-03', 'DOB parser must find the date after a bilingual label on the same line');

assert.equal(splitLineVisible.date_of_expiry, '2031-05-20');
assert.equal(splitLineVisible.document_number, 'AB123456');
assert.equal(splitLineVisible.sex, 'F', 'Hungarian NŐ must map to female');

// Regression: reverse-side OCR must not put a document number into a name field,
// accept a numeric birthplace, or leave the country suffix attached to a real place.
const noisyReverse = parseVisibleText(`Születési hely/Place of birth: 3 (MAGYARORSZAG)\nSzületési név/Name at birth: 12345\nAnyja születési neve/Mother's maiden name: 330441PE\nSzületési idő/Date of birth: 2001. 02. 03.`);
assert.equal(noisyReverse.birth_place, '', 'numeric OCR fragment is not a birthplace');
assert.equal(noisyReverse.birth_name, '', 'numeric OCR fragment is not a birth name');
assert.equal(noisyReverse.mother_birth_name, '', 'document-number-like OCR must not populate mother birth name');
const realReverse = parseVisibleText('Születési hely/Place of birth: MISKOLC (MAGYARORSZAG)');
assert.equal(realReverse.birth_place, 'MISKOLC', 'remove the country suffix from a valid birthplace');
const sexLegendOnly = parseVisibleText('Nem/Sex: F/M\nTeljes név: TESZT ANNA');
assert.equal(sexLegendOnly.sex, 'M', 'Hungarian ID F/M legend is mapped to male in this check-in flow');
const mrzWithInvalidSex = parseMRZ('I<UTOD231458907<<<<<<<<<<<<<<<\n7408122I1204159UTO<<<<<<<<<<<6\nERIKSSON<<ANNA<MARIA<<<<<<<<<<');
assert.equal(mrzWithInvalidSex.sex, '', 'I is not a valid ICAO MRZ sex marker and must never be entered as sex');
context.__test.setState(splitLineVisible);
const populatedFields = renderFields();
assert(!populatedFields.includes('date_of_expiry'), 'expiry date must not be a guest-facing check-in field');
for (const [id, value] of [['full_name','TESZT ANNA'],['date_of_birth','2001-02-03'],['document_number','AB123456']]) {
  assert(populatedFields.includes(`id=\"${id}\"`) && populatedFields.includes(`value=\"${value}\"`), `${id} input should render with its extracted value`);
}
context.__test.applyParsed(splitLineVisible);
for (const [id, value] of [['full_name','TESZT ANNA'],['date_of_birth','2001-02-03'],['sex','F'],['nationality','Hungarian'],['document_number','AB123456']]) assert.equal(mockElements[id].value, value, `${id} should be written into the existing visible field`);
context.__test.setReservation({property_name:'Test',arrival_date:'2026-10-20',departure_date:'2026-10-22'});
applyParsed(visible);
assert.equal(getState().scan_method, 'camera_ocr', 'visual OCR result must not be mislabeled as MRZ');
console.log('PASS: TD3/TD1 MRZ, conservative OCR error handling, split-line Hungarian visible OCR, populated form inputs, scan-method provenance');
