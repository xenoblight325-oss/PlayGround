#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$PROJECT_DIR/.omgithub-runtime/chess-app"
BUILD_DIR="$PROJECT_DIR/dist"
PORT="${PORT:-3000}"
RUNNER_TEMP="${RUNNER_TEMP:-/home/runner/work/_temp}"

/usr/bin/time -p test -f "$SOURCE_DIR/index.html"
/usr/bin/time -p mkdir -p "$BUILD_DIR" "$RUNNER_TEMP/omgithub-web"
# This is a dependency-free static project; copying the HTML is its build step.
if [[ ! -f "$BUILD_DIR/index.html" || "$SOURCE_DIR/index.html" -nt "$BUILD_DIR/index.html" ]]; then
  /usr/bin/time -p cp "$SOURCE_DIR/index.html" "$BUILD_DIR/index.html"
fi
/usr/bin/time -p node -e 'const fs=require("node:fs"); fs.writeFileSync(process.argv[1], JSON.stringify({project:process.argv[2],directory:process.argv[3]}, null, 2)+"\n")' \
  "$RUNNER_TEMP/omgithub-web/deployment-output.json" "$PROJECT_DIR" "$BUILD_DIR"
cd "$BUILD_DIR"
exec /usr/bin/time -p python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$BUILD_DIR"
