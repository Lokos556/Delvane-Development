const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'static', 'app.js'), 'utf8');

function extractObject(name) {
  const marker = `const ${name}`;
  const startDecl = src.indexOf(marker);
  if (startDecl < 0) throw new Error(`Missing ${name}`);
  const start = src.indexOf('{', startDecl);
  if (start < 0) throw new Error(`Missing object for ${name}`);
  let depth = 0, quote = null, escape = false, lineComment = false, blockComment = false;
  for (let i = start; i < src.length; i++) {
    const c = src[i], n = src[i+1];
    if (lineComment) { if (c === '\n') lineComment = false; continue; }
    if (blockComment) { if (c === '*' && n === '/') { blockComment = false; i++; } continue; }
    if (quote) {
      if (escape) { escape = false; continue; }
      if (c === '\\') { escape = true; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '/' && n === '/') { lineComment = true; i++; continue; }
    if (c === '/' && n === '*') { blockComment = true; i++; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    if (c === '}') {
      depth--;
      if (depth === 0) {
        const body = src.slice(start, i + 1);
        return Function(`"use strict"; return (${body});`)();
      }
    }
  }
  throw new Error(`Unterminated object ${name}`);
}

const T = extractObject('T');
const V22 = extractObject('V22_I18N');
const V223 = extractObject('V223_I18N');
const V23 = extractObject('V23_I18N');
const V26 = extractObject('V26_I18N');
const FULL = extractObject('FULL_LOCALE');
const EXTRA = extractObject('ROSA_EXTRA_LOCALE');
const FULL_UI = extractObject('ROSA_FULL_UI_PATCH');
const FINAL = extractObject('ROSA_FINAL_PATCH');
const EXTRA_PATCH = extractObject('ROSA_EXTRA_PATCH');
const DYNAMIC = extractObject('ROSA_DYNAMIC_LOCALE');

const langs = ['hu','de','es','fr','it','pt','pl','nl','ro','cs','sk','hr','sr','uk','ru','tr','zh'];
const layers = [FULL, EXTRA, FULL_UI, FINAL, EXTRA_PATCH];
const master = new Set([
  ...layers.flatMap(x => Object.keys(x.hu || {})),
  ...Object.values(T.en || {}),
  ...Object.values(V22.en || {}),
  ...Object.values(V223.en || {}),
  ...Object.values(V23.en || {}),
  ...Object.values(V26.en || {})
]);

let failed = false;
for (const lang of langs) {
  const have = new Set(layers.flatMap(x => Object.keys(x[lang] || {})));
  for (const [k, enValue] of Object.entries(T.en || {})) if (T[lang]?.[k]) have.add(enValue);
  for (const [k, enValue] of Object.entries(V22.en || {})) if (V22[lang]?.[k]) have.add(enValue);
  for (const [k, enValue] of Object.entries(V223.en || {})) if (V223[lang]?.[k]) have.add(enValue);
  for (const [k, enValue] of Object.entries(V23.en || {})) if (V23[lang]?.[k]) have.add(enValue);
  for (const [k, enValue] of Object.entries(V26.en || {})) if (V26[lang]?.[k]) have.add(enValue);
  const v223Missing = Object.keys(V223.en || {}).filter(k => !(k in (V223[lang] || {})));
  const v23Missing = Object.keys(V23.en || {}).filter(k => !(k in (V23[lang] || {})));
  const v26Missing = Object.keys(V26.en || {}).filter(k => !(k in (V26[lang] || {})));
  if (v223Missing.length) { failed = true; console.error(`${lang}: missing V2.2.3 translations: ${v223Missing.join(', ')}`); }
  if (v23Missing.length) { failed = true; console.error(`${lang}: missing V2.3 translations: ${v23Missing.join(', ')}`); }
  if (v26Missing.length) { failed = true; console.error(`${lang}: missing V2.6 translations: ${v26Missing.join(', ')}`); }
  const missing = [...master].filter(k => !have.has(k));
  if (missing.length) {
    failed = true;
    console.error(`${lang}: missing ${missing.length}: ${missing.slice(0, 20).join(' | ')}`);
  }
  const dynMissing = Object.keys(DYNAMIC.hu || {}).filter(k => !(k in (DYNAMIC[lang] || {})));
  if (dynMissing.length) {
    failed = true;
    console.error(`${lang}: missing dynamic templates: ${dynMissing.join(', ')}`);
  }
}

const requiredHungarian = {
  'Properties':'Apartmanok',
  'No blockers detected.':'Nincs észlelt akadály.',
  'Work in motion':'Folyamatban lévő munka',
  'TURNOVER':'FORDULÓ',
  'MAINTENANCE':'KARBANTARTÁS',
  'REGISTRATION':'REGISZTRÁCIÓ',
  'Ask Rosa anything…':'Kérdezz bármit Rosától…',
  'Late checkout request':'Késői kijelentkezési kérés',
  'Assign Bálint':'Bálint kijelölése',
  "What's happening tomorrow?":'Mi történik holnap?',
  "Which properties aren't ready?":'Mely apartmanok nem állnak készen?'
};
const hu = Object.assign({}, ...layers.map(x => x.hu || {}));
for (const [source, expected] of Object.entries(requiredHungarian)) {
  if (hu[source] !== expected && !Object.values(T.hu || {}).includes(expected) && !Object.values(V22.hu || {}).includes(expected)) {
    failed = true;
    console.error(`Hungarian regression: ${source} -> ${hu[source]}`);
  }
}

const requiredPatterns = [
  '/^(\\d+) decisions$/',
  '/^(\\d+) guests$/',
  'turnover is active',
  'registration risk',
  'registration is incomplete',
  'Tomorrow:'
];
for (const token of requiredPatterns) {
  if (!src.includes(token)) { failed = true; console.error(`Missing dynamic localization pattern: ${token}`); }
}

if (failed) process.exit(1);
console.log(`Localization coverage OK: ${langs.length + 1} languages, ${master.size} static phrases + dynamic templates.`);
