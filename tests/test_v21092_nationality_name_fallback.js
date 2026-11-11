// Synthetic regression test for latest noisy Hungarian ID OCR.
const fs=require('fs'), path=require('path');
const src=fs.readFileSync(path.join(__dirname,'..','static','guest-checkin.js'),'utf8');
function normalizeNationality(value){const v=String(value||'').trim();if(!v)return '';const code=v.toUpperCase().replace(/[^A-Z]/g,'');if(code.length===3)return code==='HUN'?'Hungarian':'';return v.toUpperCase()==='HUNGARIAN'?'Hungarian':'';}
function nationalityFromMRZ(value){return String(value||'').includes('HUN')?'Hungarian':'';}
const state={document_type:'auto'};
const start=src.indexOf('function normalizePersonName'), end=src.indexOf('async function getRosaOCRWorker',start);
if(start<0||end<0)throw new Error('Parser functions not found');
eval(src.slice(start,end)+`
const input=\`ORSIAG/ HUNGARY
NOSITO IGAZOLVANY/ IDENTITY
Csaladi és E6navI Fam pate 3 d.Gilugn
KOVACS MARTON
Nem/Sex: F/M Allampolgarsag/Nationality: HUN Eis
sziletési ido/Date o birth: 2008.05.14
Erveényessegiido/Date of expiry: 2030.01.01
Okmanyazonositd/Doc. No.: AB123456
Nairds/Signature\`;
const out=parseVisibleText(input);
if(out.full_name!=='KOVACS MARTON')throw new Error('Name failed: '+out.full_name);
if(out.nationality!=='Hungarian')throw new Error('Nationality failed: '+out.nationality+' raw OCR value');
if(out.date_of_birth!=='2008-05-14')throw new Error('DOB regressed: '+out.date_of_birth);
if(out.document_number!=='AB123456')throw new Error('Document number regressed: '+out.document_number);
if(out.sex!=='M')throw new Error('Sex regressed: '+out.sex);
console.log('PASS: name, nationality, DOB, document number, sex');
`);
