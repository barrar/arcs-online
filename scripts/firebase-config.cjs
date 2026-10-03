// The only source of production API-key values is the ignored local JSON file.
const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const keyNames = ['FIREBASE_WEB_API_KEY', 'FIREBASE_ANDROID_API_KEY', 'FIREBASE_IOS_API_KEY'];

function loadConfig(root = projectRoot, { emulators = false } = {}) {
  if (emulators) {
    return Object.fromEntries(keyNames.map((name) => [name, 'arcs-emulator-key']));
  }
  const filename = path.join(root, '.firebase.local.json');
  if (!fs.existsSync(filename)) {
    throw new Error('Create .firebase.local.json from config/firebase.example.json and fill in the three Firebase API keys.');
  }
  let config;
  try {
    config = JSON.parse(fs.readFileSync(filename, 'utf8'));
  } catch {
    throw new Error('.firebase.local.json must contain a valid JSON object.');
  }
  if (config === null || typeof config !== 'object' || Array.isArray(config)) {
    throw new Error('.firebase.local.json must contain a JSON object.');
  }
  for (const name of keyNames) {
    if (typeof config[name] !== 'string' || !/^AIza[0-9A-Za-z_-]{35}$/.test(config[name])) {
      throw new Error(`Set ${name} in .firebase.local.json to a valid Firebase API-key string.`);
    }
  }
  // Production commands must not silently connect to an emulator.
  if (Object.hasOwn(config, 'USE_EMULATORS')) {
    throw new Error('Keep USE_EMULATORS out of .firebase.local.json; pass it explicitly to Flutter for local development.');
  }
  return config;
}

function webConfig(config = loadConfig()) {
  return {
    apiKey: config.FIREBASE_WEB_API_KEY,
    appId: '1:451692891873:web:a7adc5706e454f0f0d31a0',
    messagingSenderId: '451692891873',
    projectId: 'arcs-online-jeremiah-2026',
    authDomain: 'arcs-online-jeremiah-2026.firebaseapp.com',
    storageBucket: 'arcs-online-jeremiah-2026.firebasestorage.app',
  };
}

function prepare(root = projectRoot, options = {}) {
  const config = loadConfig(root, options);
  const generated = [
    ['android/app/google-services.json', 'FIREBASE_ANDROID_API_KEY'],
    ['ios/Runner/GoogleService-Info.plist', 'FIREBASE_IOS_API_KEY'],
  ];
  for (const [filename, name] of generated) {
    const template = fs.readFileSync(path.join(root, `${filename}.template`), 'utf8');
    if (!template.includes(`__${name}__`)) throw new Error(`Missing key placeholder in ${filename}.template`);
    writeLocal(path.join(root, filename), template.replaceAll(`__${name}__`, config[name]));
  }
  writeLocal(path.join(root, 'web/firebase-config.js'), `self.ARCS_FIREBASE_CONFIG = ${JSON.stringify(webConfig(config), null, 2)};\n`);
  return config;
}

function writeLocal(filename, content) {
  fs.writeFileSync(filename, content, { mode: 0o600 });
  fs.chmodSync(filename, 0o600);
}

module.exports = { loadConfig, webConfig, prepare };
if (require.main === module) {
  try {
    prepare(projectRoot, { emulators: process.argv.includes('--emulators') });
    console.log('Prepared ignored Firebase build configuration.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
