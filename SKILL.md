---
name: open-design
description: "Trigger: lanzar OpenDesign, launch OpenDesign, /od, open-design status, daemon caído, opendesign mcp, iniciar opendesign. Ciclo de vida del checkout local vía tools-dev, resolución de colisión con /usr/bin/od e integración MCP."
license: Apache-2.0
metadata:
  author: "Carlos Damota"
  version: "1.0.0"
  repository: "https://github.com/CarlosDamota/open-design-skill"
---

## Activation Contract

Load this skill whenever the user or task wants to:
- Launch, start, inspect, restart, or stop the local OpenDesign instance.
- Request the Studio (web) URL for previewing design artifacts.
- Diagnose why OpenDesign is unreachable, or when OpenDesign MCP tools (`mcp__open_design__*`) fail.

## Hard Rules

- **Never call the bare `od` command:** On most Linux distributions and macOS, `/usr/bin/od` is the GNU coreutils octal-dump tool and shadows OpenDesign's binary. Calling `od` directly will hang the session in stdin or produce an octal dump error. Always invoke `scripts/od.sh` from this skill directory.
- **Never guess a port or PID:** Read them strictly from `od.sh status`, which queries the checkout's own `tools-dev` supervisor.
- **Keep `od.sh start` idempotent:** If the daemon and web server are already running, do not attempt to spawn another process or re-bind ports.
- **Never stop or restart a healthy instance** without an explicit user prompt.
- **MCP server resolution:** The MCP server resolves the daemon once at session start; starting the daemon mid-session requires reconnecting via `/mcp` in Pi or restarting the agent session.

## Decision Gates

| Situation | Action |
| :--- | :--- |
| **daemon and web running** | Report state and Studio URL; change nothing. |
| **daemon or web idle** | Run `scripts/od.sh start` (waits for real readiness). |
| **User asks to reload dev server** | Run `scripts/od.sh restart`. |
| **User asks to shut down** | Run `scripts/od.sh stop` (desktop remains untouched). |
| **Start fails or times out** | Run `scripts/od.sh logs`, then `scripts/od.sh check`; report raw diagnostic output. |
| **`mcp__open_design__*` tools missing** | Start the daemon with `od.sh start`, then prompt the user to run `/mcp` in Pi. |

## Execution Steps

1. Run `scripts/od.sh status` first; never assume the instance is up or down.
2. Apply the matching decision gate above. (Pass `--json` if another tool or script consumes the output).
3. Report the three processes (`daemon`, `web`, `desktop`) and the Studio URL exactly as observed.
4. If MCP tools were unavailable, explicitly explain that reconnecting is a client-side action in Pi (`/mcp`, or starting a new session).
5. On failure, return the output of `scripts/od.sh logs` and `scripts/od.sh check` and stop; do not arbitrarily reinstall or rebuild the checkout.

## Environment Variables

- `OD_REPO`: Absolute path to the OpenDesign source checkout (auto-detected if located in `~/open-design`, `~/projects/open-design`, etc.).
- `OD_NODE`: Node binary to use (defaults to `node` from PATH).
- `OD_TIMEOUT`: Readiness timeout in seconds (default: 90).
- `OD_VERBOSE`: Set to `1` to output raw `tools-dev` supervisor logs.

## References

- `scripts/od.sh` — The canonical entry point for OpenDesign lifecycle management.
- `tools/dev/bin/tools-dev.mjs` — OpenDesign's internal supervisor owning ports, pids, and logs.
- `~/.pi/agent/mcp.json` — The MCP server registration for OpenDesign in Pi.
