const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { loadConfig, prepare } = require('./firebase-config.cjs');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'arcs-config-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  for (const file of ['android/app/google-services.json', 'ios/Runner/GoogleService-Info.plist']) {
    fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    fs.copyFileSync(path.resolve(__dirname, '..', `${file}.template`), path.join(root, `${file}.template`));
  }
  fs.mkdirSync(path.join(root, 'web'));
  return root;
}

test('production fails clearly for missing, malformed, or incomplete local config', (t) => {
  const root = fixture(t);
  assert.throws(() => loadConfig(root), /Create .firebase.local.json/);
  fs.writeFileSync(path.join(root, '.firebase.local.json'), '{');
  assert.throws(() => loadConfig(root), /valid JSON object/);
  fs.writeFileSync(path.join(root, '.firebase.local.json'), '{}');
  assert.throws(() => loadConfig(root), /FIREBASE_WEB_API_KEY/);
});

test('emulator configuration works without any production keys', (t) => {
  const root = fixture(t);
  prepare(root, { emulators: true });
  const android = JSON.parse(fs.readFileSync(path.join(root, 'android/app/google-services.json')));
  assert.equal(android.client[0].api_key[0].current_key, 'arcs-emulator-key');
  assert.match(fs.readFileSync(path.join(root, 'ios/Runner/GoogleService-Info.plist'), 'utf8'), /arcs-emulator-key/);
  const vm = require('node:vm');
  const context = { self: {} };
  vm.runInNewContext(fs.readFileSync(path.join(root, 'web/firebase-config.js'), 'utf8'), context);
  assert.equal(context.self.ARCS_FIREBASE_CONFIG.apiKey, 'arcs-emulator-key');
  assert.equal(context.self.ARCS_FIREBASE_CONFIG.projectId, 'arcs-online-jeremiah-2026');
  assert.equal(fs.statSync(path.join(root, 'web/firebase-config.js')).mode & 0o777, 0o600);
});
