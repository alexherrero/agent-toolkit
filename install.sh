#!/usr/bin/env bash
# install.sh — agent-toolkit installer (STUB — fleshed out in task 3 of v0.1.0 plan).
#
# When complete, this installs `agent-toolkit` customizations into a target project.
# Planned usage:
#   bash install.sh [--bundle <name>] [--skill <name>] [--all] [--update] [--no-pre-push-hook] <target-project-path>
#
# Today: stub. Print explanation and exit non-zero so accidental use surfaces.

set -euo pipefail

cat >&2 <<'EOF'
agent-toolkit install.sh — not yet implemented (stub from task 1 scaffold).

The full installer body lands in task 3 of the v0.1.0 plan. Until then, customizations
in this repo are not auto-deliverable. Inspect them by hand or wait for v0.1.0.

Planned flags:
  --bundle <name>          install one bundle
  --skill <name>           install one standalone skill
  --all                    install everything (default)
  --update                 true-sync; wipe and recreate managed dirs
  --no-pre-push-hook       skip pre-push hook installation
  <target-project-path>    target project (positional)
EOF
exit 2
