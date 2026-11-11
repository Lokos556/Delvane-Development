// Regression test using synthetic, redacted-style Hungarian ID OCR output.
const fs = require('fs');
const src = fs.readFileSync('static/guest-checkin.js', 'utf8');
function normalizeNationality(x){return String(x||'').toUpperCase()==='HUN'?'HUN':''}
function nationalityFromMRZ(x){return String(x||'').toUpperCase()==='HUN'?'HUN':''}
const state={document_type:'auto'};
const start=src.indexOf('function normalizePersonName');
const end=src.indexOf('async function getRosaOCRWorker', start);
if(start<0||end<0) throw new Error('Parser functions not found');
eval(src.slice(start,end)+String.raw`
const input = 'AZONOSITO IGAZOLVANY/ IDENTITY\nCala. sut6navIF ani pase and. Giver name\nKOVACS MARTON\nem/Sex: F/M Allampolgarsag/ Nationality: HUN\nSzuletesi ido/Date of birth: 2008.05.14\nNn Okményazonositd/Dac. No. AB123456\nAlairs/Signature: i 3 7';
const out = parseVisibleText(input);
if(out.full_name !== 'KOVACS MARTON') throw new Error('Expected name, got: '+out.full_name);
if(out.document_number !== 'AB123456') throw new Error('Expected clean document number, got: '+out.document_number);
if(out.date_of_birth !== '2008-05-14') throw new Error('DOB regressed: '+out.date_of_birth);
if(out.nationality !== 'HUN') throw new Error('Nationality regressed: '+out.nationality);
if(out.sex !== 'M') throw new Error('Sex legend regressed: '+out.sex);
console.log('PASS: noisy name label, document number, DOB, nationality, sex legend');
`);
