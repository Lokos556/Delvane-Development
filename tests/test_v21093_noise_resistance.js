// Regression test for OCR speckles, split alphanumeric document numbers, and the five required fields.
const fs=require('fs'),path=require('path');
const src=fs.readFileSync(path.join(__dirname,'..','static','guest-checkin.js'),'utf8');
function normalizeNationality(value){const code=String(value||'').toUpperCase().replace(/[^A-Z]/g,'');return code==='HUN'?'Hungarian':'';}
function nationalityFromMRZ(value){return String(value||'').toUpperCase().includes('HUN')?'Hungarian':'';}
const state={document_type:'auto'};
const start=src.indexOf('function normalizePersonName'),end=src.indexOf('async function getRosaOCRWorker',start);
if(start<0||end<0)throw new Error('Parser functions not found');
eval(src.slice(start,end)+`
const input=\`ORSIAG/ HUNGARY
Csaladi gs akong Fag. pane arid Gil nam
KOVACS | 7 MARTON
Nem/Sex: F/M Allampolgarsag/Nationality: HUN Eis
sziletési ido/Date o birth: 2008.05.14
Okmanyazonositd/Doc. No.: AB12 3456
Nairds/Signature\`;
const out=parseVisibleText(input);
const expected={full_name:'KOVACS MARTON',date_of_birth:'2008-05-14',sex:'M',nationality:'Hungarian',document_number:'AB123456'};
for(const [field,value] of Object.entries(expected))if(out[field]!==value)throw new Error(field+' expected '+value+' but got '+JSON.stringify(out[field]));
const junk=parseVisibleText('//// 7 | ~~~ IDENTITY CARD DOCUMENT SIGNATURE HUN Eis random -- ...');
if(junk&&junk.full_name)throw new Error('Random OCR noise was accepted as a name: '+junk.full_name);
console.log('PASS: all five required fields survive OCR noise; random fragments are not accepted as a name');
`);
