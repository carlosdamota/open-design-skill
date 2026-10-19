# open-design-skill 🎨⚡

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Skills Standard](https://img.shields.io/badge/Agent_Skills-Compliant-brightgreen.svg)](https://github.com/anthropics/skills)

An agent skill that manages the local lifecycle of [OpenDesign](https://github.com/nexu-io/open-design) (`daemon` + `web` Studio), guarantees idempotent process supervision, and prevents the fatal collision with Linux/macOS `/usr/bin/od` (GNU coreutils octal-dump).

---

## The Problem

When coding agents (such as **Pi**, **Claude Code**, **Cursor**, or **Codex**) interact with OpenDesign from the command line, two severe operational failures regularly happen:

1. **The Octal-Dump Trap:** On most Linux distributions and macOS systems, typing `od` runs `/usr/bin/od` (the standard octal-dump utility). The agent attempts `od start` or `od status`, gets stuck waiting on `stdin`, and hangs the entire conversation.
2. **Zombie Instances & Port Collisions:** Starting OpenDesign without checking the internal `tools-dev` supervisor leads to duplicate daemons, zombie processes, and failed port allocations.

---

## The Solution

This skill provides a battle-tested lifecycle wrapper (`scripts/od.sh`) and an agent instruction set (`SKILL.md`) that:

* ✅ **Guarantees Idempotency:** Detects whether OpenDesign's daemon and web server are already running before touching processes.
* ✅ **Bypasses Binary Collisions:** Delegates directly to OpenDesign's internal `tools-dev` supervisor instead of relying on the system `PATH`.
* ✅ **Auto-detects Checkouts:** Automatically finds local checkouts in `~/open-design`, `~/projects/open-design`, or custom paths via `OD_REPO`.
* ✅ **Handles MCP Synchronization:** Automatically provides context on when and how to reconnect the `open-design` MCP server (`/mcp`).

---

## Installation

### Via Skills CLI (Recommended)
Add this skill to your current coding agent environment:

```bash
npx skills add CarlosDamota/open-design-skill
```

### Manual Installation for Pi Coding Agent
Clone or symlink this folder into your Pi agent skills directory:

```bash
git clone https://github.com/CarlosDamota/open-design-skill.git ~/.agents/skills/open-design
```

---

## Usage

Once installed, your agent will trigger this skill automatically whenever you ask to:
* *"Lanzar OpenDesign"* or *"Start OpenDesign"*
* *"¿Está corriendo OpenDesign?"* or *"OpenDesign status"*
* *"Reiniciar el servidor de OpenDesign"*
* *"Dame la URL del Studio de OpenDesign"*

You can also run the underlying script directly in your terminal:

```bash
# Check status and print Studio URL
./scripts/od.sh status

# Start daemon and web studio (idempotent: does nothing if already up)
./scripts/od.sh start

# Print the active Studio URL directly
./scripts/od.sh url

# Restart services to reload dev code
./scripts/od.sh restart

# Tail recent logs for troubleshooting
./scripts/od.sh logs

# Gracefully shut down daemon and web
./scripts/od.sh stop
```

---

## Configuration & Environment Variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `OD_REPO` | Path to the OpenDesign source checkout | Auto-detected (`~/open-design`, etc.) |
| `OD_NODE` | Path to Node.js executable | `node` from `$PATH` |
| `OD_TIMEOUT` | Readiness timeout in seconds | `90` |
| `OD_VERBOSE` | Output raw supervisor stdout | `0` (clean output) |

---

## Requirements

* **Node.js:** `>= 20`
* **Python 3:** Required for fast, zero-dependency JSON parsing of supervisor telemetry.
* **OpenDesign:** A local source checkout of [nexu-io/open-design](https://github.com/nexu-io/open-design).

---

## License

Licensed under the [Apache-2.0 License](LICENSE), matching the OpenDesign project.
