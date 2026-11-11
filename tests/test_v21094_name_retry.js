// Regression assertions for the stuck capture state and dedicated name-region OCR.
const fs=require('fs'),path=require('path');
const src=fs.readFileSync(path.join(__dirname,'..','static','guest-checkin.js'),'utf8');
const capture=src.slice(src.indexOf('async function captureAndRead()'),src.indexOf('\nfunction applyParsed',src.indexOf('async function captureAndRead()')));
if(!capture.includes('Could not capture the ID photo. Please retry.'))throw new Error('Null canvas capture must fail visibly');
if(!capture.includes('OCR took too long. You can retry the scan.'))throw new Error('OCR timeout/retry guard missing');
if(!src.includes('cropNormalizedField(primaryCanvas,.395,.292,.435,.085,4)')||!src.includes('parseHungarianNameRegion')||!src.includes('Field-isolated OCR v2.11.01'))throw new Error('Field-isolated name OCR algorithm missing');
if(!capture.includes('start.disabled=false;start.textContent=\'Capture ID photo\''))throw new Error('Capture button is not restored in finally');
if(!capture.includes("/Reading ID|Starting local OCR|Loading local OCR|Photo captured/.test(status.textContent)"))throw new Error('Finally block can still overwrite user-facing OCR errors/status');
console.log('PASS: capture failure recovery, timeout/retry, field-isolated name OCR, and button reset assertions');
