#!/bin/zsh
# Runs the reader page's tests: the built page (Apps/Shared/Web) in an offscreen WebKit view, checked
# against the notes in Tests/Fixtures/Rendering. Rebuilds the page first unless --no-build is given.
#   scripts/render-tests.sh            build, then every rendering test
#   scripts/render-tests.sh --bench    build, then print timings (cold, warm edit, same text again)
#   scripts/render-tests.sh --stills <folder> [notes] [themes] [width]   pictures of fixtures
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--no-build" ]]; then shift; else (cd Web && { [[ -d node_modules ]] || npm ci; } && npm run build); fi
case "${1:-}" in
  --bench)
    PERCH_RENDER_BENCH=1 swift test --filter RenderBenchTests 2>&1 | sed -n '/RENDER BENCH/,/^$/p' ;;
  --stills)
    PERCH_RENDER_STILLS="${2:?folder}" PERCH_RENDER_STILL_NOTES="${3:-formatting.md}" PERCH_RENDER_STILL_THEMES="${4:-perch-light,perch-dark}" \
      PERCH_RENDER_STILL_WIDTH="${5:-760}" swift test --filter RenderStillTests ;;
  *)
    swift test --filter PerchRenderTests ;;
esac
