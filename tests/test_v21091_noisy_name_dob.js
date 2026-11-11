// Regression test with synthetic values and OCR label errors seen in field reports.
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'static', 'guest-checkin.js'), 'utf8');
function normalizeNationality(x){return String(x||'').toUpperCase()==='HUN'?'HUN':''}
function nationalityFromMRZ(x){return String(x||'').toUpperCase()==='HUN'?'HUN':''}
const state={document_type:'auto'};
const start=src.indexOf('function normalizePersonName');
const end=src.indexOf('async function getRosaOCRWorker', start);
if(start<0||end<0) throw new Error('Could not locate parser');
eval(src.slice(start,end) + `
const input = \`AZONOSITO IGAZOLVANY / IDENTITY
Csaladi gs akong Fag. pane arid Gil nam
KOVACS MARTON
Nem/Sex: F/M Allampolgarsag / Nationality: HUN
Sailetesiido/Date o birth: 2008.05.14
Ervenyessegi ido/Date of expiry: 2030.01.01
OkmanyazonositdlDoc. No.: AB123456
Alairas/Signature\`;
const out = parseVisibleText(input);
if(out.full_name !== 'KOVACS MARTON') throw new Error('Name not extracted: '+out.full_name);
if(out.date_of_birth !== '2008-05-14') throw new Error('DOB not extracted: '+out.date_of_birth);
if(out.nationality !== 'HUN') throw new Error('Nationality changed: '+out.nationality);
if(out.document_number !== 'AB123456') throw new Error('Document number not extracted cleanly: '+out.document_number);
if(out.sex !== 'M') throw new Error('Sex legend incorrect: '+out.sex);
console.log('PASS: noisy name label, OCR-mangled DOB label, document number, nationality, sex');
`);
