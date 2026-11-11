// Regression test for noisy Hungarian ID visible-zone OCR.
// Synthetic values only; never use real identity-document data in this test.
const fs = require('fs');
const src = fs.readFileSync(require('path').join(__dirname, '..', 'static', 'guest-checkin.js'), 'utf8');
function normalizeNationality(x){return String(x||'').toUpperCase()==='HUN'?'HUN':''}
function nationalityFromMRZ(x){return String(x||'').toUpperCase()==='HUN'?'HUN':''}
const state={document_type:'auto'};
const start=src.indexOf('function normalizePersonName');
const end=src.indexOf('async function getRosaOCRWorker', start);
if(start<0||end<0) throw new Error('Could not locate parser functions');
eval(src.slice(start,end) + `
const input = \`AZONOSITO IGAZOLVANY/ IDENTITY
Csalad) és-utdnév/Fapily pai arid. Give name
KOVACS MARTON
em/Sex: F/M Allampolgarsag/ Nationality: HUN
Szuletesi ido/Date of birth: 2008.05.14
Okményazonosité/Dac. No. AB123456
Alairas/Signature\`;
const out = parseVisibleText(input);
if(out.full_name !== 'KOVACS MARTON') throw new Error('Name not extracted: '+out.full_name);
if(out.document_number !== 'AB123456') throw new Error('Document number not extracted cleanly: '+out.document_number);
if(out.date_of_birth !== '2008-05-14') throw new Error('DOB changed: '+out.date_of_birth);
if(out.nationality !== 'HUN') throw new Error('Nationality changed: '+out.nationality);
if(out.sex !== 'M') throw new Error('Sex legend should map to M, got: '+out.sex);
console.log('PASS: name, document number, DOB, nationality, and sex legend');
`);
