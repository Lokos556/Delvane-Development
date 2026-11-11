'use strict';
// Preload before reviewed test code. Node's permission flags enforce file/process
// restrictions; these guards deny networking, which Node 20 permissions omit.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const deny = () => { throw new Error('ISOLATION: networking is forbidden'); };
net.connect = net.createConnection = net.Socket.prototype.connect = deny;
require('node:tls').connect = deny;
for (const name of ['node:http', 'node:https']) {
  const module = require(name);
  module.request = module.get = deny;
  module.createServer = deny;
}
net.createServer = deny;
const dns = require('node:dns');
for (const key of Object.keys(dns)) {
  if (typeof dns[key] === 'function') dns[key] = deny;
}
for (const key of Object.keys(dns.promises)) {
  if (typeof dns.promises[key] === 'function') dns.promises[key] = deny;
}
require('node:dgram').createSocket = deny;
globalThis.fetch = deny;
globalThis.WebSocket = deny;

const NativeDate = Date;
globalThis.Date = class extends NativeDate {
  constructor(...args) { super(...(args.length ? args : ['2026-11-01T12:00:00Z'])); }
  static now() { return NativeDate.parse('2026-11-01T12:00:00Z'); }
};
const vm = require('node:vm');
const createContext = vm.createContext;
vm.createContext = (context = {}, ...options) => {
  context.Date = globalThis.Date;
  return createContext(context, ...options);
};

// Fail closed before running a test if permissions were omitted or ineffective.
assert.equal(process.permission?.has('fs.write'), false);
assert.equal(process.permission.has('child'), false);
assert.equal(process.permission.has('worker'), false);
assert.throws(() => fs.readFileSync(path.join(process.cwd(), '..', 'never-open.db')),
              error => error.code === 'ERR_ACCESS_DENIED');
assert.throws(() => fs.writeFileSync(path.join(process.cwd(), 'never-write.txt'), 'synthetic'),
              error => error.code === 'ERR_ACCESS_DENIED');
assert.throws(() => require('node:child_process').spawn('never-launch'),
              error => error.code === 'ERR_ACCESS_DENIED');
assert.throws(() => net.connect(1, '127.0.0.1'), /ISOLATION/);
assert.throws(() => fetch('https://example.invalid'), /ISOLATION/);
