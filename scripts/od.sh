#!/usr/bin/env bash
# OpenDesign lifecycle wrapper for a local source checkout.
#
# Delegates every operation to the checkout's own tools-dev CLI, so ports,
# runtime state, supervision and logs keep a single owner. It never guesses a
# port and never starts a second instance.
#
# Do NOT call the bare `od` command for this: on most systems /usr/bin/od is
# the GNU coreutils octal-dump tool and shadows OpenDesign's own CLI.
#
# Environment:
#   OD_REPO       checkout root               (default: auto-detected)
#   OD_NAMESPACE  tools-dev runtime namespace (default: default)
#   OD_TIMEOUT    readiness wait, seconds     (default: 90)
#   OD_NODE       node binary                 (default: node from PATH)
#   OD_VERBOSE    set to 1 to show raw tools-dev output

set -euo pipefail

NAMESPACE="${OD_NAMESPACE:-default}"
TIMEOUT="${OD_TIMEOUT:-90}"
NODE_BIN="${OD_NODE:-node}"

# Auto-detection search paths for OpenDesign source checkout
CANDIDATE_REPOS=(
  "${OD_REPO:-}"
  "$PWD"
  "$HOME/open-design"
  "$HOME/projects/open-design"
  "$HOME/dev/open-design"
  "$HOME/src/open-design"
  "/devdata/agents/open-design"
  "/devdata/projects/open-design"
)

# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------

die() { printf 'od: %s\n' "$*" >&2; exit 1; }
note() { printf 'od: %s\n' "$*" >&2; }

print_usage() {
  cat <<'USAGE'
Usage:
  od.sh status [--json]     daemon/web/desktop state + URLs (read-only)
  od.sh url                 print the studio (web) URL, or fail if down
  od.sh start               idempotent: starts daemon+web only if needed
  od.sh restart             restart daemon+web (explicit request only)
  od.sh stop                stop web then daemon (desktop untouched)
  od.sh logs [daemon|web]   tail the latest log (both by default)
  od.sh check               status + recent logs for quick diagnosis
USAGE
}

usage_error() {
  print_usage >&2
  [ "$#" -eq 0 ] || printf '\nod: %s\n' "$1" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# preflight: resolve the checkout and the runtime it needs
# ---------------------------------------------------------------------------

resolve_repo() {
  if [ -n "${OD_REPO:-}" ]; then
    [ -f "$OD_REPO/tools/dev/bin/tools-dev.mjs" ] \
      || die "OD_REPO=$OD_REPO has no tools/dev/bin/tools-dev.mjs (point it at the OpenDesign checkout)"
    printf '%s\n' "$OD_REPO"
    return 0
  fi

  # Check git root of current directory
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$git_root" ] && [ -f "$git_root/tools/dev/bin/tools-dev.mjs" ]; then
    printf '%s\n' "$git_root"
    return 0
  fi

  local candidate
  for candidate in "${CANDIDATE_REPOS[@]}"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/tools/dev/bin/tools-dev.mjs" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  die "No OpenDesign checkout found. Set OD_REPO=/path/to/open-design or clone it to ~/open-design"
}

require_python() {
  command -v python3 >/dev/null 2>&1 \
    || die "python3 is required to read tools-dev status JSON (install python3, or drive tools-dev manually)"
}

require_runtime() {
  command -v "$NODE_BIN" >/dev/null 2>&1 || die "node not found: $NODE_BIN (set OD_NODE=<path>)"
  require_python
}

# ---------------------------------------------------------------------------
# tools-dev delegation + status parsing
# ---------------------------------------------------------------------------

td() {
  local sub="$1"; shift
  "$NODE_BIN" "$ENTRY" "$sub" "$@" --namespace "$NAMESPACE"
}

# Raw tools-dev output, except with OD_VERBOSE=1. stdout is the JSON payload,
# stderr stays visible so a broken checkout reports why.
run_td() {
  local sub="$1"; shift
  if [ "${OD_VERBOSE:-0}" = "1" ]; then
    td "$sub" "$@"
  else
    td "$sub" "$@" >/dev/null
  fi
}

status_raw() { td status --json; }

# read_field <json-text> <dotted.path> -> value on stdout, empty when absent.
read_field() {
  python3 -c '
import json, sys
raw = sys.argv[1]
brace = raw.find("{")
if brace > 0:
    raw = raw[brace:]
try:
    cur = json.loads(raw)
except ValueError:
    sys.exit(0)
for key in sys.argv[2].split("."):
    if isinstance(cur, dict) and key in cur:
        cur = cur[key]
    else:
        sys.exit(0)
if cur is None or cur == "":
    sys.exit(0)
print(cur)
' "$1" "$2"
}

# normalize_json <json-text> -> one clean JSON document on stdout.
normalize_json() {
  python3 -c '
import json, sys
raw = sys.argv[1]
brace = raw.find("{")
if brace > 0:
    raw = raw[brace:]
try:
    print(json.dumps(json.loads(raw)))
except ValueError:
    sys.exit(1)
' "$1"
}

# is_up <json-text>: daemon and web both running with a URL.
is_up() {
  [ "$(read_field "$1" apps.daemon.state)" = "running" ] \
    && [ -n "$(read_field "$1" apps.daemon.url)" ] \
    && [ "$(read_field "$1" apps.web.state)" = "running" ] \
    && [ -n "$(read_field "$1" apps.web.url)" ]
}

print_rows() {
  local raw="$1" name state url pid
  for name in daemon web desktop; do
    state="$(read_field "$raw" "apps.$name.state")"
    url="$(read_field "$raw" "apps.$name.url")"
    pid="$(read_field "$raw" "apps.$name.pid")"
    printf '%-8s %-8s %-28s %s\n' \
      "$name" "${state:-unknown}" "${url:--}" "${pid:+pid $pid}"
  done
  printf '%-8s %s\n' 'studio' "$(read_field "$raw" apps.web.url || true)"
}

# wait_ready: poll until daemon+web are up, or fail after OD_TIMEOUT seconds.
wait_ready() {
  local deadline raw dots=0
  deadline=$(( $(date +%s) + TIMEOUT ))
  while :; do
    raw="$(status_raw)"
    if is_up "$raw"; then
      [ "$dots" -eq 0 ] || printf '\n' >&2
      print_rows "$raw"
      return 0
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      [ "$dots" -eq 0 ] || printf '\n' >&2
      print_rows "$raw" >&2
      note "timed out after ${TIMEOUT}s waiting for daemon+web (raise OD_TIMEOUT, then run: od.sh check)"
      return 1
    fi
    printf '.' >&2
    dots=1
    sleep 2
  done
}

mcp_hint() {
  cat <<'HINT'

If a Pi / coding agent session started while the daemon was down, the "open-design"
MCP server is failed in that session: reconnect it with /mcp (or restart session).
An already connected session is unaffected.
HINT
}

# ---------------------------------------------------------------------------
# actions
# ---------------------------------------------------------------------------

do_status() {
  local raw
  case "${1:-}" in
    "")        : ;;
    --json)    : ;;
    *)         usage_error "status accepts only --json" ;;
  esac
  raw="$(status_raw)" || die "tools-dev status failed (run: od.sh check)"
  [ -n "$raw" ] || die "tools-dev status returned nothing"
  if [ "${1:-}" = "--json" ]; then
    normalize_json "$raw" || die "could not parse tools-dev status output"
    return 0
  fi
  print_rows "$raw"
}

do_url() {
  local url
  url="$(read_field "$(status_raw)" apps.web.url)"
  [ -n "$url" ] || die "studio is not running (start it with: od.sh start)"
  printf '%s\n' "$url"
}

do_start() {
  local raw
  raw="$(status_raw)"
  if is_up "$raw"; then
    printf 'open-design already running; nothing started\n'
    print_rows "$raw"
    return 0
  fi
  printf 'starting open-design (daemon + web)...\n'
  run_td start web || die "tools-dev start failed (run: od.sh logs)"
  wait_ready || exit 1
  mcp_hint
}

do_restart() {
  printf 'restarting open-design (daemon + web)...\n'
  run_td restart web || die "tools-dev restart failed (run: od.sh logs)"
  wait_ready || exit 1
  mcp_hint
}

do_stop() {
  local raw
  printf 'stopping open-design (web then daemon; desktop untouched)...\n'
  run_td stop web || die "tools-dev stop failed"
  raw="$(status_raw)"
  print_rows "$raw"
  if is_up "$raw"; then
    note "daemon+web still report running; inspect: od.sh logs"
    exit 1
  fi
}

do_logs() {
  local apps=() app
  case "${1:-}" in
    "")         apps=(daemon web) ;;
    daemon|web) apps=("$1") ;;
    *)          usage_error "logs accepts daemon or web" ;;
  esac
  for app in "${apps[@]}"; do
    if [ "$app" != "${apps[0]}" ]; then printf '\n'; fi
    printf '=== %s ===\n' "$app"
    td logs "$app" || note "no logs for $app yet"
  done
  return 0
}

do_check() { td check; }

# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------

REPO="$(resolve_repo)"
ENTRY="$REPO/tools/dev/bin/tools-dev.mjs"

action="${1:-status}"
[ "$#" -eq 0 ] || shift
case "$action" in
  status)  require_python; do_status "$@" ;;
  url)     require_python; do_url "$@" ;;
  start)   require_runtime; do_start "$@" ;;
  restart) require_runtime; do_restart "$@" ;;
  stop)    require_runtime; do_stop "$@" ;;
  logs)    require_runtime; do_logs "$@" ;;
  check)   require_runtime; do_check "$@" ;;
  -h|--help|help) print_usage; exit 0 ;;
  *)       usage_error "unknown action: $action" ;;
esac
