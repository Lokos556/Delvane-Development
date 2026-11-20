'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('static/guest-checkin.js','utf8');
const c={state:{reservation:{arrival_date:'2026-11-20'}},Date};vm.createContext(c);
vm.runInContext(src.slice(src.indexOf('const readerOriginal='),src.indexOf('function applyParsed('))+src.slice(src.indexOf('function localToday()'),src.indexOf('function renderFields()'))+'\nthis.api={retainReaderFields,identitySubmission,mrzBirthCandidates,registrationDocumentRequired};',c);
const a=c.api;
a.retainReaderFields({family_name:'Fictional',given_names:'\u00c1rv\u00edzt\u0171r\u0151',nationality_code:'HUN',document_type:'passport',date_of_birth:'1990-01-02'});
a.retainReaderFields({family_name:'Wrong reverse side',given_names:'\u00c1rv\u00edzt\u0171r\u0151'});
let submitted=a.identitySubmission({family_name:'Reviewed',given_names:'\u00c1rv\u00edzt\u0171r\u0151',nationality_code:'HU'});
assert.equal(submitted.scanned_fields.csaladnev,'Fictional');assert.equal(submitted.scanned_fields.allampolgarsagKod,'HUN');
assert.equal(submitted.manual_fields.csaladnev,'Reviewed');assert.equal(submitted.manual_fields.utonev,'\u00c1rv\u00edzt\u0171r\u0151');
assert(submitted.scan_ambiguities.includes('conflicting_scan:csaladnev'));
assert(!('szuletesiCsaladnev' in submitted.scanned_fields));assert(!('anyjaCsaladnev' in submitted.scanned_fields));
assert.equal(a.mrzBirthCandidates('200102').length,2);
a.retainReaderFields({mrz_birth_raw:'200102',nationality_code:'NLD'});
submitted=a.identitySubmission({});assert(submitted.scan_ambiguities.includes('mrz_birth_century_confirmation'));assert(submitted.scan_ambiguities.includes('country_mapping_requires_review'));
assert.equal(a.registrationDocumentRequired('2012-11-21'),false);assert.equal(a.registrationDocumentRequired('2012-11-20'),true);
assert(!src.includes('merged.birth_name=merged.full_name'));
assert(fs.readFileSync('static/guest-checkin.html','utf8').includes('<script async src="https://cdn.jsdelivr.net/npm/tesseract.js@5/'));
console.log('PASS: immutable reader fields, paired Unicode corrections, raw codes, ambiguous dates, minor boundary and nonblocking OCR asset loading');
// V08: execute the real browser confirmation handler, not just its age helper.
(async()=>{
  const source=fs.readFileSync('static/guest-checkin.js','utf8').replace(/\r\n/g,'\n');
  async function confirmAt(born,needsDocument){
    const values={full_name:'V08 Synthetic minor',date_of_birth:born,nationality:'Hungarian',document_number:'',document_type:''};
    const nodes={};for(const id of [...Object.keys(values),'error','confirm'])nodes[id]={value:values[id]||'',textContent:'',removeAttribute(){},setAttribute(){},focus(){this.focused=true},checkValidity(){return true}};
    let submitted=0,submittedBody=null;
    const context={document:{getElementById:id=>nodes[id]},formData:()=>({...values}),identitySubmission:()=>({}),state:{reservation:{property_name:'Fictional House'}},registrationDocumentRequired:()=>needsDocument,rollingBirthMinimum:()=> '1916-01-01',localToday:()=> '2026-11-01',api:async(url,request)=>{submitted++;submittedBody=JSON.parse(request.body);return {}},token:'fictional-public-token',stopCamera(){},shell(){},esc:String,encodeURIComponent,JSON};
    vm.createContext(context);
    const start=source.indexOf("document.getElementById('confirm').onclick=");
    const end=source.indexOf('\n}\nasync function boot',start);
    vm.runInContext(source.slice(start,end),context);
    await nodes.confirm.onclick();
    assert.equal(submitted,needsDocument?0:1,'Real confirmation handler must honor age-dependent document requirements');
    if(needsDocument)assert(nodes.document_number.focused);
    else assert.equal(submittedBody.scan_method,'manual','Unscanned typed registration must not be labelled camera MRZ');
  }
  await confirmAt('2013-10-30',false);await confirmAt('2012-10-30',true);
  console.log('PASS: actual guest confirmation submits a minor without document fields and rejects missing adult documents');
})().catch(error=>{console.error(error);process.exitCode=1});
