const root=document.getElementById('guestApp');
const token=decodeURIComponent(location.pathname.split('/').pop()||'');
let state=null,stream=null,autoTimer=null,autoResumeTimer=null,previousFrame=null,stableSince=0,autoCaptureEnabled=false,scanInProgress=false,torchEnabled=false,scanSide='front';
// Keep one Tesseract worker alive for the whole check-in page. Tesseract.recognize()
// creates/tears down a worker for each call, which made the old multi-pass pipeline
// repeatedly reload OCR assets and could take minutes on phones.
let rosaOCRWorker=null,rosaOCRWorkerPromise=null,rosaOCRStatus=null,rosaOCRStage='Preparing scanner…';

// A timed-out Tesseract job must not keep the shared worker busy forever.
// Resetting the worker makes the next explicit capture a clean retry.
async function resetRosaOCRWorker(){
  const worker=rosaOCRWorker;
  rosaOCRWorker=null;
  rosaOCRWorkerPromise=null;
  if(worker&&typeof worker.terminate==='function'){
    try{await worker.terminate()}catch(_){/* worker may already have stopped */}
  }
}
function withOCRTimeout(promise,ms,message){
  let timer;
  return Promise.race([
    promise,
    new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(message)),ms)})
  ]).finally(()=>clearTimeout(timer));
}
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const api=async(path,opts={})=>{let r;try{r=await fetch(path,{...opts,headers:{'Content-Type':'application/json',...(opts.headers||{})}})}catch(_){throw new Error('Unable to connect. Check your connection and try again.')}const d=await r.json().catch(()=>({}));if(!r.ok){const error=new Error(window.guestError(r.status,d.detail));error.field=d.detail?.field;throw error}return d};
const fmt=d=>d?`<time data-guest-date datetime="${esc(d)}">${new Intl.DateTimeFormat(document.documentElement.lang==='hu'?'hu-HU':'en-GB',{day:'numeric',month:'long',year:'numeric'}).format(new Date(d+'T12:00:00'))}</time>`:'—';
function shell(body){root.innerHTML=`<div class="wrap"><div class="brand"><img class="brand-logo" src="/static/delvane-icon.png" alt=""><b>Delvane AI</b></div>${body}</div>`;window.guestTranslateDOM?.()}
function stopCamera(){
  if(autoTimer){clearInterval(autoTimer);autoTimer=null}
  if(autoResumeTimer){clearTimeout(autoResumeTimer);autoResumeTimer=null}
  autoCaptureEnabled=false;scanInProgress=false;previousFrame=null;stableSince=0;torchEnabled=false;
  const torchBtn=document.getElementById('toggleTorch');
  if(torchBtn){torchBtn.textContent='Turn on flash';torchBtn.setAttribute('aria-pressed','false')}
  if(stream){stream.getTracks().forEach(t=>t.stop());stream=null}
}
function dateFromYYMMDD(v){
  if(!/^\d{6}$/.test(v))return '';
  const yy=+v.slice(0,2),mm=+v.slice(2,4),dd=+v.slice(4,6);
  if(mm<1||mm>12||dd<1||dd>31)return '';
  const now=new Date().getFullYear()%100;
  const year=(yy>now?1900:2000)+yy;
  const date=new Date(Date.UTC(year,mm-1,dd));
  if(date.getUTCFullYear()!==year||date.getUTCMonth()!==mm-1||date.getUTCDate()!==dd)return '';
  return `${year}-${String(mm).padStart(2,'0')}-${String(dd).padStart(2,'0')}`;
}
function cleanMRZ(s){return String(s||'').toUpperCase().replace(/[ \t]/g,'').replace(/[^A-Z0-9<\n\r]/g,'');}
function normalizeMRZLine(s){return String(s||'').toUpperCase().replace(/[^A-Z0-9<]/g,'').replace(/[«‹]/g,'<');}
function mrzValue(ch){if(ch==='<')return 0;if(ch>='0'&&ch<='9')return ch.charCodeAt(0)-48;if(ch>='A'&&ch<='Z')return ch.charCodeAt(0)-55;return 0}
function mrzCheck(value,digit){
  if(!/^[0-9]$/.test(digit))return false;
  const weights=[7,3,1];let sum=0;
  for(let i=0;i<value.length;i++)sum+=mrzValue(value[i])*weights[i%3];
  return String(sum%10)===digit;
}
const NATIONALITY_BY_CODE={"ABW":"Aruba","AFG":"Afghan","AGO":"Angolan","AIA":"Anguilla","ALA":"Åland Islands","ALB":"Albanian","AND":"Andorra","ARE":"Emirati","ARG":"Argentinian","ARM":"Armenian","ASM":"American Samoa","ATA":"Antarctica","ATF":"French Southern Territories","ATG":"Antigua and Barbuda","AUS":"Australian","AUT":"Austrian","AZE":"Azerbaijani","BDI":"Burundi","BEL":"Belgian","BEN":"Benin","BES":"Bonaire, Sint Eustatius and Saba","BFA":"Burkina Faso","BGD":"Bangladeshi","BGR":"Bulgarian","BHR":"Bahrain","BHS":"Bahamas","BIH":"Bosnian and Herzegovinian","BLM":"Saint Barthélemy","BLR":"Belarus","BLZ":"Belize","BMU":"Bermuda","BOL":"Bolivian","BRA":"Brazilian","BRB":"Barbados","BRN":"Brunei Darussalam","BTN":"Bhutan","BVT":"Bouvet Island","BWA":"Botswanan","CAF":"Central African Republic","CAN":"Canadian","CCK":"Cocos (Keeling) Islands","CHE":"Swiss","CHL":"Chilean","CHN":"Chinese","CIV":"Côte d'Ivoire","CMR":"Cameroonian","COD":"Congolese","COG":"Congo","COK":"Cook Islands","COL":"Colombian","COM":"Comoros","CPV":"Cabo Verde","CRI":"Costa Rican","CUB":"Cuban","CUW":"Curaçao","CXR":"Christmas Island","CYM":"Cayman Islands","CYP":"Cypriot","CZE":"Czech","DEU":"German","DJI":"Djibouti","DMA":"Dominica","DNK":"Danish","DOM":"Dominican","DZA":"Algerian","ECU":"Ecuadorian","EGY":"Egyptian","ERI":"Eritrea","ESH":"Western Sahara","ESP":"Spanish","EST":"Estonian","ETH":"Ethiopian","FIN":"Finnish","FJI":"Fiji","FLK":"Falkland Islands (Malvinas)","FRA":"French","FRO":"Faroe Islands","FSM":"Micronesia, Federated States of","GAB":"Gabon","GBR":"British","GEO":"Georgian","GGY":"Guernsey","GHA":"Ghanaian","GIB":"Gibraltar","GIN":"Guinea","GLP":"Guadeloupe","GMB":"Gambia","GNB":"Guinea-Bissau","GNQ":"Equatorial Guinea","GRC":"Greek","GRD":"Grenada","GRL":"Greenland","GTM":"Guatemalan","GUF":"French Guiana","GUM":"Guam","GUY":"Guyana","HKG":"Hong Konger","HMD":"Heard Island and McDonald Islands","HND":"Honduras","HRV":"Croatian","HTI":"Haitian","HUN":"Hungarian","IDN":"Indonesian","IMN":"Isle of Man","IND":"Indian","IOT":"British Indian Ocean Territory","IRL":"Irish","IRN":"Iranian","IRQ":"Iraqi","ISL":"Icelandic","ISR":"Israeli","ITA":"Italian","JAM":"Jamaican","JEY":"Jersey","JOR":"Jordanian","JPN":"Japanese","KAZ":"Kazakh","KEN":"Kenyan","KGZ":"Kyrgyzstan","KHM":"Cambodian","KIR":"Kiribati","KNA":"Saint Kitts and Nevis","KOR":"South Korean","KWT":"Kuwait","LAO":"Lao","LBN":"Lebanese","LBR":"Liberia","LBY":"Libyan","LCA":"Saint Lucia","LIE":"Liechtenstein","LKA":"Sri Lankan","LSO":"Lesotho","LTU":"Lithuanian","LUX":"Luxembourgish","LVA":"Latvian","MAC":"Macao","MAF":"Saint Martin (French part)","MAR":"Moroccan","MCO":"Monaco","MDA":"Moldova, Republic of","MDG":"Malagasy","MDV":"Maldives","MEX":"Mexican","MHL":"Marshall Islands","MKD":"North Macedonian","MLI":"Mali","MLT":"Maltese","MMR":"Burmese","MNE":"Montenegrin","MNG":"Mongolian","MNP":"Northern Mariana Islands","MOZ":"Mozambican","MRT":"Mauritania","MSR":"Montserrat","MTQ":"Martinique","MUS":"Mauritian","MWI":"Malawi","MYS":"Malaysian","MYT":"Mayotte","NAM":"Namibian","NCL":"New Caledonia","NER":"Niger","NFK":"Norfolk Island","NGA":"Nigerian","NIC":"Nicaragua","NIU":"Niue","NLD":"Dutch","NOR":"Norwegian","NPL":"Nepalese","NRU":"Nauru","NZL":"New Zealander","OMN":"Oman","PAK":"Pakistani","PAN":"Panamanian","PCN":"Pitcairn","PER":"Peruvian","PHL":"Filipino","PLW":"Palau","PNG":"Papua New Guinea","POL":"Polish","PRI":"Puerto Rico","PRK":"North Korean","PRT":"Portuguese","PRY":"Paraguayan","PSE":"Palestinian","PYF":"French Polynesia","QAT":"Qatar","REU":"Réunion","ROU":"Romanian","RUS":"Russian","RWA":"Rwanda","SAU":"Saudi Arabian","SDN":"Sudan","SEN":"Senegalese","SGP":"Singaporean","SGS":"South Georgia and the South Sandwich Islands","SHN":"Saint Helena, Ascension and Tristan da Cunha","SJM":"Svalbard and Jan Mayen","SLB":"Solomon Islands","SLE":"Sierra Leone","SLV":"El Salvador","SMR":"San Marino","SOM":"Somalia","SPM":"Saint Pierre and Miquelon","SRB":"Serbian","SSD":"South Sudan","STP":"Sao Tome and Principe","SUR":"Suriname","SVK":"Slovak","SVN":"Slovenian","SWE":"Swedish","SWZ":"Eswatini","SXM":"Sint Maarten (Dutch part)","SYC":"Seychelles","SYR":"Syrian","TCA":"Turks and Caicos Islands","TCD":"Chad","TGO":"Togo","THA":"Thai","TJK":"Tajikistan","TKL":"Tokelau","TKM":"Turkmenistan","TLS":"Timor-Leste","TON":"Tonga","TTO":"Trinidadian and Tobagonian","TUN":"Tunisian","TUR":"Turkish","TUV":"Tuvalu","TWN":"Taiwanese","TZA":"Tanzanian","UGA":"Ugandan","UKR":"Ukrainian","UMI":"United States Minor Outlying Islands","URY":"Uruguayan","USA":"American","UZB":"Uzbek","VAT":"Holy See (Vatican City State)","VCT":"Saint Vincent and the Grenadines","VEN":"Venezuelan","VGB":"Virgin Islands, British","VIR":"Virgin Islands, U.S.","VNM":"Vietnamese","VUT":"Vanuatu","WLF":"Wallis and Futuna","WSM":"Samoa","YEM":"Yemen","ZAF":"South African","ZMB":"Zambia","ZWE":"Zimbabwean","XKX":"Kosovar","GBD":"British","GBN":"British","GBO":"British","GBS":"British","GBW":"British"};
const NATIONALITY_OPTIONS=[...new Set(Object.values(NATIONALITY_BY_CODE))].sort((a,b)=>a==='Hungarian'?-1:b==='Hungarian'?1:a.localeCompare(b));
function nationalityFromMRZ(code){
  const value=String(code||'').replace(/</g,'').toUpperCase();
  if(!value)return '';
  return NATIONALITY_BY_CODE[value]||'';
}
function normalizeNationality(value){
  const v=String(value||'').trim();
  if(!v)return '';
  const code=v.toUpperCase().replace(/[^A-Z]/g,'');
  if(code.length===3)return NATIONALITY_BY_CODE[code]||'';
  const exact=NATIONALITY_OPTIONS.find(x=>x.toLocaleLowerCase()===v.toLocaleLowerCase());
  if(exact)return exact;
  return '';
}
function parseNames(v){
  const parts=v.split('<<');
  const surname=(parts[0]||'').replace(/<+/g,' ').trim();
  const given=(parts.slice(1).join(' ')||'').replace(/<+/g,' ').trim();
  return {surname,given,full:[given,surname].filter(Boolean).join(' ')};
}
function normalizeMRZLines(text){
  const raw=cleanMRZ(text).split(/\r?\n/).map(normalizeMRZLine).filter(Boolean);
  const candidates=raw.filter(x=>x.length>=25);
  // Hungarian identity cards use three 30-character TD1 rows. OCR sometimes
  // removes line breaks, so reconstruct fixed-width candidates from the MRZ blob.
  const blob=raw.join('');
  if(blob.length>=90){
    for(let start=0;start+90<=blob.length;start++){
      const a=blob.slice(start,start+30),b=blob.slice(start+30,start+60),c=blob.slice(start+60,start+90);
      if(/^[ACI][A-Z<][A-Z]{3}/.test(a) && /^\d{6}[0-9<][MFX<]/.test(b) && /^[A-Z<]{2,}/.test(c)){
        candidates.push(a,b,c); break;
      }
    }
    if(candidates.length<3) for(let i=0;i+90<=blob.length;i+=30)candidates.push(blob.slice(i,i+30),blob.slice(i+30,i+60),blob.slice(i+60,i+90));
  }
  return [...new Set(candidates)];
}
function parseTD3(lines){
  for(let i=0;i<lines.length-1;i++){
    const a=lines[i].padEnd(44,'<').slice(0,44),b=lines[i+1].padEnd(44,'<').slice(0,44);
    if(!/^P[A-Z<]/.test(a)||a.length<40||b.length<40)continue;
    const name=parseNames(a.slice(5)),doc=b.slice(0,9),dob=b.slice(13,19),sex=b[20]||'';
    const checks=[mrzCheck(doc,b[9]),mrzCheck(dob,b[19]),mrzCheck(b.slice(21,27),b[27]),mrzCheck(b.slice(0,10)+b.slice(13,20)+b.slice(21,43),b[43])];
    return {document_type:'passport',full_name:name.full,family_name:name.surname,given_names:name.given,mrz_birth_raw:dob,nationality_code:b.slice(10,13),nationality:nationalityFromMRZ(b.slice(10,13)),date_of_birth:dateFromYYMMDD(dob),sex:/^[MF]$/.test(sex)?sex:'',document_number:doc.replace(/</g,''),confidence:checks.every(Boolean)?'verified':'manual_review',mrz_format:'TD3',mrz_checks:checks};
  }
  return null;
}
function parseTD2(lines){
  for(let i=0;i<lines.length-1;i++){
    const a=lines[i].padEnd(36,'<').slice(0,36),b=lines[i+1].padEnd(36,'<').slice(0,36);
    if(!/^[A-Z0-9<]{2}[A-Z<]{3}/.test(a)||a.length<32||b.length<32)continue;
    const name=parseNames(a.slice(5)),doc=b.slice(0,9),dob=b.slice(13,19),sex=b[20]||'';
    const checks=[mrzCheck(doc,b[9]),mrzCheck(dob,b[19]),mrzCheck(b.slice(21,27),b[27]),mrzCheck(b.slice(0,10)+b.slice(13,20)+b.slice(21,35),b[35])];
    return {document_type:a[0]==='P'?'passport':'id_card',full_name:name.full,family_name:name.surname,given_names:name.given,mrz_birth_raw:dob,nationality_code:b.slice(10,13),nationality:nationalityFromMRZ(b.slice(10,13)),date_of_birth:dateFromYYMMDD(dob),sex:/^[MF]$/.test(sex)?sex:'',document_number:doc.replace(/</g,''),confidence:checks.every(Boolean)?'verified':'manual_review',mrz_format:'TD2',mrz_checks:checks};
  }
  return null;
}
function parseTD1(lines){
  for(let i=0;i<lines.length-2;i++){
    const a=lines[i].padEnd(30,'<').slice(0,30),b=lines[i+1].padEnd(30,'<').slice(0,30),c=lines[i+2].padEnd(30,'<').slice(0,30);
    if(!/^[ACI][A-Z<]/.test(a)||a.length<28||b.length<28||c.length<20)continue;
    const doc=a.slice(5,14),dob=b.slice(0,6),sex=b[7]||'',expiry=b.slice(8,14);
    const checks=[mrzCheck(doc,a[14]),mrzCheck(dob,b[6]),mrzCheck(expiry,b[14]),mrzCheck(a.slice(5,30)+b.slice(0,7)+b.slice(8,15)+b.slice(18,29),b[29])];
    const name=parseNames(c);
    const normalizedName=String(name.full||'').replace(/[^A-Z ]/g,' ').replace(/\s+/g,' ').trim();
    if(!dateFromYYMMDD(dob) || normalizedName.replace(/ /g,'').length<3 || !/[A-Z]{2}/.test(normalizedName))continue;
    return {document_type:'id_card',full_name:normalizedName,family_name:name.surname,given_names:name.given,mrz_birth_raw:dob,nationality_code:b.slice(15,18),nationality:nationalityFromMRZ(b.slice(15,18)),date_of_birth:dateFromYYMMDD(dob),sex:/^[MF]$/.test(sex)?sex:'',document_number:doc.replace(/</g,''),confidence:checks.every(Boolean)?'verified':'manual_review',mrz_format:'TD1',mrz_checks:checks};
  }
  return null;
}
function parseMRZStrict(lines){return parseTD3(lines)||parseTD1(lines)||parseTD2(lines);}
function allMRZChecksPass(parsed){return !!parsed&&Array.isArray(parsed.mrz_checks)&&parsed.mrz_checks.length>0&&parsed.mrz_checks.every(Boolean);}
// Detect the printed text rows from horizontal ink density rather than assuming the
// guide crop is perfectly level or that each row occupies exactly one third.
function detectMRZRowBands(canvas){
  const ctx=canvas.getContext('2d',{willReadFrequently:true});
  const {width,height}=canvas; if(!width||!height)return [];
  const data=ctx.getImageData(0,0,width,height).data;
  const counts=new Uint32Array(height);
  // Sample every second pixel horizontally; count dark, low-saturation ink.
  for(let y=0;y<height;y++)for(let x=0;x<width;x+=2){
    const i=(y*width+x)*4, r=data[i],g=data[i+1],b=data[i+2];
    const gray=.299*r+.587*g+.114*b;
    if(gray<145 && Math.max(r,g,b)-Math.min(r,g,b)<105)counts[y]++;
  }
  const threshold=Math.max(2,Math.floor(width*.006));
  const active=[]; let start=-1;
  for(let y=0;y<height;y++){
    if(counts[y]>=threshold){if(start<0)start=y;}
    else if(start>=0){if(y-start>=2)active.push([start,y]);start=-1;}
  }
  if(start>=0&&height-start>=2)active.push([start,height]);
  if(!active.length)return [];
  // Join small gaps within glyphs; then merge nearby bands belonging to the same text row.
  const merged=[];
  for(const band of active){const last=merged[merged.length-1];if(last&&band[0]-last[1]<=Math.max(3,Math.round(height*.012)))last[1]=band[1];else merged.push(band.slice());}
  if(merged.length<=3)return merged;
  // Cluster the ink bands into 2-3 rows by the larger whitespace gaps.
  const gaps=merged.slice(0,-1).map((b,i)=>({i,gap:merged[i+1][0]-b[1]})).sort((a,b)=>b.gap-a.gap);
  const target=Math.min(3,Math.max(2,Math.round(height/Math.max(1,width)*5)));
  const cuts=new Set(gaps.slice(0,target-1).map(x=>x.i)); const out=[];let a=merged[0][0],z=merged[0][1];
  for(let i=1;i<merged.length;i++){if(cuts.has(i-1)){out.push([a,z]);a=merged[i][0];}z=merged[i][1];}out.push([a,z]);
  return out;
}
function mrzCorrectionCandidates(lines,maxEdits=1){
  // Only search OCR-confusable characters in fields protected by ICAO check digits.
  // Never alter names, nationality, document type, or a check digit itself.
  const pairs={'O':'0','0':'O','I':'1','1':'I','B':'8','8':'B','S':'5','5':'S','Z':'2','2':'Z','G':'6','6':'G','Q':'0','D':'0'};
  const out=[];const seen=new Set();const positions=[];
  const add=(arr,edits)=>{const key=arr.join('\n');if(!seen.has(key)){seen.add(key);out.push({lines:arr,edits})}};
  const addRange=(li,start,end)=>{const line=lines[li]||'';for(let ci=start;ci<Math.min(end,line.length);ci++)if(pairs[line[ci]])positions.push({li,ci,from:line[ci],to:pairs[line[ci]]})};
  if(lines.length>=3&&/^[ACI][A-Z<]/.test(lines[0])){
    addRange(0,5,14);addRange(1,0,6);addRange(1,8,14);addRange(1,18,29);
  }else if(lines.length>=2&&/^P[A-Z<]/.test(lines[0])){
    addRange(1,0,9);addRange(1,13,19);addRange(1,21,27);addRange(1,28,43);
  }else if(lines.length>=2){
    addRange(1,0,9);addRange(1,13,19);addRange(1,21,27);addRange(1,28,35);
  }
  for(let i=0;i<positions.length;i++){
    const a=positions[i],one=lines.slice();one[a.li]=one[a.li].slice(0,a.ci)+a.to+one[a.li].slice(a.ci+1);add(one,[a]);
    if(maxEdits<2)continue;
    for(let j=i+1;j<positions.length;j++){
      const b=positions[j];if(a.li===b.li&&a.ci===b.ci)continue;
      const two=lines.slice();
      two[a.li]=two[a.li].slice(0,a.ci)+a.to+two[a.li].slice(a.ci+1);
      two[b.li]=two[b.li].slice(0,b.ci)+b.to+two[b.li].slice(b.ci+1);
      add(two,[a,b]);
    }
  }
  return out;
}
function parseMRZ(text){
  // Fast deterministic parse only. Do not brute-force character substitutions on
  // a phone; an unvalidated candidate is displayed for guest review, never treated
  // as verified. A later dedicated correction pass can be opt-in if benchmarks justify it.
  return parseMRZStrict(normalizeMRZLines(text));
}
function imageQuality(canvas){
  const w=Math.min(canvas.width,900),h=Math.round(canvas.height*(w/canvas.width));
  const tmp=document.createElement('canvas');tmp.width=w;tmp.height=h;
  const tc=tmp.getContext('2d',{willReadFrequently:true});tc.drawImage(canvas,0,0,w,h);
  const data=tc.getImageData(0,0,w,h).data;let sum=0,sum2=0,edges=0,count=0;
  for(let i=0;i<data.length;i+=16){const y=.299*data[i]+.587*data[i+1]+.114*data[i+2];sum+=y;sum2+=y*y;count++}
  const mean=sum/count,contrast=Math.sqrt(Math.max(0,sum2/count-mean*mean));
  for(let y=1;y<h-1;y+=3)for(let x=1;x<w-1;x+=3){
    const p=(y*w+x)*4,q=((y-1)*w+x)*4;
    const y1=.299*data[p]+.587*data[p+1]+.114*data[p+2],y0=.299*data[q]+.587*data[q+1]+.114*data[q+2];
    edges+=Math.abs(y1-y0);
  }
  return {mean,contrast,edge:edges/Math.max(1,Math.floor((w/3)*(h/3)))};
}
function normalizePersonName(value){
  let name=String(value||'').replace(/<+/g,' ').replace(/[|\\_~]+/g,' ').replace(/[0-9]/g,' ');
  // Keep letters used in Hungarian and other European names; remove OCR speckles
  // and punctuation, then discard isolated one-character fragments (common Tesseract noise).
  name=name.replace(/[^A-Za-zÀ-ÖØ-öø-ÿĀ-ž'’.-]+/g,' ').replace(/\s+/g,' ').trim();
  name=name.split(' ').filter(part=>part.length>=2&&!/^[A-Za-zÀ-ÖØ-öø-ÿĀ-ž][.'’]?$/.test(part)).join(' ');
  return name;
}
function isPlausiblePersonName(value){
  const name=normalizePersonName(value);
  if(name.length<3||name.length>70)return false;
  // Reject OCR concatenations of document headings, labels, and random OCR fragments.
  if(/(?:IDENTITY|IGAZOLV|AZONOS[IÍ]T|DOCUMENT|PASSPORT|NATIONALITY|CITIZENSHIP|MELY|PERSONAL NUMBER|SIGNATURE|AL[AÁ]IR[AÁ]S)/i.test(name))return false;
  const parts=name.split(' ');
  if(parts.length<2||parts.length>6)return false;
  if(parts.some(part=>part.length<2||part.length>20))return false;
  if(parts.some(part=>!/^[A-Za-zÀ-ÖØ-öø-ÿĀ-ž'’.-]+$/.test(part)))return false;
  // Require at least two alphabetic components; reject digit-heavy/noise-only OCR.
  return parts.filter(part=>/[A-Za-zÀ-ÖØ-öø-ÿĀ-ž]/.test(part)).length>=2;
}

function parseVisibleText(text){
  // Multilingual visible-zone parser. OCR often returns bilingual labels and values
  // on the same line, so do not require a label to begin a line.
  const raw=String(text||'').replace(/\u00a0/g,' ');
  const lines=raw.split(/\r?\n/).map(x=>x.replace(/[|]/g,'I').replace(/[ \t]+/g,' ').trim()).filter(Boolean);
  const joined=lines.join('\n');
  const flat=lines.join('  ');
  const stripNoise=v=>String(v||'').replace(/^[\s:;.,/\\|_~—-]+/,'').replace(/[\s:;.,/\\|_~—-]+$/,'').replace(/\s+/g,' ').trim();
  const validValue=v=>{v=stripNoise(v);return v.length>0&&v.length<=100&&!/^(?:identity card|national identity card|passport|driving licence|document|family name and given name|nationality|date of birth|date of expiry)$/i.test(v)?v:''};
  const findValue=(patterns,max=90)=>{
    for(let i=0;i<lines.length;i++){
      const line=lines[i];
      for(const p of patterns){
        const re=new RegExp(p,'i'); const m=re.exec(line);
        if(!m)continue;
        let value=stripNoise(m[1]||'');
        // Treat a second bilingual label captured after the first label as no value.
        if(value&&/^(?:\/|[-–|])?\s*(?:family\s*name(?:\s*and\s*given\s*name)?|given\s*name|nationality|citizenship|date\s*o?f?\s*birth|birth\s*date|date\s*of\s*expiry|expiry\s*date|document\s*(?:no\.?|number)|doc\.?\s*no\.?|sex|nem)\s*[:：]?\s*$/i.test(value))value='';
        // Some phone OCR results put the label and its value on separate lines.
        if(!value&&i+1<lines.length){
          const next=stripNoise(lines[i+1]);
          const looksLikeLabel=/(?:name|n[eé]v|birth|sz[uü]let|date|id[oő]|expiry|[eé]rv[eé]ny|nationality|[aá]llampolg|okm[aá]ny|document|sex|nem|anyja|mother|place|hely)\s*[:：]?\s*$/i.test(next);
          if(next&&!looksLikeLabel)value=next;
        }
        if(value.includes(':')||value.includes('：'))value=stripNoise(value.slice(Math.max(value.lastIndexOf(':'),value.lastIndexOf('：'))+1));
        value=value.split(/\s+(?=(?:Nem\b|Sex\b|Állampolgárság\b|Allampolgarsag\b|Nationality\b|Születési idő\b|Szuletesi ido\b|Date of birth\b|Érvényességi idő\b|Ervenyessegi ido\b|Date of expiry\b|Érvényes eddig\b|Okmányazonosító\b|Okmanyazonosito\b|Doc\.? No\.?\b|Születési hely\b|Szuletesi hely\b|Anyja neve\b|Mother(?:'s)? name\b))/i)[0];
        value=stripNoise(value);
        if(value&&value.length<=max)return value;
      }
    }
    return '';
  };
  const parseDate=value=>{
    const v=String(value||'').replace(/[.,]/g,' ').replace(/\s+/g,' ').trim();
    let m=v.match(/\b(\d{4})[.\-/ ]+(\d{1,2})[.\-/ ]+(\d{1,2})\b/);
    if(m){const y=+m[1],mo=+m[2],d=+m[3];if(y>=1900&&y<=2100&&mo>=1&&mo<=12&&d>=1&&d<=31){const dt=new Date(Date.UTC(y,mo-1,d));if(dt.getUTCFullYear()===y&&dt.getUTCMonth()===mo-1&&dt.getUTCDate()===d)return `${y}-${String(mo).padStart(2,'0')}-${String(d).padStart(2,'0')}`;}}
    m=v.match(/\b(\d{1,2})[.\-/ ]+(\d{1,2})[.\-/ ]+(\d{4})\b/);
    if(m){const d=+m[1],mo=+m[2],y=+m[3];if(y>=1900&&y<=2100&&mo>=1&&mo<=12&&d>=1&&d<=31){const dt=new Date(Date.UTC(y,mo-1,d));if(dt.getUTCFullYear()===y&&dt.getUTCMonth()===mo-1&&dt.getUTCDate()===d)return `${y}-${String(mo).padStart(2,'0')}-${String(d).padStart(2,'0')}`;}}
    return '';
  };
  const findLabeledDate=labels=>{
    const dateToken=/\b(?:\d{4}[.\-/ ]+\d{1,2}[.\-/ ]+\d{1,2}|\d{1,2}[.\-/ ]+\d{1,2}[.\-/ ]+\d{4})\b/;
    const anotherLabel=/(?:csal[aá]di|family\s*name|given\s*name|nationality|[aá]llampolg[aá]rs[aá]g|sz[uü]let[eé]si\s*(?:id[oő]|hely|n[eé]v)|date\s*o?f?\s*birth|birth\s*date|[eé]rv[eé]ny|date\s*of\s*expiry|expiry\s*date|okm[aá]ny|document\s*(?:no|number)|\bsex\b|\bnem\b|anyja\s*neve)/i;
    for(let i=0;i<lines.length;i++){
      if(!labels.test(lines[i]))continue;
      const sameLine=lines[i].match(dateToken);if(sameLine)return sameLine[0];
      for(let j=i+1;j<Math.min(lines.length,i+3);j++){
        if(anotherLabel.test(lines[j]))break;
        const next=lines[j].match(dateToken);if(next)return next[0];
      }
    }
    return '';
  };
  const fullNameRaw=findValue([
    // Hungarian identity cards use a bilingual label; OCR commonly merges or
    // misspells parts of it, so accept the English half independently.
    '(?:csal[aá]di.{0,22}ut[oó]n[eé]v|family.{0,28}(?:given|gir|fir|g[ií]v[eé]n).{0,10}na.{0,2}e|full\\s*name|teljes\\s*n[eé]v|viselt\\s*n[eé]v)\\s*[:：]?\\s*(.*)$',
    '(?:surname|family\\s*name|vez[eé]kn[eé]v|apellido)\\s*[:：]?\\s*(.*)$'
  ],80);
  let fullName=validValue(fullNameRaw);
  // The Hungarian card label is frequently mangled by OCR (e.g. 'Csaladi ... / Fail nae and Giles nan').
  // If that noisy label consumed the line instead of capturing the value, take the next non-label line.
  const plausibleNameValue=v=>isPlausiblePersonName(v) && !/(?:HUNGARY|IDENTITY|IGAZOLV|AZONOS|DOCUMENT|PASSPORT|NATIONALITY|CITIZENSHIP|DATE OF|NEM\/SEX|SIGNATURE|AL[AÁ]IR[AÁ]S)/i.test(v);
  if(!plausibleNameValue(fullName)){
    for(let i=0;i<lines.length;i++){
      const line=lines[i];
      // OCR frequently mangles both halves of the Hungarian/English label:
      // e.g. "Csalad) és-utdnév/Fapily pai arid. Give name".
      const looksLikeNameLabel=/(?:csal[aá]d|csal[aá]di|csal).{0,85}(?:ut[oó]n|utd|given|g[ií1l]ven|giles|name|nam|nae|pane)|(?:fami?l?y|fapily|fail|pai).{0,60}(?:given|g[ií1l]ven|giles|name|nam|nae|pane)|(?:give|g[ií1l]ve)\s*nam/i.test(line);
      if(!looksLikeNameLabel)continue;
      const inline=line.replace(/.*?(?:csal[aá]di.{0,22}ut[oó]n[eé]v|family.{0,55}(?:given|g[ií]ven|giles|name|nae)|fail.{0,55}(?:given|giles|name|nae))\s*[:：]?/i,'');
      if(plausibleNameValue(inline)){fullName=normalizePersonName(inline);break;}
      for(let j=i+1;j<Math.min(lines.length,i+3);j++){
        if(/(?:nationality|allampolg|nem\/sex|date\s*o?f?\s*birth|sz[uü]let[eé]si|sailetesi|doc\.?\s*no|okm[aá]nyazonos)/i.test(lines[j]))break;
        if(plausibleNameValue(lines[j])){fullName=normalizePersonName(lines[j]);break;}
      }
      if(plausibleNameValue(fullName))break;
    }
  }
  // Broad positional fallback for the Hungarian ID layout. OCR may render the
  // bilingual label as "Csaladi és E6navI Fam pate 3 d.Gilugn" without any
  // recognizable "given name" words. Inspect the next line for a plausible name.
  if(!plausibleNameValue(fullName)){
    for(let i=0;i<lines.length;i++){
      const line=lines[i];
      const hasHungarianNameCue=/(?:csal[aá]d|csaladi|csal.{0,8}d)/i.test(line);
      const hasFamilyCue=/(?:family|fami?l?y|fam\s*pate|fap|fail|pane|given|g[ií1l]il?u?gn|name|nam)/i.test(line);
      if(!(hasHungarianNameCue&&hasFamilyCue))continue;
      for(let j=i+1;j<Math.min(lines.length,i+3);j++){
        if(/(?:nationality|allampolg|nem\/sex|date\s*o?f?\s*birth|sz[uü]let[eé]si|sailetesi|doc\.?\s*no|dac\.?\s*no|okm[aá]nyazonos)/i.test(lines[j]))break;
        if(plausibleNameValue(lines[j])){fullName=normalizePersonName(lines[j]);break;}
      }
      if(plausibleNameValue(fullName))break;
    }
  }
  // Fallback for OCR that loses the Hungarian/family-name half entirely, e.g.
  // "Cala. sut6navIF ani pase and. Giver name". A standalone noisy English
  // name label is enough to inspect the immediately following line, but only
  // accept it if that line looks like a plausible multi-part person name.
  if(!plausibleNameValue(fullName)){
    for(let i=0;i<lines.length;i++){
      if(!/(?:giver|given|giles|g[ií]ven)\s*(?:name|nae)|full\s*name/i.test(lines[i]))continue;
      for(let j=i+1;j<Math.min(lines.length,i+3);j++){
        if(/(?:nationality|allampolg|nem\/sex|date of birth|sz[uü]let[eé]si id[oő]|doc\.?\s*no|dac\.?\s*no|okm[aá]nyazonos)/i.test(lines[j]))break;
        if(plausibleNameValue(lines[j])){fullName=normalizePersonName(lines[j]);break;}
      }
      if(plausibleNameValue(fullName))break;
    }
  }
  // Avoid document headings / field-label concatenations; retain only plausible alphabetic name text.
  if(plausibleNameValue(fullName)) fullName=normalizePersonName(fullName); else fullName='';
  const birthName=findValue(['(?:sz[uü]let[eé]si\\s*n[eé]v|birth\\s*name|name\\s*at\\s*birth|nom\\s*de\\s*naissance)\\s*[:：]?\\s*(.*)$'],80);
  const birthPlace=findValue(['(?:sz[uü]l[eé]t[eé]s[ií]?\\s*hely|sz[ií]l[eé]t[eé]s[ií]?\\s*hely|szuletesi\\s*hely|place\\s*of\\s*birth|birth\\s*place|geburtsort|lieu\\s*de\\s*naissance|lugar\\s*de\\s*nacimiento)(?:\\s*[/|].{0,12})?\\s*[:：]?\\s*(.*)$'],80);
  const mother=findValue(['(?:anyja(?:\\s*sz[uü]let[eé]si)?\\s*(?:csal[aá]di\\s*[ée]s\\s*ut[oó]neve|neve)|any[aá]ja.{0,24}neve|mother(?:.{0,24})(?:maiden|birth)?\\s*name|mother(?:\\s*\\(?s\\)?|s)?\\s*(?:birth\\s*)?name|m[eè]re|母亲姓名)\\s*[:：]?\\s*(.*)$'],80);
  const natRaw=findValue(['(?:[aá]llampolg[aá]rs[aá]g|allampolgarsag|nationality|citizenship|nationalit[eé]|nacionalidad|国籍)\\s*[:：]?\\s*(.*)$'],40);
  // OCR can append nearby field fragments to HUN (e.g. "HUN Eis").
  // Extract a standalone three-letter country code before normalizing.
  const natCodeMatch=String(natRaw||'').toUpperCase().match(/\b([A-Z]{3})\b/);
  const nationality=normalizeNationality(natCodeMatch?.[1]||natRaw)||nationalityFromMRZ((natRaw||'').trim().toUpperCase());
  // On this Hungarian ID, the printed bilingual legend "Nem/Sex: F/M"
  // pairs Hungarian "Férfi" with English "Male". It must map to M (male),
  // never to F (female). Prefer an explicit cardholder value if one is present.
  // Hungarian ID cards print "Nem/Sex: F/M" as a legend (Férfi/Male),
  // not as a cardholder-specific value. OCR often drops the leading N ("em/Sex")
  // or confuses the separator, so detect the English Sex half independently.
  const sexLegend=/(?:\bnem\b\s*\/\s*)?\bsex\b\s*[:：]?\s*F\s*\/\s*M\b/i.test(flat);
  const sexText=flat.replace(/(?:\bnem\b\s*\/\s*)?\bsex\b\s*[:：]?\s*F\s*\/\s*M\b/ig,' ');
  const sexMatch=/(?:\bsex\b|\bnem\b)(?:\s*\/\s*(?:sex|nem))?\s*[:：]?\s*(n[oő]|f[eé]rfi|female|male|f|m)\s*(?=$|[\s,;])/i.exec(sexText);
  const visibleSex=sexMatch?(/f[eé]rfi|male/i.test(sexMatch[1])?'M':/n[oő]|female/i.test(sexMatch[1])?'F':String(sexMatch[1]).toUpperCase()==='M'?'M':'F'):(sexLegend?'M':'');
  // Find dates independently of which half of a bilingual label OCR recognizes first.
  const dateBirthRaw=findLabeledDate(/(?:sz[uü]let[eé]si\s*id[oő]|szuletesi\s*ido|sa[i1l]?l?e?t?e?s?i\s*id[o0őe]?|sailetesi|szilet[eé]si|date\s*o?f?\s*birth|date\s*o\s*birth|birth\s*date|geburtsdatum|data\s*di\s*nascita|fecha\s*de\s*nacimiento|date\s*de\s*naissance|出生日期)/i);
  const expiryRaw=findLabeledDate(/(?:[eé]rv[eé]nyess[eé]gi\s*id[oő]|ervenyessegi\s*ido|[eé]rv[eé]nyes\s*eddig|date\s*of\s*expiry|expiry\s*date|date\s*of\s*expiration|valid\s*until|expiration\s*date|gültig\s*bis|validity)/i);
  // OCR variants seen on Hungarian cards include "Okményazonosité/Dac. No."
  // and the value may be on the same line despite a misspelled label.
  // Prefer the token immediately following the OCR'd Doc. No. label on the same
  // line. This avoids consuming the next label (e.g. Signature) from flattened OCR.
  let docRaw='';
  for(const line of lines){
    if(!/(?:okm[aáeé]ny|okmany).{0,70}(?:doc|dac|d[o0]c)\.?\s*no\.?|(?:d[o0]c|dac)\.?\s*no\.?|document\s*(?:no\.?|number)/i.test(line))continue;
    const afterLabel=/(?:d[o0]c|dac)\.?\s*no\.?\s*[:：#]?\s*([A-Z0-9]{2,8}(?:[ -][A-Z0-9]{2,8}){1,2}|[A-Z0-9]{5,16})/i.exec(line)||/document\s*(?:no\.?|number)\s*[:：#]?\s*([A-Z0-9]{2,8}(?:[ -][A-Z0-9]{2,8}){1,2}|[A-Z0-9]{5,16})/i.exec(line);
    if(afterLabel){docRaw=afterLabel[1];break;}
  }
  if(!docRaw){
    const docInline=/(?:okm[aáeé]ny|okmany).{0,70}(?:doc|dac|d[o0]c)\.?\s*no\.?\s*[:：#]?\s*([A-Z0-9]{2,8}(?:[ -][A-Z0-9]{2,8}){1,2}|[A-Z0-9]{5,16})/i.exec(flat);
    docRaw=docInline?.[1]||findValue(['(?:okm[aáeé]ny.{0,40}(?:azonos[ií]t[oóeé]|azonosit|sz[aá]m)|igazolv[aá]ny\s*sz[aá]m|document\s*(?:no\.?|number)|d[o0]c\.?\s*no\.?|dac\.?\s*no\.?|card\s*no\.?|personal\s*no\.?|document\s*identifier)\s*[:：#]?\s*([A-Z0-9 -]{0,24})'],24);
  }
  // OCR may recognize the label but place the document number on the following line.
  if(!docRaw){
    for(let i=0;i<lines.length;i++){
      if(/(?:okm[aáeé]ny.{0,45}(?:azonos[ií]t[oóeé]|azonosit|doc\.?\s*no|dac\.?\s*no)|d[o0]c\.?\s*no\.?|dac\.?\s*no\.?|document\s*(?:no\.?|number))/i.test(lines[i])){
        const inline=/(?:d[o0]c\.?\s*no\.?|dac\.?\s*no\.?|document\s*(?:no\.?|number)|azonos[ií]t[oóeé]|azonosit)\s*[:：#]?\s*([A-Z0-9][A-Z0-9 -]{4,23})/i.exec(lines[i]);
        if(inline)docRaw=inline[1];
        if(!docRaw&&i+1<lines.length){
          const candidate=lines[i+1].replace(/[^A-Z0-9]/gi,'');
          if(/^(?=.*[A-Z0-9])[A-Z0-9]{5,16}$/i.test(candidate))docRaw=candidate;
        }
        if(docRaw)break;
      }
    }
  }
  const docCandidate=String(docRaw||'').toUpperCase().replace(/[\s-]/g,'').replace(/[^A-Z0-9]/g,'');
  const doc=(docCandidate.length>=5&&docCandidate.length<=16&&/\d/.test(docCandidate)&&!/(?:DOCUMENT|SIGNATURE|ALIRAS|NATIONALITY|HUNGARY)/i.test(docCandidate))?docCandidate:'';
  const detectedType=/passport|passeport|pasaporte|reisepass|passport no/i.test(flat)?'passport':/driver.?s licen[cs]e|driving licen[cs]e|f[uü]hrerschein|permis de conduire/i.test(flat)?'driver_license':/identity card|national identity|identit[eé] card|personalausweis|szem[eé]lyazonos[ií]t[oó]|azonos[ií]t[oó] igazolv[aá]ny|szem[eé]lyi igazolv[aá]ny/i.test(flat)?'id_card':'other';
  const out={document_type:(!state?.document_type||state.document_type==='auto')?detectedType:state.document_type,full_name:fullName,birth_name:validValue(birthName),birth_place:validValue(birthPlace),date_of_birth:parseDate(dateBirthRaw),date_of_expiry:parseDate(expiryRaw),nationality,mother_birth_name:validValue(mother),document_number:doc,sex:visibleSex,confidence:'manual_review',scan_method:'camera_ocr',ocr_text_detected:true};
  // Reject OCR noise in name-only fields rather than inserting a digit-heavy token.
  if(out.mother_birth_name && (!/[A-Za-zÀ-ÖØ-öø-ÿĀ-ž]{2}/.test(out.mother_birth_name) || /\d/.test(out.mother_birth_name) || /^X+$/i.test(out.mother_birth_name)))out.mother_birth_name='';
  if(out.birth_place)out.birth_place=out.birth_place.replace(/\s*\(\s*MAGYARORSZ[AÁ]G\s*\)/ig,'').replace(/\s*\(\s*HUNGARY\s*\)/ig,'').trim();
  if(out.birth_name && (!/[A-Za-zÀ-ÖØ-öø-ÿĀ-ž]{2}/.test(out.birth_name) || /\d/.test(out.birth_name) || /^X+$/i.test(out.birth_name)))out.birth_name='';
  if(out.birth_place && !/[A-Za-zÀ-ÖØ-öø-ÿĀ-ž]{2}/.test(out.birth_place))out.birth_place='';
  // A birthplace is a place name, not an isolated OCR digit or document fragment.
  if(out.birth_place && !/[A-Za-zÀ-ÖØ-öø-ÿĀ-ž]{2}/.test(out.birth_place)) out.birth_place='';
  const useful=['full_name','date_of_birth','document_number','nationality','birth_place','birth_name','mother_birth_name'].filter(k=>out[k]).length;
  return (useful>=1||!!out.sex||!!out.nationality)?out:null;
}
async function getRosaOCRWorker(status){
  if(!window.Tesseract)throw new Error('Scanner engine unavailable');
  rosaOCRStatus=status;
  if(rosaOCRWorker)return rosaOCRWorker;
  if(!rosaOCRWorkerPromise){
    rosaOCRWorkerPromise=(async()=>{
      rosaOCRStage='Loading OCR model…';
      const worker=await Tesseract.createWorker('eng',1,{logger:m=>{
        if(!m?.status||!rosaOCRStatus)return;
        const stage=String(m.status).replace(/[_-]+/g,' ');
        const pct=Number.isFinite(m.progress)?` ${Math.round(m.progress*100)}%`:'';
        rosaOCRStatus.textContent=`Reading document…${pct}`;
      }});
      await worker.setParameters({preserve_interword_spaces:'1',tessedit_pageseg_mode:'6'});
      rosaOCRWorker=worker;
      return worker;
    })().catch(e=>{rosaOCRWorkerPromise=null;rosaOCRWorker=null;throw e});
  }
  return rosaOCRWorkerPromise;
}
async function recognizeLocal(blob,status){
  if(!window.Tesseract)throw new Error('Scanner engine unavailable');
  const worker=await getRosaOCRWorker(status);
  const bestFields=p=>p?Object.entries(p).filter(([k,v])=>!['confidence','scan_method','mrz_format','mrz_checks','document_type','ocr_text_detected','sex','nationality'].includes(k)&&typeof v==='string'&&v.trim()).length:0;
  const hasAnyExtractedField=p=>!!p&&(bestFields(p)>0||!!p.sex||!!p.nationality);
  const mergeResults=(visible,mrz)=>{
    if(!visible&&!mrz)return null;
    // MRZ is authoritative for fields it actually contains; visible OCR supplies
    // supplementary fields such as place of birth and locally required names.
    const out={...(visible||{})};
    // Do not let empty/invalid MRZ parses erase usable visible-zone OCR.
    // MRZ fields override visible OCR only when the MRZ parser produced a non-empty value.
    if(mrz){
      for(const [k,v] of Object.entries(mrz)){
        if(['confidence','scan_method','mrz_format','mrz_checks','document_type'].includes(k))continue;
        if(typeof v==='string'&&v.trim()!=='')out[k]=v;
      }
      if(!/^[MF]$/.test(String(mrz.sex||'')))out.sex=visible?.sex||'';
    }
    for(const k of ['birth_name','birth_place','mother_birth_name','address'])if(visible?.[k])out[k]=visible[k];
    out.document_type=(!state?.document_type||state.document_type==='auto')?(mrz?.document_type||visible?.document_type||'other'):state.document_type;
    out.scan_method=mrz?.mrz_format?'camera_mrz_plus_ocr':'camera_ocr';
    if(mrz?.mrz_format){out.mrz_format=mrz.mrz_format;out.mrz_checks=mrz.mrz_checks;out.confidence=allMRZChecksPass(mrz)?'verified':'manual_review';}
    return (bestFields(out)>0||!!out.sex||!!out.nationality)?out:null;
  };
  const recognize=async(input,label,mode='general')=>{
    const started=performance.now();rosaOCRStage=label;
    if(String(mode).startsWith('mrz')){
      const psm=String(mode).startsWith('mrz-')?String(mode).slice(4):'6';
      await worker.setParameters({tessedit_pageseg_mode:psm,tessedit_char_whitelist:'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<',load_system_dawg:'0',load_freq_dawg:'0',preserve_interword_spaces:'1'});
    }else{
      // Reset MRZ-only restrictions before reading labels, names and scripts.
      await worker.setParameters({tessedit_pageseg_mode:'6',tessedit_char_whitelist:'',load_system_dawg:'1',load_freq_dawg:'1',preserve_interword_spaces:'1'});
    }
    const result=await worker.recognize(input);
    const elapsed=Math.round(performance.now()-started);
    const text=result?.data?.text||'';
    if(mode==='general'){
      // Local-only diagnostic: expose exactly what Tesseract recognized in the page.
      // This may contain personal data; it is never sent to the server or console.
      window.__rosaRawOCR={text,elapsed,label,at:new Date().toISOString()};
      const rawPanel=document.getElementById('rawOcrOutput');
      const rawMeta=document.getElementById('rawOcrMeta');
      if(rawPanel)rawPanel.textContent=text||'[Tesseract returned no text]';
      if(rawMeta)rawMeta.textContent=`OCR diagnostic · ${elapsed} ms · ${text.trim()?text.trim().split(/\r?\n/).filter(Boolean).length:0} line(s)`;
      const rawDetails=document.getElementById('rawOcrDetails');
      if(rawDetails)rawDetails.hidden=false;
    }
    let mrz=parseMRZ(text);
    // Reject impossible nationality tokens and heading-like names even when OCR
    // happens to fit the line lengths. A three-letter code must be in the MRZ table.
    if(mrz){
      if(!NATIONALITY_BY_CODE[String(mrz.nationality||'').toUpperCase()])mrz.nationality='';
      if(!isPlausiblePersonName(mrz.full_name))mrz.full_name='';
    }
    // A partially matching check digit is not enough to trust an identity.
    const validMrz=mrz;
    if(validMrz?.mrz_checks?.[1]!==true)validMrz.date_of_birth='';
    if(validMrz?.mrz_checks?.[0]!==true)validMrz.document_number='';
    const visible=mode==='general'?parseVisibleText(text):null;
    if(String(mode).startsWith('mrz')){
      const lines=normalizeMRZLines(text),checks=mrz?.mrz_checks?.map(ok=>ok?'✓':'×').join('')||'no candidate';
      window.__rosaScanDiagnostics=Array.isArray(window.__rosaScanDiagnostics)?window.__rosaScanDiagnostics:[];
      window.__rosaScanDiagnostics.push(`${label}: ${lines.length} possible line(s) [${lines.map(x=>x.length).join('/')||'none'}], checks ${checks}, ${elapsed}ms`);
      window.__rosaScanDiagnostics=window.__rosaScanDiagnostics.slice(-5);
    }
    if(mode==='general'){
      // Diagnostic summary deliberately excludes recognized text and personal data.
      // This lets us distinguish OCR failure from field-parser rejection on a phone.
      const candidateLines=normalizeMRZLines(text);
      const fieldFlags=visible?['full_name','document_number','date_of_birth','sex','nationality','birth_place','birth_name','mother_birth_name']
        .filter(k=>String(visible[k]||'').trim()).join(',')||'none':'none';
      const checks=mrz?.mrz_checks?.map(ok=>ok?'✓':'×').join('')||'no candidate';
      window.__rosaScanDiagnostics=Array.isArray(window.__rosaScanDiagnostics)?window.__rosaScanDiagnostics:[];
      window.__rosaScanDiagnostics.push(`${label}: OCR ${elapsed}ms; ${text.trim()?text.trim().split(/\r?\n/).filter(Boolean).length:0} text line(s); MRZ candidates [${candidateLines.map(x=>x.length).join('/')||'none'}]; MRZ checks ${checks}; parsed fields ${fieldFlags}`);
      window.__rosaScanDiagnostics=window.__rosaScanDiagnostics.slice(-5);
    }
    return {mrz:validMrz,visible};
  };

  // Universal strategy: never assume the selected document is Hungarian, that it
  // has an MRZ, or that its MRZ has 3 rows. Read the whole document first; MRZ is
  // an optional structured-data source, while visible OCR is always attempted.
  let visible=null,verifiedMrz=null;
  const absorb=async(input,label)=>{
    // One OCR recognition pass also checks for an MRZ in the returned text.
    // Do not run a second Tesseract pass over the same pixels: that duplicated
    // the slowest part of the workflow without adding a different source image.
    const g=await recognize(input,label,'general');
    if(g.mrz)verifiedMrz=g.mrz;
    if(g.visible&&bestFields(g.visible)>bestFields(visible))visible=g.visible;
    return mergeResults(visible,verifiedMrz);
  };
  let result=await absorb(blob,'Reading the whole document locally…');
  if(result&&bestFields(result)>=2)return result;

  // One recognition pass per capture: repeated enhancement passes caused long waits
  // on phones. A user can reposition the document and explicitly retry instead.
  result=mergeResults(visible,verifiedMrz);
  if(hasAnyExtractedField(result))return result;

  // The enhanced image is the final automatic attempt. Further passes on the
  // same frame add latency; offer an explicit retry/new side instead.
  result=mergeResults(visible,verifiedMrz);
  if(result)return result;
  window.__rosaScanDiagnostics=Array.isArray(window.__rosaScanDiagnostics)?window.__rosaScanDiagnostics:[];
  window.__rosaScanDiagnostics.push('No usable labeled fields or fully validated MRZ detected; scan both sides and review manually');
  window.__rosaScanDiagnostics=window.__rosaScanDiagnostics.slice(-5);
  return null;
}

function captureGuideCanvas(video){
  // The guide is not just decorative: crop the actual pixels inside it before OCR.
  // Account for object-fit:cover, which may crop the sides of a landscape camera feed.
  const box=document.getElementById('cameraBox');
  const guide=box?.querySelector('.guide');
  if(!box||!guide||!video.videoWidth||!video.videoHeight)return null;
  const br=box.getBoundingClientRect(),gr=guide.getBoundingClientRect();
  const bw=br.width,bh=br.height,vw=video.videoWidth,vh=video.videoHeight;
  if(!bw||!bh)return null;
  const scale=Math.max(bw/vw,bh/vh);
  const renderedW=vw*scale,renderedH=vh*scale;
  const offsetX=(bw-renderedW)/2,offsetY=(bh-renderedH)/2;
  // Expand a little beyond the visible guide border to preserve card edges.
  const padX=gr.width*.035,padY=gr.height*.035;
  const x1=Math.max(0,(gr.left-br.left-padX-offsetX)/scale);
  const y1=Math.max(0,(gr.top-br.top-padY-offsetY)/scale);
  const x2=Math.min(vw,(gr.right-br.left+padX-offsetX)/scale);
  const y2=Math.min(vh,(gr.bottom-br.top+padY-offsetY)/scale);
  const sw=Math.max(1,Math.round(x2-x1)),sh=Math.max(1,Math.round(y2-y1));
  if(sw<20||sh<20)return null;
  const canvas=document.createElement('canvas');
  canvas.width=sw;canvas.height=sh;
  canvas.getContext('2d',{willReadFrequently:true}).drawImage(video,Math.round(x1),Math.round(y1),sw,sh,0,0,sw,sh);
  return canvas;
}

// Field-isolated OCR v2.11.01. The card guide is the coordinate system; each
// field is read from its own crop so headings and nearby labels cannot become a name.
function cropNormalizedField(source,x,y,w,h,scale=3){
  const sx=Math.max(0,Math.round(source.width*x)),sy=Math.max(0,Math.round(source.height*y));
  const sw=Math.max(1,Math.min(source.width-sx,Math.round(source.width*w)));
  const sh=Math.max(1,Math.min(source.height-sy,Math.round(source.height*h)));
  const canvas=document.createElement('canvas');canvas.width=Math.max(1,sw*scale);canvas.height=Math.max(1,sh*scale);
  const ctx=canvas.getContext('2d',{willReadFrequently:true});ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='high';
  ctx.drawImage(source,sx,sy,sw,sh,0,0,canvas.width,canvas.height);
  return canvas;
}
function fieldOCRVariants(source){
  const gray=document.createElement('canvas');gray.width=source.width;gray.height=source.height;
  const g=gray.getContext('2d',{willReadFrequently:true});g.drawImage(source,0,0);
  const im=g.getImageData(0,0,gray.width,gray.height),d=im.data,hist=new Uint32Array(256);let n=0;
  for(let i=0;i<d.length;i+=4){const v=Math.max(0,Math.min(255,Math.round(.299*d[i]+.587*d[i+1]+.114*d[i+2])));d[i]=d[i+1]=d[i+2]=v;hist[v]++;n++;}
  // Stretch contrast using the 2nd/98th percentile to retain faint engraved print.
  let lo=0,hi=255,acc=0;for(let i=0;i<256;i++){acc+=hist[i];if(acc>=n*.02){lo=i;break}}
  acc=0;for(let i=255;i>=0;i--){acc+=hist[i];if(acc>=n*.02){hi=i;break}}
  if(hi<=lo)hi=lo+1;
  const hist2=new Uint32Array(256);
  for(let i=0;i<d.length;i+=4){const v=Math.max(0,Math.min(255,Math.round((d[i]-lo)*255/(hi-lo))));d[i]=d[i+1]=d[i+2]=v;hist2[v]++;d[i+3]=255;}
  g.putImageData(im,0,0);
  // Otsu threshold for a second independent attempt; no sharpening halos.
  let total=0;for(let i=0;i<256;i++)total+=i*hist2[i];let sumB=0,wB=0,best=-1,threshold=150;
  for(let t=0;t<256;t++){wB+=hist2[t];if(!wB)continue;const wF=n-wB;if(!wF)break;sumB+=t*hist2[t];const mB=sumB/wB,mF=(total-sumB)/wF;const between=wB*wF*(mB-mF)*(mB-mF);if(between>best){best=between;threshold=t;}}
  const binary=document.createElement('canvas');binary.width=gray.width;binary.height=gray.height;
  const bctx=binary.getContext('2d',{willReadFrequently:true}),bi=g.getImageData(0,0,gray.width,gray.height),bd=bi.data;
  for(let i=0;i<bd.length;i+=4){const v=bd[i]>threshold?255:0;bd[i]=bd[i+1]=bd[i+2]=v;bd[i+3]=255;}
  bctx.putImageData(bi,0,0);
  return [gray,binary];
}
async function recognizeIsolatedField(worker,source,whitelist,label){
  const candidates=[];
  for(const [index,variant] of fieldOCRVariants(source).entries()){
    await worker.setParameters({tessedit_pageseg_mode:'7',tessedit_char_whitelist:whitelist,load_system_dawg:'0',load_freq_dawg:'0',preserve_interword_spaces:'1'});
    const result=await withOCRTimeout(worker.recognize(variant),10000,`${label} OCR timed out`);
    const text=String(result?.data?.text||'').replace(/[\r\n]+/g,' ').trim();
    const confidence=Number(result?.data?.confidence);
    candidates.push({text,confidence:Number.isFinite(confidence)?confidence:0,index});
  }
  candidates.sort((a,b)=>b.confidence-a.confidence);
  return candidates;
}
function parseHungarianSexRegion(text){
  // Hungarian ID visible zone prints female as N/F and male as F/M.
  // Only this tiny value crop is consulted, never the label or whole-page text.
  const value=String(text||'').toUpperCase().replace(/[^NFM]/g,'');
  if(value.includes('N')&&value.includes('M'))return ''; // conflicting glyphs: ask for manual review
  if(value.includes('M'))return 'M';
  if(value.includes('N'))return 'F';
  if(value==='F')return 'F';
  return '';
}
function parseHungarianNameRegion(text){
  const reject=/(?:ORSZAG|HUNGARY|MAGYARORSZAG|IDENTITY|IGAZOLV|CSALADI|FAMILY|GIVEN|NATIONALITY|AL[L]?AMPOLG)/i;
  const options=String(text||'').split(/[\r\n]+/).map(line=>normalizePersonName(line)).filter(line=>isPlausiblePersonName(line)&&!reject.test(line));
  return options.sort((a,b)=>b.length-a.length)[0]||'';
}

async function captureAndRead(){
  const video=document.getElementById('cameraVideo'),status=document.getElementById('scanStatus');
  if(scanInProgress)return;
  if(!video||!video.videoWidth){if(status)status.textContent='Camera is not ready yet. Wait a moment and tap Capture ID photo again.';return}
  scanInProgress=true;
  const captureButton=document.getElementById('startCamera');
  const processing=document.getElementById('scanProcessing');
  if(processing)processing.hidden=false;
  if(captureButton){captureButton.disabled=true;captureButton.textContent='Reading ID…'}
  status.textContent='Photo captured. Reading the document and filling in your details…';
  window.__rosaScanDiagnostics=[];
  try{
    // Keep every operation that can throw (including canvas encoding) inside the
    // try/finally so the capture button can never be stranded in Reading ID… state.
    const fullCanvas=document.createElement('canvas');fullCanvas.width=video.videoWidth;fullCanvas.height=video.videoHeight;
    fullCanvas.getContext('2d').drawImage(video,0,0);
    // OCR the pixels inside the on-screen document guide, not the entire camera scene.
    // This reduces background text and makes the field crop coordinates stable.
    const guideCanvas=captureGuideCanvas(video);
    const primaryCanvas=guideCanvas||fullCanvas;
    const q=imageQuality(primaryCanvas);
    const qualityWarning=(q.mean<30||q.mean>242||q.contrast<8||q.edge<1.2);
    const primaryBlob=await new Promise((resolve,reject)=>primaryCanvas.toBlob(blob=>blob?resolve(blob):reject(new Error('Could not capture the ID photo. Please retry.')),'image/jpeg',.96));
    status.textContent=window.Tesseract?'Starting local OCR engine…':'Loading local OCR engine…';
    let parsed;
    try{
      parsed=await withOCRTimeout(
        recognizeLocal(primaryBlob,status),
        60000,
        'OCR took too long. You can retry the scan.'
      );
      if(scanSide==='back'){
        // The reverse has three labeled identity rows above the MRZ. Run a distinct
        // enhanced, enlarged pass on the upper reverse field region so the OCR engine
        // sees the field labels and values at a more useful scale.
        const worker=await getRosaOCRWorker(status);
        const reverseFieldCrop=cropNormalizedField(primaryCanvas,.02,.12,.96,.58,3);
        const reverseMRZCrop=cropNormalizedField(primaryCanvas,.02,.66,.96,.30,3);
        await worker.setParameters({tessedit_pageseg_mode:'6',tessedit_char_whitelist:'',load_system_dawg:'1',load_freq_dawg:'1',preserve_interword_spaces:'1'});
        const fieldResult=await withOCRTimeout(worker.recognize(reverseFieldCrop),18000,'Reverse-side field OCR timed out');
        const fieldText=fieldResult?.data?.text||'';
        const backFields=parseVisibleText(fieldText);
        if(backFields){
          parsed={...(parsed||{})};
          for(const key of ['birth_place','birth_name','mother_birth_name']){
            const value=String(backFields[key]||'').trim();
            if(value && !(key==='mother_birth_name' && (/\d|^X+$/i.test(value)||value.length<3))) parsed[key]=value;
          }
        }
        // Independently read the three MRZ rows; merge only check-digit-validated fields.
        await worker.setParameters({tessedit_pageseg_mode:'6',tessedit_char_whitelist:'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<',load_system_dawg:'0',load_freq_dawg:'0',preserve_interword_spaces:'1'});
        const mrzResult=await withOCRTimeout(worker.recognize(reverseMRZCrop),18000,'Reverse-side MRZ OCR timed out');
        const mrzText=mrzResult?.data?.text||'';
        const mrz=parseMRZ(mrzText);
        if(mrz){
          parsed={...(parsed||{})};
          if(mrz.mrz_checks?.[0]===true && mrz.document_number)parsed.document_number=mrz.document_number;
          if(mrz.mrz_checks?.[1]===true && mrz.date_of_birth)parsed.date_of_birth=mrz.date_of_birth;
          if(/^[MF]$/.test(mrz.sex||''))parsed.sex=mrz.sex;
          if(mrz.full_name && isPlausiblePersonName(mrz.full_name))parsed.full_name=mrz.full_name;
        }
        await worker.setParameters({tessedit_pageseg_mode:'6',tessedit_char_whitelist:'',load_system_dawg:'1',load_freq_dawg:'1',preserve_interword_spaces:'1'});
      }
    }catch(ocrError){
      if(/OCR took too long/i.test(String(ocrError?.message||ocrError)))await resetRosaOCRWorker();
      throw ocrError;
    }
    // Front-side name and sex have dedicated crops. On the reverse, do not clear
    // fields or run front-specific crops: parse the visible reverse labels and MRZ.
    if(scanSide==='front'){
      if(parsed)parsed.full_name='';
      if(parsed)parsed.sex='';
    }
    if(scanSide==='front')try{
      const worker=await getRosaOCRWorker(status);
      // Coordinates are normalized to the card aligned in the guide. The name crop
      // contains the value row only, deliberately excluding the country/title heading.
      const nameRegion=cropNormalizedField(primaryCanvas,.395,.292,.435,.085,4);
      const nameVariants=await recognizeIsolatedField(
        worker,nameRegion,
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÁÉÍÓÖŐÚÜŰáéíóöőúüű -\'',
        'Name-region'
      );
      const nameCandidates=nameVariants.map(c=>({value:parseHungarianNameRegion(c.text),confidence:c.confidence}))
        .filter(c=>c.value);
      // Prefer repeat agreement; otherwise accept only a high-confidence, structurally valid line.
      let chosenName='';
      if(nameCandidates.length){
        const counts=new Map();for(const c of nameCandidates)counts.set(c.value,(counts.get(c.value)||0)+1);
        const agreed=[...counts.entries()].sort((a,b)=>b[1]-a[1])[0];
        if(agreed&&agreed[1]>=2)chosenName=agreed[0];
        else if(nameCandidates.some(c=>c.confidence>=72))chosenName=nameCandidates.sort((a,b)=>b.confidence-a.confidence)[0].value;
      }
      if(parsed&&chosenName)parsed.full_name=chosenName;
      window.__rosaScanDiagnostics.push(`Isolated name OCR: ${chosenName?'accepted':'no safe candidate'}; variants ${nameVariants.map(c=>Math.round(c.confidence)).join('/')}`);

      // The sex field is read separately from the tiny printed Nem/Sex value row.
      // Hungarian N/F means female; F/M means male. No whole-page sex guessing.
      const sexRegion=cropNormalizedField(primaryCanvas,.475,.455,.115,.085,5);
      const sexVariants=await recognizeIsolatedField(worker,sexRegion,'NFM','Sex-region');
      const sexCandidates=sexVariants.map(c=>({value:parseHungarianSexRegion(c.text),confidence:c.confidence,text:c.text})).filter(c=>c.value);
      if(parsed&&sexCandidates.length){
        const first=sexCandidates[0],second=sexCandidates[1];
        if(second&&first.value===second.value)parsed.sex=first.value;
        else if(first.confidence>=78)parsed.sex=first.value;
      }
      window.__rosaScanDiagnostics.push(`Isolated sex OCR: ${parsed?.sex||'not confidently detected'}; variants ${sexVariants.map(c=>Math.round(c.confidence)).join('/')}`);
      await worker.setParameters({tessedit_pageseg_mode:'6',tessedit_char_whitelist:'',load_system_dawg:'1',load_freq_dawg:'1',preserve_interword_spaces:'1'});
    }catch(fieldPassError){
      if(/timed out/i.test(String(fieldPassError?.message||fieldPassError)))await resetRosaOCRWorker();
      window.__rosaScanDiagnostics.push('Field-isolated OCR unavailable; uncertain name/sex left blank for manual entry');
    }
    // Do not launch a second full-frame OCR job automatically: it doubles latency.
    // The guide is intended to contain the whole document; use Retry after repositioning if needed.
    if(parsed){
      retainReaderFields(parsed);
      // Explicitly merge the two captures before updating the form. Front is the
      // preferred source for identity/name, sex, nationality, DOB and document no.
      // Back is the preferred source for birth place, birth name and mother's birth name.
      const frontKeys=['family_name','given_names','nationality_code','full_name','sex','nationality','date_of_birth','date_of_expiry','document_number'];
      const backKeys=['birth_place','birth_name','mother_birth_name'];
      const prior=state||{};
      const merged={...prior,...parsed};
      const keys=scanSide==='back'?backKeys:frontKeys;
      for(const key of keys){
        const candidate=String(parsed[key]||'').trim();
        const invalidNameField=(key==='mother_birth_name' || key==='birth_name') && (/\d|^X+$/i.test(candidate)||candidate.length<3);
        if(candidate && !invalidNameField) merged[key]=candidate;
        else if(prior[key]) merged[key]=prior[key];
        else if(invalidNameField) merged[key]='';
      }
      if(scanSide==='back'){
        // The front scan is authoritative for its fields; reverse-side MRZ may
        // fill a missing value but must never replace an existing front value.
        for(const key of frontKeys) if(String(prior[key]||'').trim()) merged[key]=prior[key];
      }

      state=merged;
      applyParsed(merged);
    }

    // A two-stage scan is intentional: the front supplies identity fields, while
    // the reverse commonly contains birthplace, mother's birth name and a TD1 MRZ.
    // Keep the camera running between sides so the guest can flip the card and capture
    // the reverse without reopening permissions. Never treat an unreadable front as
    // a reason to skip the reverse scan.
    if(scanSide==='front'){
      scanSide='back';
      const liveStatus=document.getElementById('scanStatus')||status;
      liveStatus.textContent=parsed
        ? 'Front captured. Flip your ID and capture the BACK side now. Delvane will merge any additional fields, including place of birth, mother’s birth name and the three machine-readable lines.'
        : 'Delvane could not confidently read the front. Flip your ID and capture the BACK side; you can review and complete all fields manually afterward.';
      const start=document.getElementById('startCamera');
      if(start){start.textContent='Capture back side';start.disabled=false;}
      const guide=document.querySelector('#cameraBox .guide');
      if(guide)guide.setAttribute('data-side','back');
      const tip=document.querySelector('#cameraBox .camera-tip');
      if(tip)tip.textContent='BACK SIDE · fit all four edges';
      const processing=document.getElementById('scanProcessing');
      if(processing)processing.hidden=true;
      return;
    }

    // After the reverse is processed, stop the camera and present the merged form.
    const liveStatus=document.getElementById('scanStatus')||status;
    liveStatus.textContent=parsed
      ? 'Both sides processed. Review the merged details carefully; place of birth and mother’s birth name may need manual correction.'
      : 'The back side could not be read reliably. Review the fields and enter any missing information manually.';
    stopCamera();
    const cameraBox=document.getElementById('cameraBox');if(cameraBox)cameraBox.hidden=true;
    const actions=document.querySelector('.camera-actions');if(actions)actions.hidden=true;
    const liveProcessing=document.getElementById('scanProcessing');if(liveProcessing)liveProcessing.hidden=true;
    return;
  }catch(e){
    // Keep the camera usable, but expose the actual initialization error during diagnosis.
    const detail=String(e?.message||e||'Unknown OCR error').replace(/https?:\/\/\S+/g,'[resource URL]').slice(0,180);
    status.textContent=(e&&e.message==='Scanner engine unavailable')
      ?'Scanner engine unavailable. Check internet/CDN access, then reopen the camera.'
      :'Unable to read the document. Adjust the lighting and retry, or complete the fields manually.';
  }finally{
    scanInProgress=false;
    // Do not silently run repeated multi-pass OCR on the same unchanged frame.
    // Keep preview live so the guest can adjust the document; the next retry is explicit.
    const processingNow=document.getElementById('scanProcessing');if(processingNow)processingNow.hidden=true;
    if(stream&&document.getElementById('cameraVideo')){
      const start=document.getElementById('startCamera');
      if(start){start.disabled=false;start.textContent='Capture ID photo';}
      if(status&&(/Reading ID|Starting local OCR|Loading local OCR|Photo captured/.test(window.guestSourceText?window.guestSourceText(status):status.textContent)))status.textContent='Scan did not finish. Adjust the card and tap Capture ID photo to retry.';
    }
  }
}
const readerOriginal={};
const readerContext={};
const readerConflicts=new Set();
function readerFields(p){
  const out={};
  const map={family_name:'csaladnev',given_names:'utonev',birth_family_name:'szuletesiCsaladnev',birth_given_names:'szuletesiUtonev',mother_family_name:'anyjaCsaladnev',mother_given_names:'anyjaUtonev',date_of_birth:'szuletesiDatum',birth_place:'szuletesiHely',nationality_code:'allampolgarsagKod',document_number:'okmanyAzonositoSzam'};
  for(const [a,b] of Object.entries(map))if(p[a])out[b]=p[a];
  if(p.sex)out.nem={M:'FERFI',F:'NO',X:'EGYEB_VAGY_NEM_ISMERT'}[p.sex];
  if(p.document_type)out.okmanyTipus={passport:'UTLEVEL',id_card:'SZEM_IG',driver_license:'VEZ_ENG',other:'EGYEB'}[p.document_type];
  return out;
}
function mrzBirthCandidates(raw){
  if(!/^\d{6}$/.test(raw||''))return [];
  const today=localToday(),minimum=rollingBirthMinimum(),suffix=raw.slice(2,4)+'-'+raw.slice(4,6);
  return [1900,2000].map(c=>String(c+Number(raw.slice(0,2)))+'-'+suffix).filter(d=>d>=minimum&&d<=today&&!Number.isNaN(new Date(d).getTime())&&new Date(d).toISOString().slice(0,10)===d);
}
function retainReaderFields(p){
  if(p.mrz_birth_raw&&!readerContext.mrz_birth_raw)readerContext.mrz_birth_raw=p.mrz_birth_raw;
  if(p.mrz_format&&!readerContext.mrz_format)readerContext.mrz_format=p.mrz_format;
  for(const [key,value] of Object.entries(readerFields(p))){
    if(!value)continue;
    if(readerOriginal[key]===undefined)readerOriginal[key]=value;
    else if(readerOriginal[key]!==value)readerConflicts.add('conflicting_scan:'+key);
  }
  if(p.mrz_birth_raw&&mrzBirthCandidates(p.mrz_birth_raw).length!==1)readerConflicts.add('mrz_birth_century_confirmation');
  if(['NLD','XKX'].includes(p.nationality_code))readerConflicts.add('country_mapping_requires_review');
}
function identitySubmission(form){
  const manual=readerFields(form);
  if(!manual.allampolgarsagKod&&!readerOriginal.allampolgarsagKod){
    // A chosen label can carry its catalog code only when the option is unique.
    // Legacy free text and ambiguous labels still require a person's review.
    const codes=Object.keys(NATIONALITY_BY_CODE).filter(code=>NATIONALITY_BY_CODE[code]===form.nationality);
    if(codes.length===1)manual.allampolgarsagKod=codes[0];
  }
  for(const key of Object.keys(manual))if(manual[key]===readerOriginal[key])delete manual[key];
  for(const [a,b] of [['csaladnev','utonev'],['szuletesiCsaladnev','szuletesiUtonev'],['anyjaCsaladnev','anyjaUtonev']]){
    if(a in manual||b in manual){manual[a]=manual[a]??readerOriginal[a]??null;manual[b]=manual[b]??readerOriginal[b]??null;}
  }
  return {reader_context:{...readerContext},scanned_fields:{...readerOriginal},manual_fields:manual,scan_ambiguities:[...readerConflicts]};
}
function applyParsed(p){
  // Preserve the live form and camera DOM: only write recognized values into their
  // matching controls. Re-rendering the whole page here detached the camera/status
  // elements and made it difficult to tell whether fields had actually been filled.
  const chosen=state?.document_type;
  const additions=Object.fromEntries(Object.entries(p).filter(([k,v])=>v!==null&&v!==undefined&&String(v).trim()!==''&&(!state?.[k]||state[k]===v)));
  state={...(state||{}),...additions,document_type:(!chosen||chosen==='auto')?(p.document_type||'other'):chosen,scan_method:p.scan_method||(p.mrz_format?'camera_mrz':'camera_ocr')};
  const values={family_name:state.family_name,given_names:state.given_names,nationality_code:state.nationality_code,full_name:state.full_name,birth_name:state.birth_name,birth_place:state.birth_place,date_of_birth:state.date_of_birth,sex:state.sex,nationality:state.nationality,mother_birth_name:state.mother_birth_name,document_number:state.document_number};
  for(const [id,value] of Object.entries(values)){
    if(value===undefined||value===null||String(value).trim()==='')continue;
    const el=document.getElementById(id);if(!el)continue;
    if(id==='sex'&&!['M','F'].includes(String(value))){el.value='';continue}
    if(el.tagName==='SELECT'&&!Array.from(el.options).some(o=>o.value===String(value))){const opt=document.createElement('option');opt.value=String(value);opt.textContent=String(value);el.appendChild(opt)}
    el.value=String(value);
    if(typeof el.dispatchEvent==='function'&&typeof Event==='function'){el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));}
  }
  if(readerConflicts.size){const warning=document.getElementById('error');if(warning)warning.textContent='Ambiguous scanner values require reception review. Confirm the full birth date and nationality code.';}
  const typeEl=document.getElementById('document_type');
  if(typeEl&&state.document_type){if(typeEl.options&&!Array.from(typeEl.options).some(o=>o.value===state.document_type)){const opt=document.createElement('option');opt.value=state.document_type;opt.textContent=state.document_type;typeEl.appendChild(opt)}typeEl.value=state.document_type;}
}
function localToday(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function rollingBirthMinimum(){const d=new Date();const year=d.getFullYear()-110;const month=d.getMonth();const day=d.getDate();const last=new Date(year,month+1,0).getDate();return `${year}-${String(month+1).padStart(2,'0')}-${String(Math.min(day,last)).padStart(2,'0')}`}
function registrationDocumentRequired(born){const arrival=state?.reservation?.arrival_date||localToday();const boundary=new Date(arrival+'T12:00:00');boundary.setFullYear(boundary.getFullYear()-14);return !born||born<=boundary.toISOString().slice(0,10)}
function renderFields(){const f=state||{};return `<div class="fields" id="fields">
<div class="field wide"><label for="full_name">Full name<span aria-hidden="true"> *</span></label><input id="full_name" aria-required="true" required value="${esc(f.full_name||'')}" autocomplete="name"></div>
<div class="field"><label for="birth_name">Birth name</label><input id="birth_name" value="${esc(f.birth_name||'')}"></div>
<div class="field"><label for="birth_place">Place of birth</label><input id="birth_place" value="${esc(f.birth_place||'')}"></div>
<div class="field"><label for="date_of_birth">Date of birth<span aria-hidden="true"> *</span></label><input id="date_of_birth" aria-required="true" type="date" min="${rollingBirthMinimum()}" max="${localToday()}" required value="${esc(f.date_of_birth||'')}"></div>
<div class="field"><label for="sex">Sex</label><select id="sex"><option value="">Select</option><option ${f.sex==='M'?'selected':''} value="M">Male</option><option ${f.sex==='F'?'selected':''} value="F">Female</option></select></div>
<div class="field"><label for="nationality">Nationality<span aria-hidden="true"> *</span></label><input type="search" id="nationalitySearch" data-guest-label="Search nationalities" aria-label="Search nationalities" autocomplete="off"><select id="nationality" aria-required="true" required><option value="">Select nationality</option>${(f.nationality&&!NATIONALITY_OPTIONS.includes(f.nationality)?[f.nationality,...NATIONALITY_OPTIONS]:NATIONALITY_OPTIONS).map(n=>`<option value="${esc(n)}" ${f.nationality===n?'selected':''}>${esc(n)}</option>`).join('')}</select></div>
<div class="field"><label for="mother_birth_name">Mother's birth name</label><input id="mother_birth_name" value="${esc(f.mother_birth_name||'')}"></div>
<div class="field"><label for="document_number">Document number<span aria-hidden="true"> *</span></label><input id="document_number" aria-required="true" required value="${esc(f.document_number||'')}" autocomplete="off"></div>
${[['family_name','Family name'],['given_names','Given names'],['birth_family_name','Birth family name'],['birth_given_names','Birth given names'],['mother_family_name',"Mother family name"],['mother_given_names',"Mother given names"],['nationality_code','Nationality code (review required)']].map(([id,label])=>`<div class="field"><label for="${id}">${label}</label><input id="${id}" value="${esc(f[id]||'')}"></div>`).join('')}
<div class="field wide"><label for="address">Address (if required by the applicable document/data set)</label><input id="address" value="${esc(f.address||'')}" autocomplete="street-address"></div>
</div>`}
function formData(){const ids=['full_name','birth_name','birth_place','date_of_birth','sex','nationality','mother_birth_name','document_type','document_number','address','family_name','given_names','birth_family_name','birth_given_names','mother_family_name','mother_given_names','nationality_code'];const out={};ids.forEach(id=>out[id]=document.getElementById(id)?.value?.trim()||'');return out}
function renderForm(){
  scanSide='front';
  shell(`<section class="hero"><span class="eyebrow">GUEST CHECK-IN</span><h1>Verify your stay.</h1><p>${esc(state.reservation.property_name)} · ${fmt(state.reservation.arrival_date)} → ${fmt(state.reservation.departure_date)}</p></section>
  <section class="card"><p class="required-note">Fields marked with * are required.</p><div class="notice">International document scanning: Delvane attempts to read visible fields and supported machine-readable zones. Review every value before confirming. <b>The document image is processed on your phone and is not uploaded to Delvane.</b></div>
    <div class="field wide"><label for="document_type">What document are you scanning?<span aria-hidden="true"> *</span></label><select id="document_type" aria-required="true" required><option ${(!state.document_type||state.document_type==='auto')?'selected':''} value="auto">Auto-detect document</option><option ${state.document_type==='id_card'?'selected':''} value="id_card">National identity card (any country)</option><option ${state.document_type==='passport'?'selected':''} value="passport">Passport</option><option ${state.document_type==='driver_license'?'selected':''} value="driver_license">Driving licence</option><option ${state.document_type==='other'?'selected':''} value="other">Other document</option></select><small>Delvane tries to identify the document format automatically; you can override it if needed.</small></div>
    <ol class="scan-steps"><li>Choose the document type, then fit the <b>whole document</b> inside the guide. Do not crop to a particular line or corner.</li><li>Use bright, even light and tilt slightly to remove reflections.</li><li>Scan the FRONT first, then flip the card and scan the BACK. Delvane combines both results, including birthplace, mother's birth name, and the three machine-readable lines when present.</li></ol>
    <div class="camera" id="cameraBox"><video id="cameraVideo" autoplay playsinline muted></video><div class="guide"></div><div class="camera-tip">Fit all four edges · keep printed text visible</div><div class="scan-processing" id="scanProcessing" hidden><div class="spinner" aria-hidden="true"></div><strong>Reading your ID…</strong><span>Please wait while Delvane fills in your details.</span></div></div>
    <p class="scan-status" id="scanStatus">Open the camera, then tap Capture ID photo. Delvane scans the captured image while you wait.</p>
    <details class="raw-ocr-details" id="rawOcrDetails" hidden>
      <summary>Developer diagnostic: raw OCR result</summary>
      <p class="raw-ocr-warning">This text is displayed locally on this device and is not uploaded. It may contain personal identity information. Redact names, document numbers and dates before sharing it.</p>
      <p class="raw-ocr-meta" id="rawOcrMeta"></p>
      <pre class="raw-ocr-output" id="rawOcrOutput">Waiting for OCR…</pre>
      <button class="btn secondary" id="copyRawOcr" type="button">Copy raw OCR text</button>
    </details>
    <div class="actions camera-actions"><button class="btn primary" id="startCamera">Open camera</button><button class="btn secondary" id="toggleTorch" hidden aria-pressed="false">Turn on flash</button><button class="btn secondary" id="cancelScanBtn" hidden>Pause scanning</button></div>
    <div id="fields">${renderFields()}</div>
    <div class="actions"><button class="btn primary" id="confirm">Confirm my information</button></div><p id="error"></p>
  </section>`);
  if(window.__rosaRawOCR){
    const rawPanel=document.getElementById('rawOcrOutput');
    const rawMeta=document.getElementById('rawOcrMeta');
    const rawDetails=document.getElementById('rawOcrDetails');
    if(rawPanel)rawPanel.textContent=window.__rosaRawOCR.text||'[Tesseract returned no text]';
    if(rawMeta)rawMeta.textContent=`OCR diagnostic · ${window.__rosaRawOCR.elapsed} ms · ${window.__rosaRawOCR.text.trim()?window.__rosaRawOCR.text.trim().split(/\r?\n/).filter(Boolean).length:0} line(s)`;
    if(rawDetails)rawDetails.hidden=false;
  }
  const updateDocumentRequirement=()=>{const required=registrationDocumentRequired(document.getElementById('date_of_birth').value);for(const id of ['document_number','document_type']){const field=document.getElementById(id);field.required=required;field.setAttribute('aria-required',String(required));const marker=document.querySelector?.(`label[for="${id}"] span`);if(marker)marker.hidden=!required;}};
  document.getElementById('date_of_birth').addEventListener('change',updateDocumentRequirement);updateDocumentRequirement();
  document.getElementById('nationalitySearch').oninput=(event)=>{
    const query=event.target.value.toLocaleLowerCase(document.documentElement.lang);
    for(const option of document.getElementById('nationality').options)option.hidden=!!query&&!option.textContent.toLocaleLowerCase(document.documentElement.lang).includes(query)&&!option.value.toLowerCase().includes(query);
  };
  const copyRaw=document.getElementById('copyRawOcr');
  if(copyRaw)copyRaw.onclick=async()=>{
    const raw=String(window.__rosaRawOCR?.text||'');
    try{await navigator.clipboard.writeText(raw);copyRaw.textContent='Copied';}
    catch(_){copyRaw.textContent='Copy unavailable — select the text manually';}
  };
  document.getElementById('document_type').onchange=(e)=>{
    state.document_type=e.target.value;
    const status=document.getElementById('scanStatus');
    if(state.document_type)status.textContent='Document type selected. Keep the whole document visible; Delvane checks printed fields and any machine-readable zone it can find.';
  };
  document.getElementById('startCamera').onclick=async()=>{
    state.document_type=document.getElementById('document_type').value||'auto';
    if(stream){const v=document.getElementById('cameraVideo');if(v&&v.srcObject!==stream)v.srcObject=stream;captureAndRead();return}
    try{
      stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1920},height:{ideal:1080}},audio:false});
      const v=document.getElementById('cameraVideo');v.srcObject=stream;await v.play();
      document.getElementById('startCamera').textContent='Capture ID photo';
      document.getElementById('startCamera').disabled=false;
      document.getElementById('cancelScanBtn').hidden=false;
      document.getElementById('toggleTorch').hidden=false;
      document.getElementById('cancelScanBtn').onclick=()=>{
        stopCamera();v.srcObject=null;
        document.getElementById('startCamera').disabled=false;
        document.getElementById('startCamera').textContent='Open camera';
        document.getElementById('cancelScanBtn').hidden=true;
        document.getElementById('toggleTorch').hidden=true;
        document.getElementById('scanStatus').textContent='Scanning paused. You can adjust the card and reopen the camera.';
      };
      document.getElementById('scanStatus').textContent=scanSide==='front'
        ? 'Camera ready. Fit the FRONT of the ID inside the guide and tap Capture ID photo. Delvane will then ask for the back.'
        : 'Camera ready. Fit the BACK of the ID inside the guide and tap Capture back side.';
    }catch(e){document.getElementById('scanStatus').textContent='Camera access was not available. Check browser permission or enter the information manually.'}
  };
  document.getElementById('toggleTorch').onclick=async()=>{
    const track=stream?.getVideoTracks?.()[0];
    if(!track){document.getElementById('scanStatus').textContent='Open the camera before using the flash.';return}
    try{
      const capabilities=track.getCapabilities?track.getCapabilities():{};
      if(!capabilities.torch){
        document.getElementById('scanStatus').textContent='This phone or browser does not expose flash control to the camera. Try opening the link in your phone’s default browser.';
        return;
      }
      torchEnabled=!torchEnabled;
      await track.applyConstraints({advanced:[{torch:torchEnabled}]});
      const b=document.getElementById('toggleTorch');b.textContent=torchEnabled?'Turn off flash':'Turn on flash';b.setAttribute('aria-pressed',String(torchEnabled));
      document.getElementById('scanStatus').textContent=torchEnabled?'Flash is on. Keep the card free of reflections.':'Flash is off.';
    }catch(e){
      torchEnabled=false;
      document.getElementById('scanStatus').textContent='The camera flash could not be controlled by this browser. Try the phone’s default browser or use steady room lighting.';
    }
  };
  document.getElementById('confirm').onclick=async()=>{const form=formData();const body={...form,...identitySubmission(form),scan_method:state.scan_method||'manual',guest_confirmed:true};if(!body.full_name){document.getElementById('error').className='error';document.getElementById('error').textContent='Please enter your full name.';return}for(const id of ['full_name','date_of_birth','nationality',...(registrationDocumentRequired(body.date_of_birth)?['document_number','document_type']:[])]){const field=document.getElementById(id);field.removeAttribute('aria-invalid');if(!field.value.trim()){document.getElementById('error').textContent='Complete the required identity fields.';field.setAttribute('aria-invalid','true');field.focus();return}}const birth=document.getElementById('date_of_birth');if(!birth.value||birth.value<rollingBirthMinimum()||birth.value>localToday()||!birth.checkValidity()){document.getElementById('error').textContent='Enter a birth date within the last 110 years.';birth.setAttribute('aria-invalid','true');birth.focus();return}try{const out=await api(`/api/public/checkin/${encodeURIComponent(token)}`,{method:'POST',body:JSON.stringify(body)});stopCamera();shell(`<section class="card success"><div class="mark">✓</div><span class="eyebrow">PRE-CHECK-IN COMPLETE</span><h1>You’re all set.</h1><p class="muted">Your guest information has been received by ${esc(state.reservation.property_name)}. The property will complete the required identity verification before sending the information to VIZA.</p><div class="notice">You do not need to upload or keep a photo of your document for Delvane.</div></section>`)}catch(e){document.getElementById('error').className='error';document.getElementById('error').textContent=e.message;if(e.field){const field=document.getElementById(e.field);field?.setAttribute('aria-invalid','true');field?.focus()}}};
}
async function boot(){try{state=await api(`/api/public/checkin/${encodeURIComponent(token)}`);renderForm()}catch(e){shell(`<section class="card"><span class="eyebrow">ROSA CHECK-IN</span><h1>This link isn't available.</h1><p class="muted">${esc(e.message)}</p></section>`)}}
boot();
