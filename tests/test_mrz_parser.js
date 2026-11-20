// Synthetic regression tests for the browser MRZ parser. Uses no real identity data.
// Run from the project root: node tests/test_mrz_parser.js
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('static/guest-checkin.js', 'utf8');
const start = source.indexOf('function dateFromYYMMDD');
const end = source.indexOf('function imageQuality');
assert(start >= 0 && end > start, 'Could not locate MRZ parser source block');
const context = {};
vm.createContext(context);
vm.runInContext(source.slice(start, end) + '\nthis.testAPI={parseMRZ,allMRZChecksPass};', context);
const { parseMRZ, allMRZChecksPass } = context.testAPI;
// Regression guard for the Hungarian bilingual sex legend and document-number fallback.
assert.ok(source.includes('const sexLegend='), 'sex legend handling must exist');
assert.ok(source.includes("(sexLegend?'M':'')"), 'F/M legend must map to male, not female');
assert.ok(source.includes('OCR may recognize the label but place the document number on the following line'), 'next-line document number fallback must exist');
const value = ch => ch === '<' ? 0 : /[0-9]/.test(ch) ? Number(ch) : ch.charCodeAt(0) - 55;
const checkDigit = text => String([...text].reduce((sum, ch, i) => sum + value(ch) * [7, 3, 1][i % 3], 0) % 10);
function td1() {
  const doc = 'D23145890', dob = '740812', expiry = '120415';
  let a = ('I<UTO' + doc + checkDigit(doc) + '<'.repeat(15)).slice(0, 30);
  let b = (dob + checkDigit(dob) + 'F' + expiry + checkDigit(expiry) + 'UTO' + '<'.repeat(11) + '0').slice(0, 30);
  const c = 'ERIKSSON<<ANNA<MARIA'.padEnd(30, '<').slice(0, 30);
  const composite = a.slice(5, 30) + b.slice(0, 7) + b.slice(8, 15) + b.slice(18, 29);
  b = b.slice(0, 29) + checkDigit(composite);
  return [a, b, c];
}
function td2() {
  const a = ('I<UTO' + 'ERIKSSON<<ANNA<MARIA').padEnd(36, '<').slice(0, 36);
  const doc = 'D23145890', dob = '740812', expiry = '120415';
  let b = doc + checkDigit(doc) + 'UTO' + dob + checkDigit(dob) + 'F' + expiry + checkDigit(expiry) + '<'.repeat(7);
  b = b.slice(0, 35) + checkDigit(b.slice(0, 10) + b.slice(13, 20) + b.slice(21, 35));
  return [a, b];
}
function td3() {
  const a = ('P<UTO' + 'ERIKSSON<<ANNA<MARIA').padEnd(44, '<').slice(0, 44);
  const doc = 'L898902C3', dob = '740812', expiry = '120415', optional = 'ZE184226B<<<<<<';
  let b = doc + checkDigit(doc) + 'UTO' + dob + checkDigit(dob) + 'F' + expiry + checkDigit(expiry) + optional;
  const composite = b.slice(0, 10) + b.slice(13, 20) + b.slice(21, 43);
  b = b.slice(0, 43) + checkDigit(composite);
  return [a, b];
}
for (const [format, lines] of [['TD1', td1()], ['TD2', td2()], ['TD3', td3()]]) {
  const parsed = parseMRZ(lines.join('\n'));
  assert.ok(parsed, `${format} should parse`);
  assert.equal(parsed.mrz_format, format, `${format} should be detected as the correct format`);
  assert.ok(allMRZChecksPass(parsed), `${format} check digits should validate`);
  assert.equal(parsed.full_name, 'ANNA MARIA ERIKSSON');
}
const collapsedTD1 = parseMRZ(td1().join(''));
assert.ok(collapsedTD1, 'TD1 should parse even when OCR removes all three row breaks');
assert.equal(collapsedTD1.mrz_format, 'TD1');
assert.equal(collapsedTD1.full_name, 'ANNA MARIA ERIKSSON');
assert.ok(!source.includes('merged.birth_name=merged.full_name'), 'Unknown birth names must never be invented');
assert.equal(/Tesseract\.recognize\(\s*input/.test(source), false, 'Scanner must not use the one-shot worker API');
assert.ok(source.includes('Tesseract.createWorker('), 'Scanner should initialize a reusable worker');
console.log('PASS: synthetic TD1, TD2 and TD3 parser tests; persistent-worker source assertions.');
