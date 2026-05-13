# Installer CLI reference

Command-line reference for `install.sh` (POSIX) and `install.ps1` (Windows / PowerShell 7+).

## ⚡ Quick Reference

| Task | Command |
|---|---|
| Install everything | `bash install.sh <target>` |
| Install one bundle | `bash install.sh --bundle <name> <target>` |
| Install one skill | `bash install.sh --skill <name> <target>` |
| Install one agent | `bash install.sh --agent <name> <target>` |
| Refresh (true-sync) | `bash install.sh --update <target>` |
| Skip the pre-push hook | `bash install.sh --no-pre-push-hook <target>` |
| Print help | `bash install.sh --help` |

## Synopsis

```
install.sh [--bundle <name>] [--skill <name>] [--agent <name>] [--all] [--update] [--no-pre-push-hook] <target-project-path>
install.ps1 [-Bundle <name>] [-Skill <name>] [-Agent <name>] [-All] [-Update] [-NoPrePushHook] <target-project-path>
```

## Flags

| Flag (bash) | Flag (pwsh) | Effect |
|---|---|---|
| `--bundle <name>` | `-Bundle <name>` | Install only the named bundle (and its contents). Skips standalone skills + agents. |
| `--skill <name>` | `-Skill <name>` | Install only the named standalone skill. Skips bundles + standalone agents. |
| `--agent <name>` | `-Agent <name>` | Install only the named standalone agent. Skips bundles + standalone skills. (Available since v0.6.0.) |
| `--all` | `-All` | Install everything (default). Equivalent to omitting `--bundle` / `--skill` / `--agent`. |
| `--update` | `-Update` | True-sync: wipe toolkit-managed dirs in target (`.claude/skills/`, `.agent/skills/`, `.agents/skills/`, `.claude/agents/`, `.gemini/agents/`) and recreate from source. Orphan paths from previous versions are auto-removed. |
| `--no-pre-push-hook` | `-NoPrePushHook` | Skip installing `templates/hooks/pre-push` into target's `.git/hooks/pre-push`. By default the hook installs; this opts out. |
| `--help`, `-h` | `-Help` | Print the header comment block and exit. |

## Prerequisites

| Tool | Purpose | When needed |
|---|---|---|
| `bash` 4+ or `pwsh` 7+ | Host interpreter | Always |
| `python3` | Manifest YAML parsing (via `scripts/manifest-info.py`) | Always |
| `pyyaml` (Python package) | YAML parser | Always |
| `git` | Pre-push hook installation (target must be a git repo for the hook to install) | When pre-push hook is enabled (default) |

## Installed paths

What lands where on a default `--all` install:

| Target path | Source | Behavior on `--update` |
|---|---|---|
| `.claude/skills/<name>/` | `skills/<name>/` or `bundles/<b>/skills/<name>/` (claude-code in `supported_hosts`) | Wipe-and-recreate |
| `.agent/skills/<name>/` | same (antigravity in `supported_hosts`) — also receives agents wrapped as sub-agent-as-skill | Wipe-and-recreate |
| `.agents/skills/<name>/` | same (gemini-cli in `supported_hosts`) | Wipe-and-recreate |
| `.claude/agents/<name>.md` | `agents/<name>.md` or `bundles/<b>/agents/<name>.md` (claude-code in `supported_hosts`) | Wipe-and-recreate (v0.6.0+) |
| `.gemini/agents/<name>.md` | same (gemini-cli in `supported_hosts`) | Wipe-and-recreate (v0.6.0+) |
| `.git/hooks/pre-push` | `templates/hooks/pre-push` | Always refreshed; existing non-matching hook backed up to `.agent-toolkit-bak.<timestamp>` |

**Sibling-tool collision note (v0.6.0+):** `.claude/agents/` and `.gemini/agents/` are also written to by the sibling [`agentic-harness`](https://github.com/alexherrero/agentic-harness) installer (for `explorer` / `adversarial-reviewer` / `documenter`). When both repos are installed into the same target, the **later-run** installer's `--update` wipes the parent before recreating from its own source. Run both installers (in either order) to land the full set. The same caveat already applies to `.claude/skills/`, `.agent/skills/`, and `.agents/skills/`.

User-state paths (NEVER touched by `--update`):

- Target's repo-root files (`README.md`, `AGENTS.md`, `CLAUDE.md`, etc.)
- Target's `wiki/` content
- Target's `.harness/` state (if installed alongside the harness)
- Target's `settings.json` files (merge semantics for hooks, not overwrite)

## Pre-push hook behavior

By default, the installer copies `templates/hooks/pre-push` → `<target>/.git/hooks/pre-push` and `chmod +x` it. The hook:

- Runs on every `git push`.
- Searches for `agent-toolkit/scripts/check-no-pii.sh` via `$AGENT_TOOLKIT_PATH`, then common dev-machine paths (`~/Antigravity/agent-toolkit/`, `~/dev/agent-toolkit/`, `../agent-toolkit/`).
- If found: scans the push range; blocks push on any PII finding.
- If not found: prints a warning and exits 0 (degraded-gracefully — the hook never blocks a push without being able to verify).

**Existing-hook handling:**

- If the target already has a `.git/hooks/pre-push` byte-identical to `templates/hooks/pre-push`: no-op (`kept` message).
- If different: existing hook is backed up to `.git/hooks/pre-push.agent-toolkit-bak.<unix-timestamp>` before overwrite.
- The toolkit installer **never silently clobbers** a non-matching hook.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Target directory doesn't exist; gitleaks/PII check failed; or other operational error |
| `2` | Argument error (unknown flag, missing target, conflicting flags) |

## Related

- [Install Into Project](Install-Into-Project) — practical install recipe.
- [Manifest Schema](Manifest-Schema) — frontmatter contract.
- [Per-Host Paths](Per-Host-Paths) — destination paths by kind.
- [Customization Types](Customization-Types) — what `kind` values mean.
