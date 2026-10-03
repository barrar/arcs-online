#!/usr/bin/env bash
# Use this wrapper for run/build/test so Firebase config stays outside Git.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  flutter_bin="$FLUTTER_BIN"
elif command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
elif [[ -x /private/tmp/arcs-flutter-sdk-restored/bin/flutter ]]; then
  flutter_bin="/private/tmp/arcs-flutter-sdk-restored/bin/flutter"
else
  echo 'Install Flutter or set FLUTTER_BIN=/path/to/flutter.' >&2
  exit 1
fi

args=("$@")
case "${1:-}" in
  run|build|test)
    emulators=false
    for argument in "$@"; do
      if [[ "$argument" == '--dart-define=USE_EMULATORS=true' || "$argument" == 'USE_EMULATORS=true' ]]; then
        emulators=true
      fi
    done
    if [[ "$emulators" == true ]]; then
      node scripts/firebase-config.cjs --emulators
    else
      node scripts/firebase-config.cjs
      args+=("--dart-define-from-file=$project_root/.firebase.local.json")
    fi
    ;;
esac

if [[ -n "${FLUTTER_XDG_CONFIG_HOME:-}" ]]; then
  XDG_CONFIG_HOME="$FLUTTER_XDG_CONFIG_HOME" "$flutter_bin" "${args[@]}"
else
  "$flutter_bin" "${args[@]}"
fi
