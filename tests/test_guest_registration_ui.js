'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('static/guest-checkin-i18n.js','utf8');
const app=fs.readFileSync('static/guest-checkin.js','utf8');
function session(saved){
  let change;const values=new Map(saved?[['delvane.guest.language',saved]]:[]);
  const selector={value:'hu',addEventListener:(_,fn)=>change=fn};
  const document={documentElement:{lang:'hu'},body:{},title:'',getElementById:id=>id==='guestLanguage'?selector:null,querySelectorAll:()=>[],createTreeWalker:()=>({nextNode:()=>null})};
  const context={document,window:{},NodeFilter:{SHOW_TEXT:4},MutationObserver:class{observe(){}},sessionStorage:{getItem:key=>values.get(key),setItem:(key,value)=>values.set(key,value)},Intl};
  vm.createContext(context);vm.runInContext(source+'\nthis.translate=guestTranslate;this.error=guestError;this.regions=GUEST_REGIONS;this.dictionary=GUEST_HU;',context);
  return {context,change:value=>change({target:{value}}),values};
}
const hu=session();
assert.equal(hu.context.document.documentElement.lang,'hu');
assert.equal(hu.context.translate('You’re all set.'),'Köszönjük, az adatai megérkeztek.');
for(const label of ['Open camera','Date of birth','Nationality','Confirm my information','This link isn\'t available.','Capture back side','Reading your ID…'])assert.notEqual(hu.context.translate(label),label);
assert(hu.context.translate('Your guest information has been received by Fictional House. The property will complete the required identity verification before sending the information to VIZA.').includes('Fictional House'));
hu.change('en');assert.equal(hu.context.translate('You’re all set.'),'You’re all set.');
assert.equal(hu.values.get('delvane.guest.language'),'en');
assert.equal(session('en').context.document.documentElement.lang,'en');
assert.equal(hu.context.error(400,{code:'invalid_birth_date'}),'Enter a birth date between 1 January 1920 and today.');
assert(!hu.context.error(500,{detail:'PRIVATE SERVER TRACE'}).includes('PRIVATE'));
const countryMap=JSON.parse(app.match(/const NATIONALITY_BY_CODE=(\{.*?\});/)[1]);
for(const nationality of new Set(Object.values(countryMap)))assert(hu.context.regions[nationality],nationality+' lacks Hungarian region localization');
assert(!app.includes('Other / unknown</option>'));
assert(app.includes('min="1920-01-01"'));
assert(app.includes("a==='Hungarian'?-1"));
assert(app.includes('nationalitySearch'));
// The scanner's finalizer can still identify in-progress copy after localization.
const statusNode={nodeValue:'Photo captured. Reading the document and filling in your details…',parentElement:{closest:()=>null,tagName:'P'}};
hu.context.document.createTreeWalker=()=>{let read=false;return {nextNode:()=>read?null:(read=true,statusNode)}};
hu.change('hu');
assert.notEqual(statusNode.nodeValue,'Photo captured. Reading the document and filling in your details…');
assert.equal(hu.context.window.guestSourceText({firstChild:statusNode}),'Photo captured. Reading the document and filling in your details…');
const nationalities={value:'',options:[{value:'',textContent:'Select nationality'},{value:'French',textContent:'French'},{value:'Hungarian',textContent:'Hungarian'}],appendChild(option){this.options=this.options.filter(x=>x!==option);this.options.push(option);this.value='Hungarian'}};
const oldGet=hu.context.document.getElementById;
hu.context.document.getElementById=id=>id==='nationality'?nationalities:oldGet(id);
hu.change('hu');assert.equal(nationalities.value,'','Sorting must never automatically select Hungarian nationality');
console.log('Guest UI language, privacy, nationality and date contracts passed.');
