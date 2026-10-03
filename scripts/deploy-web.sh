#!/usr/bin/env bash
# Build and release the Flutter web client to the ARCS Firebase Hosting site.
set -euo pipefail

project_id="arcs-online-jeremiah-2026"
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

for tool in node npm npx; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required command: $tool" >&2
    exit 1
  fi
done

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  flutter_bin="$FLUTTER_BIN"
elif command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
elif [[ -x /private/tmp/arcs-flutter-sdk-restored/bin/flutter ]]; then
  flutter_bin="/private/tmp/arcs-flutter-sdk-restored/bin/flutter"
else
  echo "Flutter was not found. Install Flutter or set FLUTTER_BIN=/path/to/flutter." >&2
  exit 1
fi

if [[ ! -x "$flutter_bin" ]]; then
  echo "Flutter is not executable: $flutter_bin" >&2
  exit 1
fi

run_flutter() {
  if [[ -n "${FLUTTER_XDG_CONFIG_HOME:-}" ]]; then
    XDG_CONFIG_HOME="$FLUTTER_XDG_CONFIG_HOME" "$flutter_bin" "$@"
  else
    "$flutter_bin" "$@"
  fi
}

# Refuse to publish from a directory pointed at another Firebase project/site.
configured_project="$(node -p "JSON.parse(require('node:fs').readFileSync('.firebaserc', 'utf8')).projects.default")"
hosting_directory="$(node -p "require('./firebase.json').hosting.public")"
if [[ "$configured_project" != "$project_id" || "$hosting_directory" != "build/web" ]]; then
  echo "Firebase configuration does not match $project_id and build/web; aborting." >&2
  exit 1
fi

# Validate and prepare local configuration before any deployment work.
node scripts/firebase-config.cjs

echo "Checking Firebase CLI access..."
npx -y firebase-tools@latest projects:list --json >/dev/null

echo "Checking ARCS backend and Flutter client..."
run_flutter pub get
npm --prefix functions ci
npm --prefix functions run check
run_flutter analyze --no-pub
run_flutter test --no-pub --dart-define-from-file=.firebase.local.json

# USE_EMULATORS is deliberately omitted so the release talks to production.
echo "Building the production web client..."
run_flutter build web --release --no-pub --dart-define-from-file=.firebase.local.json
if [[ ! -s build/web/index.html || ! -s build/web/flutter_bootstrap.js ]]; then
  echo "The Flutter web build is incomplete; aborting." >&2
  exit 1
fi

echo "Deploying Hosting to $project_id..."
npx -y firebase-tools@latest deploy --only hosting --project "$project_id"
echo "Released: https://$project_id.web.app/"
